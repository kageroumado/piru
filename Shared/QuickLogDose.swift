import Foundation
import SwiftData

/// A curated quick-log dose chip: one dose *measurement* (amount + unit) the
/// user keeps as a one-tap shortcut for a given substance + route.
///
/// Quick-log chips used to be pure aggregates over ``DoseEntry`` history, so an
/// accidental or one-off dose stuck around as a suggestion until the underlying
/// journal entries were deleted, and the user had no say in what showed or in
/// what order. The curated list fixes that: each `QuickLogDose` is an explicit,
/// removable, reorderable entry. The list is seeded once from history, then
/// maintained as the user logs — a freshly logged dose is added (or floated to
/// the top), capped per (substance, route) group.
///
/// Ordering within a group is driven by ``sortOrder`` (ascending). With the
/// "keep a fixed order" preference off (the default), logging a dose rewrites
/// its `sortOrder` to the front; with it on, the order only changes when the
/// user reorders manually. ``lastUsedAt`` drives least-recently-used eviction
/// once a group reaches the cap.
///
/// SwiftData `@Model` in `Shared/` so the schema stays identical across the app,
/// widget, and Live Activity targets that open the same store.
@Model
final class QuickLogDose {
    /// Substance name as logged (matched case-insensitively against history).
    var substance: String
    /// Route of administration; persisted as `rawValue`.
    var route: RouteOfAdministration
    /// Dose amount in ``unit``.
    var amount: Double
    /// Unit of measure for ``amount``.
    var unit: String
    /// Display order within the (substance, route) group, ascending.
    var sortOrder: Double
    /// When this dose was last logged — drives float-to-top and LRU eviction.
    var lastUsedAt: Date

    init(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        sortOrder: Double,
        lastUsedAt: Date = .now,
    ) {
        self.substance = substance
        self.route = route
        self.amount = amount
        self.unit = unit
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
    }

    /// Identity of the quick-log chip: `substance(lowercased)|route|amount|unit`.
    var key: String {
        Self.makeKey(substance: substance, route: route, amount: amount, unit: unit)
    }

    static func makeKey(substance: String, route: RouteOfAdministration, amount: Double, unit: String) -> String {
        "\(substance.lowercased())|\(route.rawValue)|\(amount)|\(unit)"
    }

    /// Maximum chips kept per (substance, route) group before least-recently-used
    /// eviction. Eight distinct measurements per route is plenty for one-tap reuse.
    static let perGroupLimit = 8
}
