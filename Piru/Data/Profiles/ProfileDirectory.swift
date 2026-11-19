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
    /// People on other devices this one has paired with. Their profiles hold
    /// what they share and draw like anyone's on a shared session, but they are
    /// no journal here: the switcher, quick log and inventory list ``profiles``.
    private(set) var people: [PiruPerson]
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

    /// Set while inventory items may still name the owner by the legacy id;
    /// cleared once every journal's items name the owner's own.
    static let legacySharesPendingKey = "profiles.legacyOwnerSharesPending"

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
        identities: ShareIdentityStore = .shared,
        opener: ((PiruProfile, URL) -> ModelContainer)? = nil,
    ) {
        self.directory = directory
        self.defaults = defaults
        self.opener = opener ?? Self.openStore
        Self.migrateLegacyOwner(in: directory, defaults: defaults, identities: identities)
        profiles = ProfileRegistry.load(from: directory)
        people = PeopleRegistry.load(from: directory)
        activeProfileID = ProfileRegistry.activeProfileID(defaults: defaults, directory: directory)
    }

    /// Gives an owner still on the legacy id an id of its own. Its store and
    /// every per-profile key go by the owner's role, so they stay; the sharing
    /// identity, kept by id, is copied to the new id before the registry names
    /// it and dropped from the old one after, so a launch cut short between the
    /// steps loses nothing.
    private static func migrateLegacyOwner(in directory: URL, defaults: UserDefaults, identities: ShareIdentityStore) {
        guard ProfileRegistry.load(from: directory)[0].id == PiruProfile.legacyOwnerID else { return }
        let newID = UUID()
        let legacy = PiruProfile.legacyOwnerID
        if let data = identities.storage.read(profileID: legacy) {
            try? identities.storage.write(data, profileID: newID)
        }
        defaults.set(true, forKey: legacySharesPendingKey)
        do {
            guard try ProfileRegistry.migrateLegacyOwner(in: directory, newID: newID) != nil else {
                identities.forget(profileID: newID)
                defaults.removeObject(forKey: legacySharesPendingKey)
                return
            }
            identities.forget(profileID: legacy)
            Logger.storeRecovery.notice("Gave the owner profile an id of its own")
        } catch {
            identities.forget(profileID: newID)
            Logger.storeRecovery.error("Owner id migration failed: \(error.localizedDescription, privacy: .public)")
        }
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

    /// A journal's profile, or a paired person's. The legacy owner id finds
    /// the owner.
    func profile(id: UUID) -> PiruProfile? {
        let id = canonical(id)
        return profiles.first { $0.id == id } ?? people.first { $0.id == id }?.profile
    }

    /// `id`, or the owner's for the legacy owner id.
    func canonical(_ id: UUID) -> UUID {
        id == PiruProfile.legacyOwnerID ? owner.id : id
    }

    /// Every journal, then every paired person: whose stores a shared
    /// experience can span.
    var everyone: [PiruProfile] {
        profiles + people.map(\.profile)
    }

    func person(id: UUID) -> PiruPerson? {
        people.first { $0.id == id }
    }

    /// The color `personID` wears here: theirs when paired, else the one
    /// pairing would give them.
    func color(forNewPerson personID: UUID) -> ProfileColor {
        person(id: personID)?.profile.color ?? .next(after: everyone.map(\.color))
    }

    func isPerson(_ id: UUID) -> Bool {
        people.contains { $0.id == id }
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
        remapLegacyOwnerShares()
        return container
    }

    /// Points every inventory item shared with the owner under the legacy id
    /// at the owner's own, once. Only another profile's items can name the
    /// owner, so a device with one profile has nothing to open.
    private func remapLegacyOwnerShares() {
        guard defaults.bool(forKey: Self.legacySharesPendingKey) else { return }
        let legacy = PiruProfile.legacyOwnerID
        for profile in profiles where !profile.isOwner {
            guard let context = container(for: profile.id, writable: true)?.mainContext else { continue }
            let items = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
            var changed = false
            for item in items where item.sharedWith.contains(legacy) {
                item.sharedWith = item.sharedWith.map { $0 == legacy ? owner.id : $0 }
                changed = true
            }
            if changed { try? context.save() }
        }
        defaults.removeObject(forKey: Self.legacySharesPendingKey)
    }

    /// A profile's store: the active container for the active profile,
    /// otherwise opened on first use and kept. A read-only request is answered
    /// by a writable container when one is open; a read-only open of a profile
    /// that has never written anything is an empty in-memory store, so reading
    /// someone's journal never creates a file. `nil` for an unknown id.
    func container(for id: UUID, writable: Bool) -> ModelContainer? {
        guard let profile = profile(id: id) else { return nil }
        let id = profile.id
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
        let id = canonical(id)
        guard id != activeProfileID, let profile = profiles.first(where: { $0.id == id }) else { return nil }
        if let previous = openedActiveContainer {
            try? previous.mainContext.save()
            openContainers[OpenKey(id: activeProfileID, writable: true)] = previous
        }
        let container = writableContainer(for: profile)
        ProfileRegistry.setActiveProfileID(id, defaults: defaults, directory: directory)
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
        guard let profile = profiles.first(where: { $0.id == canonical(id) }) else { throw DirectoryError.unknownProfile }
        guard !profile.isOwner else { throw DirectoryError.ownerCannotBeDeleted }
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

    /// Put a backup's profile in place as `id`. An existing profile with that
    /// id keeps its store, and takes the backup's name, avatar and color only
    /// with `takingDetails`; any other id becomes a new profile on a store of
    /// its own.
    func restoreProfile(_ incoming: PiruProfile, as id: UUID, takingDetails: Bool) throws {
        var next = profiles
        if let index = next.firstIndex(where: { $0.id == id }) {
            guard takingDetails else { return }
            next[index].name = incoming.name
            next[index].avatar = incoming.avatar
            next[index].color = incoming.color
        } else {
            next.append(incoming.reidentified(as: id, asOwner: false))
        }
        try save(next)
    }

    // MARK: - People

    /// Pair with someone, or take a newer name and avatar for someone already
    /// paired. A person keeps the color this device gave them.
    ///
    /// A paired person's key changes only with `replacingKey`: anyone can make
    /// a code or a share that claims someone's person id, so a new key for a
    /// known person needs the user's explicit yes, never a silent overwrite.
    @discardableResult
    func savePerson(
        personID: UUID, name: String, avatar: ProfileAvatar, publicKey: Data, replacingKey: Bool = false,
    ) throws -> PiruPerson {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectoryError.emptyName }
        guard personID != PiruProfile.legacyOwnerID, !profiles.contains(where: { $0.id == personID }) else {
            throw DirectoryError.unknownProfile
        }
        var next = people
        let person: PiruPerson
        if let index = next.firstIndex(where: { $0.id == personID }) {
            guard next[index].publicKey == publicKey || replacingKey else {
                throw SessionSharingError.keyChanged(name: next[index].profile.name)
            }
            var updated = next[index]
            updated.profile.name = trimmed
            updated.profile.avatar = avatar.withPhoto(nil)
            person = PiruPerson(profile: updated.profile, publicKey: publicKey, pairedAt: updated.pairedAt)
            next[index] = person
        } else {
            person = PiruPerson.new(
                personID: personID,
                name: trimmed,
                avatar: avatar.withPhoto(nil),
                color: color(forNewPerson: personID),
                publicKey: publicKey,
            )
            next.append(person)
        }
        try PeopleRegistry.save(next, to: directory)
        people = next
        return person
    }

    /// Unpair someone and set aside what they shared, the way a deleted
    /// profile's store is set aside.
    func removePerson(id: UUID) throws {
        guard let person = person(id: id) else { throw DirectoryError.unknownProfile }
        for writable in [true, false] {
            if let container = openContainers.removeValue(forKey: OpenKey(id: id, writable: writable)) {
                try? container.mainContext.save()
            }
        }
        let next = people.filter { $0.id != id }
        try PeopleRegistry.save(next, to: directory)
        people = next
        StoreRecovery.backUpStore(at: storeURL(for: person.profile), reason: StoreRecovery.profileDeleteReason)
    }

    private func save(_ next: [PiruProfile]) throws {
        try ProfileRegistry.save(next, to: directory)
        profiles = ProfileRegistry.normalized(next)
        // Only after a write: a registry that failed to decode reads as the
        // owner alone, and a sweep then would take everyone else's photo.
        ProfilePhotoStore.sweep(keeping: profiles, in: directory)
    }
}
