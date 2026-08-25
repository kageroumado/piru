import Foundation

// Metabolism read models. The query that builds them is
// `SubstanceStore+Pharmacology.metabolism(forSubstanceName:)`.
extension SubstanceStore {
    /// One metabolism row — an enzyme/pathway and (optionally) the metabolite it
    /// produces — joined to its source + citation. Surfaced alongside
    /// ``PKRouteHit`` in the Pharmacokinetics disclosure.
    struct MetabolismHit: Identifiable, Hashable {
        let id: Int64
        let enzyme: String
        /// The **enzyme's** share of the parent's clearance — not how much
        /// metabolite appears. See ``formationFractionPct``.
        let fractionOfClearancePct: Double?
        let metaboliteName: String?
        /// The metabolite's own substance name, when we carry it as one — most
        /// of the ones that matter (O-DSMT, oxymorphone, morphine, paliperidone,
        /// psilocin, norketamine, MDA). Non-nil means the row can link to a real
        /// detail screen, and that the metabolite's own sourced half-life, dose
        /// ranges and durations are available instead of the scalar columns here.
        let metaboliteSubstanceName: String?
        let metaboliteActive: Bool?
        let metabolitePotencyVsParentPct: Double?
        /// What ``metabolitePotencyVsParentPct`` measures. Never assume clinical
        /// potency: the column has also carried receptor-affinity ratios (tramadol
        /// → M1 reads 20000% from a "~200× MOR affinity" source). Anything that
        /// multiplies by the potency must branch on this.
        let metabolitePotencyBasis: MetabolitePotencyBasis?
        /// The receptor/transporter the potency ratio was measured at ("MOR",
        /// "NET"…). A basis alone doesn't make two ratios comparable — tramadol
        /// → M1 is 20000% at MOR, quetiapine → norquetiapine 10000% at NET.
        let metabolitePotencyTarget: String?
        /// Whether the metabolite is the same drug at a different strength.
        /// Outranks the potency number: only a ``MetaboliteMechanism/scaled``
        /// mechanism with a ``MetabolitePotencyBasis/clinical`` basis may scale
        /// the parent's effect, and a rendered potency that fails that gate
        /// must carry its basis and target inline (tramadol → M1 reads 20000%
        /// at MOR with no clinical ratio existing at all).
        let metaboliteMechanismVsParent: MetaboliteMechanism
        /// The metabolite's own elimination half-life (minutes) — the field a
        /// two-compartment parent → metabolite model needs.
        let metaboliteHalfLifeMinutes: Double?
        /// Percent of an administered parent dose that becomes this metabolite.
        let formationFractionPct: Double?
        /// The route of administration this row applies to, when route-specific
        /// (e.g. oral vs inhaled THC → 11-OH-THC). Nil = route-agnostic.
        let route: String?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    /// What a ``MetabolismHit/metabolitePotencyVsParentPct`` value actually
    /// measures. Only ``clinical`` is safe to treat as an effect multiplier —
    /// and only once ``MetaboliteMechanism`` allows scaling at all.
    enum MetabolitePotencyBasis: String, Hashable, Sendable {
        case clinical
        case receptorAffinity = "receptor_affinity"
        case inVitro = "in_vitro"
        case unknown
    }

    /// Whether a metabolite is pharmacologically the parent at a different
    /// strength, or a different drug that the parent happens to produce.
    ///
    /// `unknown` is the default rather than `nil` on purpose: "not yet
    /// classified" and "known not to be a scaled copy" must not be
    /// indistinguishable to a caller, and neither may scale the parent's effect.
    enum MetaboliteMechanism: String, Hashable, Sendable {
        /// Same mechanism, different strength — nordazepam to diazepam. A
        /// potency ratio converts cleanly. Prodrugs count: the metabolite *is*
        /// the drug (psilocybin → psilocin).
        case scaled
        /// Different pharmacology, not a stronger parent — tramadol → M1,
        /// trazodone → mCPP, quetiapine → norquetiapine. Disclose it as its own
        /// agent; never fold it into the parent's curve.
        case divergent
        case unknown
    }
}
