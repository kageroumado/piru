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

    /// By-volume detail (alcohol) captured from the logged drink so the chip can
    /// render "🍺 IPA · 330 mL · 6% · 16 g" and re-stage the full drink, not a
    /// bare gram amount. All `nil` for ordinary mass doses (additive columns).
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
    var emoji: String?

    init(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        sortOrder: Double,
        lastUsedAt: Date = .now,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
    ) {
        self.substance = substance
        self.route = route
        self.amount = amount
        self.unit = unit
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
        self.volumeML = volumeML
        self.abv = abv
        self.drinkName = drinkName
        self.emoji = emoji
    }

    /// Whether this chip carries by-volume detail (a named/measured drink) vs.
    /// a plain gram amount — drives detailed vs. regular chip rendering.
    var hasDrinkDetail: Bool {
        drinkName != nil || volumeML != nil || abv != nil
    }

    /// Identity of the quick-log chip. For a by-volume drink it folds in the
    /// drink's name/strength/volume so distinct drinks (an IPA vs. a cider that
    /// happen to share grams) stay distinct chips; otherwise `substance|route|amount|unit`.
    var key: String {
        Self.makeKey(
            substance: substance,
            route: route,
            amount: amount,
            unit: unit,
            volumeML: volumeML,
            abv: abv,
            drinkName: drinkName,
        )
    }

    static func makeKey(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
    ) -> String {
        let base = "\(substance.lowercased())|\(route.rawValue)|\(amount)|\(unit)"
        guard volumeML != nil || abv != nil || drinkName != nil else { return base }
        let name = (drinkName ?? "").lowercased()
        let vol = volumeML.map { String($0) } ?? ""
        let strength = abv.map { String($0) } ?? ""
        return "\(base)|\(name)|\(vol)|\(strength)"
    }

    /// Maximum chips kept per (substance, route) group before least-recently-used
    /// eviction. Eight distinct measurements per route is plenty for one-tap reuse.
    static let perGroupLimit = 8
}
