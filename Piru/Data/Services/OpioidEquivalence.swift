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
///
/// No daily-MME risk band belongs here. CDC 2022 removed the 90 MME/day
/// threshold its 2016 guideline carried, and reframed 50 as a point to "pause
/// and carefully reassess" while stating the dosage recommendations "are not
/// intended to be used as an inflexible, rigid standard of care." A band that
/// sorts a day's total into caution/high-risk asserts the rigidity the source
/// withdrew — and reads as a verdict on the reader besides.
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
            "Methadone's half-life is long and variable, and its effect on breathing peaks later than its pain relief. CDC publishes a single population factor for it; Piru shows no figure."
        case .transdermal:
            "Transdermal fentanyl is dosed in micrograms per hour, a rate rather than a mass, so it has no figure in this mg-based table."
        case .excluded:
            "CDC excludes buprenorphine from MME."
        }
    }

    /// The oral MME of `doseMg` of this opioid (linear opioids only).
    func mme(forDoseMg doseMg: Double) -> Double? {
        guard doseMg > 0, let factor = mmePerMg else { return nil }
        return doseMg * factor
    }
}
