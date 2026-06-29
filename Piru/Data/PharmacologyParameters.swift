import Foundation

/// Resolved pharmacology inputs for the absolute-exposure → receptor-occupancy pipeline (the
/// pharmacology axis's Foundation A), produced by ``SubstanceStore/pharmacologyParameters(forSubstanceName:)``.
///
/// It bundles what the engine needs to turn a *dose* into an *occupancy curve*: the molar mass, the
/// best graded volume of distribution + bioavailability + half-life, and the engaged targets with
/// their half-saturation constants — each value carrying the confidence tier it was graded at, so the
/// engine can run on verified numbers and the UI can badge how much to trust the prediction.
nonisolated struct PharmacologyParameters {
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
        var id: String {
            "\(target)-\(action.rawValue)-\(kind.rawValue)"
        }
    }

    let substanceName: String
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
    /// Engaged targets carrying a numeric half-max, **tightest (most potent) first**.
    let targets: [TargetEngagement]

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
    /// end. Returns nil when inputs are insufficient. `fu` defaults to 1 (Stage 0; real unbound
    /// fraction lands with the alcohol/benzo verticals).
    func peakPrimaryOccupancy(doseMg: Double, weightKg: Double, unboundFraction fu: Double = 1) -> Double? {
        guard let vdLPerKg, let molarMassGramsPerMole, let halfLifeMinutes,
              let bioavailabilityFraction, let primaryTarget else { return nil }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        let ka = PKModel.defaultKa(ke: ke)
        let peak = PKModel.tmax(ke: ke, ka: ka)
        let molar = PKModel.concentrationMolar(
            dose: doseMg * doseScale, bioavailability: bioavailabilityFraction, vdPerKg: vdLPerKg,
            weightKg: weightKg, molarMassGramsPerMole: molarMassGramsPerMole, ke: ke, ka: ka, at: peak,
        )
        let freeNanomolar = fu * molar * 1e9 // mol/L → nM, matching the half-max unit
        return PKModel.occupancy(concentration: freeNanomolar, halfMax: primaryTarget.halfMaxNanomolar)
    }
}
