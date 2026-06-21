import Foundation

/// Pharmacodynamic tolerance dynamics — the layer **above** ``PKModel``.
///
/// `PKModel` answers *where the drug is* (concentration → receptor occupancy). `PDModel` answers
/// *how repeated occupancy changes the receptor's responsiveness over time* — the tolerance state.
/// Like `PKModel` it is **pure**: no state, no I/O, every function unit-testable in isolation. The
/// stateful orchestration (reading the dose log, resolving per-substance pharmacology, persisting a
/// snapshot) lives in `ToleranceStore`; the per-class rate constants live in `ReceptorClasses`.
///
/// ## The model
/// One first-order ODE per receptor target `R`, integrated over the dose log:
/// ```
/// dA_R/dt = (1 − A_R)/τ_R  −  κ_R · O_R(t) · A_R · μ_R(t)
///             └ recovery ┘     └──────── depression ────────┘
/// ```
/// - `A_R` ∈ [0, 1] is **availability** — 1 = naïve/rested, 0 = fully tolerant. Per target, shared
///   across every substance that hits `R`, which is why cross-tolerance falls out for free (LSD
///   depressing `A(5-HT2A)` lowers tomorrow's predicted psilocybin response — same state variable).
/// - Recovery pulls `A_R` back toward 1 with the class time-constant `τ_R`.
/// - Depression scales with **current occupancy** `O_R(t)` (so it is *dose-dependent* — the keystone
///   the normalized-PK model could not express) and with **currently-available receptors** `A_R`
///   (you can't downregulate what's already gone → the right saturating shape), times the modulation
///   factor `μ_R(t)` (the memantine ↓ opioid case; default 1 until Stage 4).
///
/// The same machinery, with different `(κ, τ)`, serves the two other tolerance axes a single
/// availability variable can't capture (see ``ReceptorClass``):
/// - **acute pool** (`κ` large, `τ` ≈ hours): within-session tachyphylaxis / the redose loop.
/// - **allostatic load** (a leaky integrator of occupancy, `τ` ≈ months): a recovery-state
///   indicator, *never* multiplied into effect — what honestly replaces the fake "stimulant
///   tolerance %".
enum PDModel {
    // MARK: - Availability step (the tolerance ODE)

    /// Advance one availability variable across `dtMinutes`, treating occupancy as constant over the
    /// step. Solved in **closed form** rather than by Euler: with occupancy held constant the ODE is
    /// linear with constant coefficients,
    /// ```
    /// dA/dt = (1−A)/τ − κ·O·μ·A  =  a − (a + b)·A,   a = 1/τ,  b = κ·O·μ
    /// ```
    /// whose exact solution over the step is `A_ss + (A − A_ss)·e^{−(a+b)·dt}` with steady state
    /// `A_ss = a/(a+b)`. This is **unconditionally stable for any `dt`** and exact for piecewise-
    /// constant occupancy (Euler would overshoot/oscillate on a coarse grid). `A` stays in `[A_ss, A]`
    /// so a value starting in `[0, 1]` never leaves it.
    ///
    /// - Parameters:
    ///   - availability: current `A_R` ∈ [0, 1].
    ///   - occupancy: `O_R(t)` ∈ [0, 1] over this step (the PD bridge from ``PKModel/occupancy(concentration:halfMax:hillCoefficient:)``).
    ///   - dtMinutes: step length (minutes); must be > 0.
    ///   - kappa: per-class depression rate `κ_R` (per minute), from ``ReceptorClasses``.
    ///   - tauMinutes: per-class recovery time-constant `τ_R` (minutes); must be > 0.
    ///   - modulation: `μ_R(t)` tolerance-modulation factor (Stage 4); default 1.
    /// - Returns: the advanced availability.
    nonisolated static func stepAvailability(
        availability: Double,
        occupancy: Double,
        dtMinutes: Double,
        kappa: Double,
        tauMinutes: Double,
        modulation: Double = 1,
    ) -> Double {
        guard dtMinutes > 0, tauMinutes > 0 else { return availability }
        let recovery = 1.0 / tauMinutes // a — constant pull toward 1
        let depression = max(0, kappa * max(0, occupancy) * max(0, modulation)) // b coefficient on A
        let relaxation = recovery + depression // a + b
        guard relaxation > 0 else { return availability }
        let steadyState = recovery / relaxation // A_ss = a/(a+b)
        let decay = exp(-relaxation * dtMinutes)
        return steadyState + (availability - steadyState) * decay
    }

    /// Integrate availability over a uniformly-sampled occupancy series, returning the availability
    /// at each sample (length `occupancy.count + 1`: the initial value plus one per step). The driving
    /// `occupancy[i]` is the occupancy held across the *i*-th step.
    ///
    /// This is the function the tolerance gate exercises: feed it a daily vs a weekly dosing pattern
    /// and the trace reproduces the canonical dynamics — clustered doses drive `A` down faster than
    /// `τ` recovers it (suppression accumulates), spacing lets it climb back between doses.
    nonisolated static func availabilityTrace(
        occupancy: [Double],
        dtMinutes: Double,
        kappa: Double,
        tauMinutes: Double,
        initial: Double = 1,
        modulation: Double = 1,
    ) -> [Double] {
        var a = initial
        var trace = [a]
        trace.reserveCapacity(occupancy.count + 1)
        for o in occupancy {
            a = stepAvailability(
                availability: a, occupancy: o, dtMinutes: dtMinutes,
                kappa: kappa, tauMinutes: tauMinutes, modulation: modulation,
            )
            trace.append(a)
        }
        return trace
    }

    // MARK: - Allostatic load (leaky integrator)

    /// Advance the **allostatic load** `L` across `dtMinutes` for constant occupancy — a leaky
    /// integrator that relaxes toward the (gain-scaled) current occupancy with a months-scale `τ`:
    /// `dL/dt = (γ·O − L)/τ`, steady state `γ·O`, solved closed-form. With `γ = 1` this keeps `L` in
    /// `[0, 1]` (for `O ∈ [0, 1]`) as a **normalized cumulative-exposure / recovery-state indicator**.
    ///
    /// It is the honest slow-axis readout for the stimulant/releaser classes, where the *availability*
    /// axis is deliberately near-inert (transporter occupancy saturates at therapeutic doses, so it
    /// cannot distinguish dose — and a slow "tolerance %" there is the wrong-signed error this engine
    /// refuses). Load instead integrates *exposure over time*: a brief occasional dose barely moves a
    /// months-τ integrator, while chronic frequent high exposure climbs it — dose- and frequency-
    /// dependent without relying on a saturating peak. It is **never** multiplied into a predicted
    /// effect; it is a recovery-state display only.
    nonisolated static func stepLoad(
        load: Double,
        occupancy: Double,
        dtMinutes: Double,
        tauMinutes: Double,
        gain: Double = 1,
    ) -> Double {
        guard dtMinutes > 0, tauMinutes > 0 else { return load }
        let target = max(0, gain) * max(0, occupancy)
        let decay = exp(-dtMinutes / tauMinutes)
        return target + (load - target) * decay
    }

    // MARK: - Cross-substance occupancy combination

    /// Combine the occupancy contributions of several ligands at one **shared** target into a single
    /// site-occupancy fraction via the probabilistic union `1 − Π(1 − Oᵢ)` — a site is engaged if any
    /// ligand engages it. Saturating, order-independent, stays in `[0, 1]`, and reduces to a single
    /// `Oᵢ` when only one ligand is present. This is the cross-substance analogue of the timeline's
    /// single-substance dose superposition: it lets one `A_R` be driven by every drug hitting `R`.
    nonisolated static func combinedOccupancy(_ occupancies: [Double]) -> Double {
        let complementProduct = occupancies.reduce(1.0) { acc, o in
            acc * (1 - min(1, max(0, o)))
        }
        return 1 - complementProduct
    }
}
