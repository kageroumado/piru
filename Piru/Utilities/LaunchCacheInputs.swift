import Foundation

/// The inputs a launch cache's key folds in beyond the dose log itself: what
/// a resolution reads that can change between launches without a dose write.
/// Every cache (``TimelineStripCache``, ``JournalDeriveCache``,
/// ``BodyLevelsTrailCache``) draws its share from here so they agree on how
/// each input is signed.
@MainActor
enum LaunchCacheInputs {
    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// The custom-substance overlay: relabels, duration overrides, dose
    /// ladders. Signed over its encoding, so any edit misses. Keys are sorted
    /// because a dictionary's encoded order otherwise follows the process's
    /// hash seed, and the signature would change on every launch.
    static var customSubstanceSignature: Int {
        var hasher = StableHasher()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(CustomSubstanceStore.shared.all) {
            hasher.combine(bytes: data)
        }
        return hasher.finalize()
    }

    /// The substance database in use and its source order.
    static var databaseSignature: String {
        SubstanceStore.shared.dataSignature
    }

    /// Order-independent signature of the color assignments, so the same
    /// rows signed from a main-context query and from a background fetch
    /// agree regardless of row order.
    nonisolated static func colorSignature(_ pairs: [ColorPair]) -> Int {
        var hasher = StableHasher()
        for pair in pairs.sorted(by: { ($0.substance, $0.hex) < ($1.substance, $1.hex) }) {
            hasher.combine(pair.substance)
            hasher.combine(pair.hex)
        }
        return hasher.finalize()
    }

    static func colorSignature(_ colors: [SubstanceColor]) -> Int {
        colorSignature(colors.map { ColorPair(substance: $0.substance, hex: $0.hexColor) })
    }

    nonisolated struct ColorPair: Sendable {
        let substance: String
        let hex: String
    }
}
