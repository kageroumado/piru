import SwiftUI

/// The Canvas drawing engine behind ``TimelineGraphView`` — every draw pass,
/// path builder, and scrub-sampling routine, with no view-identity dependency.
/// Split out of `TimelineGraphView.swift` the same way `TimelineGraphSupport`
/// was: the view owns state (zoom/pan/scrub, the derived-model cache plumbing,
/// gestures) and windowing math; this struct is a value snapshot of everything
/// drawing reads, rebuilt per body evaluation — never cached in `@State`, so it
/// always reflects the state being rendered.
struct TimelineGraphRenderer {
    let substances: [ActiveSubstanceState]
    let markers: [DoseMarker]
    /// Session notes placed on the time axis; the rated ones also draw the
    /// Shulgin step lane. The tappable glyphs are SwiftUI overlays in the view.
    let noteMarkers: [NoteMarker]
    let derived: TimelineCurveModel.Derived
    let currentTime: Date
    let compact: Bool
    let stackRedoses: Bool
    let showNowIndicator: Bool
    let highlighted: String?
    let chartFrame: Bool
    let vitals: SessionVitals?
    let vitalsBandEnlarged: Bool
    /// Lane-mode gate, resolved by the view (it owns the AppStorage prefs).
    let laneMode: Bool
    /// Compact baseline + dose-dot gate, resolved by the view.
    let showCompactMarkers: Bool
    /// X position (canvas points) of the active scrub rule, or nil at rest —
    /// the one piece of view `@State` drawing reads (it suppresses the resting
    /// now-dots and draws the scrub rule).
    let scrubX: CGFloat?
    /// Whether the view draws phase milestones over the curves, resolved by the
    /// view (``TimelineGraphView/showsMilestones``). The relative-hour row
    /// yields wherever a milestone reaches up into it.
    var showsMilestones = false

    /// The visible-window snapshot, computed by the view's windowing math.
    struct Viewport {
        let visibleStart: Double
        let visibleSpan: Double
        let totalSpan: Double
        let maxPanOffset: Double
    }

    var earliestDose: Date {
        derived.earliestDose
    }

    /// Height reserved for time labels below the graph
    private var labelAreaHeight: CGFloat {
        compact ? 0 : GraphMetrics.axisLabels
    }

    /// Height reserved for relative time labels above the graph
    private var topLabelAreaHeight: CGFloat {
        compact ? 0 : GraphMetrics.topLabels
    }

    /// Whether the companion vitals lane is drawn — the full graph only, and only
    /// when the session actually has heart-rate samples (BP alone never draws it).
    var vitalsBandActive: Bool {
        guard !compact, let vitals, vitals.hasHeartRate else { return false }
        return true
    }

    /// Height of the vitals lane's drawable strip (grows when enlarged).
    private var vitalsBandHeight: CGFloat {
        GraphMetrics.vitalsBand(enlarged: vitalsBandEnlarged)
    }

    /// Vertical space the vitals lane consumes below the effect curves, or 0.
    var vitalsBandTotal: CGFloat {
        vitalsBandActive ? GraphMetrics.vitalsBandTotal(enlarged: vitalsBandEnlarged) : 0
    }

    /// Whether the Shulgin-rating lane is drawn — the full graph only, and only
    /// when at least one note carries a rating.
    var shulginLaneActive: Bool {
        !compact && noteMarkers.contains { $0.shulgin != nil }
    }

    /// Vertical space the Shulgin lane consumes below the effect curves, or 0.
    var shulginLaneTotal: CGFloat {
        shulginLaneActive ? GraphMetrics.shulginLaneTotal : 0
    }

    /// Everything stacked under the effect curves: the Shulgin lane, then the
    /// vitals lane. The now-rule and scrub rule extend through all of it.
    var belowCurvesTotal: CGFloat {
        shulginLaneTotal + vitalsBandTotal
    }

    /// One lane per distinct substance, in first-dose order, carrying every dose
    /// of that substance so redoses share a lane.
    private var laneGroups: [TimelineCurveModel.LaneGroup] {
        TimelineCurveModel.laneGroups(of: substances)
    }

    /// Single-dose (non-stacked) height: the same saturating Hill link applied
    /// to this dose's magnitude, so a lone dose and a stacked group of the same
    /// total agree on height. The *unclamped* magnitude already encodes relative
    /// dose size (a 17 g alcohol renders ~half a 34 g, a heavy dose saturates),
    /// so no separate multi-dose multiplier is needed. `substances`/`maxDose`
    /// are retained for call-site symmetry with the stacked path.
    private func heightScale(for substance: ActiveSubstanceState) -> Double {
        TimelineCurveModel.heightScale(for: substance, substances: substances, maxDose: derived.maxDoseBySubstance)
    }

    /// Multiplier mapping the tallest curve to full height (capped so a tiny
    /// floor value can't blow up beyond the graph).
    private var yNormalization: Double {
        derived.yNormalization
    }

    /// How prominently a curve is drawn. On a busy day only the curves active
    /// *now* (or an isolated one) read at full strength; worn-off history and
    /// non-isolated curves fade back so the graph collapses to what matters.
    private enum CurveEmphasis {
        case full // active now, or the isolated substance
        case faded // worn-off history
        case dimmed // a non-isolated curve while another is isolated

        var fillOpacity: Double {
            switch self {
            case .full: 0.15
            case .faded: 0.06
            case .dimmed: 0.12
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .full: 1
            case .faded, .dimmed: 0.3
            }
        }
    }

    /// True when `currentTime` falls inside at least one curve's active window —
    /// i.e. the session is live *right now*. Worn-off fading only makes sense
    /// then: a fully historical day has no "now" on the axis to contrast
    /// against, so fading every curve would just wash the whole graph out.
    var hasActiveNow: Bool {
        guard showNowIndicator else { return false }
        return substances.contains { s in
            let elapsed = currentTime.timeIntervalSince(s.doseTimestamp) / 60
            return elapsed >= 0 && elapsed <= s.totalMinutes
        }
    }

    /// Emphasis for a curve given legend isolation and whether its effect window
    /// still includes `currentTime`. Compact contexts (thumbnails, accessory,
    /// Live Activity) and fully historical days always render at full strength —
    /// emphasis is a live, busy-full-graph declutter, not a global restyle.
    private func emphasis(name: String, isActive: Bool) -> CurveEmphasis {
        guard !compact else { return .full }
        if let highlighted, !highlighted.isEmpty {
            return highlighted.caseInsensitiveCompare(name) == .orderedSame ? .full : .dimmed
        }
        guard hasActiveNow else { return .full }
        return isActive ? .full : .faded
    }

    // MARK: - Geometry

    /// The drawable rectangle of the canvas, derived once from the view size so
    /// the `Canvas` closure, the pan/scrub gestures, and the callout overlay all
    /// map points ⇄ minutes through identical math.
    nonisolated struct GraphGeometry {
        let inset: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    func geometry(for size: CGSize) -> GraphGeometry {
        // The bordered chart runs flush to its side frame horizontally (no rounded
        // card corner to clear) but keeps a small vertical gap; every other host
        // uses a uniform inset.
        let hInset: CGFloat = compact ? GraphMetrics.compactInset : (chartFrame ? 0 : GraphMetrics.canvasInset)
        let vInset: CGFloat = compact ? GraphMetrics.compactInset : (chartFrame ? GraphMetrics.chartFrameVInset : GraphMetrics.canvasInset)
        return GraphGeometry(
            inset: hInset,
            top: vInset + topLabelAreaHeight,
            width: size.width - hInset * 2,
            // The effect-curve region excludes the companion vitals lane, which
            // sits in the extra height the host reserves below it (via
            // GraphMetrics.vitalsBandTotal), so the curves keep their normal size.
            height: size.height - labelAreaHeight - topLabelAreaHeight - vInset * 2 - belowCurvesTotal,
        )
    }

    // MARK: - Scrub inspection

    /// One curve's value at a scrubbed instant, used by both the in-canvas dots
    /// and the SwiftUI callout. `value` is the normalized [0, 1] height.
    struct ScrubSample: Identifiable {
        let id: Int
        let name: String
        let color: Color
        let value: Double
        let phase: LocalizedStringResource?
    }

    /// Localized phase label for a dose `elapsed` minutes in. Mirrors
    /// ``DosePhaseProgressBar/phase(_:elapsedMinutes:)`` boundary-for-boundary so
    /// the scrub readout names the same phase the dose-detail hero would.
    private func scrubPhaseName(elapsed: Double, for s: ActiveSubstanceState) -> LocalizedStringResource? {
        guard elapsed >= 0, elapsed <= s.totalMinutes else { return nil }
        if elapsed <= s.onsetEndMinutes { return "Onset" }
        if elapsed <= s.comeupEndMinutes { return "Come-up" }
        if elapsed <= s.peakEndMinutes { return "Peak" }
        if elapsed <= s.offsetEndMinutes { return "Offset" }
        return "Afterglow"
    }

    /// Every curve present at `global` minutes (since `earliestDose`), sorted
    /// strongest-first. Handles both stacked and per-dose rendering so the
    /// readout matches whatever the canvas drew.
    func scrubSamples(atMinute global: Double) -> [ScrubSample] {
        let yNorm = yNormalization
        var out: [ScrubSample] = []
        if stackRedoses {
            for (gi, group) in stackedGroups.enumerated() {
                guard let first = group.first else { continue }
                let (gStart, gEnd) = stackedGroupRange(group)
                guard global >= gStart, global <= gEnd else { continue }
                let v = min(1, max(0, stackedIntensity(atGlobalMinutes: global, group: group) * yNorm))
                guard v > 0.01 else { continue }
                out.append(ScrubSample(id: gi, name: first.substanceName, color: first.tint.color, value: v, phase: scrubPhaseName(elapsed: global - gStart, for: first)))
            }
        } else {
            for (i, s) in substances.enumerated() {
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let local = global - offset
                guard local >= 0, local <= TimelineCurveModel.curveExtent(for: s) else { continue }
                let v = min(1, max(0, TimelineCurveModel.intensity(at: local, for: s) * heightScale(for: s) * yNorm))
                guard v > 0.01 else { continue }
                out.append(ScrubSample(id: i, name: s.substanceName, color: s.tint.color, value: v, phase: scrubPhaseName(elapsed: local, for: s)))
            }
        }
        return out.sorted { $0.value > $1.value }
    }

    func scrubClockTime(atMinute global: Double) -> String {
        Self.timeLabelFormatter.string(from: earliestDose.addingTimeInterval(global * 60))
    }

    // MARK: - Milestones

    /// One phase-boundary mark: the phase glyph stacked over its clock time,
    /// the stack centered at (`x`, `y`) in canvas points.
    struct MilestonePlacement: Identifiable {
        let id: String
        let x: CGFloat
        let y: CGFloat
        let symbol: String
        let color: Color
        /// The clock time under the glyph, with its `~` prefix.
        let label: String
    }

    /// Font sizes and stack metrics shared by the view, which draws the
    /// milestones, and the relative-hour row, which steps around them.
    nonisolated enum MilestoneMetrics {
        static let glyphSize: CGFloat = 9
        static let labelSize: CGFloat = 9
        static let spacing: CGFloat = 1
        /// Glyph line plus label line plus the spacing between them.
        static let stackHeight: CGFloat = 23
        /// How far above its curve the stack's center sits.
        static let liftAboveCurve: CGFloat = 16
        /// Lowest center y, so the glyph never clips at the canvas top.
        static let minimumCenterY: CGFloat = 14

        static func labelFont() -> Font {
            .system(size: labelSize, weight: .medium, design: .rounded).monospacedDigit()
        }
    }

    /// Every visible milestone, placed: the glyph at the height its own curve
    /// has there, the clock time under it. Empty unless ``showsMilestones``.
    func milestonePlacements(geom: GraphGeometry, visibleStart: Double, visibleSpan: Double) -> [MilestonePlacement] {
        guard showsMilestones, geom.width > 0, visibleSpan > 0 else { return [] }
        var placements: [MilestonePlacement] = []
        for (doseIndex, dose) in substances.enumerated() {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            for milestone in Self.milestones(of: dose) {
                let global = offset + milestone.minutes
                let x = geom.inset + CGFloat((global - visibleStart) / visibleSpan) * geom.width
                guard x >= geom.inset, x <= geom.inset + geom.width else { continue }
                // The sample for *this* curve, not the tallest one there: with
                // two doses drawn, `scrubSamples` is sorted strongest-first and
                // its head can easily belong to the other one.
                guard let value = scrubSamples(atMinute: global)
                    .first(where: { $0.name == dose.substanceName })?.value else { continue }
                placements.append(MilestonePlacement(
                    id: "\(doseIndex)|\(milestone.minutes)",
                    x: x,
                    y: max(
                        MilestoneMetrics.minimumCenterY,
                        geom.top + geom.height * CGFloat(1 - value) - MilestoneMetrics.liftAboveCurve,
                    ),
                    symbol: milestone.symbol,
                    color: dose.tint.color,
                    label: "~\(scrubClockTime(atMinute: global))",
                ))
            }
        }
        return placements
    }

    /// Where a milestone's clock time is centered: under its glyph, slid
    /// sideways just enough to stay inside the plot when centering it there
    /// would run past either edge. The glyph keeps its moment.
    nonisolated static func milestoneLabelCenterX(_ x: CGFloat, labelWidth: CGFloat, geom: GraphGeometry) -> CGFloat {
        let lowest = geom.inset + labelWidth / 2
        let highest = geom.inset + geom.width - labelWidth / 2
        guard lowest <= highest else { return geom.inset + geom.width / 2 }
        return min(max(x, lowest), highest)
    }

    /// Each milestone's glyph-and-time stack as the view draws it, in canvas
    /// points: what the Now rule breaks around and the relative-hour row
    /// yields to.
    func milestoneFrames(_ milestones: [MilestonePlacement], context: GraphicsContext, size: CGSize, geom: GraphGeometry) -> [CGRect] {
        milestones.map { milestone in
            let labelWidth = context.resolve(Text(verbatim: milestone.label).font(MilestoneMetrics.labelFont()))
                .measure(in: size).width
            let top = milestone.y - MilestoneMetrics.stackHeight / 2
            let labelCenter = Self.milestoneLabelCenterX(milestone.x, labelWidth: labelWidth, geom: geom)
            let label = CGRect(
                x: labelCenter - labelWidth / 2, y: top,
                width: labelWidth, height: MilestoneMetrics.stackHeight,
            )
            let glyph = CGRect(
                x: milestone.x - MilestoneMetrics.glyphSize, y: top,
                width: MilestoneMetrics.glyphSize * 2, height: MilestoneMetrics.stackHeight,
            )
            return label.union(glyph)
        }
    }

    /// A dose's four modeled moments, in minutes from the dose.
    ///
    /// Boundaries at or past the curve's end contribute nothing, and two that
    /// land within a few minutes of each other are the same pixel — the later
    /// one is dropped rather than drawn on top of the earlier.
    static func milestones(of dose: ActiveSubstanceState) -> [(minutes: Double, symbol: String)] {
        let candidates: [(Double, String)] = [
            (dose.onsetEndMinutes, DosePhaseGlyph.comeup),
            (dose.comeupEndMinutes, DosePhaseGlyph.peak),
            (dose.peakEndMinutes, DosePhaseGlyph.offset),
            (dose.totalMinutes, DosePhaseGlyph.ended),
        ]
        var kept: [(minutes: Double, symbol: String)] = []
        for (minutes, symbol) in candidates where minutes > 0 {
            if let last = kept.last, minutes - last.minutes < dose.totalMinutes * 0.06 { continue }
            kept.append((minutes, symbol))
        }
        return kept
    }

    /// Heart rate (bpm) at a scrubbed minute-since-`earliestDose`, for the scrub
    /// callout: the value of the curve the vitals lane draws at this zoom, the same
    /// one its tracking dot reads. Nil in a gap between readings and outside them.
    func scrubHeartRate(atMinute minute: Double, visibleSpan: Double) -> Int? {
        guard vitalsBandActive, let trace = vitals?.heartRateTrace else { return nil }
        let date = earliestDose.addingTimeInterval(minute * 60)
        return trace.bpm(at: date, visibleSpan: visibleSpan * 60).map { Int($0.rounded()) }
    }

    /// Normalized height of the heavy-dose bound on this graph, memoized inputs
    /// only — see ``TimelineCurveModel/heavyThresholdHeight(substances:stackedGroups:stackRedoses:yNormalization:)``
    /// for when it is `nil` (which is most of the time, by design).
    var heavyThresholdHeight: Double? {
        guard !compact else { return nil }
        return TimelineCurveModel.heavyThresholdHeight(
            substances: substances,
            stackedGroups: stackedGroups,
            stackRedoses: stackRedoses,
            yNormalization: yNormalization,
        )
    }

    // MARK: - Canvas draw pass

    func draw(in context: GraphicsContext, size: CGSize, geom: GraphGeometry, viewport: Viewport) {
        var context = context
        let graphInset = geom.inset
        let graphTop = geom.top
        let graphWidth = geom.width
        let graphHeight = geom.height

        // Clip every draw to the inset plot column. A curve is drawn out to
        // `curveExtent` (its ~1.5 % taper), which can run a hair past the
        // at-rest visible span (a 4 %-height threshold) — so its elimination
        // tail would otherwise bleed into the right inset and clip at the bare
        // canvas edge, leaving the curve flush-right but inset-left (the
        // asymmetric-padding bug). Clipping to `[graphInset, width-graphInset]`
        // makes both margins exactly `graphInset`. Labels anchor inside this
        // band, so they're unaffected; the full height is kept for the
        // top/bottom label rows.
        context.clip(to: Path(CGRect(
            x: graphInset, y: 0,
            width: max(0, size.width - graphInset * 2), height: size.height,
        )))

        let vStart = viewport.visibleStart
        let vSpan = viewport.visibleSpan
        guard vSpan > 0, graphHeight > 0 else { return }

        let diamondSize: CGFloat = 4

        // Pre-compute marker positions for two-pass rendering (stems behind,
        // dots on top). Full graph only — compact thumbnails render markers
        // as dots on the shared baseline instead (see below).
        let markerSlots: [(marker: DoseMarker, x: CGFloat, cy: CGFloat)]
        if !compact, !laneMode, !markers.isEmpty {
            var slots: [(marker: DoseMarker, slot: Int)] = []
            var groups: [[Int]] = []
            for (i, marker) in markers.enumerated() {
                let matched = groups.firstIndex { group in
                    group.contains { j in
                        abs(markers[j].timestamp.timeIntervalSince(marker.timestamp)) < 120
                    }
                }
                if let gi = matched {
                    let slotIndex = groups[gi].count
                    groups[gi].append(i)
                    slots.append((marker: marker, slot: slotIndex))
                } else {
                    groups.append([i])
                    slots.append((marker: marker, slot: 0))
                }
            }

            markerSlots = slots.compactMap { item in
                let markerOffset = item.marker.timestamp.timeIntervalSince(earliestDose) / 60
                let rawX = graphInset + CGFloat((markerOffset - vStart) / vSpan) * graphWidth
                guard rawX >= -5, rawX <= size.width + 5 else { return nil }
                let x = max(graphInset + diamondSize + 1, rawX)

                // Dots hang from the top of the graph area (matching the
                // mechanistic chart's dose ticks); near-simultaneous doses
                // stack downward so their heads don't overlap.
                let usableTop = graphTop + diamondSize + 2
                let usableBottom = graphTop + graphHeight - diamondSize - 2
                let spacing = diamondSize * 2 + 4
                let cy = min(usableBottom, usableTop + CGFloat(item.slot) * spacing)
                return (marker: item.marker, x: x, cy: cy)
            }
        } else {
            markerSlots = []
        }

        // Phase bands (bottom layer — onset/come-up/peak/offset regions for a
        // lone substance, like the curve tuner). Self-guards on count == 1.
        drawPhaseBands(
            context: context,
            size: size,
            visibleStart: vStart,
            visibleSpan: vSpan,
            graphTop: graphTop,
            graphHeight: graphHeight,
            graphInset: graphInset,
        )

        // The heavy-dose tier's stretch of axis, over the phase bands but
        // still behind the gridlines and the curve.
        if let heavyHeight = heavyThresholdHeight {
            HeavyThresholdBand.draw(
                in: context, height: heavyHeight, size: size,
                graphTop: graphTop, graphHeight: graphHeight, graphInset: graphInset,
                squareCorners: chartFrame,
            )
        }

        // Tick marks & gridlines (behind everything)
        if !compact {
            drawTickMarks(
                context: context,
                size: size,
                visibleStart: vStart,
                visibleSpan: vSpan,
                graphTop: graphTop,
                graphHeight: graphHeight,
                graphInset: graphInset,
            )
        }

        // Pass 1: Marker stems — a full-height rule in the dose's own color
        // dropping from the head to the baseline, matching the mechanistic
        // chart's dose ticks so "when was it taken" reads at a glance even
        // when the substance draws no curve.
        for item in markerSlots {
            let color = item.marker.tint.color
            var linePath = Path()
            linePath.move(to: CGPoint(x: item.x, y: item.cy))
            linePath.addLine(to: CGPoint(x: item.x, y: graphTop + graphHeight))
            context.stroke(linePath, with: .color(color.opacity(0.55)), lineWidth: 2)
        }

        // "Now" indicator — a full-height vertical line at the current
        // moment. The per-curve dot alone reads poorly against the filled
        // area, so the line answers "where are we now" at a glance. Drawn
        // behind the curves (Health-style) so the dose dots still sit on
        // top of it.
        // Vitals lane backdrop (the faint framed strip), drawn first so the
        // now-line/scrub rule and the HR trace layer on top of it.
        if vitalsBandActive {
            drawVitalsLaneBackdrop(
                context: context, graphTop: graphTop, graphHeight: graphHeight,
                graphInset: graphInset, graphWidth: graphWidth,
            )
        }

        // Bordered-chart frame — drawn on top of the bands/curves so the lines
        // read crisply (not tinted through the fills), but under the now-line.
        // Left + right verticals down to a bottom origin line (the effect-curve
        // baseline); square corners, top-left open. The verticals sit a hair
        // inside the canvas so a 1pt stroke isn't halved by the edge.
        if chartFrame, !compact, graphHeight > 0 {
            let left = max(graphInset, 0.5), right = min(graphInset + graphWidth, size.width - 0.5)
            let baseline = graphTop + graphHeight
            var verticals = Path()
            verticals.move(to: CGPoint(x: left, y: graphTop))
            verticals.addLine(to: CGPoint(x: left, y: baseline))
            verticals.move(to: CGPoint(x: right, y: graphTop))
            verticals.addLine(to: CGPoint(x: right, y: baseline))
            context.stroke(verticals, with: .color(.primary.opacity(0.20)), lineWidth: 1)
            var origin = Path()
            origin.move(to: CGPoint(x: left, y: baseline))
            origin.addLine(to: CGPoint(x: right, y: baseline))
            context.stroke(origin, with: .color(.primary.opacity(0.28)), lineWidth: 1)
        }

        let milestoneStacks = milestoneFrames(
            milestonePlacements(geom: geom, visibleStart: vStart, visibleSpan: vSpan),
            context: context, size: size, geom: geom,
        )

        let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
        let nowX = graphInset + CGFloat((nowMinutes - vStart) / vSpan) * graphWidth
        // Only while the session is live. Once every dose's effect window has
        // ended, a bar pinned at "now" is a stray rule in dead space — and the
        // axis no longer stretches out to reach it (see `spanIncludingMarkers`).
        // Skipped on compact graphs, where a full-height line reads as a
        // glitch, not a "you are here" cue; the Live Activity marks now with
        // its own time-driven rail (`TimelineGraphView.timeDrivenNow`).
        if !compact, hasActiveNow, scrubX == nil, nowMinutes >= 0,
           nowX >= graphInset, nowX <= graphInset + graphWidth {
            let indicatorBottom = graphTop + graphHeight + belowCurvesTotal
            // The rule breaks around each milestone stack, so it never
            // strikes through a clock time it passes.
            var ruleContext = context
            for frame in milestoneStacks {
                ruleContext.clip(to: Path(frame.insetBy(dx: -2, dy: -1)), options: .inverse)
            }
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: nowX, y: graphTop))
            // Extend through the companion vitals lane so the "you are here"
            // rule is one continuous line across both curves and the HR band.
            nowLine.addLine(to: CGPoint(x: nowX, y: indicatorBottom))
            ruleContext.stroke(nowLine, with: .color(.primary.opacity(0.7)), lineWidth: 2.5)
            // A small dot centered on the baseline (the origin line), anchoring
            // the rule to "now" on the time axis rather than floating at the top.
            let capRadius: CGFloat = 3
            context.fill(
                Path(ellipseIn: CGRect(x: nowX - capRadius, y: graphTop + graphHeight - capRadius, width: capRadius * 2, height: capRadius * 2)),
                with: .color(.primary.opacity(0.7)),
            )
        }

        // Pan-extent indicator — a 2pt track at the very bottom showing the
        // visible window's position within the full scrollable extent.
        // Replaces the removed slider; non-interactive, only when there's
        // overflow to pan.
        if !compact, viewport.maxPanOffset > 1, viewport.totalSpan > 0 {
            let trackY = size.height - 1.5
            var track = Path()
            track.move(to: CGPoint(x: graphInset, y: trackY))
            track.addLine(to: CGPoint(x: graphInset + graphWidth, y: trackY))
            context.stroke(track, with: .color(.secondary.opacity(0.18)), lineWidth: 2)
            let segStart = graphInset + CGFloat(vStart / viewport.totalSpan) * graphWidth
            let segEnd = graphInset + CGFloat((vStart + vSpan) / viewport.totalSpan) * graphWidth
            var seg = Path()
            seg.move(to: CGPoint(x: segStart, y: trackY))
            seg.addLine(to: CGPoint(x: segEnd, y: trackY))
            context.stroke(seg, with: .color(.secondary.opacity(0.55)), lineWidth: 2)
        }

        // Compact baseline — the single axis that grounds both the curves
        // and the dose dots that rest on it. Drawn only when there are dots
        // to carry (or no curves at all), so the live session accessory
        // (curves only, no markers) stays unadorned.
        let compactBaselineY = graphTop + graphHeight
        if showCompactMarkers {
            var base = Path()
            base.move(to: CGPoint(x: graphInset, y: compactBaselineY))
            base.addLine(to: CGPoint(x: graphInset + graphWidth, y: compactBaselineY))
            context.stroke(base, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        }

        // Substance curves
        if laneMode {
            drawLanes(
                context: context,
                visibleStart: vStart,
                visibleSpan: vSpan,
                graphWidth: graphWidth,
                graphHeight: graphHeight,
                graphInset: graphInset,
                graphTop: graphTop,
            )
        } else if stackRedoses {
            drawStackedCurves(
                context: context,
                visibleStart: vStart,
                visibleSpan: vSpan,
                graphWidth: graphWidth,
                graphHeight: graphHeight,
                graphInset: graphInset,
                graphTop: graphTop,
            )
        } else {
            let yNorm = yNormalization
            for substance in substances {
                let color = substance.tint.color
                let substanceOffset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let scale = TimelineCurveModel.compressedAmplitude(heightScale(for: substance) * yNorm)
                let elapsed = currentTime.timeIntervalSince(substance.doseTimestamp) / 60
                let emph = emphasis(
                    name: substance.substanceName,
                    isActive: elapsed >= 0 && elapsed <= substance.totalMinutes,
                )

                let fillPath = intensityFillPath(
                    for: substance,
                    substanceOffset: substanceOffset,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    graphInset: graphInset,
                    graphTop: graphTop,
                    scale: scale,
                )
                // On the home-page thumbnails the area fill turns into mud
                // once several curves overlap, so drop it on busy compact
                // graphs and let the strokes carry the shape.
                if !compact || substances.count <= 3 {
                    context.fill(fillPath, with: .color(color.opacity(emph.fillOpacity)))
                }

                let strokePath = intensityStrokePath(
                    for: substance,
                    substanceOffset: substanceOffset,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    graphInset: graphInset,
                    graphTop: graphTop,
                    scale: scale,
                )
                context.stroke(
                    strokePath,
                    with: .color(color.opacity(emph.strokeOpacity)),
                    lineWidth: compact ? 1.5 : 2,
                )

                // Resting now-dot: one on EVERY active curve at the current
                // instant (not just the frontmost), tinted to match each
                // curve's emphasis. Superseded by the scrub dots while scrubbing.
                if showNowIndicator, scrubX == nil, elapsed >= 0, elapsed <= substance.totalMinutes {
                    let minutePos = substanceOffset + elapsed
                    let x = graphInset + CGFloat((minutePos - vStart) / vSpan) * graphWidth
                    let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: elapsed, for: substance) * scale) * graphHeight * 0.93
                    if x >= -5, x <= graphWidth + 5 {
                        let dotSize: CGFloat = compact ? 5 : 7
                        let dot = Path(ellipseIn: CGRect(
                            x: x - dotSize / 2,
                            y: y - dotSize / 2,
                            width: dotSize,
                            height: dotSize,
                        ))
                        context.fill(dot, with: .color(color.opacity(emph.strokeOpacity)))
                        context.stroke(dot, with: .color(.white.opacity(0.8 * emph.strokeOpacity)), lineWidth: 1)
                    }
                }
            }
        }

        // Pass 2: Marker heads (drawn on top of substance curves)
        for item in markerSlots {
            let color = item.marker.tint.color
            let circle = Path(ellipseIn: CGRect(
                x: item.x - diamondSize,
                y: item.cy - diamondSize,
                width: diamondSize * 2,
                height: diamondSize * 2,
            ))
            context.fill(circle, with: .color(color))
        }

        // Scrub readout — a vertical rule the user drags, with a dot on every
        // curve present at that instant. Supersedes the resting now-dot while
        // active; the SwiftUI callout renders the labels on top.
        if !compact, let sx = scrubX {
            let clampedX = min(max(sx, graphInset), graphInset + graphWidth)
            var rule = Path()
            rule.move(to: CGPoint(x: clampedX, y: graphTop))
            rule.addLine(to: CGPoint(x: clampedX, y: graphTop + graphHeight + belowCurvesTotal))
            context.stroke(rule, with: .color(.primary.opacity(0.55)), lineWidth: 1)

            let minute = vStart + Double((clampedX - graphInset) / graphWidth) * vSpan
            for sample in scrubSamples(atMinute: minute) where !laneMode {
                let y = graphTop + graphHeight - CGFloat(sample.value) * graphHeight * 0.93
                let dotSize: CGFloat = 7
                let dot = Path(ellipseIn: CGRect(
                    x: clampedX - dotSize / 2,
                    y: y - dotSize / 2,
                    width: dotSize,
                    height: dotSize,
                ))
                context.fill(dot, with: .color(sample.color))
                context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
            }
        }

        // Compact: duration-less doses rest as small color-coded dots on the
        // shared baseline, placed by time. Replaces the stacked floating
        // circles, which read as scattered noise at thumbnail size.
        if showCompactMarkers {
            let r: CGFloat = 2.5
            for marker in markers {
                let offset = marker.timestamp.timeIntervalSince(earliestDose) / 60
                let rawX = graphInset + CGFloat((offset - vStart) / vSpan) * graphWidth
                guard rawX >= graphInset - 1, rawX <= graphInset + graphWidth + 1 else { continue }
                let x = min(max(graphInset + r, rawX), graphInset + graphWidth - r)
                let dot = Path(ellipseIn: CGRect(
                    x: x - r,
                    y: compactBaselineY - r * 2,
                    width: r * 2,
                    height: r * 2,
                ))
                context.fill(dot, with: .color(marker.tint.color))
                context.stroke(dot, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
            }
        }

        // Companion vitals lane (heart rate + blood pressure), drawn on top of
        // the extended now-line/scrub rule so the HR trace and dots read clearly.
        if shulginLaneActive {
            drawShulginLane(
                context: context, visibleStart: vStart, visibleSpan: vSpan,
                graphInset: graphInset, graphWidth: graphWidth,
                graphTop: graphTop, graphHeight: graphHeight,
            )
        }
        if vitalsBandActive, let vitals {
            drawVitalsLane(
                context: context, size: size, vitals: vitals,
                visibleStart: vStart, visibleSpan: vSpan,
                graphInset: graphInset, graphWidth: graphWidth,
                graphTop: graphTop, graphHeight: graphHeight,
            )
        }

        if !compact {
            drawTimeLabels(
                context: context,
                size: size,
                visibleStart: vStart,
                visibleSpan: vSpan,
                // The horizontal inset must match the curves' inset, or the
                // clock labels drift off their ticks.
                inset: graphInset,
                top: graphTop,
                // Inflate the height passed to the label placer so the clock
                // labels land below the vitals lane, not inside it.
                graphHeight: graphHeight + belowCurvesTotal,
            )
            drawRelativeTimeLabels(
                context: context,
                size: size,
                visibleStart: vStart,
                visibleSpan: vSpan,
                inset: graphInset,
                graphTop: graphTop,
                dataSpan: viewport.totalSpan,
                avoiding: markerSlots.map(\.x),
                milestoneFrames: milestoneStacks,
            )
        }
    }

    // MARK: - Lane Rendering (small multiples)

    /// Render a busy day as stacked per-substance lanes. Each lane is an
    /// independent horizon strip: its own baseline, its own vertical scale (so a
    /// faint dose reads as a real hump beside a heavy one), the substance name
    /// inline as a label. The lanes share the x-axis, the gridlines, the now-line
    /// and the scrub rule — only the y-mapping is partitioned. Reuses the same
    /// Bateman path builders, just handed a lane-local top/height.
    private func drawLanes(
        context: GraphicsContext,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
    ) {
        let curveLanes = laneGroups
        // Duration-less substances get their own labeled lanes too, rather than
        // an unlabelled cluster of dots dumped at the graph's foot — which read
        // as stray, disconnected points overlapping the bottom lane. Every
        // substance is one labeled horizon strip: curves get a hump, instant
        // doses get a baseline row of dots.
        let markerLanes = TimelineCurveModel.markerOnlyLanes(excluding: curveLanes, markers: markers)
        let rowCount = curveLanes.count + markerLanes.count
        guard rowCount > 0 else { return }
        // Pin lanes take a fixed strip; the curves divide what's left. Splitting
        // the canvas evenly gave a two-dot row the same height as a full Bateman
        // hump, so a session with several duration-less substances squeezed
        // every curve flat to pay for them. Capped at half the canvas so a
        // pin-heavy day can't starve the curves either.
        let markerBlock = min(
            CGFloat(markerLanes.count) * GraphMetrics.markerLaneHeight,
            curveLanes.isEmpty ? graphHeight : graphHeight * 0.5,
        )
        let markerLaneHeight = markerLanes.isEmpty ? 0 : markerBlock / CGFloat(markerLanes.count)
        let curveLaneHeight = curveLanes.isEmpty
            ? 0
            : (graphHeight - markerBlock) / CGFloat(curveLanes.count)
        let curveBlock = CGFloat(curveLanes.count) * curveLaneHeight
        // Headroom above each curve and a gap above the baseline keep adjacent
        // lanes from touching; floored so very tight lanes still draw.
        let topHeadroom: CGFloat = min(10, curveLaneHeight * 0.28)
        let bottomGap: CGFloat = 2
        let labelInset: CGFloat = 4

        for (i, lane) in curveLanes.enumerated() {
            let laneTop = graphTop + CGFloat(i) * curveLaneHeight
            let baseline = laneTop + curveLaneHeight - bottomGap
            let amplitude = max(curveLaneHeight - topHeadroom - bottomGap, 6)
            let laneGraphTop = baseline - amplitude
            let color = lane.tint.color

            // Hairline separating this lane from the one above.
            if i > 0 {
                var sep = Path()
                sep.move(to: CGPoint(x: graphInset, y: laneTop))
                sep.addLine(to: CGPoint(x: graphInset + graphWidth, y: laneTop))
                context.stroke(sep, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            // With redose stacking on, the lane shows one summed envelope per
            // route (matching the global stacked view) instead of a pile of
            // overlapping per-dose humps; otherwise each dose draws on its own.
            if stackRedoses {
                let groups = TimelineCurveModel.stackedGroups(of: lane.doses)
                // Per-lane peak across the summed envelopes so this substance's
                // tallest moment fills the lane, independent of the others.
                var peak = 1e-6
                for group in groups {
                    let (gs, ge) = stackedGroupRange(group)
                    guard ge > gs else { continue }
                    let steps = 40
                    for j in 0 ... steps {
                        let t = gs + Double(j) / Double(steps) * (ge - gs)
                        peak = max(peak, stackedIntensity(atGlobalMinutes: t, group: group))
                    }
                }
                let norm = 1.0 / peak
                for group in groups {
                    drawStackedLaneGroup(group, context: context, color: color, norm: norm, baseline: baseline, amplitude: amplitude, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset)
                }
            } else {
                // Per-lane peak so this substance's tallest moment fills the lane,
                // regardless of how it compares to other substances.
                var peak = 1e-6
                for dose in lane.doses {
                    let hs = heightScale(for: dose)
                    let end = TimelineCurveModel.curveExtent(for: dose)
                    let steps = 40
                    for j in 0 ... steps {
                        let t = Double(j) / Double(steps) * end
                        peak = max(peak, TimelineCurveModel.intensity(at: t, for: dose) * hs)
                    }
                }
                let norm = 1.0 / peak

                for dose in lane.doses {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let scale = heightScale(for: dose) * norm
                    let fill = intensityFillPath(
                        for: dose,
                        substanceOffset: offset,
                        visibleStart: visibleStart,
                        visibleSpan: visibleSpan,
                        graphWidth: graphWidth,
                        graphHeight: amplitude,
                        graphInset: graphInset,
                        graphTop: laneGraphTop,
                        scale: scale,
                    )
                    context.fill(fill, with: .color(color.opacity(0.16)))
                    let stroke = intensityStrokePath(
                        for: dose,
                        substanceOffset: offset,
                        visibleStart: visibleStart,
                        visibleSpan: visibleSpan,
                        graphWidth: graphWidth,
                        graphHeight: amplitude,
                        graphInset: graphInset,
                        graphTop: laneGraphTop,
                        scale: scale,
                    )
                    context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: 1.6)
                }

                // "You are here" dot on this lane's frontmost active dose, so a
                // busy day still marks the present per-substance — matching the
                // overlapping/stacked renderers.
                if showNowIndicator, scrubX == nil {
                    let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
                    let nowX = graphInset + CGFloat((nowGlobal - visibleStart) / visibleSpan) * graphWidth
                    if nowX >= graphInset, nowX <= graphInset + graphWidth {
                        var bestV = -1.0
                        for dose in lane.doses {
                            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                            let elapsed = nowGlobal - offset
                            guard elapsed >= 0, elapsed <= dose.totalMinutes else { continue }
                            let v = TimelineCurveModel.intensity(at: elapsed, for: dose) * heightScale(for: dose) * norm
                            bestV = max(bestV, v)
                        }
                        if bestV >= 0 {
                            let y = baseline - CGFloat(min(1, max(0, bestV))) * amplitude * 0.93
                            drawNowDot(context, x: nowX, y: y, color: color)
                        }
                    }
                }
            }

            drawLaneLabel(lane.name, color: color, context: context, laneTop: laneTop, graphInset: graphInset, labelInset: labelInset)

            // A substance can carry both curve doses and duration-less doses (a
            // route with no duration data); draw the latter as low lollipops on
            // this lane's own baseline so they stay attached to their substance
            // without the head punching up through the curve above.
            let attachedLabelWidth = labelInset + 10 + CGFloat(lane.name.count) * 5.5
            for marker in markers where marker.substanceName.lowercased() == lane.name.lowercased() {
                drawMarkerLollipop(marker, context: context, baseline: baseline, laneTop: laneTop, amplitude: min(amplitude, 46), liftFraction: 0.3, labelWidth: attachedLabelWidth, radius: 3.5, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset, color: color)
            }
        }

        // Each duration-less substance as its own labeled lane below the curves.
        for (j, lane) in markerLanes.enumerated() {
            let i = curveLanes.count + j
            let laneTop = graphTop + curveBlock + CGFloat(j) * markerLaneHeight
            let baseline = laneTop + markerLaneHeight - bottomGap
            let color = lane.tint.color

            if i > 0 {
                var sep = Path()
                sep.move(to: CGPoint(x: graphInset, y: laneTop))
                sep.addLine(to: CGPoint(x: graphInset + graphWidth, y: laneTop))
                context.stroke(sep, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            drawLaneLabel(lane.name, color: color, context: context, laneTop: laneTop, graphInset: graphInset, labelInset: labelInset)

            // Heads ride high in the lane so a real stem drops to the baseline;
            // only markers that actually fall under the name label (near the left
            // edge) are held down to clear it — the rest get the full lane.
            let amplitude = max(markerLaneHeight - bottomGap - 2, 6)
            let r = min(5.5, max(3.5, amplitude * 0.34))
            let labelWidth = labelInset + 10 + CGFloat(lane.name.count) * 5.5
            for marker in lane.markers {
                drawMarkerLollipop(marker, context: context, baseline: baseline, laneTop: laneTop, amplitude: amplitude, liftFraction: 0.72, labelWidth: labelWidth, radius: r, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset, color: color)
            }
        }
    }

    /// Draw one stacked redose group's summed envelope inside a lane, normalized
    /// by the lane's own peak (`norm`) and mapped to the lane's `baseline` and
    /// `amplitude`. Mirrors ``drawStackedCurves`` — superpose the per-dose
    /// intensities, then (for a genuine redose stack) pass the envelope through
    /// the effect-site low-pass so frequent redoses read as one smooth session
    /// hump rather than a spiky sawtooth.
    private func drawStackedLaneGroup(
        _ group: [ActiveSubstanceState],
        context: GraphicsContext,
        color: Color,
        norm: Double,
        baseline: CGFloat,
        amplitude: CGFloat,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphInset: CGFloat,
    ) {
        let (gStart, gEnd) = stackedGroupRange(group)
        let gSpan = gEnd - gStart
        guard gSpan > 0 else { return }
        let steps = compact ? 48 : 140

        var vs: [Double] = []
        vs.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let t = gStart + Double(i) / Double(steps) * gSpan
            vs.append(stackedIntensity(atGlobalMinutes: t, group: group) * norm)
        }

        var pts: [CGPoint] = []
        pts.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let t = gStart + Double(i) / Double(steps) * gSpan
            let x = graphInset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
            let y = baseline - CGFloat(min(1.0, max(0, vs[i]))) * amplitude * 0.93
            pts.append(CGPoint(x: x, y: y))
        }

        var fill = Path()
        let startX = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
        fill.move(to: CGPoint(x: startX, y: baseline))
        addSmoothCurve(pts, to: &fill, startNew: false)
        let endX = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
        fill.addLine(to: CGPoint(x: endX, y: baseline))
        fill.closeSubpath()
        context.fill(fill, with: .color(color.opacity(0.16)))

        var stroke = Path()
        addSmoothCurve(pts, to: &stroke, startNew: true)
        context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: 1.6)

        // "You are here" dot, read from the same smoothed sample array so it
        // stays glued to the rendered envelope.
        if showNowIndicator, scrubX == nil {
            let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if nowGlobal >= gStart, nowGlobal <= gEnd {
                let nowX = graphInset + CGFloat((nowGlobal - visibleStart) / visibleSpan) * graphWidth
                if nowX >= graphInset, nowX <= graphInset + graphWidth {
                    let idx = max(0, min(Double(steps), (nowGlobal - gStart) / gSpan * Double(steps)))
                    let lo = Int(idx.rounded(.down))
                    let hi = min(lo + 1, steps)
                    let frac = idx - Double(lo)
                    let v = min(1, max(0, vs[lo] * (1 - frac) + vs[hi] * frac))
                    let y = baseline - CGFloat(v) * amplitude * 0.93
                    drawNowDot(context, x: nowX, y: y, color: color)
                }
            }
        }
    }

    /// Color swatch + substance name at a lane's top-left.
    private func drawLaneLabel(_ name: String, color: Color, context: GraphicsContext, laneTop: CGFloat, graphInset: CGFloat, labelInset: CGFloat) {
        let dotR: CGFloat = 3
        let dot = Path(ellipseIn: CGRect(x: graphInset + labelInset, y: laneTop + labelInset, width: dotR * 2, height: dotR * 2))
        context.fill(dot, with: .color(color))
        let label = context.resolve(
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary),
        )
        context.draw(label, at: CGPoint(x: graphInset + labelInset + dotR * 2 + 4, y: laneTop + labelInset + dotR), anchor: .leading)
    }

    // swiftlint:disable function_parameter_count

    /// A single duration-less dose as a lollipop: a thin stem rising from the
    /// lane baseline to a filled, ringed head at `headCenterY`. The stem grounds
    /// the dose to the time axis while the head gives it the vertical presence of
    /// a curve's hump, so an instant dose reads as a real logged event rather
    /// than a stray fleck on an otherwise empty lane. Mirrors the marker-line +
    /// circle treatment the non-lane overlay already uses.
    ///
    /// The parameters are flat lane/viewport geometry scalars for a single
    /// Canvas draw pass, so the count exemption beats a one-off wrapper struct.
    private func drawMarkerLollipop(_ marker: DoseMarker, context: GraphicsContext, baseline: CGFloat, laneTop: CGFloat, amplitude: CGFloat, liftFraction: CGFloat, labelWidth: CGFloat, radius r: CGFloat, visibleStart: Double, visibleSpan: Double, graphWidth: CGFloat, graphInset: CGFloat, color: Color) {
        let off = marker.timestamp.timeIntervalSince(earliestDose) / 60
        let rawX = graphInset + CGFloat((off - visibleStart) / visibleSpan) * graphWidth
        guard rawX >= graphInset - 1, rawX <= graphInset + graphWidth + 1 else { return }
        let x = min(max(graphInset + r, rawX), graphInset + graphWidth - r)

        // Float the head at a fraction of the lane height, but never higher than
        // the name label allows — and only markers whose x falls under the label
        // (near the left edge) are held down; the rest float free for a full stem.
        let lifted = baseline - amplitude * liftFraction
        let minHeadY = x < graphInset + labelWidth ? laneTop + 13 + r : laneTop + r + 2
        let headCenterY = min(max(lifted, minHeadY), baseline - r * 0.4)

        // Stem fades toward the foot so it reads as grounded rather than a hard
        // full-strength rule competing with the curves.
        var stem = Path()
        stem.move(to: CGPoint(x: x, y: baseline))
        stem.addLine(to: CGPoint(x: x, y: headCenterY))
        context.stroke(
            stem,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.2), color.opacity(0.85)]),
                startPoint: CGPoint(x: x, y: baseline),
                endPoint: CGPoint(x: x, y: headCenterY),
            ),
            lineWidth: 3,
        )

        let head = Path(ellipseIn: CGRect(x: x - r, y: headCenterY - r, width: r * 2, height: r * 2))
        context.fill(head, with: .color(color))
    }

    // swiftlint:enable function_parameter_count

    /// The "you are here" dot: a filled, white-ringed circle on a curve at the
    /// current moment. Shared by the overlapping, stacked, and lane renderers so
    /// every graph marks the present the same way.
    private func drawNowDot(_ context: GraphicsContext, x: CGFloat, y: CGFloat, color: Color, size: CGFloat = 7) {
        let dot = Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        context.fill(dot, with: .color(color))
        context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
    }

    // MARK: - Path Builders

    private func intensityStrokePath(
        for substance: ActiveSubstanceState,
        substanceOffset: Double,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
        scale: Double = 1.0,
    ) -> Path {
        Path { path in
            let steps = compact ? 48 : 140
            let drawEnd = TimelineCurveModel.curveExtent(for: substance)
            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: t, for: substance) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: true)
        }
    }

    private func intensityFillPath(
        for substance: ActiveSubstanceState,
        substanceOffset: Double,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
        scale: Double = 1.0,
    ) -> Path {
        Path { path in
            let steps = compact ? 48 : 140
            let baseline = graphTop + graphHeight
            let drawEnd = TimelineCurveModel.curveExtent(for: substance)

            let startX = graphInset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: t, for: substance) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: false)

            let endX = graphInset + CGFloat((substanceOffset + drawEnd - visibleStart) / visibleSpan) * graphWidth
            path.addLine(to: CGPoint(x: endX, y: baseline))
            path.closeSubpath()
        }
    }

    /// Append a smooth curve through `pts` using a **monotone** cubic Hermite
    /// spline (Fritsch–Carlson tangents) converted to cubic Bézier segments.
    ///
    /// Never interpolate with a tangent scheme that isn't monotone-clamped: a
    /// fast-onset dose (kratom) sits flat at baseline through the onset, then
    /// rises near-vertically, and an averaged tangent at that corner dips the
    /// spline *below the baseline* before the rise or bulges *above* the flat
    /// peak plateau. Fritsch–Carlson clamps each tangent so the interpolant
    /// stays monotone within every monotone data run: zero slope at extrema (a
    /// rounded peak, a clean baseline touchdown) and no excursion past the data.
    /// Because x is strictly increasing for a sampled curve we interpolate y as a
    /// function of x, so the guarantee holds in screen space directly.
    ///
    /// When `startNew` is false the current point is assumed to be `pts[0]` (used
    /// by the fill path, which has already moved to the baseline start).
    private func addSmoothCurve(_ pts: [CGPoint], to path: inout Path, startNew: Bool) {
        guard pts.count >= 2 else {
            if let p = pts.first {
                if startNew {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
            }
            return
        }
        let n = pts.count

        // Secant slopes dy/dx between consecutive samples. x increases left→right,
        // so dx > 0; guard against a degenerate coincident pair anyway.
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0 ..< n - 1 {
            let dx = Double(pts[i + 1].x - pts[i].x)
            delta[i] = dx != 0 ? Double(pts[i + 1].y - pts[i].y) / dx : 0
        }

        // Fritsch–Carlson tangents: average adjacent secants, force zero at any
        // sign change (local extremum), and cap magnitude at 3× the smaller
        // neighbouring secant so a cubic segment can't overshoot its endpoints.
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1 ..< n - 1 {
            if delta[i - 1] * delta[i] <= 0 {
                m[i] = 0
            } else {
                let avg = (delta[i - 1] + delta[i]) / 2
                let lim = 3 * min(abs(delta[i - 1]), abs(delta[i]))
                m[i] = min(max(avg, -lim), lim)
            }
        }

        if startNew { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        for i in 0 ..< n - 1 {
            let dx = Double(pts[i + 1].x - pts[i].x)
            let c1 = CGPoint(x: pts[i].x + CGFloat(dx / 3), y: pts[i].y + CGFloat(m[i] * dx / 3))
            let c2 = CGPoint(x: pts[i + 1].x - CGFloat(dx / 3), y: pts[i + 1].y - CGFloat(m[i + 1] * dx / 3))
            path.addCurve(to: pts[i + 1], control1: c1, control2: c2)
        }
    }

    // MARK: - Stacked Rendering

    /// Groups substance states by lowercased substance name, preserving original order.
    private var stackedGroups: [[ActiveSubstanceState]] {
        derived.stackedGroups
    }

    /// Combined intensity of a group at a given global time (minutes since
    /// earliestDose) — the **upper envelope** (max) of the per-dose curves, each
    /// weighted by its `doseIntensity`.
    ///
    /// This is deliberately *not* a numeric sum. The curve is a coarse subjective
    /// approximation (a flat-topped plateau, not a precise plasma trace), so
    /// summing two overlapping doses produced a stepped, far-too-wavy shape — two
    /// plateaus adding to 2× in the overlap and dropping back on the flanks — that
    /// read as arithmetic rather than as one sustained effect. The envelope
    /// instead merges overlapping redoses into a single clean plateau (as smooth
    /// as one dose, just longer), a bigger redose still rises higher where it
    /// dominates, and well-separated doses keep their distinct humps. The caller
    /// normalizes by the combined peak (`peakCurveValue`); the effect-site
    /// low-pass then rounds the hand-off where one dose overtakes another.
    private func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState]) -> Double {
        TimelineCurveModel.stackedIntensity(atGlobalMinutes: global, group: group, earliestDose: derived.earliestDose)
    }

    private func stackedGroupRange(_ group: [ActiveSubstanceState]) -> (start: Double, end: Double) {
        TimelineCurveModel.stackedGroupRange(group, earliestDose: derived.earliestDose)
    }

    private func drawStackedCurves(
        context: GraphicsContext,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
    ) {
        let baseline = graphTop + graphHeight
        let steps = compact ? 60 : 200
        let yNorm = yNormalization

        let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
        for group in stackedGroups {
            guard let first = group.first else { continue }
            let color = first.tint.color
            let (gStart, gEnd) = stackedGroupRange(group)
            let gSpan = gEnd - gStart
            guard gSpan > 0 else { continue }
            let activeEnd = group.map { $0.doseTimestamp.timeIntervalSince(earliestDose) / 60 + $0.totalMinutes }.max() ?? gEnd
            let emph = emphasis(name: first.substanceName, isActive: nowGlobal >= gStart && nowGlobal <= activeEnd)

            // Sample the merged curve `Hill(Σ magnitude·bell)`. The Hill
            // superposition is already smooth and keeps overlapping crests flat,
            // so no post-hoc envelope low-pass is needed — and spread-out redoses
            // whose bells don't overlap stay as distinct humps (correct: they're
            // separate experiences), instead of being fused into one dome.
            var vs: [Double] = []
            vs.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = gStart + Double(i) / Double(steps) * gSpan
                vs.append(stackedIntensity(atGlobalMinutes: t, group: group) * yNorm)
            }
            // Compress this group's amplitude (its peak) the same way the
            // non-stacked path does, scaling the whole sampled envelope by a
            // single factor so a light group lifts off the axis without
            // deforming its shape.
            if let groupPeak = vs.max(), groupPeak > 0 {
                let factor = TimelineCurveModel.compressedAmplitude(groupPeak) / groupPeak
                if factor != 1 {
                    for i in vs.indices {
                        vs[i] *= factor
                    }
                }
            }

            func curveValue(atFraction f: Double) -> Double {
                let idx = max(0, min(Double(steps), f * Double(steps)))
                let lo = Int(idx.rounded(.down))
                let hi = min(lo + 1, steps)
                let frac = idx - Double(lo)
                return min(1.0, max(0, vs[lo] * (1 - frac) + vs[hi] * frac))
            }

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = gStart + Double(i) / Double(steps) * gSpan
                let x = graphInset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
                let y = baseline - CGFloat(min(1.0, max(0, vs[i]))) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }

            var fillPath = Path()
            let startX = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
            fillPath.move(to: CGPoint(x: startX, y: baseline))
            addSmoothCurve(pts, to: &fillPath, startNew: false)
            let endX = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
            fillPath.addLine(to: CGPoint(x: endX, y: baseline))
            fillPath.closeSubpath()
            // On the home-page thumbnails the fills turn into a single blob once
            // several curves overlap, so drop them on busy compact graphs and
            // let the strokes carry the shape.
            if !compact || stackedGroups.count <= 3 {
                context.fill(fillPath, with: .color(color.opacity(emph.fillOpacity)))
            }

            var strokePath = Path()
            addSmoothCurve(pts, to: &strokePath, startNew: true)
            context.stroke(strokePath, with: .color(color.opacity(emph.strokeOpacity)), lineWidth: compact ? 1.5 : 2)

            // Small tick glyphs at each redose time along the baseline so the user
            // can see where additional doses contributed to the curve.
            if group.count > 1, !compact {
                for dose in group {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let x = graphInset + CGFloat((offset - visibleStart) / visibleSpan) * graphWidth
                    guard x >= -5, x <= graphWidth + 5 else { continue }
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: baseline))
                    tick.addLine(to: CGPoint(x: x, y: baseline - 5))
                    context.stroke(tick, with: .color(color.opacity(emph == .full ? 0.75 : 0.3)), lineWidth: 1.5)
                }
            }

            // Current-time dot on the summed curve. Must use the SAME normalized
            // value as `point(at:)` above — `stackedIntensity * yNorm`, clamped —
            // or the dot detaches from the curve whenever `yNorm` shifts (e.g. a
            // dose is added/removed and the graph rescales to fill the height).
            // Resting now-dot: one on EVERY active group's summed curve (not just
            // the frontmost), tinted to match its emphasis. Superseded by scrub dots.
            let elapsedGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if showNowIndicator, scrubX == nil, elapsedGlobal >= gStart, elapsedGlobal <= gEnd {
                let x = graphInset + CGFloat((elapsedGlobal - visibleStart) / visibleSpan) * graphWidth
                // Read from the same smoothed sample array as the curve so the
                // dot stays glued to it.
                let v = curveValue(atFraction: (elapsedGlobal - gStart) / gSpan)
                let y = baseline - CGFloat(v) * graphHeight * 0.93
                if x >= -5, x <= graphWidth + 5 {
                    let dotSize: CGFloat = compact ? 5 : 7
                    let dot = Path(ellipseIn: CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize,
                    ))
                    context.fill(dot, with: .color(color.opacity(emph.strokeOpacity)))
                    context.stroke(dot, with: .color(.white.opacity(0.8 * emph.strokeOpacity)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Tick Marks

    /// Shaded onset / come-up / peak / offset regions behind the curve, mirroring
    /// the curve tuner's legend so the phases are legible at a glance. Drawn only
    /// for a **single substance's single dose** (the "open a card for it" case) —
    /// multiple curves or a redose stack would overlap into mud, so they stay
    /// unbanded. Compact thumbnails skip it (too small for labels).
    private func drawPhaseBands(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        graphTop: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
    ) {
        guard !compact, substances.count == 1, let s = substances.first else { return }
        let graphWidth = size.width - graphInset * 2
        guard graphWidth > 0, visibleSpan > 0 else { return }
        let doseOffset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60

        // Use the same synthesized come-up the curve is fit to, so the blue
        // band tracks the rendered rise even when the source data lists no
        // come-up phase (otherwise the curve climbs through a "peak"-colored
        // band with no come-up band at all).
        let peakEndForBands = max(s.peakEndMinutes, s.onsetEndMinutes + 2)
        let comeupEndForBands = TimelineCurveModel.effectiveComeupEnd(for: s, onsetEnd: s.onsetEndMinutes, peakEnd: peakEndForBands)
        // Bands are non-text marks, so they take the phase scale's `accent`
        // variant. These were inline hexes duplicated across three files; the
        // hues are unchanged, only lightness and chroma moved to clear the
        // contrast gates. See `design-system/color/`.
        let bands: [(start: Double, end: Double, color: Color)] = [
            (0, s.onsetEndMinutes, .Phase.Onset.accent),
            (s.onsetEndMinutes, comeupEndForBands, .Phase.Comeup.accent),
            (comeupEndForBands, s.peakEndMinutes, .Phase.Peak.accent),
            (s.peakEndMinutes, s.offsetEndMinutes, .Phase.Offset.accent),
        ]

        let leftBound = graphInset
        let rightBound = graphInset + graphWidth

        // Clip the whole band block to a rounded rect so its outer corners are
        // concentric with the hosting card instead of square against it. Scoped to
        // a layer so the rounding affects only the bands, not the curve/gridlines.
        // Internal phase boundaries stay crisp — only edges meeting a corner round.
        let plotRect = CGRect(x: graphInset, y: graphTop, width: graphWidth, height: graphHeight)
        // Square corners in the bordered-chart host (the drawn frame is square);
        // rounded to sit concentric with the card everywhere else.
        let bandCorner: CGFloat = chartFrame ? 0 : 10
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: plotRect, cornerRadius: bandCorner, style: .continuous))
            for band in bands {
                guard band.end > band.start else { continue }
                let gStart = doseOffset + band.start
                let gEnd = doseOffset + band.end
                let rawX0 = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
                let rawX1 = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
                let x0 = min(max(rawX0, leftBound), rightBound)
                let x1 = min(max(rawX1, leftBound), rightBound)
                guard x1 - x0 > 0.5 else { continue }

                // Background tint only — the curve's shape already names the phases,
                // and labels would collide with the line.
                layer.fill(
                    Path(CGRect(x: x0, y: graphTop, width: x1 - x0, height: graphHeight)),
                    with: .color(band.color.opacity(0.12)),
                )
            }
        }
    }

    private func drawTickMarks(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        graphTop: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
    ) {
        let graphWidth = size.width - graphInset * 2
        let calendar = Calendar.current
        let interval = TimelineCurveModel.intervalForSpan(visibleSpan)

        let graphOrigin = earliestDose
        let windowStart = graphOrigin.addingTimeInterval(visibleStart * 60)
        let windowEnd = graphOrigin.addingTimeInterval((visibleStart + visibleSpan) * 60)

        let startHour = calendar.component(.hour, from: windowStart)
        let startMinute = calendar.component(.minute, from: windowStart)
        let totalStartMinutes = Double(startHour * 60 + startMinute)
        let firstTickMinutes = ceil(totalStartMinutes / interval) * interval
        let firstTickDate = calendar.startOfDay(for: windowStart)
            .addingTimeInterval(firstTickMinutes * 60)

        var tickDate = firstTickDate

        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = graphInset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            if x >= graphInset, x <= size.width - graphInset {
                // Subtle full-height gridline
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: graphTop))
                gridLine.addLine(to: CGPoint(x: x, y: graphTop + graphHeight))
                context.stroke(gridLine, with: .color(.primary.opacity(0.08)), lineWidth: 0.5)

                // Small tick mark at bottom edge
                var bottomTick = Path()
                bottomTick.move(to: CGPoint(x: x, y: graphTop + graphHeight))
                bottomTick.addLine(to: CGPoint(x: x, y: graphTop + graphHeight + 4))
                context.stroke(bottomTick, with: .color(.primary.opacity(0.25)), lineWidth: 0.75)

                // Small tick mark at top edge — skipped in the bordered-chart host,
                // where the full-height gridline already marks the hour under each
                // duration label (the tick just doubles it).
                if !chartFrame {
                    var topTick = Path()
                    topTick.move(to: CGPoint(x: x, y: graphTop))
                    topTick.addLine(to: CGPoint(x: x, y: graphTop - 3))
                    context.stroke(topTick, with: .color(.primary.opacity(0.2)), lineWidth: 0.5)
                }
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
        }
    }

    // MARK: - Vitals lane (heart rate + blood pressure)

    /// Lane colors (shared with the entry-row chips via ``VitalsPalette``).
    private static let hrColor = VitalsPalette.heart
    private static let bpColor = VitalsPalette.bloodPressure
    /// bpm guide spacings, finest first; the lane uses the first one whose lines
    /// sit at least ``bpmGuideMinSpacing`` apart.
    private static let bpmGuideSteps: [Double] = [20, 40, 50, 100]
    private static let bpmGuideMinSpacing: CGFloat = 14
    /// Cap height of the 7 pt guide numerals, used to keep them out of the lane-label row.
    private static let bpmGuideLabelHeight: CGFloat = 7
    /// Clear space required between two blood-pressure labels before the second
    /// one is allowed to draw. Below this they overprint into an unreadable mush.
    private static let bpLabelGap: CGFloat = 6

    /// The faint framed strip the vitals trace sits in. Drawn before the now-line
    /// so both the rule and the HR trace layer on top of it.
    /// The Shulgin lane: each rated note's level (± … ++++) as a faint step line
    /// held until the next rated note, with a dot at every rating. A record of
    /// what was felt when — it shares the time axis, so it pans and zooms with
    /// the curves.
    private func drawShulginLane(
        context: GraphicsContext, visibleStart: Double, visibleSpan: Double,
        graphInset: CGFloat, graphWidth: CGFloat,
        graphTop: CGFloat, graphHeight: CGFloat,
    ) {
        let rated = noteMarkers
            .compactMap { marker -> (minute: Double, level: Int)? in
                guard let level = marker.shulgin else { return nil }
                return (marker.timestamp.timeIntervalSince(earliestDose) / 60, level)
            }
            .sorted { $0.minute < $1.minute }
        guard !rated.isEmpty, visibleSpan > 0 else { return }
        let bandTop = graphTop + graphHeight + GraphMetrics.shulginLaneGap
        let laneHeight = GraphMetrics.shulginLane
        let rect = CGRect(x: graphInset, y: bandTop, width: graphWidth, height: laneHeight)
        context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(Color.accentColor.opacity(0.06)))
        let plotTop = bandTop + 5
        let plotHeight = laneHeight - 10
        func x(_ minute: Double) -> CGFloat {
            graphInset + CGFloat((minute - visibleStart) / visibleSpan) * graphWidth
        }
        func y(_ level: Int) -> CGFloat {
            plotTop + (1 - CGFloat(level) / 4) * plotHeight
        }
        let right = graphInset + graphWidth
        var step = Path()
        for (index, point) in rated.enumerated() {
            let startX = min(max(x(point.minute), graphInset), right)
            let endMinute = index + 1 < rated.count ? rated[index + 1].minute : visibleStart + visibleSpan
            let endX = min(max(x(endMinute), graphInset), right)
            guard endX > startX else { continue }
            step.move(to: CGPoint(x: startX, y: y(point.level)))
            step.addLine(to: CGPoint(x: endX, y: y(point.level)))
            if index + 1 < rated.count {
                step.addLine(to: CGPoint(x: endX, y: y(rated[index + 1].level)))
            }
        }
        context.stroke(step, with: .color(Color.accentColor.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        for point in rated {
            let px = x(point.minute)
            guard px >= graphInset - 3, px <= right + 3 else { continue }
            let dot = Path(ellipseIn: CGRect(x: px - 3, y: y(point.level) - 3, width: 6, height: 6))
            context.fill(dot, with: .color(Color.accentColor))
            context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
        }
        let labelFont = Font.system(size: 7, weight: .semibold, design: .rounded)
        let top = Text(verbatim: "++++").font(labelFont).foregroundStyle(Color.accentColor.legibleOpacity(0.7))
        let bottom = Text(verbatim: "±").font(labelFont).foregroundStyle(Color.accentColor.legibleOpacity(0.7))
        context.draw(context.resolve(top), at: CGPoint(x: graphInset + 3, y: plotTop), anchor: .topLeading)
        context.draw(context.resolve(bottom), at: CGPoint(x: graphInset + 3, y: plotTop + plotHeight), anchor: .bottomLeading)
    }

    private func drawVitalsLaneBackdrop(
        context: GraphicsContext, graphTop: CGFloat, graphHeight: CGFloat,
        graphInset: CGFloat, graphWidth: CGFloat,
    ) {
        let bandTop = graphTop + graphHeight + shulginLaneTotal + GraphMetrics.vitalsBandGap
        let rect = CGRect(x: graphInset, y: bandTop, width: graphWidth, height: vitalsBandHeight)
        context.fill(Path(roundedRect: rect, cornerRadius: 9), with: .color(Self.hrColor.opacity(0.06)))
    }

    /// The companion cardio lane: HR as a min–max envelope + mean line on a bpm
    /// scale, BP as systolic→diastolic range bars on their own mmHg scale, plus a
    /// lane label and the HR dot. Shares the effect graph's time axis, so it
    /// pans / zooms / scrubs in lockstep; both scales span the whole session.
    private func drawVitalsLane(
        context: GraphicsContext, size: CGSize, vitals: SessionVitals,
        visibleStart: Double, visibleSpan: Double,
        graphInset: CGFloat, graphWidth: CGFloat,
        graphTop: CGFloat, graphHeight: CGFloat,
    ) {
        let earliest = earliestDose
        let visEnd = visibleStart + visibleSpan
        let bandTop = graphTop + graphHeight + shulginLaneTotal + GraphMetrics.vitalsBandGap
        let innerPad: CGFloat = 12 // room for the lane-label row at the top
        let plotTop = bandTop + innerPad
        let plotH = vitalsBandHeight - innerPad - 4
        func x(_ minute: Double) -> CGFloat {
            graphInset + CGFloat((minute - visibleStart) / visibleSpan) * graphWidth
        }

        // Heart rate comes pre-bucketed in absolute time (see ``HeartRateTrace``):
        // panning only moves the same points sideways, and the axis spans the whole
        // series, so nothing here changes shape while the graph moves.
        let trace = vitals.heartRateTrace
        guard let axis = trace.axis, let level = trace.level(forVisibleSpan: visibleSpan * 60) else { return }
        let lo = axis.lowerBound, hi = axis.upperBound
        let earliestTime = earliest.timeIntervalSinceReferenceDate
        func xTime(_ time: TimeInterval) -> CGFloat {
            x((time - earliestTime) / 60)
        }
        // Unclamped: every point lies inside the axis by construction, and a Bézier
        // control point outside it must stay where it is or the stroke would leave
        // the curve the dot reads.
        func yH(_ bpm: Double) -> CGFloat {
            plotTop + (1 - CGFloat((bpm - lo) / (hi - lo))) * plotH
        }

        // bpm guide lines every 20 bpm, each labeled at the left inset so the lane
        // reads as a real bpm axis at a glance — the exact values used to live only
        // behind a long-press scrub, which is what the "no legend" report was about.
        // The axis spans the whole series, so a wide range in this short lane would
        // stack 20-bpm labels on top of each other: the step widens until labels
        // clear one another, and a label that would reach into the lane-label row
        // keeps its line but drops its number.
        let guideStep = Self.bpmGuideSteps.first { CGFloat($0 / (hi - lo)) * plotH >= Self.bpmGuideMinSpacing }
            ?? Self.bpmGuideSteps.last!
        var guideBpm = (lo / guideStep).rounded(.down) * guideStep
        if guideBpm <= lo { guideBpm += guideStep }
        let guideFont = Font.system(size: 7, weight: .medium, design: .rounded).monospacedDigit()
        while guideBpm < hi {
            let gy = yH(guideBpm)
            var line = Path()
            line.move(to: CGPoint(x: graphInset, y: gy))
            line.addLine(to: CGPoint(x: graphInset + graphWidth, y: gy))
            context.stroke(line, with: .color(.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 0.5, dash: [1, 4]))
            if gy - 4 - Self.bpmGuideLabelHeight >= plotTop {
                let tick = Text(verbatim: "\(Int(guideBpm))").font(guideFont).foregroundStyle(Self.hrColor.legibleOpacity(0.75))
                context.draw(context.resolve(tick), at: CGPoint(x: graphInset + 2, y: gy - 4), anchor: .bottomLeading)
            }
            guideBpm += guideStep
        }

        // Each run: the min–max envelope, then the mean as the monotone cubic the
        // trace's tangents describe. Only the stretch overlapping the visible window
        // is built (plus one point either side, so the stroke enters and leaves the
        // plot column rather than stopping short of its edge).
        let visibleStartTime = earliestTime + visibleStart * 60
        let visibleEndTime = earliestTime + visEnd * 60
        for run in level.runs {
            guard let first = run.first, let last = run.last,
                  last.time >= visibleStartTime - level.bucket,
                  first.time <= visibleEndTime + level.bucket
            else { continue }
            if run.count == 1 {
                let p = CGPoint(x: xTime(first.time), y: yH(first.mean))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Self.hrColor))
                continue
            }
            let lower = run.lastIndex(where: { $0.time <= visibleStartTime }) ?? 0
            let upper = run.firstIndex(where: { $0.time >= visibleEndTime }) ?? run.count - 1
            guard upper > lower else { continue }
            let slice = run[lower ... upper]

            var envelope = Path()
            envelope.move(to: CGPoint(x: xTime(run[lower].time), y: yH(run[lower].high)))
            for point in slice.dropFirst() {
                envelope.addLine(to: CGPoint(x: xTime(point.time), y: yH(point.high)))
            }
            for point in slice.reversed() {
                envelope.addLine(to: CGPoint(x: xTime(point.time), y: yH(point.low)))
            }
            envelope.closeSubpath()
            context.fill(envelope, with: .color(Self.hrColor.opacity(0.16)))

            var mean = Path()
            mean.move(to: CGPoint(x: xTime(run[lower].time), y: yH(run[lower].mean)))
            for i in lower ..< upper {
                let a = run[i], b = run[i + 1]
                let third = (b.time - a.time) / 3
                mean.addCurve(
                    to: CGPoint(x: xTime(b.time), y: yH(b.mean)),
                    control1: CGPoint(x: xTime(a.time + third), y: yH(a.mean + a.slope * third)),
                    control2: CGPoint(x: xTime(b.time - third), y: yH(b.mean - b.slope * third)),
                )
            }
            context.stroke(mean, with: .color(Self.hrColor), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }

        // Blood pressure — systolic→diastolic range bars on their own mmHg scale,
        // fitted to every reading rather than the visible ones, so the bars hold
        // still while the graph pans just as the heart-rate axis does.
        let bp = vitals.bloodPressure.filter {
            let m = $0.date.timeIntervalSince(earliest) / 60
            return m >= visibleStart && m <= visEnd
        }
        if !bp.isEmpty {
            var bpLo = ((vitals.bloodPressure.map(\.diastolic).min() ?? 60) / 10).rounded(.down) * 10 - 10
            var bpHi = ((vitals.bloodPressure.map(\.systolic).max() ?? 130) / 10).rounded(.up) * 10 + 10
            if bpHi - bpLo < 30 { bpHi = bpLo + 30 }
            bpLo = max(0, bpLo)
            func yBP(_ v: Double) -> CGFloat {
                plotTop + (1 - CGFloat((min(bpHi, max(bpLo, v)) - bpLo) / (bpHi - bpLo))) * plotH
            }
            // Every reading keeps its bar — the marks are the data. Only the
            // *labels* thin out: five readings inside forty minutes land within
            // a few points of each other on a multi-hour axis, and drawing all
            // five printed "107/71 110/69 …472" on top of itself. A label is
            // drawn only once the last drawn one is clear of it, so what remains
            // is legible and still anchored to real readings. The last reading
            // is always labeled — it's the one being asked about.
            var lastLabelMaxX = -CGFloat.greatestFiniteMagnitude
            for (index, reading) in bp.enumerated() {
                let cx = x(reading.date.timeIntervalSince(earliest) / 60)
                let ys = yBP(reading.systolic), yd = yBP(reading.diastolic)
                var bar = Path()
                bar.move(to: CGPoint(x: cx, y: ys))
                bar.addLine(to: CGPoint(x: cx, y: yd))
                context.stroke(bar, with: .color(Self.bpColor), lineWidth: 1.4)
                for cy in [ys, yd] {
                    var cap = Path()
                    cap.move(to: CGPoint(x: cx - 2.5, y: cy))
                    cap.addLine(to: CGPoint(x: cx + 2.5, y: cy))
                    context.stroke(cap, with: .color(Self.bpColor), lineWidth: 1.4)
                }
                let text = Text(verbatim: "\(Int(reading.systolic))/\(Int(reading.diastolic))")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.bpColor)
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width
                let rightSide = cx + labelWidth + 6 > graphInset + graphWidth
                let originX = rightSide ? cx - 4 - labelWidth : cx + 4
                let isLast = index == bp.count - 1
                guard isLast || originX > lastLabelMaxX + Self.bpLabelGap else { continue }
                lastLabelMaxX = originX + labelWidth
                context.draw(
                    resolved,
                    at: CGPoint(x: rightSide ? cx - 4 : cx + 4, y: ys - 6),
                    anchor: rightSide ? .trailing : .leading,
                )
            }
        }

        // The HR dot. While scrubbing it sits on the stroked curve under the rule
        // (its bpm rides in the SwiftUI callout above, read from the same curve),
        // and disappears where there is no reading to sit on. At rest it marks the
        // newest reading, at that reading's own time, while that reading is recent.
        let marker: (time: TimeInterval, bpm: Double)?
        if let sx = scrubX {
            let minute = visibleStart + Double((min(max(sx, graphInset), graphInset + graphWidth) - graphInset) / graphWidth) * visibleSpan
            let time = earliestTime + minute * 60
            marker = HeartRateTrace.bpm(at: time, in: level).map { (time, $0) }
        } else if showNowIndicator {
            marker = trace.latestPoint(asOf: currentTime, visibleSpan: visibleSpan * 60).map { ($0.time, $0.mean) }
        } else {
            marker = nil
        }
        if let marker, marker.time >= visibleStartTime, marker.time <= visibleEndTime {
            let cx = xTime(marker.time), cy = yH(marker.bpm)
            let dot = CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dot), with: .color(Self.hrColor))
            context.stroke(Path(ellipseIn: dot), with: .color(.white.opacity(0.9)), lineWidth: 1)
        }

        // Lane labels split to opposite corners, each by its own axis: heart rate
        // left (bpm), blood pressure right (mmHg). Lowercased (they read as axis
        // captions, not titles) and inset from the edges. No heart glyph — the
        // crimson trace already reads as heart rate, and the lane is tight.
        let labelFont = Font.system(size: 8, weight: .semibold, design: .rounded)
        let labelPad: CGFloat = 10
        let hrText = String(localized: "Heart rate").lowercased()
        let hrLabel = Text(verbatim: hrText).font(labelFont).foregroundStyle(Self.hrColor)
        context.draw(context.resolve(hrLabel), at: CGPoint(x: graphInset + labelPad, y: bandTop + 7), anchor: .leading)
        if vitals.hasBloodPressure {
            let bpText = String(localized: "Blood pressure").lowercased()
            let bpLabel = Text(verbatim: bpText).font(labelFont).foregroundStyle(Self.bpColor)
            context.draw(context.resolve(bpLabel), at: CGPoint(x: graphInset + graphWidth - labelPad, y: bandTop + 7), anchor: .trailing)
        }
    }

    // MARK: - Time Labels

    private static let timeLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private static let timeHourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    private func drawTimeLabels(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        inset: CGFloat,
        top: CGFloat,
        graphHeight: CGFloat,
    ) {
        let graphWidth = size.width - inset * 2
        let labelY = top + graphHeight + labelAreaHeight / 2 + 2
        let calendar = Calendar.current

        let interval = TimelineCurveModel.intervalForSpan(visibleSpan)

        // Graph origin is earliestDose shifted left by padding
        let graphOrigin = earliestDose
        let windowStart = graphOrigin.addingTimeInterval(visibleStart * 60)
        let windowEnd = graphOrigin.addingTimeInterval((visibleStart + visibleSpan) * 60)

        // First tick is at the graph origin (already clock-aligned)
        let startHour = calendar.component(.hour, from: windowStart)
        let startMinute = calendar.component(.minute, from: windowStart)
        let totalStartMinutes = Double(startHour * 60 + startMinute)
        let firstTickMinutes = ceil(totalStartMinutes / interval) * interval
        let firstTickDate = calendar.startOfDay(for: windowStart)
            .addingTimeInterval(firstTickMinutes * 60)

        var tickDate = firstTickDate
        let minLabelSpacing: CGFloat = 8
        var lastLabelRight: CGFloat = -.infinity

        // Deep zoom can frame a window that straddles no whole hour at all
        // (e.g. 12:05–12:50 at a 15-min tick stride) — labeling only whole
        // hours would leave the axis blank, so fall back to minute labels then.
        let nextWholeHour = calendar.dateInterval(of: .hour, for: windowStart)?.end ?? windowStart
        let windowHasWholeHour = nextWholeHour <= windowEnd

        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = inset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            // Only whole hours get a *label*; the sub-hour marks (`:15`/`:30`)
            // stay as bare ticks (drawn in `drawTickMarks`) so a zoomed-in axis
            // isn't crowded with "12:30 PM"-style labels.
            let minute = calendar.component(.minute, from: tickDate)
            if x >= 0, x <= size.width, minute == 0 || !windowHasWholeHour {
                let label = minute == 0
                    ? Self.timeHourFormatter.string(from: tickDate)
                    : Self.timeLabelFormatter.string(from: tickDate)

                let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.legibleOpacity(0.6))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat = if x < 20 {
                    x
                } else if x > size.width - 20 {
                    x - labelWidth
                } else {
                    x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minLabelSpacing {
                    let anchor: UnitPoint = if x < 20 {
                        .leading
                    } else if x > size.width - 20 {
                        .trailing
                    } else {
                        .center
                    }
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    lastLabelRight = labelLeft + labelWidth
                }
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
        }
    }

    // MARK: - Relative Time Labels

    private func drawRelativeTimeLabels(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        inset: CGFloat,
        graphTop _: CGFloat,
        dataSpan: Double,
        avoiding markerXs: [CGFloat] = [],
        milestoneFrames: [CGRect] = [],
    ) {
        let graphWidth = size.width - inset * 2
        let labelY: CGFloat = 12
        // Determine hour step based on visible span
        let hourStep: Int
        let visibleHours = visibleSpan / 60
        if visibleHours <= 4 { hourStep = 1 } else if visibleHours <= 12 { hourStep = 2 } else if visibleHours <= 24 { hourStep = 4 } else { hourStep = 6 }

        // Always step in whole hours to avoid duplicates
        var hour = 0
        let maxHours = Int(ceil(dataSpan / 60))
        var lastLabelRight: CGFloat = -.infinity
        let minSpacing: CGFloat = 8
        // A milestone riding a curve near the top reaches up into this row
        // (`milestoneFrames`); the hour label yields to it, since the milestone
        // already names the time.

        while hour <= maxHours {
            let minutePos = Double(hour) * 60
            let x = inset + CGFloat((minutePos - visibleStart) / visibleSpan) * graphWidth

            // Skip labels that would run past the drawable width and get sliced
            // by the canvas clip (the trailing anchor only kicks in at width-15,
            // so a label landing between there and the edge still spills).
            if x >= 8, x <= size.width - 8, markerXs.allSatisfy({ abs($0 - x) > 16 }) {
                let label = String(localized: "\(hour)h")

                let text = Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.legibleOpacity(0.6))
                let resolved = context.resolve(text)
                let labelSize = resolved.measure(in: size)
                let labelWidth = labelSize.width

                let labelLeft: CGFloat = if x < 15 {
                    x
                } else if x > size.width - 15 {
                    x - labelWidth
                } else {
                    x - labelWidth / 2
                }
                let labelFrame = CGRect(
                    x: labelLeft, y: labelY - labelSize.height / 2,
                    width: labelWidth, height: labelSize.height,
                ).insetBy(dx: -2, dy: -1)

                if labelLeft >= lastLabelRight + minSpacing,
                   !milestoneFrames.contains(where: { $0.intersects(labelFrame) }) {
                    let anchor: UnitPoint = if x < 15 {
                        .leading
                    } else if x > size.width - 15 {
                        .trailing
                    } else {
                        .center
                    }
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    lastLabelRight = labelLeft + labelWidth
                }
            }
            hour += hourStep
        }
    }
}
