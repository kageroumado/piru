import Foundation

/// A benzodiazepine paired with its cited diazepam-equivalence, for the
/// converter tool. Loaded in one batched query by
/// ``SubstanceStore/benzoEquivalences()`` (highest-priority enabled source per
/// substance), so the converter never N+1-resolves every benzo's detail record.
///
/// Equivalences are **approximate and contested** — Ashton, manufacturer, and
/// clinical tables disagree — so the converter surfaces the cited
/// ``DiazepamEquivalent/displayText`` and a "tables disagree" band alongside
/// every number, never a bare milligram presented as clinical truth.
struct BenzoEquivalence: Identifiable, Hashable {
    /// Canonical name — the key for half-life and library joins.
    let name: String
    /// User-facing display name.
    let displayName: String
    /// The cited equivalence row (source prose + the dose/diazepam mg parsed from it).
    let equivalent: DiazepamEquivalent

    var id: String {
        name
    }

    /// Milligrams of diazepam equivalent to **1 mg** of this benzodiazepine
    /// (e.g. alprazolam ≈ 20, since 0.5 mg ≈ 10 mg diazepam). `nil` when the
    /// cited prose didn't parse to two usable numbers.
    var diazepamPerMg: Double? {
        guard let dose = equivalent.doseMg, dose > 0,
              let diazepam = equivalent.equivalentDiazepamMg, diazepam > 0 else { return nil }
        return diazepam / dose
    }
}

extension BenzoEquivalence {
    /// The diazepam-equivalent milligrams of `doseMg` of this benzodiazepine.
    func diazepamEquivalent(forDoseMg doseMg: Double) -> Double? {
        guard doseMg > 0, let ratio = diazepamPerMg else { return nil }
        return doseMg * ratio
    }

    /// `doseMg` of this benzodiazepine expressed as an equivalent dose of
    /// `target`, routed through diazepam as the common unit. `nil` if either
    /// side's equivalence didn't parse. This is the cross-taper conversion
    /// (A → diazepam → B).
    func equivalentDose(forDoseMg doseMg: Double, in target: BenzoEquivalence) -> Double? {
        guard let diazepam = diazepamEquivalent(forDoseMg: doseMg),
              let targetRatio = target.diazepamPerMg, targetRatio > 0 else { return nil }
        return diazepam / targetRatio
    }
}
