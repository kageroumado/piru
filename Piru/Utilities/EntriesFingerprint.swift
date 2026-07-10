import Foundation

/// A cheap content fingerprint for `@Query` results, used as a `task(id:)` /
/// `onChange` token so derived UI refreshes on in-place edits (amount,
/// substance, time…) — a `.count` key misses edits entirely.
///
/// Hashes the same fields as `JournalModel.fingerprint`: the ones derived UI
/// actually depends on, hashed cheaply (no SQL / PK work).
enum EntriesFingerprint {
    /// Token covering the entries' content.
    static func make(_ entries: [DoseEntry]) -> Int {
        var hasher = Hasher()
        combine(entries, into: &hasher)
        return hasher.finalize()
    }

    /// Token covering the entries' content plus the substance-color
    /// assignments, for UI that also derives a color map.
    static func make(_ entries: [DoseEntry], colors: [SubstanceColor]) -> Int {
        var hasher = Hasher()
        combine(entries, into: &hasher)
        for color in colors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    private static func combine(_ entries: [DoseEntry], into hasher: inout Hasher) {
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entry.timestamp)
            hasher.combine(entry.amount)
            hasher.combine(entry.substance)
            hasher.combine(entry.route)
            hasher.combine(entry.unit)
        }
    }
}
