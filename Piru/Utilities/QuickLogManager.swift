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
    private static let seededKey = "quickLogSeeded.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: StoreRecovery.appGroupID) ?? .standard
    }

    // MARK: - Seeding

    /// One-time populate from dose history so existing users keep their familiar
    /// chips. Ranks each (substance, route) group's distinct measurements by
    /// frequency (recency as tiebreak) and keeps the top ``perGroupLimit``.
    /// Idempotent: guarded by a flag and a "no rows yet" check.
    static func seedIfNeeded(history: [DoseEntry], context: ModelContext) {
        guard !defaults.bool(forKey: seededKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<QuickLogDose>())) ?? 0
        guard existing == 0 else {
            defaults.set(true, forKey: seededKey)
            return
        }

        struct Measure { var amount: Double; var unit: String; var count: Int; var last: Date }
        // groupKey -> (substance, route) and measureKey -> aggregated Measure.
        var groupMeta: [String: (substance: String, route: RouteOfAdministration)] = [:]
        var groupMeasures: [String: [String: Measure]] = [:]

        for entry in history {
            let groupKey = "\(entry.substance.lowercased())|\(entry.route.rawValue)"
            let measureKey = "\(entry.amount)|\(entry.unit)"
            groupMeta[groupKey] = (entry.substance, entry.route)
            var measures = groupMeasures[groupKey] ?? [:]
            var m = measures[measureKey] ?? Measure(amount: entry.amount, unit: entry.unit, count: 0, last: .distantPast)
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
                ))
            }
        }
        try? context.save()
        defaults.set(true, forKey: seededKey)
    }

    // MARK: - Maintenance on log

    /// Record a freshly-logged dose. Refreshes recency; floats the dose to the
    /// front of its group unless `fixedOrder` (then it stays put / new doses
    /// append at the back). Evicts the least-recently-used chip past the cap.
    static func record(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        fixedOrder: Bool,
        context: ModelContext,
    ) {
        let group = fetchGroup(substance: substance, route: route, context: context)
        let key = QuickLogDose.makeKey(substance: substance, route: route, amount: amount, unit: unit)

        if let existing = group.first(where: { $0.key == key }) {
            existing.lastUsedAt = .now
            if !fixedOrder, let minOrder = group.map(\.sortOrder).min() {
                existing.sortOrder = minOrder - 1
            }
        } else {
            let sortOrder: Double = if fixedOrder {
                (group.map(\.sortOrder).max() ?? -1) + 1
            } else {
                (group.map(\.sortOrder).min() ?? 0) - 1
            }
            context.insert(QuickLogDose(
                substance: substance,
                route: route,
                amount: amount,
                unit: unit,
                sortOrder: sortOrder,
            ))
            evictIfNeeded(substance: substance, route: route, context: context)
        }
        try? context.save()
    }

    /// Drop least-recently-used chips once a group exceeds the cap.
    private static func evictIfNeeded(substance: String, route: RouteOfAdministration, context: ModelContext) {
        let group = fetchGroup(substance: substance, route: route, context: context)
        guard group.count > QuickLogDose.perGroupLimit else { return }
        let byRecency = group.sorted { $0.lastUsedAt > $1.lastUsedAt }
        for stale in byRecency[QuickLogDose.perGroupLimit...] {
            context.delete(stale)
        }
    }

    /// All curated chips for a (substance, route) group. The list is tiny, so a
    /// fetch-all + in-memory filter (case-insensitive substance) is fine and
    /// avoids `#Predicate` enum/case-folding limitations.
    private static func fetchGroup(substance: String, route: RouteOfAdministration, context: ModelContext) -> [QuickLogDose] {
        let all = (try? context.fetch(FetchDescriptor<QuickLogDose>())) ?? []
        let name = substance.lowercased()
        return all.filter { $0.substance.lowercased() == name && $0.route == route }
    }
}
