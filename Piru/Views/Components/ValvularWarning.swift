import Foundation

/// The heart-valve warning: the substance, or the class it belongs to, activates
/// the 5-HT2B receptor, the mechanism of drug-induced valvular heart disease.
///
/// Three independent bases, any one sufficient. The substance's own binding
/// rows decide it when they engage the receptor (``engagesAntitarget(_:)``). An
/// active metabolite's rows decide it for a parent that is weak itself:
/// fenfluramine binds 5-HT2B at ~4 µM, and norfenfluramine, which it is cleared
/// to, is the agonist that damaged valves. A class declaration reaches the
/// members that were never assayed, which is most of every class that carries
/// the risk. Shown on the substance page at every detail level, whether or not
/// the substance has transporter data.
struct ValvularWarning: Hashable {
    /// The `class_warnings.kind` this warning reads.
    static let kind = "valvulopathy-5ht2b"

    /// The substance's own binding rows engage 5-HT2B.
    let engagedByBindings: Bool
    /// The first active metabolite (by name) whose own rows engage 5-HT2B.
    let engagingMetabolite: String?
    /// The class declaration that reaches this substance, when one does.
    let declaringClass: ClassWarning?

    /// `nil` unless at least one basis holds.
    static func resolve(
        bindings: [BindingHit],
        metabolites: [MetaboliteBindings] = [],
        classWarnings: [ClassWarning],
    ) -> ValvularWarning? {
        let engaged = engagesAntitarget(bindings)
        let metabolite = metabolites.first { engagesAntitarget($0.bindings) }?.name
        let declaring = classWarnings.first { $0.kind == kind }
        guard engaged || metabolite != nil || declaring != nil else { return nil }
        return ValvularWarning(engagedByBindings: engaged, engagingMetabolite: metabolite, declaringClass: declaring)
    }

    /// Whether the bindings engage 5-HT2B strongly enough for the warning.
    ///
    /// **Partial agonism counts.** Pergolide, cabergoline and norfenfluramine are partial agonists at
    /// this receptor and are precisely the drugs that caused valvular fibrosis; reading only `agonist`
    /// missed 25B-NBOMe and 25C-NBOMe at Kᵢ 0.5 and 1.1 nM. Antagonists never count — cariprazine,
    /// phentermine and viloxazine block the receptor.
    ///
    /// **Potency counts too**, on the app's own ``ReceptorStrength`` bands, at moderate or better.
    /// Without that floor 4-fluoroamphetamine qualifies on a 14.4 µM EC₅₀ — three orders of magnitude
    /// above any dose — and a heart-valve warning that appears on anything ever assayed at 5-HT2B
    /// teaches the reader to ignore it. A row with no measurement falls back to its curated
    /// ``BindingHit/affinityTier``, so a hand-graded row still speaks; a row with neither says nothing.
    static func engagesAntitarget(_ bindings: [BindingHit]) -> Bool {
        bindings.contains { hit in
            guard hit.target.uppercased().hasPrefix("5-HT2B"),
                  hit.action == "agonist" || hit.action == "partialAgonist" else { return false }
            let tier = ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm)
                ?? hit.affinityTier
            return (tier ?? 0) >= 2
        }
    }
}
