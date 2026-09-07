import Foundation

/// The body-load graph's launch cache: the warmed default-range
/// ``BodyLoadTrail`` on disk, so the background warm after launch fills the
/// in-memory cache from a file read off the main actor instead of fetching
/// the whole dose log and resolving every dose on the main actor (~135 ms
/// there, colliding with early frames).
///
/// The key carries the same store identity as the other launch caches (store
/// generation, entry count, newest timestamp) plus the range, the hour
/// bucket the trail was sampled in (decay moves with the clock), and the
/// resolution inputs (colors, custom overlay, database, build).
nonisolated enum BodyLevelsTrailCache {
    nonisolated struct Key: Codable, Hashable, Sendable {
        /// Bumped when the encoded trail changes shape, so a file from an
        /// older build misses instead of half-decoding.
        var format = 1
        let range: String
        let storeGeneration: Int
        let entryCount: Int
        let newestTimestamp: Date?
        let hourBucket: Int
        let colorSignature: Int
        let customSignature: Int
        let databaseSignature: String
        let appBuild: String
    }

    private nonisolated struct Payload: Codable {
        let key: Key
        let trail: BodyLoadTrail
    }

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("body-levels.cache")
    }

    /// The cached trail when it was built from exactly `key`, decoded off the
    /// main actor; `nil` otherwise.
    static func load(matching key: Key) async -> BodyLoadTrail? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) { () -> BodyLoadTrail? in
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.key == key
            else { return nil }
            return payload.trail
        }.value
    }

    /// Write `trail` as the cache for `key`, encoding off the main actor.
    static func save(_ trail: BodyLoadTrail, key: Key) {
        guard let url else { return }
        let payload = Payload(key: key, trail: trail)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Remove the cache, for a store restore or a wipe.
    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
