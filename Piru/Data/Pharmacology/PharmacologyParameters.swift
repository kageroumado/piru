import Foundation

/// Resolved pharmacology inputs for the absolute-exposure → receptor-occupancy pipeline (the
/// pharmacology axis's Foundation A), produced by ``SubstanceStore/pharmacologyParameters(forSubstanceName:)``.
///
/// It bundles what the engine needs to turn a *dose* into an *occupancy curve*: the molar mass, the
/// best graded volume of distribution + bioavailability + half-life, and the engaged targets with
/// their half-saturation constants — each value carrying the confidence tier it was graded at, so the
/// engine can run on verified numbers and the UI can badge how much to trust the prediction.
nonisolated struct PharmacologyParameters {
    /// The `substance_flags.flag` values the engine reads. Spelled once here so a resolver and a
    /// pipeline row can never drift apart on a string literal.
    enum Flag {
        /// Metabolites suppress tryptophan hydroxylase, routing the substance onto the weeks-scale
        /// synthesis pool instead of the days-scale transporter reset. See ``suppressesSerotoninSynthesis``.
        static let suppressesSerotoninSynthesis = "suppresses-serotonin-synthesis"
        /// Pressed and sold as MDMA/"molly" while being a DAT-dominant reuptake blocker. Read by
        /// ``MonoamineProfile``, not by the tolerance engine — it lives here so every
        /// `substance_flags` value is spelled in one place.
        static let missoldAsMDMA = "missold-as-mdma"
    }

    /// Which constant a target's ``TargetEngagement/halfMaxNanomolar`` is, by mechanism.
    enum HalfMaxKind: String {
        /// Binding affinity (agonist / antagonist / PAM).
        case ki
        /// Functional release potency (releaser / substrate — amphetamine, MDMA).
        case ec50
        /// Uptake-inhibition potency (reuptake blocker — methylphenidate, cocaine).
        case ic50
    }

    /// One engaged receptor/transporter and the half-saturation constant that drives its occupancy.
    struct TargetEngagement: Identifiable, Hashable {
        let target: String
        let action: BindingAction
        /// Half-saturation constant in **nanomolar** — Kᵢ, EC₅₀, or IC₅₀ per ``kind``. Compared
        /// against the free molar concentration (×1e9) in ``PKModel/occupancy(concentration:halfMax:hillCoefficient:)``.
        let halfMaxNanomolar: Double
        let kind: HalfMaxKind
        let confidence: ConfidenceTier
        /// The dataset/source slug this value came from (`peer-review-primary`, `piru-curated`, …).
        let sourceSlug: String
        /// The specific paper this value was measured in (`doi:…` or `pmid:…`), when cited — the
        /// identity that lets a consumer take a coherent DAT/NET/SERT triple from ONE assay rather than
        /// mixing potencies across labs (only ratios *within* one assay are physically meaningful).
        let citationKey: String?
        /// Study species (`human`/`rat`/…), when recorded — part of assay identity.
        let species: String?
        var id: String {
            "\(target)-\(action.rawValue)-\(kind.rawValue)"
        }

        /// Provenance (`sourceSlug`/`citationKey`/`species`) defaults to "unknown" so synthetic (test)
        /// engagements need not supply it; the resolver always passes the real assay identity.
        init(
            target: String, action: BindingAction, halfMaxNanomolar: Double, kind: HalfMaxKind,
            confidence: ConfidenceTier, sourceSlug: String = "", citationKey: String? = nil, species: String? = nil,
        ) {
            self.target = target
            self.action = action
            self.halfMaxNanomolar = halfMaxNanomolar
            self.kind = kind
            self.confidence = confidence
            self.sourceSlug = sourceSlug
            self.citationKey = citationKey
            self.species = species
        }
    }

    /// An active metabolite the parent produces, carried so the tolerance engine can extend a dose's
    /// occupancy tail past the parent's own elimination (K.5). The load-bearing case is diazepam →
    /// nordazepam (t½ ≈ 100 h, equipotent at GABA-A): without it, diazepam's integrated tolerance and
    /// its withdrawal-onset window are both computed from the parent's ~2-day clock instead of the
    /// metabolite's ~5-day one.
    struct MetaboliteContributor: Identifiable, Hashable {
        let metaboliteName: String
        /// The metabolite's own elimination half-life (minutes) — required; a contributor is only built
        /// when a half-life is known (the PK shape needs it).
        let halfLifeMinutes: Double
        /// Percent of a parent dose that becomes this metabolite.
        let formationFractionPct: Double?
        /// The metabolite's potency relative to the parent (percent).
        let potencyVsParentPct: Double?
        /// What ``potencyVsParentPct`` measures (`clinical` / `receptor_affinity` / …) — a non-clinical
        /// basis floors the folded contributor's confidence.
        let potencyBasis: String?
        /// `scaled` / `divergent` / `unknown`. Only `scaled` may be folded into the parent's curve.
        let mechanismVsParent: String

        var id: String {
            metaboliteName
        }

        /// Whether this metabolite may be **summed into** the parent's tolerance curve (K.5.1). Only a
        /// `scaled` metabolite (same mechanism, different strength — nordazepam to diazepam) qualifies;
        /// a `divergent` one (tramadol → M1) has a qualitatively different mechanism that no scalar maps
        /// parent occupancy onto, and `unknown` is treated as divergent (conservative).
        var canFold: Bool {
            mechanismVsParent == "scaled"
        }

        /// Concentration prefactor relative to the parent: formation fraction × potency ratio. Each
        /// missing factor defaults to 100% — a fully-formed, equipotent metabolite, the conservative
        /// "counts as much as the parent" reading (nordazepam: 100% × 100% = 1.0).
        var foldPrefactor: Double {
            let ff = (formationFractionPct ?? 100) / 100
            let pp = (potencyVsParentPct ?? 100) / 100
            return ff * pp
        }

        /// Whether the potency ratio is a clinical equivalence (safe to trust) rather than an affinity
        /// constant — a non-clinical basis floors the folded contributor's confidence to `.low`.
        var isClinicalBasis: Bool {
            potencyBasis == "clinical"
        }
    }

    let molarMassGramsPerMole: Double?
    let vdLPerKg: Double?
    /// Oral bioavailability as a fraction in `(0, 1]`.
    ///
    /// When no F was measured the resolver defaults this to **1.0** (full
    /// fraction-absorbed) rather than leaving it nil — see
    /// ``bioavailabilityConfidence``. Absolute oral F is "definitionally
    /// underivable without an IV arm" for most recreational drugs (per the
    /// pharmacology-evidence discipline), and the stored Vd for such drugs is
    /// already an *apparent* Vd (V/F) — so `C = F·dose/((V/F)·wt)` is consistent
    /// with `F = 1` (the F cancels), and a separately-invented F would double-count
    /// it. Defaulting to 1 keeps occupancy computable (it errs toward *showing*
    /// tolerance, which is the safety-positive direction) while the confidence
    /// badge marks the prediction unverified.
    let bioavailabilityFraction: Double?
    /// Confidence of ``bioavailabilityFraction``: the source row's grade when F was
    /// measured, `.unverified` when it was defaulted to 1.0.
    let bioavailabilityConfidence: ConfidenceTier
    /// Active-fraction multiplier applied to a logged dose before the exposure math:
    /// **mg of active compound per mg of the logged substance**.
    ///
    /// `1.0` for a pure compound (no scaling). For a *preparation* routed to its
    /// active constituent (Cannabis→THC, Mushrooms→psilocybin, Kratom→mitragynine —
    /// see ``SubstanceStore/preparationRouting``) the pharmacology comes from the
    /// active compound's row and this scales the logged plant/preparation mass to
    /// active-compound mass. Every dose→concentration site multiplies by it.
    let doseScale: Double
    /// Confidence of ``doseScale`` — `.high` for a pure compound (no scaling),
    /// lower for an *estimated* preparation content fraction (potency varies by
    /// strain/species). Caps ``occupancyConfidence`` like the other inputs.
    let doseScaleConfidence: ConfidenceTier
    let halfLifeMinutes: Double?
    /// Time-to-peak (Tmax) in **minutes** for the coherent PK row, when the source carries one — used
    /// to wire a *real* absorption rate `ka` (via ``PKModel/estimateKa(timeToPeak:ke:)``) instead of
    /// the `4·ke` elimination-derived default, so a fast-onset insufflated stimulant and a slow oral
    /// extended-release no longer share an absorption shape (`Specs/tolerance-faithful-model-improvements.md`
    /// §3). `nil` ⇒ the engine falls back to ``PKModel/defaultKa(ke:)``.
    let tmaxMinutes: Double?
    /// Confidence of ``tmaxMinutes`` — the source PK row's grade when a Tmax was read, `.unverified`
    /// (the neutral floor) when none was; folded into the contributor confidence so a guessed onset
    /// badges the prediction down.
    let tmaxConfidence: ConfidenceTier
    /// Study **species** of the coherent PK row the Vd/half-life were read from (`human`, `rat`,
    /// `pig`, …), lowercased, or `nil` when unstated / human. Set by the resolver after interspecies
    /// allometric scaling (``SubstanceStore/scaledToHuman(_:)``): a non-human row keeps its
    /// species-invariant Vd/kg but has its confidence floored, so this string is the honest provenance
    /// flag behind a low ``vdConfidence`` — the app can caption "predicted from rat kinetics".
    let pkSpecies: String?
    /// Confidence of the resolved ``vdLPerKg`` (`.unverified` when no graded Vd row exists).
    let vdConfidence: ConfidenceTier
    /// The substance's **reference "heavy" dose** in mg — the denominator of the dose-relative
    /// *escalation* factor (`dose ÷ referenceDoseMg`) that gates the deep tolerance layer.
    ///
    /// Resolved from the substance's own primary dose ladder (oral first, else the first route with a
    /// range): `heavy ?? strong.upperBound ?? common.upperBound`. Expressed in the **logged
    /// preparation's** mg (the same units the logged dose is in), so the escalation ratio carries no
    /// `doseScale`. `nil` when the substance has no dose ladder — which keeps the escalation factor at
    /// `0` and the deep gate closed (the conservative fallback: no deep tolerance without evidence of
    /// how much constitutes "heavy").
    let referenceDoseMg: Double?
    /// Whether this substance suppresses **serotonin synthesis** (TPH), the per-substance data field
    /// that splits the SERT releaser class onto two recovery clocks (`Specs/tolerance-faithful-model.md`
    /// §3.4). `true` for the methylenedioxy entactogens (MDMA, MDA, …) whose metabolites down-regulate
    /// the synthesis machinery — recovery waits weeks (the slow synthesis pool). `false` for the
    /// cathinone releasers (mephedrone/4-MMC) which spare synthesis and reset in days on
    /// receptor/transporter resensitisation alone. Resolved from the substance's
    /// `suppresses-serotonin-synthesis` row in the bundled DB's `substance_flags`; gates the engine's
    /// parallel synthesis layer.
    let suppressesSerotoninSynthesis: Bool
    /// **Intrinsic efficacy** relative to a full agonist ∈ (0, 1], scaling how much *tolerance drive*
    /// a unit of occupancy produces (`Specs/tolerance-faithful-model-improvements.md` §5c). Tolerance
    /// is driven by occupancy, but a partial/low-efficacy agonist entrenches less per unit occupancy —
    /// so the adaptive and synthesis layers' drive is multiplied by this. `1.0` (default) for a full
    /// agonist / when unknown; curated `< 1` for the known partials (mitragynine, buprenorphine,
    /// tianeptine at μ). It scales the *drive*, not the deep escalation gate, and ships low-confidence.
    let intrinsicEfficacy: Double
    /// Tolerance classes inferred from the substance's **pharmacological category** (benzodiazepine →
    /// GABA, opioid → μ, …), independent of binding data. Lets the missing-PK fallback model a
    /// categorised-but-untargeted substance as its class representative even when the DB ships no
    /// receptor rows for it (`Specs/tolerance-faithful-model-improvements.md` §7 follow-up). Empty when
    /// the substance has no category that maps to a modeled tolerance class.
    let categoryClasses: Set<ReceptorClasses.ReceptorClass>
    /// Fraction of total plasma concentration that is **unbound** (free) — `fu = 1 − proteinBinding/100`.
    /// Multiplied into the molar → nM prefactor in the tolerance engine so occupancy is computed against
    /// *free* drug, matching the assay conditions the Kᵢ/EC₅₀ was measured under. Defaults to **1.0**
    /// (no binding correction) when no `protein_binding_pct` is available for the substance.
    let fractionUnbound: Double
    /// Engaged targets carrying a numeric half-max, **tightest (most potent) first**.
    let targets: [TargetEngagement]
    /// Active metabolites this substance produces that may extend its occupancy tail (K.5). Empty for
    /// substances with no metabolite data (and for every synthetic test-built parameter set).
    let metabolites: [MetaboliteContributor]
    /// **Diazepam-milligram-equivalent** factor — diazepam-mg per 1 mg of this substance, from the
    /// bundled DB's `diazepam_equivalents`. Lifts the GABA missing-PK fallback's confidence floor from
    /// `.unverified` (dose-fraction guess) to `.low` (validated clinical equivalence): a named benzo
    /// with no PK is modeled as the GABA representative at `dose × factor` mg. `nil` for the designer
    /// benzos whose circulating multipliers are back-derived folklore — they fall through to the
    /// dose-fraction proxy rather than borrowing a number nobody measured.
    let diazepamPerMg: Double?
    /// **Morphine-milligram-equivalent** factor — morphine-mg per 1 mg of this substance, from the
    /// bundled DB's `opioid_mme`. The μ-opioid counterpart of ``diazepamPerMg``, and the same
    /// contract: present only for the linearly convertible full agonists, so methadone, transdermal
    /// fentanyl and buprenorphine fall through to the dose-fraction proxy instead of being converted
    /// by a factor that does not exist for them.
    let opioidMMEPerMg: Double?
    /// The tolerance mechanism classes this substance is the **class representative** for — the
    /// PK-complete stand-in a PK-less member of the class is modeled as (Stage D missing-PK fallback).
    /// From the bundled DB's `class_representatives`. Empty for every substance that is not a
    /// representative, which is nearly all of them.
    let representsClasses: Set<ReceptorClasses.ReceptorClass>

    /// Explicit memberwise-shaped initializer with the newer inputs (Tmax, intrinsic efficacy) as
    /// **trailing defaulted** parameters, so the many existing call sites (the resolver and the test
    /// factories) that end at `targets:` keep compiling unchanged while the resolver can supply the new
    /// values. Everything else mirrors the stored-property order.
    init(
        molarMassGramsPerMole: Double?,
        vdLPerKg: Double?,
        bioavailabilityFraction: Double?,
        bioavailabilityConfidence: ConfidenceTier,
        doseScale: Double,
        doseScaleConfidence: ConfidenceTier,
        halfLifeMinutes: Double?,
        vdConfidence: ConfidenceTier,
        referenceDoseMg: Double?,
        suppressesSerotoninSynthesis: Bool,
        targets: [TargetEngagement],
        tmaxMinutes: Double? = nil,
        tmaxConfidence: ConfidenceTier = .unverified,
        intrinsicEfficacy: Double = 1,
        categoryClasses: Set<ReceptorClasses.ReceptorClass> = [],
        pkSpecies: String? = nil,
        fractionUnbound: Double = 1,
        metabolites: [MetaboliteContributor] = [],
        diazepamPerMg: Double? = nil,
        opioidMMEPerMg: Double? = nil,
        representsClasses: Set<ReceptorClasses.ReceptorClass> = [],
    ) {
        self.molarMassGramsPerMole = molarMassGramsPerMole
        self.vdLPerKg = vdLPerKg
        self.bioavailabilityFraction = bioavailabilityFraction
        self.bioavailabilityConfidence = bioavailabilityConfidence
        self.doseScale = doseScale
        self.doseScaleConfidence = doseScaleConfidence
        self.halfLifeMinutes = halfLifeMinutes
        self.tmaxMinutes = tmaxMinutes
        self.tmaxConfidence = tmaxConfidence
        self.vdConfidence = vdConfidence
        self.referenceDoseMg = referenceDoseMg
        self.suppressesSerotoninSynthesis = suppressesSerotoninSynthesis
        self.intrinsicEfficacy = intrinsicEfficacy
        self.categoryClasses = categoryClasses
        self.pkSpecies = pkSpecies
        self.fractionUnbound = fractionUnbound
        self.targets = targets
        self.metabolites = metabolites
        self.diazepamPerMg = diazepamPerMg
        self.opioidMMEPerMg = opioidMMEPerMg
        self.representsClasses = representsClasses
    }

    /// The most potent engaged target — the occupancy driver.
    var primaryTarget: TargetEngagement? {
        targets.first
    }

    /// Whether every input occupancy needs (Vd, molar mass, half-life, a primary target) is present.
    var canComputeOccupancy: Bool {
        vdLPerKg != nil && molarMassGramsPerMole != nil && halfLifeMinutes != nil
            && bioavailabilityFraction != nil && primaryTarget != nil
    }

    /// Overall occupancy confidence = the weakest link among the inputs that feed it (the resolved
    /// Vd, the bioavailability, and the primary target). A graded Vd with an un-graded Kᵢ is only as
    /// trustworthy as the Kᵢ; a defaulted F (`.unverified`) likewise caps the whole prediction.
    var occupancyConfidence: ConfidenceTier {
        Swift.min(vdConfidence, bioavailabilityConfidence, doseScaleConfidence, primaryTarget?.confidence ?? .unverified)
    }

    /// Peak fractional occupancy/engagement of the primary target for a single oral dose, evaluated
    /// at the modeled Tmax. A pure composition of the Foundation-A pathway — dose → molar
    /// concentration → Hill occupancy — and the function the dose-dependence gate exercises end to
    /// end. Returns nil when inputs are insufficient. `fu` defaults to the stored
    /// ``fractionUnbound``; pass an explicit value to override (tests use this to compare fu=1 vs
    /// fu=0.02 without rebuilding the parameters).
    func peakPrimaryOccupancy(doseMg: Double, weightKg: Double, unboundFraction fu: Double? = nil) -> Double? {
        guard let vdLPerKg, let molarMassGramsPerMole, let halfLifeMinutes,
              let bioavailabilityFraction, let primaryTarget else { return nil }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        let ka = PKModel.defaultKa(ke: ke)
        let peak = PKModel.tmax(ke: ke, ka: ka)
        let molar = PKModel.concentrationMolar(
            dose: doseMg * doseScale, bioavailability: bioavailabilityFraction, vdPerKg: vdLPerKg,
            weightKg: weightKg, molarMassGramsPerMole: molarMassGramsPerMole, ke: ke, ka: ka, at: peak,
        )
        let freeNanomolar = (fu ?? fractionUnbound) * molar * 1e9
        return PKModel.occupancy(concentration: freeNanomolar, halfMax: primaryTarget.halfMaxNanomolar)
    }
}
