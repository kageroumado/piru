import Foundation

/// The **tolerance-modulation graph** — curated edges where one substance, while onboard, *changes how
/// fast another mechanism builds tolerance* (`Specs/pharmacology-axis-meta-plan.md`, Stage 4b). This is
/// the `μ_R(t)` factor in the availability ODE
/// ```
/// dA_R/dt = (1 − A_R)/τ_R − κ_R · O_R(t) · A_R · μ_R(t)
/// ```
/// — `μ < 1` *attenuates* tolerance development, `μ > 1` would accelerate it. Edges are keyed by the
/// **modulator's receptor class** (mechanism-based, like the rest of the engine), evidence-tiered, and
/// applied only while the modulator is actually present (the time-resolved presence is computed in
/// ``ToleranceStore/simulate(entries:now:weightKg:timestepMinutes:lookbackDays:resolve:)``, so the edge
/// is concentration/overlap-gated for free).
///
/// ## v1 seed
/// **NMDA antagonism ↓ μ-opioid tolerance.** Blocking NMDA receptors attenuates the development of
/// opioid analgesic tolerance — the best-known clinical use is ketamine/memantine alongside opioids.
/// The effect is robust preclinically and used clinically, but the human magnitude is variable, so it
/// ships ``ConfidenceTier/low`` and as a *shape* (μ ≈ 0.5 at full NMDA engagement), never a precise %.
/// Because it is keyed by the `.nmdaAntagonist` class it covers memantine, ketamine, DXM, and MXE.
nonisolated enum ToleranceModulation {
    /// One modulation edge: while the modulator is present, scale tolerance development at
    /// ``affectedClass`` by ``muFactor`` (proportional to the modulator's current engagement).
    struct Edge {
        /// The tolerance class whose `μ_R(t)` this edge scales.
        let affectedClass: ReceptorClasses.ReceptorClass
        /// Tolerance-development factor at *full* modulator engagement. `< 1` attenuates; the engine
        /// blends it toward 1 by the modulator's time-resolved presence.
        let muFactor: Double
        let confidence: ConfidenceTier
        let note: String
    }

    /// The edges for which `modulatorClass` is the modulator. Empty for classes with no curated edge.
    static func edges(forModulatorClass modulatorClass: ReceptorClasses.ReceptorClass) -> [Edge] {
        switch modulatorClass {
        case .nmdaAntagonist:
            [Edge(
                affectedClass: .muOpioid,
                muFactor: 0.5,
                confidence: .low,
                note: "NMDA antagonism attenuates opioid tolerance development (preclinically robust, human magnitude variable).",
            )]
        default:
            []
        }
    }

    /// Whether any curated edge exists with `modulatorClass` as the modulator — a cheap pre-check.
    static func hasEdges(forModulatorClass modulatorClass: ReceptorClasses.ReceptorClass) -> Bool {
        !edges(forModulatorClass: modulatorClass).isEmpty
    }
}
