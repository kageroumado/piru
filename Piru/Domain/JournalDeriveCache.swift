import Foundation

/// The Journal's launch cache for ``JournalModel/rebuildDerived``: every
/// entry's resolved category, timeline state and marker, on disk, so a launch
/// whose dose log is unchanged since the previous run seeds the derive map
/// from a file read off the main actor instead of re-resolving the whole
/// history through `SubstanceLibrary` (the derive was ~170–290 ms of
/// main-thread work at launch).
///
/// Same validity scheme as ``TimelineStripCache``: the persistent store
/// generation, the entry count and newest timestamp (widget writes cannot
/// bump the generation), plus everything the resolution reads that lives
/// outside the dose log — the color assignments, the body weight that scales
/// dose intensity, the custom-substance overlay (relabels, durations, dose
/// ladders), the substance database file, and the app build. Rows are keyed
/// by the entry's `UUID` and carry the deterministic fingerprint the diff
/// engine compares, so an entry edited since the cache was written simply
/// misses and re-resolves.
nonisolated enum JournalDeriveCache {
    nonisolated struct Key: Codable, Equatable, Sendable {
        /// Bumped when the encoded rows change shape, so a file from an older
        /// build misses instead of half-decoding.
        var format = 1
        let storeGeneration: Int
        let entryCount: Int
        let newestTimestamp: Date?
        let colorSignature: Int
        let weightKg: Double
        let customSignature: Int
        let databaseSignature: String
        let appBuild: String
    }

    nonisolated struct Row: Codable, Sendable {
        let fingerprint: Int
        let derived: JournalModel.EntryDerived
    }

    private nonisolated struct Payload: Codable {
        let key: Key
        let builtAt: Date
        let rows: [String: Row]
    }

    /// The resolution has no clock in it, so a hit only ages out of caution
    /// against inputs the key does not see.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("journal-derive.cache")
    }

    /// The cached rows by entry id when they were built from exactly `key`
    /// within ``maxAge``, decoded off the main actor; `nil` otherwise.
    static func load(matching key: Key, now: Date = .now) async -> [UUID: Row]? {
        guard let url else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> [UUID: Row]? in
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.key == key,
                  now.timeIntervalSince(payload.builtAt) < maxAge,
                  !payload.rows.isEmpty
            else { return nil }
            var rows: [UUID: Row] = [:]
            rows.reserveCapacity(payload.rows.count)
            for (id, row) in payload.rows {
                if let uuid = UUID(uuidString: id) { rows[uuid] = row }
            }
            return rows
        }.value
    }

    /// Write `rows` as the cache for `key`, encoding off the main actor.
    static func save(_ rows: [UUID: Row], key: Key, now: Date = .now) {
        guard let url, !rows.isEmpty else { return }
        var keyed: [String: Row] = [:]
        keyed.reserveCapacity(rows.count)
        for (id, row) in rows {
            keyed[id.uuidString] = row
        }
        let payload = Payload(key: key, builtAt: now, rows: keyed)
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
