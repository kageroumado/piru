import Foundation
import Synchronization

/// The list of profiles on this device, as `profiles.json` in the App Group
/// container, and which one is active, as `activeProfileID` in the App Group
/// defaults. A file rather than SwiftData because it is read before any store
/// opens, and by the widgets.
///
/// The owner is implicit: with no file on disk the registry is the owner alone,
/// so an install where nobody added a person never writes one.
nonisolated enum ProfileRegistry {
    static let fileName = "profiles.json"
    static let activeProfileKey = "activeProfileID"

    /// Bumped when the file changes shape, so an older build reading a newer
    /// file falls back to the owner instead of half-decoding it.
    static let formatVersion = 1

    private struct File: Codable {
        var version: Int
        var profiles: [PiruProfile]
    }

    /// The App Group container, with the fallbacks the store uses so a
    /// misconfigured entitlement still launches.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// The App Group defaults the app, the widgets and the Live Activity share.
    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroup) ?? .standard
    }

    /// The name the owner shows under until renamed.
    static var defaultOwnerName: String {
        String(localized: "Me")
    }

    // MARK: - Reading

    private struct Cached {
        let path: String
        let modified: Date?
        let profiles: [PiruProfile]
    }

    private static let cache = Mutex<Cached?>(nil)

    /// Every profile, the owner first. The file is re-read only when its
    /// modification date moves, so the hot paths (notification identifiers, the
    /// store generation) cost a `stat`.
    static func load(from directory: URL = containerURL) -> [PiruProfile] {
        let url = directory.appendingPathComponent(fileName)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let hit = cache.withLock({ $0 }), hit.path == url.path, hit.modified == modified {
            return hit.profiles
        }
        let profiles = decode(at: url)
        cache.withLock { $0 = Cached(path: url.path, modified: modified, profiles: profiles) }
        return profiles
    }

    private static func decode(at url: URL) -> [PiruProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data),
              file.version <= formatVersion
        else { return [PiruProfile.defaultOwner(name: defaultOwnerName)] }
        return normalized(file.profiles)
    }

    /// The owner first and exactly once, every other id once, in file order.
    static func normalized(_ profiles: [PiruProfile]) -> [PiruProfile] {
        var seen = Set<UUID>()
        var others: [PiruProfile] = []
        var owner: PiruProfile?
        for profile in profiles where seen.insert(profile.id).inserted {
            if profile.isOwner { owner = profile } else { others.append(profile) }
        }
        return [owner ?? .defaultOwner(name: defaultOwnerName)] + others
    }

    /// Whether more than the owner is on this device.
    static func hasMultipleProfiles(in directory: URL = containerURL) -> Bool {
        load(from: directory).count > 1
    }

    static func profile(id: UUID, in directory: URL = containerURL) -> PiruProfile? {
        load(from: directory).first { $0.id == id }
    }

    // MARK: - Writing

    /// Writes the list atomically, so a widget reading mid-write sees the old
    /// file or the new one, never half of either.
    static func save(_ profiles: [PiruProfile], to directory: URL = containerURL) throws {
        let file = File(version: formatVersion, profiles: normalized(profiles))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        cache.withLock { $0 = nil }
    }

    // MARK: - Active profile

    /// The profile the app, the widgets and the watch open; the owner when
    /// nothing is set or the stored id names a profile that no longer exists.
    static func activeProfileID(defaults: UserDefaults = groupDefaults, directory: URL = containerURL) -> UUID {
        guard let raw = defaults.string(forKey: activeProfileKey),
              let id = UUID(uuidString: raw),
              id != PiruProfile.ownerID
        else { return PiruProfile.ownerID }
        return profile(id: id, in: directory) == nil ? PiruProfile.ownerID : id
    }

    static func setActiveProfileID(_ id: UUID, defaults: UserDefaults = groupDefaults) {
        if id == PiruProfile.ownerID {
            defaults.removeObject(forKey: activeProfileKey)
        } else {
            defaults.set(id.uuidString, forKey: activeProfileKey)
        }
    }

    static func activeProfile(defaults: UserDefaults = groupDefaults, directory: URL = containerURL) -> PiruProfile {
        let id = activeProfileID(defaults: defaults, directory: directory)
        return profile(id: id, in: directory) ?? .defaultOwner(name: defaultOwnerName)
    }

    /// Where the active profile's store lives — what a widget opens.
    static func activeStoreURL(defaults: UserDefaults = groupDefaults, directory: URL = containerURL) -> URL {
        directory.appendingPathComponent(activeProfile(defaults: defaults, directory: directory).storeFileName)
    }
}

/// Whose journal the code running now reads and writes: the active profile,
/// unless a task pinned another one with ``$pinned`` to work in a profile's
/// store that is not on screen (a watch dose for the owner, another profile's
/// reminder sync, a backup).
///
/// Everything keyed per profile goes through here: notification identifiers,
/// the dose log's store generation, launch-pass tokens and caches. The owner's
/// keys are unscoped, so an owner's existing identifiers and caches keep working.
nonisolated enum ProfileScope {
    @TaskLocal static var pinned: UUID?

    static var currentID: UUID {
        pinned ?? ProfileRegistry.activeProfileID()
    }

    static var isOwner: Bool {
        currentID == PiruProfile.ownerID
    }

    /// Whether the code running now works in the journal on screen, as
    /// opposed to writing into someone else's (a dose logged for them).
    static var isActive: Bool {
        pinned.map { $0 == ProfileRegistry.activeProfileID() } ?? true
    }

    static var current: PiruProfile {
        ProfileRegistry.profile(id: currentID) ?? .defaultOwner(name: ProfileRegistry.defaultOwnerName)
    }

    /// `key` for the owner; `key.<uuid>` for anyone else.
    static func key(_ base: String) -> String {
        key(base, for: currentID)
    }

    static func key(_ base: String, for id: UUID) -> String {
        id == PiruProfile.ownerID ? base : "\(base).\(id.uuidString.lowercased())"
    }

    /// The segment after `piru.notif.` that keeps one profile's requests apart
    /// from another's: empty for the owner, so its identifiers stay as shipped.
    static var notificationNamespace: String {
        notificationNamespace(for: currentID)
    }

    static func notificationNamespace(for id: UUID) -> String {
        id == PiruProfile.ownerID ? "" : "\(id.uuidString.lowercased())."
    }

    /// Whose journal a notification request belongs to, read back from its
    /// identifier (`piru.notif.<uuid>.<type>…`); the owner for every request
    /// without an id there, which includes everything scheduled before
    /// profiles existed.
    static func profileID(fromNotificationIdentifier identifier: String) -> UUID {
        let prefix = "piru.notif."
        guard identifier.hasPrefix(prefix) else { return PiruProfile.ownerID }
        let segment = identifier.dropFirst(prefix.count).prefix { $0 != "." }
        return UUID(uuidString: String(segment)) ?? PiruProfile.ownerID
    }

    /// A notification title that names the person when more than one profile
    /// exists: "Alice · Concerta".
    static func personalized(_ title: String) -> String {
        guard ProfileRegistry.hasMultipleProfiles() else { return title }
        return "\(current.name) · \(title)"
    }
}
