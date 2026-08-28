import Foundation

enum DoseUnit {
    /// Conversion factor from each canonical mass unit to milligrams.
    private nonisolated static let toMg: [String: Double] = ["µg": 0.001, "mg": 1, "g": 1_000]

    /// Every spelling of a bare mass unit that resolves to a canonical key.
    ///
    /// "µg" and "μg" are different codepoints — MICRO SIGN (U+00B5) and GREEK
    /// SMALL LETTER MU (U+03BC) — and the catalog contains both, because
    /// different upstreams type them differently. Keying only on the first meant
    /// `convert` returned nil for LSD's oral ladder, all three fentanyl routes
    /// and sufentanil IV: no scale-precision warning on microgram-dosed drugs,
    /// no tolerance contribution, no combined-depression term. Silent, and worst
    /// exactly where the margin is thinnest.
    ///
    /// Deliberately bare spellings only. A qualified unit ("mg (freebase)",
    /// "mg (salt)") states a basis, and folding it onto plain mg would let a
    /// freebase amount be compared against a salt amount as though the
    /// qualifier were decoration. Rate and per-mass units ("µg/kg", "mcg/hr")
    /// are not masses at all and must keep failing.
    private nonisolated static let canonicalUnit: [String: String] = [
        "µg": "µg", "μg": "µg", "mcg": "µg", "ug": "µg",
        "microgram": "µg", "micrograms": "µg", "mcgs": "µg", "ugs": "µg",
        "mg": "mg", "mgs": "mg", "milligram": "mg", "milligrams": "mg",
        "g": "g", "gs": "g", "gram": "g", "grams": "g", "gm": "g",
    ]

    /// Fold a written mass unit onto its canonical key, or nil if it is not a
    /// bare mass unit.
    nonisolated static func canonical(_ unit: String) -> String? {
        canonicalUnit[unit.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Convert a dose amount between compatible mass units (µg, mg, g).
    /// Returns `nil` if either unit is not a convertible mass unit (e.g. mL, IU).
    /// `nonisolated` (pure) so the off-main inventory replay can call it.
    nonisolated static func convert(_ amount: Double, from: String, to: String) -> Double? {
        // Identity first, and for ANY unit: converting mL to mL is the amount
        // itself, and the inventory replay depends on that for non-mass units.
        guard from != to else { return amount }
        guard let fromUnit = canonical(from), let toUnit = canonical(to) else { return nil }
        guard fromUnit != toUnit else { return amount }
        guard let fromFactor = toMg[fromUnit], let toFactor = toMg[toUnit] else { return nil }
        return amount * fromFactor / toFactor
    }
}

/// A colloquial unit that resolves to a fixed amount in a known physical unit.
/// e.g. `("drink", 14, "g")` for alcohol — "2 drinks" is logged as 28 g of ethanol.
struct UnitAlias: Hashable {
    /// User-facing display label (what appears in the unit picker).
    let label: String
    /// How many `unit`s a single instance of `label` represents.
    let amountPerUnit: Double
    /// The physical unit that `amountPerUnit` is denominated in.
    let unit: String
}

extension Substance {
    /// Colloquial unit aliases for this substance. Keys are the canonical
    /// (lowercased) substance name or any alias; the lookup matches whichever
    /// is canonical at runtime.
    ///
    /// References:
    /// - **drink**: US standard drink = 14 g of pure ethanol per
    ///   [NIAAA](https://www.niaaa.nih.gov/alcohols-effects-health/overview-alcohol-consumption/what-standard-drink).
    private static let unitAliasTable: [String: [UnitAlias]] = [
        "alcohol": [
            UnitAlias(label: "drink", amountPerUnit: 14, unit: "g"),
        ],
        "ethanol": [
            UnitAlias(label: "drink", amountPerUnit: 14, unit: "g"),
        ],
    ]

    /// Unit aliases applicable to this substance — the user's own
    /// (``customUnitAliases``) ahead of the curated conventions, looked up by
    /// canonical name or any alias. Empty for substances with neither.
    var unitAliases: [UnitAlias] {
        let candidates = [name.lowercased()] + aliases.map { $0.lowercased() }
        let curated = candidates.lazy.compactMap { Self.unitAliasTable[$0] }.first ?? []
        return customUnitAliases + curated
    }

    /// By-volume dose-input capability (concentration × measured volume → canonical
    /// mass), looked up by canonical name or alias. Non-nil only for the curated
    /// adopters (alcohol in v1); the dose form renders the by-volume panel when set.
    var byVolumeDosing: ByVolumeDosing? {
        ByVolumeCatalog.capability(forAnyOf: [name] + aliases)
    }

    /// Convert an amount-in-some-unit to this substance's native unit for the
    /// given route, against the route's **default-salt** unit.
    ///
    /// Route-only overload (see the overload-family note on
    /// ``unit(for:saltForm:)``): it resolves the reference unit via the default
    /// salt by design. For substances whose salts share a unit this is exact; it
    /// only mis-targets when a *specific* selected salt uses a different unit
    /// than the route default. Reach for
    /// ``convert(amount:from:toRoute:saltForm:)`` on any surface that converts
    /// for a chosen/logged salt.
    func convert(amount: Double, from unit: String, toRoute route: RouteOfAdministration) -> Double? {
        convert(amount: amount, from: unit, toRoute: route, saltForm: nil)
    }

    /// Salt-aware unit conversion: resolves the reference unit via
    /// ``unit(for:saltForm:)`` so a salt whose unit differs from the route
    /// default (elemental mg vs compound mg, or an IU-dosed form) converts
    /// against its *own* unit. Tries direct mass conversion first, then falls
    /// back to substance-specific aliases (e.g. "drink" → grams of ethanol).
    /// Returns `nil` if no conversion path exists. A `nil` (or unknown) salt
    /// label falls back to the route's default-salt unit, so the route-only
    /// ``convert(amount:from:toRoute:)`` delegates here unchanged.
    func convert(
        amount: Double,
        from unit: String,
        toRoute route: RouteOfAdministration,
        saltForm: String?,
    ) -> Double? {
        let targetUnit = self.unit(for: route, saltForm: saltForm)
        if let direct = DoseUnit.convert(amount, from: unit, to: targetUnit) {
            return direct
        }
        if let alias = unitAliases.first(where: { $0.label == unit }) {
            let canonicalAmount = amount * alias.amountPerUnit
            return DoseUnit.convert(canonicalAmount, from: alias.unit, to: targetUnit) ?? canonicalAmount
        }
        return nil
    }
}
