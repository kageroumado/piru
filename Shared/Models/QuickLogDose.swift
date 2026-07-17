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

    /// The PSID identity a chip inherits from the dose it was minted for, so
    /// recents split and merge on substance identity rather than a name — a
    /// Concerta chip (Methylphenidate·XR) and a Ritalin IR chip
    /// (Methylphenidate·IR) stay distinct even though `substance` is the same
    /// canonical string. All `nil` for a chip seeded from a pre-PSID history row
    /// (which keys by lowercased name, as before) until the backfill resolves it.
    /// Additive optionals — a free lightweight migration. See ``identityKey`` and
    /// `Specs/psid-identity-consumption.md` D.2.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    /// The user's own word for this dose ("Concerta", "Vyvanse"), carried so a
    /// re-staged chip logs the product it named — not the canonical family. Not
    /// part of the identity key: "Concerta" and "Methylphenidate XR" share a card.
    var productName: String?

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
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
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
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }

    /// This chip's substance-identity key — its card/group are grouped by this.
    var identityKey: String {
        Self.identityKey(
            substanceUID: substanceUID, substance: substance,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
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
            substanceUID: substanceUID,
            isomer: isomer,
            releaseForm: releaseForm,
            saltForm: saltForm,
            volumeML: volumeML,
            abv: abv,
            drinkName: drinkName,
        )
    }

    /// The substance-identity portion of every recents key: the PSID family plus
    /// the form facets that make one drug two distinct recents (a picked isomer,
    /// a release form). Falls back to the lowercased name when the row hasn't
    /// resolved to a `substanceUID` — so a pre-PSID chip keys exactly as it did
    /// before, and two casings of one name still collide.
    ///
    /// `productName` is deliberately **not** here: "Concerta" and "Methylphenidate
    /// XR" both resolve to Methylphenidate·XR and share one card (D.2.5). Facets
    /// of `nil`/`""`/`"0"` (the PSID unspecified sentinel) are absent, so an
    /// unfaceted resolved dose keys by bare family uid and matches a plain log.
    static func identityKey(
        substanceUID: String?,
        substance: String,
        isomer: String?,
        releaseForm: String?,
        saltForm: String?,
    ) -> String {
        func present(_ value: String?) -> String? {
            guard let value, !value.isEmpty, value != "0" else { return nil }
            return value
        }
        let base = (substanceUID?.isEmpty == false) ? substanceUID! : substance.lowercased()
        let facets = [present(isomer), present(releaseForm), present(saltForm)]
        guard facets.contains(where: { $0 != nil }) else { return base }
        return "\(base)#\(facets.map { $0 ?? "0" }.joined(separator: ","))"
    }

    static func makeKey(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
    ) -> String {
        // Identity replaces the bare name so a Concerta chip and a Ritalin IR chip
        // (same canonical `substance`) get distinct keys. With no identity args —
        // a pre-PSID chip, or the drink-preset callers — `identityKey` returns the
        // lowercased name, so the key is byte-identical to the old scheme.
        let identity = identityKey(
            substanceUID: substanceUID, substance: substance,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
        let base = "\(identity)|\(route.rawValue)|\(amount)|\(unit)"
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
