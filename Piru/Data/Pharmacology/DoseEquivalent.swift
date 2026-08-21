import Foundation

/// Turning "640 ng/mL" into "≈ 480 mg oral" — the dose that reaches a named
/// plasma concentration.
///
/// One relation, the definition of volume of distribution:
///
///     C = F · Dose / (Vd · weight)   →   Dose = C · Vd · weight / F
///
/// It describes the concentration once distribution is complete, which is what
/// makes it right for an **absorption-limited** route and wrong for an
/// intravenous bolus. Given orally, a drug is still being absorbed while it
/// distributes, so peak plasma sits at the post-distribution level this
/// predicts. Pushed into a vein it does not: propofol's plasma peak is
/// enormously higher than `F·D/Vd` because the effect happens before the drug
/// has reached the tissues its Vd counts, and the relation understates the
/// induction dose by three- to fivefold. So intravenous is excluded, and that
/// exclusion is the whole reason this can be shown at all.
///
/// It is an estimate and reads as one: rounded hard, prefixed "≈", and carrying
/// the body weight it assumed.
enum DoseEquivalent {
    /// Concentration units the conversion understands, as milligrams per litre.
    ///
    /// `mM` is absent deliberately: converting a molar concentration needs the
    /// molar mass, and for lithium it needs to know whether the dose is quoted
    /// as the element or the carbonate. A wrong answer there is worse than none.
    static func milligramsPerLitre(_ value: Double, unit: String) -> Double? {
        // The unit string carries a suffix on some rows ("ng/mL psilocin").
        let normalized = unit.lowercased()
            .replacingOccurrences(of: "\u{03bc}", with: "\u{00b5}")
        switch true {
        case normalized.hasPrefix("pg/ml"): return value * 1e-6
        case normalized.hasPrefix("ng/ml"): return value * 1e-3
        case normalized.hasPrefix("\u{00b5}g/ml"), normalized.hasPrefix("ug/ml"): return value
        case normalized.hasPrefix("mg/l"): return value
        default: return nil
        }
    }

    /// Effect descriptions the conversion refuses.
    ///
    /// A **fatal or post-mortem** concentration must never be turned into a
    /// dose: the number would read as the dose that kills, which is not a thing
    /// this app prints, and post-mortem redistribution makes it wrong anyway.
    /// A **whole-blood** concentration is not a plasma concentration — the
    /// blood:plasma ratio is drug-specific and not recorded here.
    static func isConvertible(effect: String) -> Bool {
        let text = effect.lowercased()
        let refusals = ["fatal", "lethal", "post-mortem", "postmortem", "antemortem", "whole blood", "overdose death"]
        return !refusals.contains { text.contains($0) }
    }

    /// The dose reaching `concentration` by `route`, in milligrams.
    ///
    /// - Parameters:
    ///   - vdLitresPerKg: the drug's volume of distribution.
    ///   - bioavailabilityPct: the fraction of the dose reaching circulation by
    ///     this route.
    ///   - weightKg: the reader's body weight, or the population default.
    static func milligrams(
        concentrationMgPerL concentration: Double,
        vdLitresPerKg: Double,
        bioavailabilityPct: Double,
        weightKg: Double,
    ) -> Double? {
        guard concentration > 0, vdLitresPerKg > 0, weightKg > 0,
              bioavailabilityPct > 0, bioavailabilityPct <= 100
        else { return nil }
        return concentration * vdLitresPerKg * weightKg / (bioavailabilityPct / 100)
    }

    /// A dose-ladder unit as a multiplier into milligrams, or `nil` when the
    /// ladder is in something the comparison cannot use (`mL`, `g`, a count).
    static func milligramScale(ofDoseUnit unit: String) -> Double? {
        let normalized = unit.lowercased().replacingOccurrences(of: "\u{03bc}", with: "\u{00b5}")
        switch true {
        // "mg THC" and the like: the qualifier names what is being weighed,
        // and the unit is still milligrams.
        case normalized.hasPrefix("mg"): return 1
        case normalized.hasPrefix("\u{00b5}g"), normalized.hasPrefix("ug"), normalized.hasPrefix("mcg"):
            return 0.001
        default: return nil
        }
    }

    /// Whether a derived dose is close enough to the substance's own ladder to
    /// be worth printing.
    ///
    /// Generous on both sides — this is not a range check, it is a check that
    /// the model and the curated data are describing the same drug. A threshold
    /// effect legitimately sits below the light dose, and a toxicity endpoint
    /// legitimately sits above the heavy one; six times the heavy dose does not.
    static func agreesWithLadder(_ milligrams: Double, low: Double, high: Double) -> Bool {
        milligrams >= low * 0.3 && milligrams <= high * 3
    }

    /// `milligrams` at two significant figures — the precision the estimate
    /// actually carries. Printing "483.84 mg" from a Vd quoted to two figures
    /// claims a precision nothing in the chain has.
    static func rounded(_ milligrams: Double) -> Double {
        guard milligrams > 0 else { return 0 }
        let scale = pow(10, floor(log10(milligrams)) - 1)
        return (milligrams / scale).rounded() * scale
    }
}
