import Foundation

/// Oral **morphine-milligram-equivalent (MME)** data for the opioid conversion
/// tool. Factors are morphine-mg per **1 mg** of the named opioid, from the
/// CDC Clinical Practice Guideline for Prescribing Opioids for Pain — United
/// States, 2022 (MMWR RR-71 No. 3), CDC's sole official MME resource.
///
/// Conversion is deliberately **structural, not a flat lookup**: only the pure
/// full-agonist opioids carry a linear factor. Methadone (dose-dependent,
/// nonlinear), transdermal fentanyl (dosed in mcg/hr, no oral-mg analogue), and
/// buprenorphine (partial agonist with a respiratory-depression ceiling — CDC
/// deliberately omits it) are modelled as *un-convertible* cases so the tool
/// can never back-calculate a dangerous dose for them.
struct OpioidEquivalence: Identifiable {
    let name: String
    let displayName: String
    let convertibility: Convertibility

    var id: String {
        name
    }

    enum Convertibility {
        /// Pure full µ-agonist with a stable oral MME factor (morphine-mg per 1 mg).
        case linear(mmePerMg: Double)
        /// Nonlinear, dose-dependent potency (methadone) — never auto-convert.
        case nonlinear(reason: LocalizedStringResource)
        /// Dosed in mcg/hr, not mg (transdermal fentanyl) — separate unit space.
        case transdermal(reason: LocalizedStringResource)
        /// Partial agonist with a ceiling — MME does not apply (buprenorphine).
        case excluded(reason: LocalizedStringResource)
    }

    /// Morphine-mg equivalent to 1 mg of this opioid, or `nil` for the
    /// un-convertible (nonlinear / transdermal / excluded) cases.
    var mmePerMg: Double? {
        if case let .linear(factor) = convertibility { return factor }
        return nil
    }

    /// Why this opioid can't be linearly converted, for the un-convertible cases.
    var unconvertibleReason: LocalizedStringResource? {
        switch convertibility {
        case .linear: nil
        case let .nonlinear(reason), let .transdermal(reason), let .excluded(reason): reason
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

extension OpioidEquivalence {
    /// CDC 2022 oral MME factors + the structurally un-convertible opioids.
    /// Morphine is the reference standard (factor 1.0) and leads the list.
    static let table: [OpioidEquivalence] = [
        OpioidEquivalence(name: "morphine", displayName: String(localized: "Morphine"), convertibility: .linear(mmePerMg: 1.0)),
        OpioidEquivalence(name: "codeine", displayName: String(localized: "Codeine"), convertibility: .linear(mmePerMg: 0.15)),
        OpioidEquivalence(name: "hydrocodone", displayName: String(localized: "Hydrocodone"), convertibility: .linear(mmePerMg: 1.0)),
        OpioidEquivalence(name: "oxycodone", displayName: String(localized: "Oxycodone"), convertibility: .linear(mmePerMg: 1.5)),
        OpioidEquivalence(name: "oxymorphone", displayName: String(localized: "Oxymorphone"), convertibility: .linear(mmePerMg: 3.0)),
        OpioidEquivalence(name: "hydromorphone", displayName: String(localized: "Hydromorphone"), convertibility: .linear(mmePerMg: 5.0)),
        OpioidEquivalence(name: "tramadol", displayName: String(localized: "Tramadol"), convertibility: .linear(mmePerMg: 0.2)),
        OpioidEquivalence(name: "tapentadol", displayName: String(localized: "Tapentadol"), convertibility: .linear(mmePerMg: 0.4)),
        OpioidEquivalence(
            name: "methadone",
            displayName: String(localized: "Methadone"),
            convertibility: .nonlinear(reason: "Methadone's potency rises with dose (nonlinear) and its long, variable half-life makes any single factor unsafe. CDC removed its conversion factor. Never back-calculate a methadone dose from MME — this must be done by a clinician."),
        ),
        OpioidEquivalence(
            name: "fentanyl",
            displayName: String(localized: "Fentanyl (transdermal)"),
            convertibility: .transdermal(reason: "Transdermal fentanyl is dosed in micrograms per hour, not milligrams — it has no oral-mg equivalent (CDC uses ≈ 2.4 MME per mcg/hr). It can't share the mg-based table."),
        ),
        OpioidEquivalence(
            name: "buprenorphine",
            displayName: String(localized: "Buprenorphine"),
            convertibility: .excluded(reason: "Buprenorphine is a partial agonist with a ceiling on respiratory depression, so overdose risk doesn't scale linearly. CDC deliberately excludes it — MME does not apply."),
        ),
    ]

    /// CDC daily-MME risk reference bands (per day, oral morphine equivalents).
    static let cautionMMEPerDay: Double = 50
    static let highRiskMMEPerDay: Double = 90
}
