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

    /// A smoothstep gate ∈ [0, 1]: `0` while `value` sits below `threshold`, ramping smoothly (C¹ at
    /// both edges — no kink) to `1` once it exceeds `threshold + width`. `smoothstep(t) = t²(3 − 2t)`
    /// with `t = clamp((value − threshold)/width, 0, 1)`.
    ///
    /// The **deep** tolerance layer's drive is the *product* of two of these
    /// (`Specs/tolerance-faithful-model-improvements.md` §2): a **magnitude** gate on the dose-relative
    /// escalation factor (`dose ÷ heavy ceiling`) × a **chronicity** gate on the leaky duty-cycle
    /// accumulator. Escalation rather than the adaptive shift is the magnitude signal because saturating
    /// occupancy makes therapeutic and heavy dosing indistinguishable at the receptor; chronicity adds
    /// the frequency/duration axis a per-dose magnitude cliff was blind to. Both must be high for deep to
    /// accrue — a heavy one-off binge (chronicity ≈ 0) recovers, a therapeutic daily dose (magnitude ≈ 0)
    /// stays stable.
    nonisolated static func smoothstepGate(_ value: Double, threshold: Double, width: Double) -> Double {
        guard width > 0 else { return value >= threshold ? 1 : 0 }
        let t = max(0, min(1, (value - threshold) / width))
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
    ///
    /// **Mechanism-aware saturation cap** (`Specs/tolerance-faithful-model-improvements.md` §5). The
    /// uncapped ratio is the *physically exact* usual-dose occupancy ratio `O(D, K·S)/O(D, K)` — correct
    /// for **agonists / PAMs / antagonists**, where usual-dose occupancy is the effect proxy (a heavy
    /// opioid user at their elevated dose then shows realistic *residual* response, e.g. `r ≈ 9, S ≈ 10`
    /// → ~0.53, "roughly half", not "barely anything"). For **release / reuptake** classes occupancy
    /// saturates at recreational doses (a releaser at DAT sits at occupancy ≈ 1), so felt effect tracks
    /// flux, not static occupancy — pass `occupancyCap = 0.5` to evaluate at the sensitive half-sat point
    /// so a meaningful `S` doesn't wash out to "no tolerance". `occupancyCap == nil` ⇒ uncapped. The
    /// caller decides per class via ``ReceptorClasses/ReceptorClass/gaugeOccupancyCap``.
    nonisolated static func responseFraction(
        shiftFactor: Double, representativeOccupancy: Double, occupancyCap: Double? = nil,
    ) -> Double {
        guard shiftFactor > 0 else { return 1 }
        let capped = occupancyCap.map { Swift.min($0, representativeOccupancy) } ?? representativeOccupancy
        // Clamp just below 1 so a fully-saturated (uncapped) occupancy can't divide by zero — it then
        // reads a large ratio and a response near `1`, which is the honest reading for that degenerate case.
        let occupancy = max(0, min(0.999_999, capped))
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
        while shiftAt(high) > targetShift, high < 2_628_000 {
            high *= 2
        }
        if shiftAt(high) > targetShift { return high }
        for _ in 0 ..< 60 {
            let mid = (low + high) / 2
            if shiftAt(mid) > targetShift { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: - Cross-substance occupancy combination

    /// Combine the occupancy contributions of several ligands at one **shared, competitive** target into
    /// a single site-occupancy fraction via **Gaddum competitive summation** `Σrᵢ / (1 + Σrᵢ)`, where
    /// each ligand's binding ratio `rᵢ = Oᵢ/(1 − Oᵢ) = Cᵢ/Kᵢ` is recovered from its individual occupancy
    /// `Oᵢ`. This is the physically correct form for ligands *competing* for the same site: two ligands
    /// each at half-saturation give `2/3 ≈ 0.667`, not the `0.75` the probabilistic union `1 − Π(1 − Oᵢ)`
    /// over-counts (the union treats the site as if each ligand had its own independent copy). It is
    /// order-independent, stays in `[0, 1]`, is *cheaper* than the union (one running sum, no products),
    /// and — the load-bearing property — reduces **exactly** to a single `Oᵢ` when only one ligand is
    /// present, so single-substance right-shifts are unchanged; only polydrug co-occupancy at one target
    /// moves, downward toward the correct value.
    nonisolated static func competitiveOccupancy(_ occupancies: [Double]) -> Double {
        let sumRatio = occupancies.reduce(0.0) { acc, occupancy in
            let clamped = min(1, max(0, occupancy))
            // A ligand at (or above) full occupancy has an unbounded ratio — saturate the sum so the
            // result is 1 without dividing by zero.
            return clamped >= 1 ? .infinity : acc + clamped / (1 - clamped)
        }
        guard sumRatio.isFinite else { return 1 }
        return sumRatio / (1 + sumRatio)
    }
}
