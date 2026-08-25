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
        /// Outranks the potency number; see ``canScaleParentEffect``.
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
        let notes: String?

        /// Whether this metabolite's potency may be used to scale the parent's
        /// effect — the single gate any modelling must pass, and equally the
        /// gate on **displaying a bare "N× parent"**. A reader assumes a potency
        /// figure means clinical strength; only a row passing this actually
        /// does.
        ///
        /// Three rules follow for any view that renders
        /// ``metabolitePotencyVsParentPct``, because a large number reads as
        /// authoritative regardless of what produced it:
        ///
        /// 1. A row failing this gate must carry its basis and target inline —
        ///    "200× µ-opioid *binding affinity*, not clinical potency" — or show
        ///    no figure. Tramadol → M1 is the worst case in the catalog: 20000%
        ///    at MOR, with no clinical ratio existing at all to sit beside it.
        /// 2. Never mix or average bases for the same metabolite. Oxycodone →
        ///    oxymorphone is 4000% by affinity and 1000% clinically; a mean of
        ///    those answers neither question. Group by basis, or show only the
        ///    clinical row.
        /// 3. A large potency whose basis is ``MetabolitePotencyBasis/unknown``
        ///    gets no number at all — five rows sit at ≥1000% with nobody having
        ///    recorded what was measured. Describe the metabolite instead.
        ///
        /// A ``MetaboliteMechanism/divergent`` metabolite is generally better
        /// described than quantified: its number, whatever the basis, does not
        /// summarize what actually changes.
        ///
        /// Both conditions are load-bearing. ``MetaboliteMechanism/scaled``
        /// establishes that one number *can* relate the two molecules at all,
        /// and ``MetabolitePotencyBasis/clinical`` that this particular number
        /// is the one that does. Tramadol → M1 fails the first (M1 is a strong
        /// opioid; tramadol is an SNRI plus a weak one, so no scalar maps
        /// between them — which is why no clinical ratio for M1 exists to look
        /// up). Oxycodone → oxymorphone's 4000% row fails the second: real, but
        /// a receptor-affinity ratio, and using it in place of the 1000%
        /// clinical figure overstates the metabolite fourfold.
        var canScaleParentEffect: Bool {
            metaboliteMechanismVsParent == .scaled && metabolitePotencyBasis == .clinical
        }
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
    /// indistinguishable to a caller, and both must fail ``canScaleParentEffect``.
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
