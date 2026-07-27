import Foundation

/// Pure curve-synthesis math behind ``TimelineGraphView``, extracted into a
/// namespace of static functions so it can run anywhere (the off-main
/// `computeDerived` pass, widget snapshots) and be tested directly.
///
/// Everything here is a pure function of its inputs: the Bateman/phase-shaped
/// effect curves, the `Hill(Σ magnitude·bell)` redose merge, amplitude
/// γ-compression, tail scanning, and the lane/tick layout math. No view state,
/// no caching — ``TimelineModelCache`` and the `Derived` memoization wiring
/// stay with the view.
nonisolated enum TimelineCurveModel {
    /// All input-derived geometry that does **not** depend on zoom/pan/scrub —
    /// computed exactly once in `init` so the `Canvas` closure and the span
    /// accessors read O(1) stored values instead of re-walking the PK curves on
    /// every property access. This collapses the former recomputation diamond
    /// (each `visibleSpan`/`totalSpan` read re-ran the 240-step `renderedTail`
    /// scan ~10×, and `earliestDose` re-mapped + re-`min`'d the dose array on
    /// every one of its 24 call sites) down to a single evaluation per instance.
    struct Derived {
        let earliestDose: Date
        let maxDoseBySubstance: [String: Double]
        let stackedGroups: [[ActiveSubstanceState]]
        let peakCurveValue: Double
        let yNormalization: Double
        /// `renderedTail(threshold: 0.04)` — the full scrollable extent.
        let rawDataTail: Double
        /// `renderedTail(threshold: 0.20, framing: true)` — labeled-active window.
        let rawActivityTail: Double
    }

    /// Absorption / elimination rate constants for a one-compartment Bateman
    /// curve, fit to a dose's subjective duration profile. Precomputed once per
    /// curve — the `estimateKa` Newton solve is far too costly to run per pixel.
    struct PKCurveParams {
        let ka: Double
        let ke: Double
        let cmax: Double
    }

    /// One lane per distinct substance, in first-dose order, carrying every dose
    /// of that substance so redoses share a lane.
    struct LaneGroup {
        let name: String
        let colorHex: String
        let doses: [ActiveSubstanceState]
    }

    /// A duration-less substance rendered as its own lane: a name label plus a
    /// baseline row of dots, one per dose.
    struct MarkerLane {
        let name: String
        let colorHex: String
        let markers: [DoseMarker]
    }

    /// Hard cap on the timeline window (48h). Activity past this is clipped so
    /// the meaningful first two days stay legible.
    nonisolated static let maxDisplayMinutes: Double = 48 * 60

    /// Target number of time labels on the x-axis for consistency.
    nonisolated static let targetTickCount: Int = 8

    /// Choose a clean tick interval that yields ~8 labels for the given span.
    nonisolated static func intervalForSpan(_ span: Double) -> Double {
        let candidates: [Double] = [15, 30, 60, 120, 240, 480, 720, 1_440]
        let ideal = span / Double(targetTickCount)
        return candidates.first { $0 >= ideal } ?? 1_440
    }

    /// Build the entire ``Derived`` model in dependency order — once, in `init`.
    /// Every helper it calls is `static`/pure precisely so this can run before
    /// the view's stored properties are initialized.
    nonisolated static func computeDerived(
        substances: [ActiveSubstanceState],
        markers: [DoseMarker],
        stackRedoses: Bool,
        dayBounded: Bool,
        currentTime: Date,
    ) -> Derived {
        let earliest = (substances.map(\.doseTimestamp) + markers.map(\.timestamp)).min() ?? currentTime
        var maxDose: [String: Double] = [:]
        for s in substances {
            let key = s.substanceName.lowercased()
            maxDose[key] = max(maxDose[key] ?? 0, s.amount)
        }
        let groups = stackRedoses ? Self.stackedGroups(of: substances) : []
        let peak = Self.peakCurveValue(
            substances: substances,
            stackedGroups: groups,
            earliestDose: earliest,
            maxDose: maxDose,
            stackRedoses: stackRedoses,
        )
        let yNorm = min(1.0 / peak, 20.0)
        let displayCap = dayBounded ? 24 * 60 : maxDisplayMinutes
        let dataTail = Self.renderedTail(threshold: 0.04, framing: false, substances: substances, stackedGroups: groups, earliestDose: earliest, yNorm: yNorm, maxDose: maxDose, stackRedoses: stackRedoses, displayCap: displayCap)
        let activityTail = Self.renderedTail(threshold: 0.20, framing: true, substances: substances, stackedGroups: groups, earliestDose: earliest, yNorm: yNorm, maxDose: maxDose, stackRedoses: stackRedoses, displayCap: displayCap)
        return Derived(
            earliestDose: earliest,
            maxDoseBySubstance: maxDose,
            stackedGroups: groups,
            peakCurveValue: peak,
            yNormalization: yNorm,
            rawDataTail: dataTail,
            rawActivityTail: activityTail,
        )
    }

    /// Empirically find where the rendered curve envelope returns toward
    /// baseline: the latest minute at which the tallest drawn curve still
    /// exceeds `threshold` of full graph height. Params/scale are precomputed
    /// once (not per sample) so the scan stays cheap.
    ///
    /// When `framing` is true, curves that never decay below `threshold` within
    /// the window (persistent long-acting background like a daily maintenance
    /// med) are dropped from the envelope, so they don't drag the default frame
    /// out to days and crush the acute action. They still count toward the full
    /// scrollable extent (`framing: false`). If every curve is persistent, none
    /// are dropped, so a long-acting-only day still shows its curve.
    nonisolated static func renderedTail(
        threshold: Double,
        framing: Bool,
        substances: [ActiveSubstanceState],
        stackedGroups: [[ActiveSubstanceState]],
        earliestDose: Date,
        yNorm: Double,
        maxDose: [String: Double],
        stackRedoses: Bool,
        displayCap: Double,
    ) -> Double {
        var curves: [(Double) -> Double] = []
        var upper: Double = 1

        if stackRedoses {
            for group in stackedGroups {
                let params = group.map { Self.pkParams(for: $0) }
                for (di, dose) in group.enumerated() {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    upper = max(upper, offset + Self.curveExtent(for: dose, params: params[di]))
                }
                curves.append { t in Self.stackedIntensity(atGlobalMinutes: t, group: group, params: params, earliestDose: earliestDose) * yNorm }
            }
        } else {
            for s in substances {
                let params = Self.pkParams(for: s)
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let scale = Self.heightScale(for: s, substances: substances, maxDose: maxDose)
                upper = max(upper, offset + Self.curveExtent(for: s, params: params))
                curves.append { t in
                    let local = t - offset
                    return local >= 0 ? Self.intensity(at: local, for: s, params: params) * scale * yNorm : 0
                }
            }
        }
        upper = min(upper, displayCap)

        var contributing = curves
        if framing {
            let transient = curves.filter { $0(upper) < threshold }
            if !transient.isEmpty { contributing = transient }
        }

        let steps = 240
        var lastActive: Double = 0
        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * upper
            var h = 0.0
            for curve in contributing {
                h = max(h, curve(t))
                if h >= threshold { break }
            }
            if h >= threshold { lastActive = t }
        }
        return max(lastActive, 1)
    }

    /// Single-dose (non-stacked) height: the same saturating Hill link applied
    /// to this dose's magnitude, so a lone dose and a stacked group of the same
    /// total agree on height. The *unclamped* magnitude already encodes relative
    /// dose size (a 17 g alcohol renders ~half a 34 g, a heavy dose saturates),
    /// so no separate multi-dose multiplier is needed. `substances`/`maxDose`
    /// are retained for call-site symmetry with the stacked path.
    nonisolated static func heightScale(
        for substance: ActiveSubstanceState,
        substances _: [ActiveSubstanceState],
        maxDose _: [String: Double],
    ) -> Double {
        max(0.0001, hill(substance.doseMagnitude))
    }

    /// Highest curve peak across all substances/groups. Used to normalize the
    /// y-axis so the tallest curve fills the height — a lone low dose then
    /// reaches the top instead of rendering as a flat sliver, and multiple
    /// curves keep their relative proportions.
    nonisolated static func peakCurveValue(
        substances: [ActiveSubstanceState],
        stackedGroups: [[ActiveSubstanceState]],
        earliestDose: Date,
        maxDose: [String: Double],
        stackRedoses: Bool,
    ) -> Double {
        if stackRedoses {
            var maxV = 0.0
            for group in stackedGroups {
                let (s, e) = Self.stackedGroupRange(group, earliestDose: earliestDose)
                guard e > s else { continue }
                let params = group.map { Self.pkParams(for: $0) }
                let steps = 48
                for i in 0 ... steps {
                    let t = s + Double(i) / Double(steps) * (e - s)
                    maxV = max(maxV, Self.stackedIntensity(atGlobalMinutes: t, group: group, params: params, earliestDose: earliestDose))
                }
            }
            return max(maxV, 0.0001)
        } else {
            return max(substances.map { Self.heightScale(for: $0, substances: substances, maxDose: maxDose) }.max() ?? 1, 0.0001)
        }
    }

    /// Compression exponent applied to each curve's *amplitude* — the peak
    /// height it's scaled to — never to its time-varying shape. Linear
    /// (`1.0`) makes a threshold dose beside a heavy one collapse to an
    /// unreadable sliver and its long elimination skirt hug the axis. `< 1`
    /// lifts the low end (a 10 %-of-peak dose rises to ~32 % at `0.5`) while
    /// pinning the tallest curve at full height and preserving dose ordering.
    /// Because only the amplitude is scaled, onset/peak/offset proportions —
    /// and the relative tail length — are untouched; the light dose simply
    /// reads as a real hump instead of a flat smear.
    nonisolated static let amplitudeGamma: Double = 0.5

    /// Map a linear normalized amplitude in `[0, 1]` to its display height,
    /// compressing the low end so faint doses stay legible next to heavy ones.
    nonisolated static func compressedAmplitude(_ amplitude: Double) -> Double {
        pow(min(max(amplitude, 0), 1), amplitudeGamma)
    }

    // MARK: - Intensity (mechanistic Bateman PK curve)

    /// Fit a Bateman curve to a dose's subjective phase timing.
    ///
    /// The duration phases describe *subjective effect*, not plasma
    /// concentration, so they are not literally Bateman-shaped (a Bateman peak
    /// always satisfies `tmax < 1/ke`, which a long "peak" plateau violates). We
    /// therefore map the phases onto the closest well-formed one-compartment
    /// curve rather than reproduce them:
    ///
    /// - **Elimination (`ke`)** is chosen so the curve decays to ~5 % of its
    ///   peak by `totalMinutes` — the curve fades out exactly when the listed
    ///   effects end, keeping it consistent with the axis (also built from
    ///   `totalMinutes`).
    /// - **Absorption (`ka`)** is chosen so the peak lands at the center of the
    ///   subjective peak plateau, clamped just inside `1/ke` so the curve stays
    ///   well-formed. A long plateau pushes the target peak late, driving
    ///   `ka → ke` and naturally yielding the broad, rounded `ke·t·e^(−ke·t)`
    ///   top — a sustained peak without the artificial flat trapezoid lid.
    nonisolated static func pkParams(for s: ActiveSubstanceState) -> PKCurveParams {
        let total = max(s.totalMinutes, 1)
        let peakCenter = (s.comeupEndMinutes + s.peakEndMinutes) / 2
        // Decay to 5% of peak by `total`; anchor the window on the peak center
        // but never let it collapse to nothing.
        let decayWindow = max(total - min(peakCenter, total * 0.5), total * 0.25)
        let ke = log(20) / decayWindow
        // Floor the peak time at a few minutes so a very short-duration
        // substance still shows a visible up-slope rather than a vertical wall.
        // A feasible Bateman peak must also satisfy tmax < 1/ke — clamp inside.
        // Critically, do NOT cap absorption *relative to* elimination: a
        // long-half-life compound has fast absorption and a slow tail
        // (ka ≫ ke), and a ratio cap would wrongly push its peak out by hours.
        let tmaxTarget = min(max(peakCenter, 8), 0.85 / ke)
        let ka = PKModel.estimateKa(timeToPeak: tmaxTarget, ke: ke)
        let cmax = max(PKModel.cmax(ke: ke, ka: ka), 1e-9)
        return PKCurveParams(ka: ka, ke: ke, cmax: cmax)
    }

    /// Normalized `[0, 1]` effect intensity at `minutes` past the dose. Delegates
    /// the shape to ``effectShape(at:for:)`` (a phase-based subjective-effect
    /// curve) and, for releasers, crashes the descending limb faster than the
    /// listed offset via ``toleranceGate``. `params` is retained for call-site
    /// stability but no longer drives the shape — the curve is built from the
    /// duration phases, not a plasma-concentration fit.
    nonisolated static func intensity(at minutes: Double, for s: ActiveSubstanceState, params _: PKCurveParams) -> Double {
        let shape = effectShape(at: minutes, for: s)
        guard shape > 0 else { return 0 }
        return shape * toleranceGate(at: minutes, for: s)
    }

    /// Subjective effect-strength curve in `[0, 1]`, built directly from the
    /// dose's duration phases rather than a plasma-concentration model. The graph
    /// shows *how strong the effects feel*, not blood level, so:
    ///
    /// The curve is a **Gaussian-shouldered bell**: a rising Gaussian half on the
    /// left, an optional flat (or rounded) crest across the peak, and a falling
    /// Gaussian half on the right. Each shoulder is anchored to its phase window —
    ///
    /// - **σ↑** `= (comeupEnd − onsetEnd) / comeupSharpness` widens the rising
    ///   shoulder to span the come-up; the **onset delay falls out for free** as
    ///   that shoulder's far-left tail (≈0 through the onset window). `comeupEnd`
    ///   is the ``effectiveComeupEnd`` — synthesized when the data lists no
    ///   come-up phase, so the rise never collapses to a vertical wall.
    /// - **σ↓** `= (offsetEnd − peakEnd) / offsetSharpness` widens the falling
    ///   shoulder to span the offset.
    /// - **crest** holds at 1.0 between `leftEdge`/`rightEdge`; ``peakDome`` shrinks
    ///   that flat span toward the peak center, so a short peak rounds to a bell
    ///   tip while a long one keeps a gently broad crest.
    ///
    /// Both shoulders meet the crest with zero slope (a Gaussian's derivative is 0
    /// at its mean), so the whole curve is C¹-smooth — no shoulder kinks like the
    /// old smoothstep+sine. The asymmetry users expect (fast rise, slow fall)
    /// comes from the offset window being wider than the come-up window in the
    /// data, not from the constants. Tuned with the offline curve tools.
    /// Zero-order elimination kinetics + the logged dose in **milligrams** for a substance whose
    /// clearing enzyme saturates across its dose range (alcohol). `nil` for every first-order
    /// substance, or when the dose can't be read as a mass — both fall back to the phase bell.
    nonisolated static func zeroOrderKinetics(for s: ActiveSubstanceState) -> (PKModel.ZeroOrderKinetics, doseMg: Double)? {
        zeroOrderKinetics(substanceName: s.substanceName, amount: s.amount, unit: s.unit, weightKg: s.bodyWeightKg)
    }

    /// The zero-order kinetics + dose (mg) for a substance identified by raw fields, so the
    /// state *builder* can consult the same model the curve uses before an `ActiveSubstanceState`
    /// exists. `nil` for every first-order substance or an unreadable dose.
    nonisolated static func zeroOrderKinetics(substanceName: String, amount: Double, unit: String, weightKg: Double = PKModel.referenceBodyWeightKg) -> (PKModel.ZeroOrderKinetics, doseMg: Double)? {
        let kinetics: PKModel.ZeroOrderKinetics
        switch substanceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "alcohol", "ethanol": kinetics = PKModel.ethanolZeroOrder(weightKg: weightKg)
        default: return nil
        }
        guard let mg = zeroOrderDoseMilligrams(amount: amount, unit: unit) else { return nil }
        return (kinetics, mg)
    }

    /// Dose-scaled phase boundaries (minutes) for a zero-order substance, derived from its own
    /// kinetics so the phase bar, phase-band coloring, now-line active window, and "{elapsed} in ·
    /// {remaining} left" readout all track the same clock as the curve — which for alcohol *grows
    /// with dose* instead of sitting on a fixed profile. `nil` for first-order substances, unreadable
    /// doses, or a dose too small to form a real peak (all fall back to the fixed `DurationProfile`).
    ///
    /// The curve is an absorption rise to a BAC peak (`zeroOrderPeakMinutes`) followed by a long
    /// linear decline to clearance (`zeroOrderClearMinutes`), so the whole descending limb maps to a
    /// single wide "offset" and there is no afterglow.
    nonisolated static func zeroOrderBoundaries(substanceName: String, amount: Double, unit: String, weightKg: Double = PKModel.referenceBodyWeightKg)
        -> (onsetEnd: Double, comeupEnd: Double, peakEnd: Double, offsetEnd: Double, total: Double)? {
        guard let (kinetics, doseMg) = zeroOrderKinetics(substanceName: substanceName, amount: amount, unit: unit, weightKg: weightKg) else { return nil }
        let peak = PKModel.zeroOrderPeakMinutes(doseMg: doseMg, kinetics: kinetics)
        let clear = PKModel.zeroOrderClearMinutes(doseMg: doseMg, kinetics: kinetics)
        guard peak > 0, clear > peak else { return nil }
        // A short crest around the BAC peak, clamped so it never crosses into the decline.
        let peakEnd = min(peak * 1.15, (peak + clear) / 2)
        return (onsetEnd: peak * 0.35, comeupEnd: peak * 0.85, peakEnd: peakEnd, offsetEnd: clear, total: clear)
    }

    /// The logged amount in milligrams of ethanol. Mass units convert directly;
    /// colloquial **drink/unit** counts convert at the NIAAA standard-drink mass
    /// (`ByVolumeDosing.usStandardDrinkGrams`, 14 g) so alcohol logged "2 drinks"
    /// still drives the zero-order ceiling model instead of falling back to the
    /// generic phase bell. A volume unit (mL of a *drink*) isn't a mass and
    /// returns `nil` so the caller falls back rather than mistaking mL for mg.
    nonisolated static func zeroOrderDoseMilligrams(amount: Double, unit: String) -> Double? {
        guard amount.isFinite, amount > 0 else { return nil }
        switch unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "g", "gram", "grams": return amount * 1_000
        case "mg", "milligram", "milligrams": return amount
        case "drink", "drinks", "unit", "units", "standard drink", "standard drinks":
            // NIAAA US standard drink = 14 g ethanol (matches
            // `ByVolumeDosing.usStandardDrinkGrams`, inlined as this is nonisolated).
            return amount * 14 * 1_000
        default: return nil
        }
    }

    nonisolated static func effectShape(at minutes: Double, for s: ActiveSubstanceState) -> Double {
        guard minutes >= 0 else { return 0 }
        // Zero-order substances (alcohol) ignore the fixed phase windows: their curve is a dose-scaled
        // linear-decline BAC shape, so duration grows with dose — the defining property the bell can't show.
        if let (kinetics, doseMg) = zeroOrderKinetics(for: s),
           let shape = PKModel.zeroOrderShape(doseMg: doseMg, at: minutes, kinetics: kinetics) {
            return shape
        }
        let onsetEnd = s.onsetEndMinutes
        let peakEnd = max(s.peakEndMinutes, onsetEnd + 2)
        let offsetEnd = max(s.offsetEndMinutes, peakEnd + 1)
        let comeupEnd = Self.effectiveComeupEnd(for: s, onsetEnd: onsetEnd, peakEnd: peakEnd)

        let sigmaUp = max((comeupEnd - onsetEnd) / Self.comeupSharpness, 1e-3)
        let sigmaDown = max((offsetEnd - peakEnd) / Self.offsetSharpness, 1e-3)
        let center = (comeupEnd + peakEnd) / 2
        // Round the flat crest's edges inward for a soft dome — but never by more
        // than the adjacent shoulder's own width. A substance whose listed `peak`
        // phase runs many times longer than its come-up (a hypnotic like zolpidem:
        // a ~1 h come-up but a 3–6 h peak) would otherwise have its *time to peak*
        // dragged to the center of that long plateau: the come-up is over, yet the
        // curve keeps climbing for another hour-plus before it reads as "peak".
        // Capping the inward shift at the come-up / offset width keeps the plateau
        // anchored to when the effects actually plateau (end of come-up) and lift
        // (start of offset). For ordinary profiles — where the peak phase is at most
        // ~4× the come-up — the cap never binds, so their tuned shape is unchanged.
        let leftEdge = comeupEnd + min((center - comeupEnd) * Self.peakDome, comeupEnd - onsetEnd)
        let rightEdge = peakEnd - min((peakEnd - center) * Self.peakDome, offsetEnd - peakEnd)

        // The crest is a shallow dome, not a lid. Returning a literal `1` across
        // the whole peak band drew a trapezoid — a near-vertical rise into an
        // exactly flat top — which is not a shape any pharmacokinetics produces.
        // It was most visible exactly where the cap above binds hardest: a
        // profile with a short come-up and a long peak (methamphetamine IV: a
        // ~2-minute rise into 91 minutes of dead-flat 1.0). The dome keeps the
        // plateau's *timing* untouched — leftEdge/rightEdge are unchanged, so
        // zolpidem's time-to-peak stays anchored where the comment above put it
        // — and only lets the level drift across it, peaking at the crest's
        // midpoint. The shoulders anchor to the dome's edge value so the curve
        // stays continuous, and the maximum is still exactly 1 at the midpoint,
        // so nothing downstream needs to renormalize.
        let crestHalfSpan = max((rightEdge - leftEdge) / 2, 0)
        let crestMid = (leftEdge + rightEdge) / 2
        func crest(_ at: Double) -> Double {
            guard crestHalfSpan > 1e-6 else { return 1 }
            let offset = (at - crestMid) / crestHalfSpan
            return 1 - Self.crestFall * offset * offset
        }

        if minutes <= leftEdge {
            let z = (leftEdge - minutes) / sigmaUp
            return crest(leftEdge) * exp(-0.5 * z * z)
        }
        if minutes <= rightEdge { return crest(minutes) }
        let z = (minutes - rightEdge) / sigmaDown
        return crest(rightEdge) * exp(-0.5 * z * z)
    }

    /// The come-up boundary the rising shoulder is fit to — synthesizing a
    /// plausible climb when the source data carries **no come-up phase**.
    ///
    /// Many profiles list only onset → peak (kratom oral: onset, peak, offset,
    /// no come-up), so `comeupEndMinutes` collapses onto `onsetEnd`. The old
    /// `max(comeupEnd, onsetEnd + 1)` left a 1-minute window → the curve shot up
    /// as a near-vertical wall, which is wrong for an absorbed (oral) dose. When
    /// the explicit window is essentially empty we instead borrow a come-up from
    /// the dose's own timing: as long as the onset itself, floored at 12 min, but
    /// capped at 60 % of the onset→peak gap so a flat peak still remains. Because
    /// it scales off `onsetEnd`, a 30-min oral onset yields a broad ~30-min climb
    /// while a 2-min insufflated onset stays quick — route falls out of the data.
    /// A genuine come-up in the data is kept exactly as given.
    ///
    /// The floor is itself capped by the onset. A flat `max(onsetEnd * 0.6, 8)`
    /// gave *every* route at least an 8-minute climb, so an insufflated or IV
    /// dose with a 2-minute onset was drawn with a 10-minute absorption shoulder
    /// it does not have — the "rising shoulders on non-oral routes" report, and
    /// the exact opposite of what the paragraph above promises. Flooring at
    /// `min(comeupFloorMinutes, onsetEnd)` keeps the slow climb for anything
    /// genuinely absorbed while letting a fast route stay as fast as its data.
    nonisolated static func effectiveComeupEnd(for s: ActiveSubstanceState, onsetEnd: Double, peakEnd: Double) -> Double {
        let explicit = s.comeupEndMinutes - onsetEnd
        let gap = peakEnd - onsetEnd
        let floor = min(Self.comeupFloorMinutes, max(onsetEnd, 0))
        let window = explicit > 1
            ? explicit
            : min(max(onsetEnd * 0.6, floor), gap * 0.5)
        return onsetEnd + max(window, 1e-3)
    }

    /// Longest come-up the model will synthesize when the data lists none — and
    /// only for a dose whose onset is at least this long. See
    /// ``effectiveComeupEnd(for:onsetEnd:peakEnd:)``.
    nonisolated static let comeupFloorMinutes: Double = 8

    /// σ↑ divisor: how many standard deviations the come-up window spans. Higher =
    /// steeper rise hugging the come-up band.
    nonisolated static let comeupSharpness: Double = 1.7
    /// σ↓ divisor: how many standard deviations the offset window spans. `2.4`
    /// lands the falling shoulder at ~5 % of peak right as the offset band closes
    /// — a graceful touchdown rather than a clipped cliff. Lowering it pushes
    /// residual effect past the substance's own stated end.
    nonisolated static let offsetSharpness: Double = 2.4
    /// Peak rounding: `0` keeps a flat plateau across the whole peak band, `1`
    /// collapses it to a point (pure split-normal bell). `0.46` is a rounded crest
    /// that still broadens with peak duration.
    nonisolated static let peakDome: Double = 0.46
    /// How far the crest sags at the edges of the peak band, as a fraction of the
    /// maximum. Small on purpose: enough that a long peak reads as a dome rather
    /// than a flat lid, not so much that the plateau stops looking like a plateau.
    nonisolated static let crestFall: Double = 0.06

    /// Acute-tolerance (tachyphylaxis) multiplier on the descending limb. For
    /// `s.tachyphylaxis == 0` it's identity, so non-tolerant compounds keep the
    /// pure Bateman offset. For releasers (stimulants, empathogens) the felt
    /// effect crashes faster than plasma: across the offset window
    /// `[peakEnd, total]` we fade the curve by up to `tachyphylaxis` via a
    /// smoothstep, so it lands at baseline by `totalMinutes` instead of trailing
    /// off on the slow elimination tail. Onset and peak are untouched.
    nonisolated static func toleranceGate(at minutes: Double, for s: ActiveSubstanceState) -> Double {
        let kappa = s.tachyphylaxis
        guard kappa > 0 else { return 1 }
        let peakEnd = s.peakEndMinutes
        let end = max(s.totalMinutes, peakEnd + 1)
        guard minutes > peakEnd else { return 1 }
        let x = min(1, (minutes - peakEnd) / (end - peakEnd))
        let smooth = x * x * (3 - 2 * x)
        return max(0, 1 - kappa * smooth)
    }

    /// Minutes after the dose at which the curve has returned to baseline — the
    /// point past which nothing remains to draw. The phase curve eases to zero by
    /// the end of the offset, so the draw end is simply that point: no long
    /// elimination tail to chase, and no flat near-zero skirt stretching the axis
    /// (an explicit `total` or an afterglow phase can sit beyond it). Capped at
    /// the display window.
    nonisolated static func curveExtent(for s: ActiveSubstanceState, params _: PKCurveParams) -> Double {
        // Zero-order substances clear in a dose-scaled time (≈ F·Dose/Vmax), not at a fixed offset.
        if let (kinetics, doseMg) = zeroOrderKinetics(for: s) {
            let clear = PKModel.zeroOrderClearMinutes(doseMg: doseMg, kinetics: kinetics)
            if clear > 0 { return min(max(clear * 1.04, 1), Self.maxDisplayMinutes) }
        }
        let peakEnd = max(s.peakEndMinutes, s.comeupEndMinutes)
        let offsetEnd = max(s.offsetEndMinutes, peakEnd + 1)
        // The falling Gaussian sits at ~5% of peak at `offsetEnd`; draw ½σ further
        // so it eases to ~1–2% and lands on the axis instead of being clipped.
        let sigmaDown = (offsetEnd - peakEnd) / Self.offsetSharpness
        let end = offsetEnd + sigmaDown * 0.5
        return min(max(end, 1), Self.maxDisplayMinutes)
    }

    /// Minutes after the dose past which this curve is no longer *visible* beside
    /// a curve of magnitude `peerMagnitude` — as opposed to ``curveExtent``, which
    /// asks only when the curve reaches its own baseline.
    ///
    /// The two differ by a lot, and the gap is what left the Active Now card with
    /// most of its width empty. `curveExtent` is amplitude-blind: it ends each
    /// curve at ~1–2 % of *its own* peak. A small or heavily-tolerant dose beside
    /// a tall one is drawn against the tall one's scale, so its last hours sit far
    /// below one device pixel while still sizing the axis — a long-acting
    /// background dose could hold the window open until 6 AM with nothing on it.
    ///
    /// Solved in closed form rather than by sampling: the falling limb is
    /// `crest · exp(-½z²)` with `z = (t - rightEdge) / σ↓`, so the moment it
    /// crosses a threshold is `rightEdge + σ↓·√(-2·ln θ)`. That keeps this cheap
    /// enough to call from a view body — no 240-step scan, no Newton solve — and
    /// it never returns more than ``curveExtent``, so the window can only shrink.
    /// The tolerance gate is deliberately ignored: it only pulls the tail in
    /// further, so skipping it errs toward keeping pixels that might be visible.
    nonisolated static func visibleExtent(
        for s: ActiveSubstanceState,
        params: PKCurveParams,
        peerMagnitude: Double,
        threshold: Double = 0.02,
    ) -> Double {
        let full = curveExtent(for: s, params: params)
        // Zero-order (alcohol) isn't a Gaussian tail — leave its extent alone.
        if zeroOrderKinetics(for: s) != nil { return full }
        let magnitude = max(s.doseMagnitude, 0)
        let peer = max(peerMagnitude, magnitude)
        guard magnitude > 0, peer > 0, threshold > 0 else { return full }

        let onsetEnd = s.onsetEndMinutes
        let peakEnd = max(s.peakEndMinutes, onsetEnd + 2)
        let offsetEnd = max(s.offsetEndMinutes, peakEnd + 1)
        let comeupEnd = effectiveComeupEnd(for: s, onsetEnd: onsetEnd, peakEnd: peakEnd)
        let sigmaDown = max((offsetEnd - peakEnd) / offsetSharpness, 1e-3)
        let center = (comeupEnd + peakEnd) / 2
        let rightEdge = peakEnd - min((peakEnd - center) * peakDome, offsetEnd - peakEnd)

        // The shape value at which this dose stops registering against `peer`.
        let cutoff = threshold * peer / magnitude
        // Already below the bar at its own crest: it never reads as anything, so
        // let its own peak bound it rather than an invisible tail.
        guard cutoff < 1 else { return min(max(rightEdge, 1), full) }
        let z = (-2 * log(cutoff)).squareRoot()
        return min(max(rightEdge + sigmaDown * z, 1), full)
    }

    // MARK: - Stacked Merge

    /// Groups substance states by lowercased substance name, preserving original order.
    nonisolated static func stackedGroups(of substances: [ActiveSubstanceState]) -> [[ActiveSubstanceState]] {
        // Group by (substance, route) so that e.g. insufflated heroin and smoked
        // heroin draw as separate curves even when "Stack Redoses" is on. Doses
        // of the same substance via the same route still stack into a combined
        // curve as before.
        var order: [String] = []
        var buckets: [String: [ActiveSubstanceState]] = [:]
        for s in substances {
            let key = "\(s.substanceName.lowercased())|\(s.route.lowercased())"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = [s]
            } else {
                buckets[key]?.append(s)
            }
        }
        return order.compactMap { buckets[$0] }
    }

    /// Combined intensity of a group at a given global time (minutes since
    /// `earliestDose`) — linear dose superposition passed through one saturating
    /// Hill link. `params` holds the precomputed Bateman fit per dose, aligned
    /// to `group`. The caller normalizes by the combined peak
    /// (``peakCurveValue(substances:stackedGroups:earliestDose:maxDose:stackRedoses:)``).
    nonisolated static func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState], params: [PKCurveParams], earliestDose: Date) -> Double {
        // Linear dose superposition, then ONE saturating Hill link. Each dose
        // contributes `magnitude × bell`; summing the *unclamped* magnitudes
        // means a genuine 4× stack reaches 4× the input, and a single combined
        // dose of the same total lands identically — `4×20 mg ≡ 1×80 mg` falls
        // out for free. Hill then saturates the sum so overlapping crests flatten
        // (no dome) while doses spaced wider than their bells stay distinct humps.
        var sum = 0.0
        for (i, dose) in group.enumerated() {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let local = global - offset
            guard local >= 0 else { continue }
            sum += dose.doseMagnitude * Self.intensity(at: local, for: dose, params: params[i])
        }
        return Self.hill(sum)
    }

    /// Half-saturation point of the effect link, in dose-magnitude units: a dose
    /// at `amount = hillEC50 × heavy_threshold` sits at half the saturated
    /// height. Pinned *above* a typical single dose so single doses live in
    /// Hill's near-linear region — their come-up stays uncompressed — while
    /// stacks push into saturation and flatten. Tuned with the offline curve
    /// tools (a scorer verifies the `4×20 ≡ 1×80` superposition invariant).
    nonisolated static let hillEC50: Double = 0.78
    /// Hill exponent — saturation sharpness and stacking dynamic range. `1.4`
    /// gives the flattest overlap crest while still separating 2- from 4-dose
    /// stacks; raising it pushes stacks harder toward the ceiling.
    nonisolated static let hillExponent: Double = 1.4

    /// Saturating dose→height link `Cʰ / (EC50ʰ + Cʰ)` (Emax = 1). Applied once
    /// to the superposed dose magnitude, so a single dose and a stack of the
    /// same total render identically and overlapping crests saturate flat.
    nonisolated static func hill(_ magnitude: Double) -> Double {
        guard magnitude > 0 else { return 0 }
        let m = pow(magnitude, hillExponent)
        return m / (pow(hillEC50, hillExponent) + m)
    }

    nonisolated static func stackedGroupRange(_ group: [ActiveSubstanceState], earliestDose: Date) -> (start: Double, end: Double) {
        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        for dose in group {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            start = min(start, offset)
            end = max(end, offset + Self.curveExtent(for: dose, params: Self.pkParams(for: dose)))
        }
        return (start, end)
    }

    // MARK: - Lane Layout

    /// One lane per distinct substance, in first-dose order, carrying every dose
    /// of that substance so redoses share a lane.
    nonisolated static func laneGroups(of substances: [ActiveSubstanceState]) -> [LaneGroup] {
        var order: [String] = []
        var doses: [String: [ActiveSubstanceState]] = [:]
        var colorOf: [String: String] = [:]
        for s in substances {
            let key = s.substanceName.lowercased()
            if doses[key] == nil {
                order.append(key)
                colorOf[key] = s.colorHex
            }
            doses[key, default: []].append(s)
        }
        return order.map { key in
            LaneGroup(name: doses[key]!.first!.substanceName, colorHex: colorOf[key]!, doses: doses[key]!)
        }
    }

    /// Distinct marker substances with no curve lane, in first-dose order — each
    /// becomes its own labeled lane so a logged dose never floats unattached.
    nonisolated static func markerOnlyLanes(excluding curveLanes: [LaneGroup], markers: [DoseMarker]) -> [MarkerLane] {
        let curveNames = Set(curveLanes.map { $0.name.lowercased() })
        var order: [String] = []
        var byKey: [String: [DoseMarker]] = [:]
        var meta: [String: (name: String, colorHex: String)] = [:]
        for marker in markers {
            let key = marker.substanceName.lowercased()
            guard !curveNames.contains(key) else { continue }
            if byKey[key] == nil {
                order.append(key)
                meta[key] = (marker.substanceName, marker.colorHex)
            }
            byKey[key, default: []].append(marker)
        }
        return order.map { MarkerLane(name: meta[$0]!.name, colorHex: meta[$0]!.colorHex, markers: byKey[$0]!) }
    }
}
