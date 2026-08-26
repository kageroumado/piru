import Foundation
import os

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
/// The edges come from the bundled DB's `tolerance_modulation`, loaded once by ``SubstanceStore`` at
/// index build. They are held in a lock-guarded static rather than read per call because the one
/// caller — the replay's `appendModulators` — is `nonisolated` and runs off the main actor inside the
/// per-dose loop, where a GRDB hop per dose would dominate the integration. Before the load lands,
/// ``edges(forModulatorClass:)`` returns nothing and tolerance develops unmodulated.
nonisolated enum ToleranceModulation {
    /// One modulation edge: while the modulator is present, scale tolerance development at
    /// ``affectedClass`` by ``muFactor`` (proportional to the modulator's current engagement).
    struct Edge: Sendable {
        /// The tolerance class whose `μ_R(t)` this edge scales.
        let affectedClass: ReceptorClasses.ReceptorClass
        /// Tolerance-development factor at *full* modulator engagement. `< 1` attenuates; the engine
        /// blends it toward 1 by the modulator's time-resolved presence.
        let muFactor: Double
    }

    private static let table = OSAllocatedUnfairLock<[ReceptorClasses.ReceptorClass: [Edge]]>(
        initialState: [:],
    )

    /// Install the edges read from `tolerance_modulation`. Called once per store init.
    static func load(_ edges: [ReceptorClasses.ReceptorClass: [Edge]]) {
        table.withLock { $0 = edges }
    }

    /// The edges for which `modulatorClass` is the modulator. Empty for classes with no curated edge.
    static func edges(forModulatorClass modulatorClass: ReceptorClasses.ReceptorClass) -> [Edge] {
        table.withLock { $0[modulatorClass] ?? [] }
    }
}
