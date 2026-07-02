import Foundation
import SwiftData

/// Maintains the curated quick-log list (``QuickLogDose``).
///
/// The list is seeded once from the user's existing dose history, then kept
/// current as doses are logged: a freshly logged dose is added (or floated to
/// the front of its (substance, route) group), and each group is capped at
/// ``QuickLogDose/perGroupLimit`` via least-recently-used eviction. With the
/// "keep a fixed order" preference on, logging never reorders — it only refreshes
/// recency and appends genuinely new doses at the back.
enum QuickLogManager {
    /// `@AppStorage` key for the "keep a fixed order" preference (default off).
    static let fixedOrderDefaultsKey = "quickLogFixedOrder"

    // MARK: - Seeding

    /// Populate the curated list from dose history so existing users keep their
    /// familiar chips. Ranks each (substance, route) group's distinct measurements
    /// by frequency (recency as tiebreak) and keeps the top ``perGroupLimit``.
    ///
    /// Idempotent and self-healing: it seeds **only when the curated table is
    /// empty**, and keys off nothing but that emptiness. There is deliberately no
    /// persistent "already seeded" flag. The previous `quickLogSeeded` flag lived
    /// in App-Group `UserDefaults`, which outlives the SwiftData store it
    /// described — so any store reset that empties the table but leaves the flag
    /// (a mid-cycle schema change that recreates a fresh store, "Delete All Data",
    /// or a backup restore) permanently suppressed re-seeding and the quick-log
    /// list came back empty after every restore. Tying seeding to the store's own
    /// lifecycle fixes that. The one state this re-seeds is a list the user
    /// emptied by hand — an acceptable trade, since the list is "seeded from your
    /// history" by definition and a removed chip re-floats on its next log anyway.
    ///
    /// Seeds from the screen's already-loaded recent window (`history`) rather
    /// than its own full-table fetch — 120 days is plenty to surface a user's
    /// familiar chips, and lifetime-exhaustive ranking isn't worth a second pass
    /// over the whole dose table on first open.
    static func seedIfNeeded(history: [DoseEntry], context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<QuickLogDose>())) ?? 0
        guard existing == 0, !history.isEmpty else { return }

        struct Measure {
            var amount: Double; var unit: String; var count: Int; var last: Date
            var volumeML: Double?; var abv: Double?; var drinkName: String?
        }
        // groupKey -> (substance, route) and measureKey -> aggregated Measure.
        var groupMeta: [String: (substance: String, route: RouteOfAdministration)] = [:]
        var groupMeasures: [String: [String: Measure]] = [:]

        for entry in history {
            let groupKey = "\(entry.substance.lowercased())|\(entry.route.rawValue)"
            // By-volume drinks (alcohol) key by their drink identity so distinct
            // drinks seed as distinct detailed chips, not one merged grams chip.
            let measureKey = QuickLogDose.makeKey(
                substance: entry.substance, route: entry.route, amount: entry.amount, unit: entry.unit,
                volumeML: entry.volumeML, abv: entry.abv, drinkName: entry.drinkName,
            )
            groupMeta[groupKey] = (entry.substance, entry.route)
            var measures = groupMeasures[groupKey] ?? [:]
            var m = measures[measureKey] ?? Measure(
                amount: entry.amount, unit: entry.unit, count: 0, last: .distantPast,
                volumeML: entry.volumeML, abv: entry.abv, drinkName: entry.drinkName,
            )
            m.count += 1
            if entry.timestamp > m.last { m.last = entry.timestamp }
            measures[measureKey] = m
            groupMeasures[groupKey] = measures
        }

        for (groupKey, measures) in groupMeasures {
            guard let meta = groupMeta[groupKey] else { continue }
            let ranked = measures.values
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
                .prefix(QuickLogDose.perGroupLimit)
            for (index, m) in ranked.enumerated() {
                context.insert(QuickLogDose(
                    substance: meta.substance,
                    route: meta.route,
                    amount: m.amount,
                    unit: m.unit,
                    sortOrder: Double(index),
                    lastUsedAt: m.last,
                    volumeML: m.volumeML,
                    abv: m.abv,
                    drinkName: m.drinkName,
                ))
            }
        }
        try? context.save()
    }

    // MARK: - Maintenance on log

    /// One freshly-logged dose to fold into the curated list. By-volume detail
    /// (alcohol) rides along so the chip becomes a re-loggable drink, not a bare
    /// gram amount; `nil` for ordinary mass doses.
    struct LoggedDose {
        let substance: String
        let route: RouteOfAdministration
        let amount: Double
        let unit: String
        var volumeML: Double?
        var abv: Double?
        var drinkName: String?
        var emoji: String?
    }

    /// Record a freshly-logged dose. Convenience wrapper around the batch form.
    static func record(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        fixedOrder: Bool,
        context: ModelContext,
    ) {
        record(
            [LoggedDose(substance: substance, route: route, amount: amount, unit: unit)],
            fixedOrder: fixedOrder,
            context: context,
        )
    }

    /// Record several freshly-logged doses in one pass. Each refreshes recency
    /// and floats to the front of its (substance, route) group unless
    /// `fixedOrder` (then it stays put / new doses append at the back), evicting
    /// the least-recently-used chip past the cap.
    ///
    /// The whole `QuickLogDose` table is fetched *once* and the context saved
    /// *once*, no matter how many doses commit together — the old per-call form
    /// did two full-table fetches and a save *per dose*, which showed up as
    /// ~160 ms of the Log-button hang when a multi-chip tray committed.
    static func record(_ doses: [LoggedDose], fixedOrder: Bool, context: ModelContext) {
        guard !doses.isEmpty else { return }
        var all = (try? context.fetch(FetchDescriptor<QuickLogDose>())) ?? []
        for dose in doses {
            apply(dose, fixedOrder: fixedOrder, all: &all, context: context)
        }
        try? context.save()
    }

    /// Fold one dose into the in-memory `all` snapshot (mutating it so later
    /// doses in the same batch see freshly-inserted chips), inserting/deleting
    /// in the context but never fetching or saving — the batch driver owns that.
    private static func apply(
        _ dose: LoggedDose,
        fixedOrder: Bool,
        all: inout [QuickLogDose],
        context: ModelContext,
    ) {
        let name = dose.substance.lowercased()
        var group = all.filter { $0.substance.lowercased() == name && $0.route == dose.route }
        let key = QuickLogDose.makeKey(
            substance: dose.substance, route: dose.route, amount: dose.amount, unit: dose.unit,
            volumeML: dose.volumeML, abv: dose.abv, drinkName: dose.drinkName,
        )

        if let existing = group.first(where: { $0.key == key }) {
            existing.lastUsedAt = .now
            if !fixedOrder, let minOrder = group.map(\.sortOrder).min() {
                existing.sortOrder = minOrder - 1
            }
            return
        }

        let sortOrder: Double = if fixedOrder {
            (group.map(\.sortOrder).max() ?? -1) + 1
        } else {
            (group.map(\.sortOrder).min() ?? 0) - 1
        }
        let inserted = QuickLogDose(
            substance: dose.substance,
            route: dose.route,
            amount: dose.amount,
            unit: dose.unit,
            sortOrder: sortOrder,
            volumeML: dose.volumeML,
            abv: dose.abv,
            drinkName: dose.drinkName,
            emoji: dose.emoji,
        )
        context.insert(inserted)
        all.append(inserted)
        group.append(inserted)

        // Evict least-recently-used chips once the group exceeds the cap.
        guard group.count > QuickLogDose.perGroupLimit else { return }
        let byRecency = group.sorted { $0.lastUsedAt > $1.lastUsedAt }
        for stale in byRecency[QuickLogDose.perGroupLimit...] {
            context.delete(stale)
            all.removeAll { $0 === stale }
        }
    }
}
