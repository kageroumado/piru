import Foundation

/// Pharmacodynamic tolerance dynamics — the layer **above** ``PKModel``.
///
/// `PKModel` answers *where the drug is* (concentration → receptor occupancy). `PDModel` answers
/// *how repeated occupancy changes the receptor's responsiveness over time* — the tolerance state.
/// Like `PKModel` it is **pure**: no state, no I/O, every function unit-testable in isolation. The
/// stateful orchestration (reading the dose log, resolving per-substance pharmacology, persisting a
/// snapshot) lives in `ToleranceStore`; the per-class rate constants live in `ReceptorClasses`.
///
/// ## The model — a dose-response right-shift
/// Tolerance is a **shift factor** `S(t) ≥ 1` that moves the dose-response curve right (loss of
/// potency, slope preserved — what controlled ED50 studies measure): `ED50(t) = ED50_naive · S(t)`.
/// `S` is built in **log space** from three additive layer contributions, each an exposure-driven
/// leaky integrator with its own gain (ln-shift ceiling) and time-constant:
/// ```
/// ln S(t) = s_acute + s_adaptive + s_deep
/// ṡ_layer = (shiftMax_layer · O(t) · drive_layer − s_layer) / τ_layer
/// ```
/// where `O(t)` ∈ [0, 1] is receptor occupancy from the replay. Each layer is solved **closed form**
/// per step (identical structure across the three; see ``stepShift(current:shiftMax:occupancy:drive:dtMinutes:tauMinutes:)``).
///
/// - **Acute** (`drive = 1`, τ ≈ hours): within-session tachyphylaxis / the redose loop.
/// - **Adaptive** (`drive = μ`, the modulation factor, τ ≈ days–weeks): the baseline shift people
///   mean by "tolerance".
/// - **Deep** (`drive = gate`, τ ≈ months): entrenched neuroadaptation. The gate (see ``deepGate``)
///   keeps it **off** until the dose is sustained well **above the substance's heavy ceiling** (the
///   *dose-relative escalation* signal — see ``deepGate(escalation:threshold:width:)``), and
///   `shiftMax_deep` provides the asymptote — so therapeutic users never accrue it. Keying the gate
///   on escalation rather than on the adaptive shift is the principled fix: transporter occupancy
///   saturates, so therapeutic and heavy dosing look identical at the receptor — only the dose
///   relative to the heavy ceiling distinguishes "significant escalation".
///
/// The user-facing gauge is the **response fraction** at the usual dose (see ``responseFraction``),
/// and recovery milestones are the times for `S(t)` to decay back through gauge thresholds (see
/// ``shiftDecayMinutes(layers:toShift:)``).
enum PDModel {
    // MARK: - Right-shift layer step

    /// Advance one right-shift layer across `dtMinutes`, treating occupancy as constant over the
    /// step. A leaky integrator relaxing toward `shiftMax·occupancy·drive`, solved in **closed form**
    /// rather than by Euler: with the target held constant the ODE `ṡ = (target − s)/τ` has exact
    /// solution `target + (s − target)·e^{−dt/τ}` — **unconditionally stable for any `dt`** and exact
    /// for piecewise-constant occupancy. The same structure serves all three layers (acute, adaptive,
    /// deep), distinguished only by their `(shiftMax, τ, drive)`.
    ///
    /// - Parameters:
    ///   - current: current ln-shift contribution `s_layer ≥ 0`.
    ///   - shiftMax: the layer's ln-shift ceiling (gain); `0` disables the layer (target ≡ 0).
    ///   - occupancy: `O(t)` ∈ [0, 1] over this step (the PD bridge from ``PKModel``).
    ///   - drive: the layer's gate factor — `1` (acute), the modulation `μ` (adaptive), or the deep
    ///     ``deepGate(escalation:threshold:width:)`` (deep).
    ///   - dtMinutes: step length (minutes); must be > 0.
    ///   - tauMinutes: the layer's build/recover time-constant (minutes); must be > 0.
    /// - Returns: the advanced ln-shift contribution.
    nonisolated static func stepShift(
        current: Double,
        shiftMax: Double,
        occupancy: Double,
        drive: Double,
        dtMinutes: Double,
        tauMinutes: Double,
    ) -> Double {
        guard dtMinutes > 0, tauMinutes > 0 else { return current }
        let target = max(0, shiftMax) * max(0, min(1, occupancy)) * max(0, drive)
        let decay = exp(-dtMinutes / tauMinutes)
        return target + (current - target) * decay
    }

    /// Smoothstep gate for the **deep** layer, keyed on the **dose-relative escalation** factor
    /// `escalation = dose ÷ the substance's heavy ceiling`: `0` while escalation sits below
    /// `threshold`, ramping smoothly to `1` once it exceeds `threshold + width`. So the deep
    /// (months-scale, entrenched) layer only engages once dosing runs sustainedly above the heavy
    /// ceiling — a therapeutic user, dosing at/below the ladder, never lights it. Escalation rather
    /// than the adaptive shift is the gate signal because saturating occupancy makes therapeutic and
    /// heavy dosing indistinguishable at the receptor (the Stage-A bug); the dose-to-heavy ratio is
    /// what actually separates "significant escalation" from ordinary use.
    ///
    /// `smoothstep(t) = t²(3 − 2t)` with `t = clamp((escalation − threshold)/width, 0, 1)` — C¹ at
    /// both edges, so the deep layer fades in without a kink.
    nonisolated static func deepGate(escalation: Double, threshold: Double, width: Double) -> Double {
        guard width > 0 else { return escalation >= threshold ? 1 : 0 }
        let t = max(0, min(1, (escalation - threshold) / width))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Gauge

    /// The **response fraction** ∈ [0, 1] — how much of the naïve effect you'd feel at your usual dose
    /// under the current right-shift `S`. The shift means effective dose is `D/S`; with occupancy
    /// `O = C/(C+K)` and `C ∝ dose`, the occupancy at `D/S` is `C/(C + K·S)`, so the ratio to the
    /// naïve occupancy `C/(C+K)` is `(r+1)/(r+S)` where `r = O_rep/(1 − O_rep) = C/K` from the
    /// representative peak occupancy at the usual dose.
    ///
    /// Equals `1` at `S = 1` (naïve), decreasing as `S` grows; at low representative occupancy it is
    /// ≈ `1/S`. This is the honest 5-bucket gauge's continuous source — a saturating output, not a
    /// false percentage.
    nonisolated static func responseFraction(shiftFactor: Double, representativeOccupancy: Double) -> Double {
        guard shiftFactor > 0 else { return 1 }
        let occupancy = max(0, min(0.999_999, representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        return max(0, min(1, (ratio + 1) / (ratio + shiftFactor)))
    }

    // MARK: - Recovery forecast (closed-form decay inverse)

    /// Minutes until the total right-shift `S` decays to `targetShift` with **no further occupancy**,
    /// given the current per-layer `(s, τ)` contributions. With occupancy ≡ 0 each layer decays
    /// `s_layer(t) = s_layer·e^{−t/τ}`, so `S(t) = exp(Σ s_layer·e^{−t/τ})` is strictly decreasing in
    /// `t` toward `1` — found by bisection.
    ///
    /// This is the "if you stop now" tolerance-break forecast the Tool renders. Returns `0` when `S`
    /// is already at/below `targetShift`, and `nil` when `targetShift < 1` (full reset to `S = 1` is
    /// asymptotic — never reached in finite time, so a target below it is unreachable).
    nonisolated static func shiftDecayMinutes(layers: [(s: Double, tau: Double)], toShift targetShift: Double) -> Double? {
        let initialSum = layers.reduce(0) { $0 + max(0, $1.s) }
        let currentShift = exp(initialSum)
        if currentShift <= targetShift { return 0 }
        guard targetShift >= 1 else { return nil }

        func shiftAt(_ minutes: Double) -> Double {
            exp(layers.reduce(0) { $0 + $1.s * exp(-minutes / max(1, $1.tau)) })
        }

        var low = 0.0
        var high = 1.0
        // Expand the bracket until S(high) is below the target (cap ~5 years of minutes).
        while shiftAt(high) > targetShift, high < 2_628_000 { high *= 2 }
        if shiftAt(high) > targetShift { return high }
        for _ in 0 ..< 60 {
            let mid = (low + high) / 2
            if shiftAt(mid) > targetShift { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: - Cross-substance occupancy combination

    /// Combine the occupancy contributions of several ligands at one **shared** target into a single
    /// site-occupancy fraction via the probabilistic union `1 − Π(1 − Oᵢ)` — a site is engaged if any
    /// ligand engages it. Saturating, order-independent, stays in `[0, 1]`, and reduces to a single
    /// `Oᵢ` when only one ligand is present. This is the cross-substance analogue of the timeline's
    /// single-substance dose superposition: it lets one class's right-shift be driven by every drug
    /// hitting that target.
    nonisolated static func combinedOccupancy(_ occupancies: [Double]) -> Double {
        let complementProduct = occupancies.reduce(1.0) { acc, o in
            acc * (1 - min(1, max(0, o)))
        }
        return 1 - complementProduct
    }
}
