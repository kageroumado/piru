#if os(iOS)
    import ActivityKit
#endif
import Foundation

// Wire format for the Piru Live Activity widget extension.
//
// `PiruActivityAttributes` defines two parts of the data the app and extension
// exchange via ActivityKit:
//
// - **Static attributes** (this struct's stored properties): set once at
//   `Activity.request(…)` time and immutable for the lifetime of the activity.
//   Currently just `startTime`.
// - **`ContentState`**: mutable per-update payload pushed via `activity.update(…)`.
//   Drives the widget's timeline graph, progress bar, and timer labels.
//
// Because the app target and the widget extension can be on different versions
// at runtime (a widget extension launched against an older activity, or vice
// versa after an upgrade), every field on `ContentState`, `ActiveSubstanceState`,
// and the static attributes MUST be treated as a stable, append-only contract:
//
// - Never remove or rename fields without a deprecation window.
// - New fields must be optional (`Codable` decoding tolerates missing keys) or
//   provide a default in a custom `init(from:)` — see `ActiveSubstanceState`'s
//   `doseIntensity` for the pattern.
#if os(iOS)
    nonisolated struct PiruActivityAttributes: ActivityAttributes {
        nonisolated struct ContentState: Codable, Hashable {
            var activeSubstances: [ActiveSubstanceState]
            var lastUpdated: Date
        }

        let startTime: Date
    }
#endif

nonisolated struct ActiveSubstanceState: Codable, Hashable {
    /// What to call the dose: its resolved title (a relabel, the product as
    /// logged, or the catalog's display title). For showing only — a title is
    /// not a name the catalog resolves ("K" is a user's relabel of Ketamine and
    /// also an alias Clonazepam lists), so every lookup reads ``canonicalName``.
    let substanceName: String
    /// The library's canonical name for the substance, the key for every lookup,
    /// color and relabel. Equals ``substanceName`` for a substance the catalog
    /// does not know.
    var canonicalName: String {
        canonical ?? substanceName
    }

    /// ``canonicalName`` when it differs from the title, else `nil` — encoded
    /// only then, to keep the Live Activity inside ActivityKit's 4 KB budget.
    private let canonical: String?
    let tint: P3Color
    let doseTimestamp: Date
    let amount: Double
    let unit: String
    let route: String
    /// The phase boundaries, in minutes after the dose, are the effect curve's
    /// own anchors (``TimelineCurveModel/curveAnchors(onsetEnd:comeupEnd:peakEnd:offsetEnd:comeupSpread:offsetSpread:)``):
    /// both initializers pass what they are given through it. A come-up the
    /// data leaves out is the one the curve synthesizes, and come-up and offset
    /// spreads are folded into the boundary they move. Every reader — the
    /// phase word, the milestone marks, the Live Activity countdown — therefore
    /// names the phase the drawn curve is in.
    let onsetEndMinutes: Double
    let comeupEndMinutes: Double
    let peakEndMinutes: Double
    let offsetEndMinutes: Double
    let afterglowEndMinutes: Double?
    /// When the dose's effects end: never before the curve's tail lands at
    /// ``offsetEndMinutes``.
    let totalMinutes: Double
    /// Dose intensity used to scale the timeline curve height, clamped to
    /// `[0.05, 1.0]`.
    ///
    /// Computed by `ActiveSubstanceState.computeDoseIntensity(dose:ladder:)`:
    /// `amount / heavy_threshold` in the ladder's unit, with looser fallbacks
    /// (strong upper, common upper × 1.5) when `heavy` isn't defined. Substances
    /// with no dose-range data, and doses in a unit the ladder can't express,
    /// fall back to `unknownIntensity` (0.60) — a neutral mid-common-ish
    /// height. Sub-threshold doses are floored at `minimumIntensity` (0.05) so
    /// they still render as a visible nub instead of disappearing.
    let doseIntensity: Double

    /// Unclamped dose magnitude — `amount / heavy_threshold` with the *same*
    /// reference as ``doseIntensity`` but **without the 1.0 cap**. This is the
    /// linear quantity the timeline superposes: stacked doses sum their
    /// magnitudes (`4×0.7 → 2.8`) and a single combined dose of the same total
    /// (`80 mg → 2.8`) lands identically, so the merged curve passes one
    /// saturating Hill link and `4×20 mg ≡ 1×80 mg` falls out for free. Floored
    /// at `minimumIntensity`; defaults to ``doseIntensity`` when not supplied.
    let doseMagnitude: Double

    /// Where the substance's **sourced** heavy-dose bound falls on the
    /// ``doseMagnitude`` scale, or `nil` when its dose ladder carries no heavy
    /// bound at all.
    ///
    /// Because magnitude is `amount / heavy_threshold`, this is `1.0` whenever
    /// the denominator *is* a published `heavy` value — so the number itself
    /// carries no new information, but its presence does: it is the difference
    /// between a threshold somebody wrote down and one
    /// `ActiveSubstanceState.heavyReference(for:)` improvised from the
    /// strong/common bounds so the curve would have *some* height. Only the
    /// former may be drawn as a marked region on the graph; the fallbacks scale
    /// a curve honestly enough but are nobody's stated threshold.
    ///
    /// Route caveat: the ladder is the one that scaled this dose, which for a
    /// route with no doses of its own is another route's (see
    /// `Substance.scalingLadder(for:)`). That is
    /// already true of the curve's whole height, so the band inherits it rather
    /// than introducing it.
    let heavyThresholdMagnitude: Double?

    /// `true` when the substance has no dose ladder to scale this dose
    /// against, or the dose's unit can't be read on it, so ``doseIntensity`` is
    /// the neutral `ActiveSubstanceState.unknownIntensity` rather than a reading of
    /// the amount. The timeline draws such a curve at that fixed height and
    /// dotted, so it never reads as the substance's strongest dose.
    let doseIsUnscaled: Bool

    /// Acute-tolerance (tachyphylaxis) strength, `0...1`, from the substance's
    /// category (`SubstanceCategory.acuteToleranceFactor`). Drives the timeline
    /// curve's descending-limb gate: stimulants/empathogens crash faster than
    /// their plasma curve, so the felt effect returns to baseline by
    /// `totalMinutes` rather than trailing off on the slow elimination tail. `0`
    /// leaves the pure Bateman offset unchanged.
    let tachyphylaxis: Double

    /// The user's body weight (kg) captured when this state was built. Only zero-order elimination
    /// reads it — a heavier body clears a fixed gram dose faster (`Vmax ∝ weight`), so the alcohol
    /// curve narrows with weight. Riding inside the (immutable, `Hashable`) state keeps the off-main
    /// curve math weight-aware without a shared global, and folds weight into the model cache key for
    /// free. Defaults to ``PKModel/referenceBodyWeightKg`` for first-order doses, which ignore it.
    let bodyWeightKg: Double

    /// Saturable (zero-order) elimination parameters, already scaled to ``bodyWeightKg`` — non-nil
    /// **exactly** for the substances the bundled DB's `zero_order_kinetics` carries a row for, and
    /// therefore the switch onto the dose-scaled linear-decline curve.
    ///
    /// It rides on the state because the curve engine is shared with the widget and the Live Activity,
    /// which link no GRDB and cannot resolve it themselves: the phone answers "is this substance
    /// zero-order, and with what Vmax" once, at build time, and every renderer reads that answer.
    let zeroOrder: PKModel.ZeroOrderKinetics?

    /// Widths (max − min, minutes) of the come-up, peak, and offset phase
    /// ranges the boundary midpoints came from, so a "peak 3–5 h" profile
    /// draws broader and softer than a "peak 4 h" one. Peak spread broadens the
    /// crest dome. Come-up and offset spreads move the full-effect and tail
    /// anchors, so the initializers fold them into ``comeupEndMinutes`` and
    /// ``offsetEndMinutes`` and store `nil` here; a payload from a build that
    /// stored the raw boundaries is folded when it is decoded. `nil` means zero
    /// spread.
    let comeupSpreadMinutes: Double?
    let peakSpreadMinutes: Double?
    let offsetSpreadMinutes: Double?

    init(substanceName: String, canonicalName: String? = nil, tint: P3Color, doseTimestamp: Date, amount: Double, unit: String, route: String, onsetEndMinutes: Double, comeupEndMinutes: Double, peakEndMinutes: Double, offsetEndMinutes: Double, afterglowEndMinutes: Double?, totalMinutes: Double, doseIntensity: Double = 1.0, doseMagnitude: Double? = nil, heavyThresholdMagnitude: Double? = nil, doseIsUnscaled: Bool = false, tachyphylaxis: Double = 0, bodyWeightKg: Double = PKModel.referenceBodyWeightKg, zeroOrder: PKModel.ZeroOrderKinetics? = nil, comeupSpreadMinutes: Double? = nil, peakSpreadMinutes: Double? = nil, offsetSpreadMinutes: Double? = nil) {
        self.substanceName = substanceName
        self.canonical = canonicalName == substanceName ? nil : canonicalName
        self.tint = tint
        self.doseTimestamp = doseTimestamp
        self.amount = amount
        self.unit = unit
        self.route = route
        let timing = Self.curveTiming(
            onsetEnd: onsetEndMinutes, comeupEnd: comeupEndMinutes, peakEnd: peakEndMinutes,
            offsetEnd: offsetEndMinutes, afterglowEnd: afterglowEndMinutes, total: totalMinutes,
            comeupSpread: comeupSpreadMinutes, offsetSpread: offsetSpreadMinutes,
        )
        self.onsetEndMinutes = timing.anchors.onsetEnd
        self.comeupEndMinutes = timing.anchors.comeupEnd
        self.peakEndMinutes = timing.anchors.peakEnd
        self.offsetEndMinutes = timing.anchors.offsetEnd
        self.afterglowEndMinutes = timing.afterglowEnd
        self.totalMinutes = timing.total
        self.doseIntensity = doseIntensity
        self.doseMagnitude = doseMagnitude ?? doseIntensity
        self.heavyThresholdMagnitude = heavyThresholdMagnitude
        self.doseIsUnscaled = doseIsUnscaled
        self.tachyphylaxis = tachyphylaxis
        self.bodyWeightKg = bodyWeightKg
        self.zeroOrder = zeroOrder
        self.comeupSpreadMinutes = nil
        self.peakSpreadMinutes = peakSpreadMinutes
        self.offsetSpreadMinutes = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try c.decode(String.self, forKey: .substanceName)
        // Absent when the title is the canonical name, and on an activity started
        // by an older build, whose title was the only name it carried.
        canonical = try c.decodeIfPresent(String.self, forKey: .canonical)
        tint = try c.decode(P3Color.self, forKey: .tint)
        doseTimestamp = try c.decode(Date.self, forKey: .doseTimestamp)
        amount = try c.decode(Double.self, forKey: .amount)
        unit = try c.decode(String.self, forKey: .unit)
        route = try c.decode(String.self, forKey: .route)
        // Folded through the curve's anchors like the memberwise init, so a payload
        // an older build encoded with raw boundaries reads the same as a new one.
        let timing = try Self.curveTiming(
            onsetEnd: c.decode(Double.self, forKey: .onsetEndMinutes),
            comeupEnd: c.decode(Double.self, forKey: .comeupEndMinutes),
            peakEnd: c.decode(Double.self, forKey: .peakEndMinutes),
            offsetEnd: c.decode(Double.self, forKey: .offsetEndMinutes),
            afterglowEnd: c.decodeIfPresent(Double.self, forKey: .afterglowEndMinutes),
            total: c.decode(Double.self, forKey: .totalMinutes),
            comeupSpread: c.decodeIfPresent(Double.self, forKey: .comeupSpreadMinutes),
            offsetSpread: c.decodeIfPresent(Double.self, forKey: .offsetSpreadMinutes),
        )
        onsetEndMinutes = timing.anchors.onsetEnd
        comeupEndMinutes = timing.anchors.comeupEnd
        peakEndMinutes = timing.anchors.peakEnd
        offsetEndMinutes = timing.anchors.offsetEnd
        afterglowEndMinutes = timing.afterglowEnd
        totalMinutes = timing.total
        doseIntensity = try c.decodeIfPresent(Double.self, forKey: .doseIntensity) ?? 1.0
        doseMagnitude = try c.decodeIfPresent(Double.self, forKey: .doseMagnitude) ?? doseIntensity
        // Absent on an activity started by an older build: no marked region, which
        // is the same answer as a substance with no published heavy bound.
        heavyThresholdMagnitude = try c.decodeIfPresent(Double.self, forKey: .heavyThresholdMagnitude)
        doseIsUnscaled = try c.decodeIfPresent(Bool.self, forKey: .doseIsUnscaled) ?? false
        tachyphylaxis = try c.decodeIfPresent(Double.self, forKey: .tachyphylaxis) ?? 0
        bodyWeightKg = try c.decodeIfPresent(Double.self, forKey: .bodyWeightKg) ?? PKModel.referenceBodyWeightKg
        // Absent on an activity started by an older build: the dose draws the fixed phase bell, which
        // is what every first-order substance gets and what alcohol got before this field existed.
        zeroOrder = try c.decodeIfPresent(PKModel.ZeroOrderKinetics.self, forKey: .zeroOrder)
        // Absent on an activity started by an older build: zero spread — the pure midpoint fit.
        comeupSpreadMinutes = nil
        peakSpreadMinutes = try c.decodeIfPresent(Double.self, forKey: .peakSpreadMinutes)
        offsetSpreadMinutes = nil
    }

    /// The boundaries a state stores: the curve's anchors, the afterglow
    /// shifted with the tail so it keeps its length, and a total no earlier
    /// than the tail landing.
    private static func curveTiming(
        onsetEnd: Double, comeupEnd: Double, peakEnd: Double, offsetEnd: Double,
        afterglowEnd: Double?, total: Double, comeupSpread: Double?, offsetSpread: Double?,
    ) -> (anchors: TimelineCurveModel.CurveAnchors, afterglowEnd: Double?, total: Double) {
        let anchors = TimelineCurveModel.curveAnchors(
            onsetEnd: onsetEnd, comeupEnd: comeupEnd, peakEnd: peakEnd, offsetEnd: offsetEnd,
            comeupSpread: comeupSpread, offsetSpread: offsetSpread,
        )
        let tailShift = anchors.offsetEnd - offsetEnd
        return (
            anchors,
            afterglowEnd.map { max($0 + tailShift, anchors.offsetEnd) },
            max(total, anchors.offsetEnd),
        )
    }
}

// MARK: - Timing

nonisolated extension ActiveSubstanceState {
    /// When this dose's curve runs out: `doseTimestamp + totalMinutes`.
    var endDate: Date {
        doseTimestamp.addingTimeInterval(totalMinutes * 60)
    }

    /// Every instant the Live Activity's phase readout changes for this dose:
    /// the boundaries `SessionTiming.nextTransition` counts down to, ending
    /// with ``endDate``.
    var phaseChangeDates: [Date] {
        var minutes = [onsetEndMinutes, comeupEndMinutes, peakEndMinutes]
        if afterglowEndMinutes != nil { minutes.append(offsetEndMinutes) }
        minutes.append(totalMinutes)
        return minutes.map { doseTimestamp.addingTimeInterval($0 * 60) }
    }
}

#if os(iOS)
    nonisolated extension PiruActivityAttributes.ContentState {
        /// When the last curve in this state runs out, or `nil` for an empty state.
        var endDate: Date? {
            activeSubstances.map(\.endDate).max()
        }

        /// Whether every curve in this state has run out by `now`. An empty
        /// state has nothing left to show, so it counts as run out.
        func hasRunOut(at now: Date = .now) -> Bool {
            guard let endDate else { return true }
            return endDate <= now
        }
    }
#endif
