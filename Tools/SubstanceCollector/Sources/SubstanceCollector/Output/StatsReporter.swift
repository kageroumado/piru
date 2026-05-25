import Foundation

/// Builds the stderr summary printed at the end of every run.
enum StatsReporter {
    struct Summary {
        let total: Int
        let categoryCounts: [(String, Int)]
        let tagCounts: [(String, Int)]
        let withDose: Int
        let withoutDose: Int
        let mergedCount: Int
        let countsByProvenance: [String: Int]
        let warnings: [String]
        let cacheHits: Int
        let cacheMisses: Int
    }

    static func summarize(
        _ subs: [BundledSubstance],
        countsByProvenance: [String: Int],
        mergedCount: Int,
        warnings: [String],
        cacheHits: Int,
        cacheMisses: Int
    ) -> Summary {
        var byCategory: [String: Int] = [:]
        var byTag: [String: Int] = [:]
        var withDose = 0
        for s in subs {
            byCategory[s.category, default: 0] += 1
            for t in s.tags { byTag[t, default: 0] += 1 }
            if !s.hasNoDoseData { withDose += 1 }
        }
        let catSorted = byCategory.sorted { $0.value > $1.value }
        let tagSorted = byTag.sorted { $0.value > $1.value }
        return Summary(
            total: subs.count,
            categoryCounts: catSorted,
            tagCounts: tagSorted,
            withDose: withDose,
            withoutDose: subs.count - withDose,
            mergedCount: mergedCount,
            countsByProvenance: countsByProvenance,
            warnings: warnings,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses
        )
    }

    static func render(_ s: Summary) -> String {
        var out = ""
        out += "\n================ SubstanceCollector Summary ================\n"
        out += "Total compounds:  \(s.total)\n"
        out += "With dose data:   \(s.withDose)\n"
        out += "Without dose:     \(s.withoutDose)\n"
        out += "Merged duplicates: \(s.mergedCount)\n"
        out += "Cache:            \(s.cacheHits) hits, \(s.cacheMisses) misses\n"
        out += "\nProvenance counts (pre-dedup):\n"
        for (k, v) in s.countsByProvenance.sorted(by: { $0.value > $1.value }) {
            out += "  \(k.padding(toLength: 20, withPad: " ", startingAt: 0)) \(v)\n"
        }
        out += "\nBy category:\n"
        for (cat, count) in s.categoryCounts {
            out += "  \(cat.padding(toLength: 20, withPad: " ", startingAt: 0)) \(count)\n"
        }
        out += "\nTop 30 tags:\n"
        for (tag, count) in s.tagCounts.prefix(30) {
            out += "  \(tag.padding(toLength: 30, withPad: " ", startingAt: 0)) \(count)\n"
        }
        if !s.warnings.isEmpty {
            out += "\nWarnings (\(s.warnings.count)):\n"
            for w in s.warnings.prefix(20) {
                out += "  - \(w)\n"
            }
            if s.warnings.count > 20 {
                out += "  ... and \(s.warnings.count - 20) more\n"
            }
        }
        out += "============================================================\n"
        return out
    }
}
