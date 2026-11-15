import Foundation
import os
import SwiftData

/// The profiles part of a backup made with more than one profile: who they
/// are, and each journal but the owner's. The owner's journal is the backup's
/// own top level, so a build that predates profiles restores the owner's.
nonisolated struct PiruProfilesSection: Codable, Sendable {
    /// Every profile on the device that made the backup, the owner first.
    var registry: [PiruProfile]
    var journals: [PiruProfileJournal]
}

/// One profile's journal, in the same shape as a whole Piru file.
nonisolated struct PiruProfileJournal: Codable, Sendable {
    var profileID: UUID
    var file: PiruFile
}

extension DataExportImport {
    /// The journal a backup writes: today's single-journal file while the
    /// owner is alone, and otherwise the owner's journal at the top level with
    /// every other profile's in ``PiruFile/profiles``. `context` is the open
    /// journal's, read in place; the others are read through their own stores.
    @MainActor
    static func exportBackupJSON(context: ModelContext, directory: ProfileDirectory = .shared) throws -> Data {
        guard directory.hasMultipleProfiles else { return try exportJSON(context: context) }
        var file = try journalFile(for: directory.owner, context: context, directory: directory)
        var journals: [PiruProfileJournal] = []
        for profile in directory.profiles where !profile.isOwner {
            var journal = try journalFile(for: profile, context: context, directory: directory)
            // App preferences travel once, with the top level.
            journal.settings = nil
            journals.append(PiruProfileJournal(profileID: profile.id, file: journal))
        }
        file.profiles = PiruProfilesSection(registry: directory.profiles, journals: journals)
        return try encodeJSON(file)
    }

    @MainActor
    private static func journalFile(
        for profile: PiruProfile, context: ModelContext, directory: ProfileDirectory,
    ) throws -> PiruFile {
        let (journalContext, customStore) = try store(for: profile, openContext: context, directory: directory, writable: false)
        return try makePiruFile(context: journalContext, customStore: customStore, settings: .live)
    }

    /// The profiles section of a Piru file, or `nil` for any other file and for
    /// a backup made with one profile.
    nonisolated static func profilesSection(in data: Data) -> PiruProfilesSection? {
        guard case .piruNative = try? classify(data) else { return nil }
        return (try? JSONDecoder().decode(PiruFile.self, from: data))?.profiles
    }

    /// A profile's context and custom-substance store: the open journal's own
    /// (`openContext` and the shared store) for the active profile, otherwise
    /// its store opened through `directory`.
    @MainActor
    static func store(
        for profile: PiruProfile, openContext: ModelContext, directory: ProfileDirectory, writable: Bool,
    ) throws -> (ModelContext, CustomSubstanceStore) {
        if profile.id == directory.activeProfileID {
            return (openContext, .shared)
        }
        guard let container = directory.container(for: profile.id, writable: writable) else {
            throw ProfileDirectory.DirectoryError.unknownProfile
        }
        return (container.mainContext, .inactiveProfile(container: container))
    }
}

extension BackupManager {
    /// Restore a backup made with more than one profile: the profiles come
    /// back with their own ids (so their store files and per-profile keys line
    /// up), the top level goes into the owner's journal, and each other journal
    /// into its profile's, each by `strategy`. The whole file is decoded
    /// before any store is touched.
    func applyProfiles(
        _ section: PiruProfilesSection,
        plaintext: Data,
        strategy: RestoreStrategy,
        context: ModelContext,
        directory: ProfileDirectory,
    ) throws {
        try DataExportImport.validate(plaintext)
        for profile in section.registry {
            try directory.restoreProfile(profile)
        }
        let (ownerContext, ownerCustoms) = try DataExportImport.store(
            for: directory.owner, openContext: context, directory: directory, writable: true,
        )
        try ProfileScope.$pinned.withValue(PiruProfile.ownerID) {
            try apply(journal: plaintext, strategy: strategy, context: ownerContext, customStore: ownerCustoms)
        }
        for journal in section.journals {
            guard let profile = directory.profile(id: journal.profileID) else { continue }
            let (journalContext, customs) = try DataExportImport.store(
                for: profile, openContext: context, directory: directory, writable: true,
            )
            let data = try DataExportImport.encodeJSON(journal.file)
            try ProfileScope.$pinned.withValue(profile.id) {
                try apply(journal: data, strategy: strategy, context: journalContext, customStore: customs)
            }
        }
        Logger.backupManager.notice("Restored \(section.journals.count + 1, privacy: .public) profiles' journals.")
    }
}
