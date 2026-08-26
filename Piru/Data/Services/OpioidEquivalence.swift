import Foundation

/// Oral **morphine-milligram-equivalent (MME)** data for the opioid conversion
/// tool, resolved from the bundled DB's `opioid_mme`. Factors are morphine-mg
/// per **1 mg** of the named opioid.
///
/// Conversion is deliberately **structural, not a flat lookup**: only the pure
/// full-agonist opioids carry a linear factor. Methadone (dose-dependent,
/// nonlinear), transdermal fentanyl (dosed in mcg/hr, no oral-mg analogue), and
/// buprenorphine (partial agonist with a respiratory-depression ceiling) are
/// carried as *un-convertible* cases so the tool can never back-calculate a
/// dangerous dose for them.
///
/// The factors are data and live in the DB; the **explanation** for each
/// un-convertible case is UI copy and stays here, keyed by
/// ``Convertibility`` — so it is localized like every other string the reader
/// sees, and a row can never ship an untranslated reason.
nonisolated struct OpioidEquivalence: Identifiable {
    let name: String
    let displayName: String
    let convertibility: Convertibility
    /// Morphine-mg equivalent to 1 mg of this opioid. `nil` for every
    /// un-convertible case — the resolver refuses to read a factor for a row
    /// that is not ``Convertibility/linear``, so this is never a stale number.
    let mmePerMg: Double?

    var id: String {
        name
    }

    enum Convertibility: String {
        /// Pure full µ-agonist with a stable oral MME factor (morphine-mg per 1 mg).
        case linear
        /// Nonlinear, dose-dependent potency (methadone) — never auto-convert.
        case nonlinear
        /// Dosed in mcg/hr, not mg (transdermal fentanyl) — separate unit space.
        case transdermal
        /// Partial agonist with a ceiling — MME does not apply (buprenorphine).
        case excluded
    }

    /// The name to show in the converter's picker. Transdermal fentanyl shares a
    /// substance row with every other fentanyl route, so the route it is dosed by
    /// is what the label has to disambiguate.
    var pickerLabel: String {
        switch convertibility {
        case .transdermal: String(localized: "\(displayName) (transdermal)")
        default: displayName
        }
    }

    /// Why this opioid can't be linearly converted, for the un-convertible cases.
    var unconvertibleReason: LocalizedStringResource? {
        switch convertibility {
        case .linear:
            nil
        case .nonlinear:
            "Methadone's half-life is long and variable, and its peak effect on breathing arrives later and lasts longer than its peak pain relief — so a converted dose can look adequate while the risk is still building. CDC publishes a single factor for population-level accounting; Piru will not use it to convert a dose. This one belongs to a clinician."
        case .transdermal:
            "Transdermal fentanyl is dosed in micrograms per hour — a rate, not a mass, so it shares no unit space with the mg-based table (CDC gives 2.4 MME per mcg/hr). Absorption also changes with heat and other factors."
        case .excluded:
            "Buprenorphine is a partial agonist with a ceiling on its effect on breathing, so risk doesn't scale the way a full agonist's does. CDC excludes it from MME entirely and says it should not be counted toward a daily total."
        }
    }

    /// The oral MME of `doseMg` of this opioid (linear opioids only).
    func mme(forDoseMg doseMg: Double) -> Double? {
        guard doseMg > 0, let factor = mmePerMg else { return nil }
        return doseMg * factor
    }

    /// `doseMg` of this opioid expressed as an equivalent dose of `target`,
    /// routed through morphine (MME) as the common unit. `nil` unless both
    /// sides are linear.
    func equivalentDose(forDoseMg doseMg: Double, in target: OpioidEquivalence) -> Double? {
        guard let mme = mme(forDoseMg: doseMg),
              let targetFactor = target.mmePerMg, targetFactor > 0 else { return nil }
        return mme / targetFactor
    }
}

nonisolated extension OpioidEquivalence {
    /// CDC daily-MME risk reference bands (per day, oral morphine equivalents).
    static let cautionMMEPerDay: Double = 50
    static let highRiskMMEPerDay: Double = 90
}
