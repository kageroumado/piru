import Foundation

/// Resolved pharmacology inputs for the absolute-exposure → receptor-occupancy pipeline (the
/// pharmacology axis's Foundation A), produced by ``SubstanceStore/pharmacologyParameters(forSubstanceName:)``.
///
/// It bundles what the engine needs to turn a *dose* into an *occupancy curve*: the molar mass, the
/// best graded volume of distribution + bioavailability + half-life, and the engaged targets with
/// their half-saturation constants — each value carrying the confidence tier it was graded at, so the
/// engine can run on verified numbers and the UI can badge how much to trust the prediction.
struct PharmacologyParameters {
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
    /// Oral bioavailability as a fraction in `(0, 1]`, or nil when unknown.
    let bioavailabilityFraction: Double?
    let halfLifeMinutes: Double?
    /// Confidence of the resolved ``vdLPerKg`` (`.unverified` when no graded Vd row exists).
    let vdConfidence: ConfidenceTier
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
    /// Vd and the primary target). A graded Vd with an un-graded Kᵢ is only as trustworthy as the Kᵢ.
    var occupancyConfidence: ConfidenceTier {
        Swift.min(vdConfidence, primaryTarget?.confidence ?? .unverified)
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
            dose: doseMg, bioavailability: bioavailabilityFraction, vdPerKg: vdLPerKg,
            weightKg: weightKg, molarMassGramsPerMole: molarMassGramsPerMole, ke: ke, ka: ka, at: peak,
        )
        let freeNanomolar = fu * molar * 1e9 // mol/L → nM, matching the half-max unit
        return PKModel.occupancy(concentration: freeNanomolar, halfMax: primaryTarget.halfMaxNanomolar)
    }
}
