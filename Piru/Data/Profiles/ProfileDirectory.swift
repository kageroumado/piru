import Foundation
import Observation
import os
import SwiftData

/// The people on this device and the store each one's journal lives in.
///
/// Owns the registry (``ProfileRegistry``), which profile is active, and the
/// open `ModelContainer`s: the active one the root view hands to SwiftUI, and
/// other profiles' stores opened on demand through
/// ``container(for:writable:)`` and kept for the rest of the process.
///
/// Changing the active profile is ``ProfileSwitcher``'s job; this type only
/// opens the store and records the choice.
@Observable
@MainActor
final class ProfileDirectory {
    static let shared = ProfileDirectory()

    enum DirectoryError: Error, LocalizedError {
        case ownerCannotBeDeleted
        case unknownProfile
        case emptyName

        var errorDescription: String? {
            switch self {
            case .ownerCannotBeDeleted: String(localized: "This device's own profile can't be deleted.")
            case .unknownProfile: String(localized: "That profile no longer exists.")
            case .emptyName: String(localized: "A profile needs a name.")
            }
        }
    }

    /// Every profile, the owner first.
    private(set) var profiles: [PiruProfile]
    private(set) var activeProfileID: UUID
    /// The active profile's store. Set by ``openActiveStore()`` before any view
    /// reads it.
    private(set) var openedActiveContainer: ModelContainer?

    @ObservationIgnored private var openContainers: [OpenKey: ModelContainer] = [:]
    @ObservationIgnored private let directory: URL

    /// The folder holding `profiles.json`, every store and the photos.
    var containerURL: URL {
        directory
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let opener: (PiruProfile, URL) -> ModelContainer

    private struct OpenKey: Hashable {
        let id: UUID
        let writable: Bool
    }

    /// `opener` opens a profile's store for writing; the default runs the
    /// owner's recovery first and publishes an open failure the way launch
    /// always has. Tests pass a directory and defaults of their own.
    init(
        directory: URL = ProfileRegistry.containerURL,
        defaults: UserDefaults = ProfileRegistry.groupDefaults,
        opener: ((PiruProfile, URL) -> ModelContainer)? = nil,
    ) {
        self.directory = directory
        self.defaults = defaults
        self.opener = opener ?? Self.openStore
        profiles = ProfileRegistry.load(from: directory)
        activeProfileID = ProfileRegistry.activeProfileID(defaults: defaults, directory: directory)
    }

    // MARK: - Reading

    var activeProfile: PiruProfile {
        profiles.first { $0.id == activeProfileID } ?? owner
    }

    var owner: PiruProfile {
        profiles.first(where: \.isOwner) ?? .defaultOwner(name: ProfileRegistry.defaultOwnerName)
    }

    var hasMultipleProfiles: Bool {
        profiles.count > 1
    }

    var activeContainer: ModelContainer {
        guard let openedActiveContainer else {
            preconditionFailure("ProfileDirectory.openActiveStore() must run before the store is read")
        }
        return openedActiveContainer
    }

    func profile(id: UUID) -> PiruProfile? {
        profiles.first { $0.id == id }
    }

    func storeURL(for profile: PiruProfile) -> URL {
        profile.isOwner
            ? directory.appendingPathComponent(StoreRecovery.activeStoreName)
            : directory.appendingPathComponent(profile.storeFileName)
    }

    // MARK: - Opening stores

    /// Open the active profile's store. Called once at launch.
    @discardableResult
    func openActiveStore() -> ModelContainer {
        let container = writableContainer(for: activeProfile)
        openedActiveContainer = container
        return container
    }

    /// A profile's store: the active container for the active profile,
    /// otherwise opened on first use and kept. A read-only request is answered
    /// by a writable container when one is open; a read-only open of a profile
    /// that has never written anything is an empty in-memory store, so reading
    /// someone's journal never creates a file. `nil` for an unknown id.
    func container(for id: UUID, writable: Bool) -> ModelContainer? {
        guard let profile = profile(id: id) else { return nil }
        if id == activeProfileID, let openedActiveContainer { return openedActiveContainer }
        if let open = openContainers[OpenKey(id: id, writable: true)] { return open }
        if writable { return writableContainer(for: profile) }
        if let open = openContainers[OpenKey(id: id, writable: false)] { return open }
        let container = Self.openReadOnly(at: storeURL(for: profile))
        openContainers[OpenKey(id: id, writable: false)] = container
        return container
    }

    private func writableContainer(for profile: PiruProfile) -> ModelContainer {
        let key = OpenKey(id: profile.id, writable: true)
        if let open = openContainers[key] { return open }
        let container = ProfileScope.$pinned.withValue(profile.id) {
            opener(profile, storeURL(for: profile))
        }
        openContainers[key] = container
        return container
    }

    /// The owner's store goes through recovery, exactly as launch always did;
    /// anyone else's just opens, creating the file the first time.
    private static func openStore(_ profile: PiruProfile, at url: URL) -> ModelContainer {
        if profile.isOwner {
            StoreRecovery.prepareCanonicalStore()
        }
        let opened = StoreRecovery.openContainer(at: url)
        if let detail = opened.failureDetail {
            StoreLaunchState.shared.failureDetail = detail
            StoreLaunchState.shared.storeUnavailable = true
        }
        return opened.container
    }

    private static func openReadOnly(at url: URL) -> ModelContainer {
        if FileManager.default.fileExists(atPath: url.path), StoreHealth.isReadable(at: url),
           let container = try? ModelContainer(
               for: Schema(PiruSchema.models), configurations: StoreRecovery.probeConfiguration(at: url),
           ) {
            return container
        }
        do {
            return try ModelContainer(
                for: Schema(PiruSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
            )
        } catch {
            fatalError("Failed to create even an in-memory ModelContainer: \(error)")
        }
    }

    // MARK: - Activating

    /// Make `id` the active profile and open its store. Returns the store, or
    /// `nil` when `id` is already active or unknown. Binding the singletons and
    /// running the store's passes is ``ProfileSwitcher``'s.
    func activate(_ id: UUID) -> ModelContainer? {
        guard id != activeProfileID, let profile = profile(id: id) else { return nil }
        if let previous = openedActiveContainer {
            try? previous.mainContext.save()
            openContainers[OpenKey(id: activeProfileID, writable: true)] = previous
        }
        let container = writableContainer(for: profile)
        ProfileRegistry.setActiveProfileID(id, defaults: defaults)
        openedActiveContainer = container
        activeProfileID = id
        return container
    }

    // MARK: - Editing

    /// Add a person. Their store is created the first time it is opened.
    @discardableResult
    func addProfile(name: String, avatar: ProfileAvatar? = nil, color: ProfileColor? = nil) throws -> PiruProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectoryError.emptyName }
        let profile = PiruProfile.new(
            name: trimmed,
            avatar: avatar ?? .monogram(for: trimmed),
            color: color ?? .next(after: profiles.map(\.color)),
        )
        try save(profiles + [profile])
        return profile
    }

    /// Replace a profile's name, avatar and color. The id and store stay.
    func update(_ profile: PiruProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { throw DirectoryError.unknownProfile }
        var updated = profile
        updated.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { throw DirectoryError.emptyName }
        var next = profiles
        next[index] = updated
        try save(next)
    }

    /// Remove a person and set their journal aside. The store file is moved to
    /// `<file>.profiledelete-<time>`, an intentional sidecar that recovery
    /// never brings back, so the bytes stay on the device without ever
    /// reappearing as a profile. The active profile must be switched away
    /// from first.
    func deleteProfile(id: UUID) throws {
        guard id != PiruProfile.ownerID else { throw DirectoryError.ownerCannotBeDeleted }
        guard let profile = profile(id: id) else { throw DirectoryError.unknownProfile }
        precondition(id != activeProfileID, "Switch away from a profile before deleting it")
        for writable in [true, false] {
            if let container = openContainers.removeValue(forKey: OpenKey(id: id, writable: writable)) {
                try? container.mainContext.save()
            }
        }
        try save(profiles.filter { $0.id != id })
        StoreRecovery.backUpStore(at: storeURL(for: profile), reason: StoreRecovery.profileDeleteReason)
        Logger.storeRecovery.notice("Deleted a profile; its store was set aside")
    }

    /// Put a profile back from a backup with its own id, so its store file and
    /// every per-profile key line up with what the backup recorded. An existing
    /// profile with that id keeps its store and takes the backup's name, avatar
    /// and color.
    func restoreProfile(_ profile: PiruProfile) throws {
        var next = profiles
        if let index = next.firstIndex(where: { $0.id == profile.id }) {
            next[index].name = profile.name
            next[index].avatar = profile.avatar
            next[index].color = profile.color
        } else {
            next.append(PiruProfile(
                id: profile.id,
                name: profile.name,
                avatar: profile.avatar,
                color: profile.color,
                storeFileName: profile.isOwner ? PiruProfile.ownerStoreFileName : PiruProfile.storeFileName(for: profile.id),
                createdAt: profile.createdAt,
            ))
        }
        try save(next)
    }

    private func save(_ next: [PiruProfile]) throws {
        try ProfileRegistry.save(next, to: directory)
        profiles = ProfileRegistry.normalized(next)
        // Only after a write: a registry that failed to decode reads as the
        // owner alone, and a sweep then would take everyone else's photo.
        ProfilePhotoStore.sweep(keeping: profiles, in: directory)
    }
}
