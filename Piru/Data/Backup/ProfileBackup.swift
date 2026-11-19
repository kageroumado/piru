import Foundation
import os
import SwiftData

/// The profiles part of a backup made with more than one profile, or with an
/// owner who has a photo: who they are, their photos, and each journal but
/// the owner's. The owner's journal is the backup's own top level, so a build
/// that predates profiles restores the owner's.
nonisolated struct PiruProfilesSection: Codable, Sendable {
    /// Every profile on the device that made the backup, the owner first.
    var registry: [PiruProfile]
    var journals: [PiruProfileJournal]
    /// Each profile photo by its file name in ``ProfilePhotoStore``.
    var photos: [String: Data]?

    /// The largest photo a restore writes; a saved avatar is ~20 KB.
    static let maxPhotoBytes = 1_000_000
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
        try encodeJSON(makeBackupFile(context: context, directory: directory))
    }

    /// The file ``exportBackupJSON(context:directory:)`` encodes, gathered on
    /// the main actor so the encode can run off it.
    @MainActor
    static func makeBackupFile(context: ModelContext, directory: ProfileDirectory = .shared) throws -> PiruFile {
        guard directory.hasMultipleProfiles || directory.owner.avatar.photo != nil else {
            return try makePiruFile(context: context, customStore: .shared, settings: .live)
        }
        var file = try journalFile(for: directory.owner, context: context, directory: directory)
        var journals: [PiruProfileJournal] = []
        for profile in directory.profiles where !profile.isOwner {
            var journal = try journalFile(for: profile, context: context, directory: directory)
            // App preferences travel once, with the top level.
            journal.settings = nil
            journals.append(PiruProfileJournal(profileID: profile.id, file: journal))
        }
        let photos = directory.profiles.compactMap(\.avatar.photo).reduce(into: [String: Data]()) { photos, name in
            photos[name] = ProfilePhotoStore.data(named: name, in: directory.containerURL)
        }
        file.profiles = PiruProfilesSection(
            registry: directory.profiles, journals: journals, photos: photos.isEmpty ? nil : photos,
        )
        return file
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
    /// What a backup made with more than one profile needs the user to settle
    /// before it restores here; empty for any other file.
    func profileConflicts(in plaintext: Data, directory: ProfileDirectory = .shared) -> [ProfileRestoreConflict] {
        guard let section = DataExportImport.profilesSection(in: plaintext) else { return [] }
        return plan(for: section, directory: directory, choices: [:]).conflicts
    }

    func plan(
        for section: PiruProfilesSection, directory: ProfileDirectory, choices: [UUID: ProfileRestoreChoice],
    ) -> ProfileRestorePlan {
        ProfileRestorePlan(
            registry: section.registry,
            local: directory.profiles,
            reserved: Set(directory.people.map(\.id)),
            choices: choices,
        )
    }

    /// Restore a backup made with more than one profile, each profile where
    /// ``ProfileRestorePlan`` puts it under `choices`: the top level into the
    /// backup owner's target, each other journal into its profile's, each by
    /// `strategy`. Inventory shared between the backup's profiles is shared
    /// between the profiles they land in. The whole file is decoded before any
    /// store is touched.
    func applyProfiles(
        _ section: PiruProfilesSection,
        plaintext: Data,
        strategy: RestoreStrategy,
        context: ModelContext,
        directory: ProfileDirectory,
        choices: [UUID: ProfileRestoreChoice] = [:],
    ) throws {
        try DataExportImport.validate(plaintext)
        var top = try JSONDecoder().decode(PiruFile.self, from: plaintext)
        top.profiles = nil
        let plan = plan(for: section, directory: directory, choices: choices)
        let targets = plan.targets.merging([PiruProfile.legacyOwnerID: directory.owner.id]) { mine, _ in mine }

        // Only photos a profile takes from the backup, at a photo's size.
        let named = Set(plan.steps.filter(\.takesDetails).compactMap(\.incoming.avatar.photo))
        for (name, data) in section.photos ?? [:] where named.contains(name) && data.count <= PiruProfilesSection.maxPhotoBytes {
            try? ProfilePhotoStore.write(data, named: name, in: directory.containerURL)
        }
        for step in plan.steps {
            try directory.restoreProfile(step.incoming, as: step.target, takingDetails: step.takesDetails)
        }

        var journals = [(plan.ownerTarget ?? directory.owner.id, top)]
        for journal in section.journals {
            guard let target = targets[journal.profileID] else { continue }
            journals.append((target, journal.file))
        }
        for (target, file) in journals {
            guard let profile = directory.profile(id: target) else { continue }
            let (journalContext, customs) = try DataExportImport.store(
                for: profile, openContext: context, directory: directory, writable: true,
            )
            let data = try DataExportImport.encodeJSON(file.remappingProfiles(targets))
            try ProfileScope.$pinned.withValue(profile.id) {
                try apply(journal: data, strategy: strategy, context: journalContext, customStore: customs)
            }
        }
        Logger.backupManager.notice("Restored \(journals.count, privacy: .public) profiles' journals.")
    }
}

nonisolated extension PiruFile {
    /// The file with every inventory item's sharing pointed at the profiles
    /// the backup's profiles restore into; an id with no target stays.
    func remappingProfiles(_ targets: [UUID: UUID]) -> PiruFile {
        var file = self
        file.inventory = inventory?.map { item in
            var item = item
            item.sharedWith = item.sharedWith?.map { targets[$0] ?? $0 }
            return item
        }
        return file
    }
}
