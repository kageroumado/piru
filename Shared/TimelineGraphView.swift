import SwiftUI

/// A dose without duration data, shown as a timestamp marker on the graph.
struct DoseMarker {
    let substanceName: String
    let timestamp: Date
    let colorHex: String
    let amount: Double
    let unit: String
}

struct TimelineGraphView: View {
    let substances: [ActiveSubstanceState]
    let currentTime: Date
    let compact: Bool
    var markers: [DoseMarker] = []
    var stackRedoses: Bool = false
    /// Draws the per-curve "now" dot at `currentTime`. Meaningful on the live
    /// session accessory and the full detail graph; off for the historical
    /// journal thumbnails, where it's an axis-less artifact.
    var showNowIndicator: Bool = true

    // Zoom & pan state (only active when !compact)
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: Double = 0
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var gestureStartPan: Double = 0

    private var earliestDose: Date {
        let substanceDates = substances.map(\.doseTimestamp)
        let markerDates = markers.map(\.timestamp)
        return (substanceDates + markerDates).min() ?? currentTime
    }

    /// Height reserved for time labels below the graph
    private var labelAreaHeight: CGFloat {
        compact ? 0 : 16
    }

    /// Height reserved for relative time labels above the graph
    private var topLabelAreaHeight: CGFloat {
        compact ? 0 : 12
    }

    /// Full scrollable extent — the latest minute the tallest *rendered* curve
    /// is still above ~4 % of full graph height. Found by sampling the actual
    /// drawn envelope rather than each dose's own-peak %, so a flat near-zero
    /// tail is cut regardless of stacking or height scaling. Capped at the
    /// display window so a multi-day half-life can't stretch the axis to weeks.
    private var dataSpan: Double {
        spanIncludingMarkers(renderedTail(threshold: 0.04))
    }

    /// Add marker (duration-less dose) positions to a computed span so they
    /// still land on the visible axis.
    private func spanIncludingMarkers(_ base: Double) -> Double {
        var maxEnd = base
        for marker in markers {
            let offset = marker.timestamp.timeIntervalSince(earliestDose) / 60
            maxEnd = max(maxEnd, offset + 60)
        }
        return min(max(maxEnd, 1), Self.maxDisplayMinutes)
    }

    /// Empirically find where the rendered curve envelope returns toward
    /// baseline: the latest minute at which the tallest drawn curve still
    /// exceeds `threshold` of full graph height. Params/scale are precomputed
    /// once (not per sample) so the scan stays cheap.
    private func renderedTail(threshold: Double) -> Double {
        let yNorm = yNormalization
        if stackRedoses {
            let groups = stackedGroups
            let params = groups.map { $0.map { pkParams(for: $0) } }
            var upper: Double = 1
            for (gi, group) in groups.enumerated() {
                for (di, dose) in group.enumerated() {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    upper = max(upper, offset + curveExtent(for: dose, params: params[gi][di]))
                }
            }
            upper = min(upper, Self.maxDisplayMinutes)
            func height(_ t: Double) -> Double {
                var h = 0.0
                for (gi, group) in groups.enumerated() {
                    h = max(h, stackedIntensity(atGlobalMinutes: t, group: group, params: params[gi]) * yNorm)
                }
                return h
            }
            return scanTail(upper: upper, threshold: threshold, height: height)
        } else {
            let params = substances.map { pkParams(for: $0) }
            let scales = substances.map { heightScale(for: $0) }
            var upper: Double = 1
            for (i, s) in substances.enumerated() {
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                upper = max(upper, offset + curveExtent(for: s, params: params[i]))
            }
            upper = min(upper, Self.maxDisplayMinutes)
            func height(_ t: Double) -> Double {
                var h = 0.0
                for (i, s) in substances.enumerated() {
                    let local = t - s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    guard local >= 0 else { continue }
                    h = max(h, intensity(at: local, for: s, params: params[i]) * scales[i] * yNorm)
                }
                return h
            }
            return scanTail(upper: upper, threshold: threshold, height: height)
        }
    }

    private func scanTail(upper: Double, threshold: Double, height: (Double) -> Double) -> Double {
        let steps = 240
        var lastActive: Double = 0
        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * upper
            if height(t) >= threshold { lastActive = t }
        }
        return max(lastActive, 1)
    }

    /// Hard cap on the timeline window (48h). Activity past this is clipped so
    /// the meaningful first two days stay legible.
    private static let maxDisplayMinutes: Double = 48 * 60

    /// Above this many duration-less doses, the compact baseline dots stop
    /// adding information and collapse into a noisy smear — so on a curve-rich
    /// day we drop them entirely (the curves already read as "busy"). A
    /// curve-less day always shows them: they're the card's only content.
    private static let maxCompactMarkers: Int = 5

    /// Whether to render the compact baseline + its dose dots. Skipped on busy
    /// curve days where the dots are redundant clutter; always on when there
    /// are no curves to carry the card.
    private var showCompactMarkers: Bool {
        guard compact, !markers.isEmpty else { return false }
        return substances.isEmpty || markers.count <= Self.maxCompactMarkers
    }

    /// Target number of time labels on the x-axis for consistency.
    private static let targetTickCount: Int = 8

    /// Choose a clean tick interval that yields ~8 labels for the given span.
    private static func intervalForSpan(_ span: Double) -> Double {
        let candidates: [Double] = [15, 30, 60, 120, 240, 480, 720, 1_440]
        let ideal = span / Double(targetTickCount)
        return candidates.first { $0 >= ideal } ?? 1_440
    }

    /// Full scrollable extent — ends exactly where the last curve does, so a
    /// panned-out view has no empty axis past the data. (No rounding up to a
    /// tick boundary; ticks land wherever they fall inside the window.)
    private var totalSpan: Double {
        compact ? autoFitSpan : dataSpan
    }

    /// The labeled-active window: earliest dose to the latest *subjective* end
    /// (`totalMinutes`), ignoring the long elimination tails. A long-acting
    /// compound's days-long tail therefore doesn't crush the acute action into
    /// the left edge — the tail stays reachable by panning past this window.
    private var activitySpan: Double {
        spanIncludingMarkers(renderedTail(threshold: 0.20))
    }

    /// Span shown at rest (`zoom == 1`). Normally the full extent — but when a
    /// long elimination tail makes that more than 1.6× the labeled-active
    /// window, we frame just the activity window instead (the tail stays
    /// reachable by panning). This keeps simple days showing everything with no
    /// scrollbar, while long-acting compounds no longer crush the acute action.
    private var autoFitSpan: Double {
        let activityInterval = Self.intervalForSpan(activitySpan)
        let activity = max(ceil(activitySpan / activityInterval) * activityInterval, 1)
        let full = max(dataSpan, 1)
        // Reframe when the low tail adds real dead axis (> 2.5 h past the
        // clearly-active window). Short curves with a small tail show whole.
        return full - activity > 150 ? activity : full
    }

    /// Max dose amount per substance name, used to scale curve heights proportionally.
    private var maxDoseBySubstance: [String: Double] {
        var result: [String: Double] = [:]
        for s in substances {
            let key = s.substanceName.lowercased()
            result[key] = max(result[key] ?? 0, s.amount)
        }
        return result
    }

    /// Height scale factor combining dose intensity (vs heavy threshold) and
    /// relative scaling when multiple doses of the same substance are present.
    /// The multi-dose multiplier preserves PsychonautWiki-style behavior where
    /// a 17g alcohol next to a 34g alcohol renders at roughly half the height.
    private func heightScale(for substance: ActiveSubstanceState) -> Double {
        var scale = substance.doseIntensity
        let key = substance.substanceName.lowercased()
        if let maxDose = maxDoseBySubstance[key], maxDose > 0 {
            let count = substances.count(where: { $0.substanceName.lowercased() == key })
            if count > 1 {
                scale *= max(0.2, substance.amount / maxDose)
            }
        }
        return max(0.05, scale)
    }

    /// Highest curve peak across all substances/groups. Used to normalize the
    /// y-axis so the tallest curve fills the height — a lone low dose then
    /// reaches the top instead of rendering as a flat sliver, and multiple
    /// curves keep their relative proportions.
    private var peakCurveValue: Double {
        if stackRedoses {
            var maxV = 0.0
            for group in stackedGroups {
                let (s, e) = stackedGroupRange(group)
                guard e > s else { continue }
                let params = group.map { pkParams(for: $0) }
                let steps = 48
                for i in 0 ... steps {
                    let t = s + Double(i) / Double(steps) * (e - s)
                    maxV = max(maxV, stackedIntensity(atGlobalMinutes: t, group: group, params: params))
                }
            }
            return max(maxV, 0.0001)
        } else {
            return max(substances.map { heightScale(for: $0) }.max() ?? 1, 0.0001)
        }
    }

    /// Multiplier mapping the tallest curve to full height (capped so a tiny
    /// floor value can't blow up beyond the graph).
    private var yNormalization: Double {
        min(1.0 / peakCurveValue, 20.0)
    }

    private var effectiveZoom: CGFloat {
        compact ? 1 : max(1, zoom)
    }

    /// Visible window. At rest this is `autoFitSpan` (the activity window);
    /// pinch-zoom shrinks it further. Capped at the full extent so it can never
    /// exceed what there is to show.
    private var visibleSpan: Double {
        min(autoFitSpan / Double(effectiveZoom), totalSpan)
    }

    private var visibleStart: Double {
        guard !compact else { return 0 }
        let maxPan = max(0, totalSpan - visibleSpan)
        return min(max(0, panOffset), maxPan)
    }

    private var maxPanOffset: Double {
        max(0, totalSpan - visibleSpan)
    }

    var body: some View {
        if compact {
            graphCanvas
        } else {
            VStack(spacing: 0) {
                graphCanvas
                    .contentShape(Rectangle())
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let fit = autoFitSpan
                                let full = totalSpan
                                guard fit > 0, full > 0 else { return }
                                let newZoom = max(1.0, min(10.0, gestureStartZoom * value.magnification))
                                let oldVisibleSpan = min(fit / Double(max(1, gestureStartZoom)), full)
                                let newVisibleSpan = min(fit / Double(newZoom), full)
                                let anchorX = Double(value.startAnchor.x)
                                let minuteAtAnchor = gestureStartPan + anchorX * oldVisibleSpan
                                let newPan = minuteAtAnchor - anchorX * newVisibleSpan
                                let maxPan = max(0, full - newVisibleSpan)
                                zoom = newZoom
                                panOffset = min(max(0, newPan), maxPan)
                            }
                            .onEnded { _ in
                                gestureStartZoom = zoom
                                gestureStartPan = panOffset
                            },
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            zoom = 1.0
                            panOffset = 0
                            gestureStartZoom = 1.0
                            gestureStartPan = 0
                        }
                    }

                if maxPanOffset > 1 {
                    Slider(
                        value: $panOffset,
                        in: 0 ... max(0.001, maxPanOffset),
                        onEditingChanged: { editing in
                            if !editing {
                                gestureStartPan = panOffset
                            }
                        },
                    )
                    .tint(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: maxPanOffset > 1)
        }
    }

    private var graphCanvas: some View {
        Canvas { context, size in
            let graphInset: CGFloat = 2
            let graphTop = graphInset + topLabelAreaHeight
            let graphWidth = size.width - graphInset * 2
            let graphHeight = size.height - labelAreaHeight - topLabelAreaHeight - graphInset * 2

            let vStart = visibleStart
            let vSpan = visibleSpan
            guard vSpan > 0, graphHeight > 0 else { return }

            let diamondSize: CGFloat = 3

            // Pre-compute marker positions for two-pass rendering (lines behind,
            // diamonds on top). Full graph only — compact thumbnails render
            // markers as dots on the shared baseline instead (see below).
            let markerSlots: [(marker: DoseMarker, x: CGFloat, cy: CGFloat)]
            if !compact, !markers.isEmpty {
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

                // Group slots by their x position for even vertical distribution
                let groupedSlots: [[Int]] = groups
                markerSlots = slots.compactMap { item in
                    let markerOffset = item.marker.timestamp.timeIntervalSince(earliestDose) / 60
                    let rawX = graphInset + CGFloat((markerOffset - vStart) / vSpan) * graphWidth
                    guard rawX >= -5, rawX <= size.width + 5 else { return nil }
                    let x = max(graphInset + diamondSize + 1, rawX)

                    // Find which group this marker belongs to
                    let groupIndex = groupedSlots.firstIndex { group in
                        group.contains { j in
                            abs(markers[j].timestamp.timeIntervalSince(item.marker.timestamp)) < 120
                        }
                    } ?? 0
                    _ = groupedSlots[groupIndex].count

                    // Stack diamonds from the bottom of the graph upward, clamped to graph area
                    let usableBottom = graphTop + graphHeight - diamondSize - 2
                    let usableTop = graphTop + diamondSize + 2
                    let spacing = diamondSize * 2 + 4
                    let cy = max(usableTop, usableBottom - CGFloat(item.slot) * spacing)
                    return (marker: item.marker, x: x, cy: cy)
                }
            } else {
                markerSlots = []
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

            // Pass 1: Marker lines (subtle pink gradient behind diamonds)
            let markerLineColor = Color(hex: "FFAACC")
            for item in markerSlots {
                let topY = item.cy + diamondSize
                let bottomY = graphTop + graphHeight

                var linePath = Path()
                linePath.move(to: CGPoint(x: item.x, y: topY))
                linePath.addLine(to: CGPoint(x: item.x, y: bottomY))
                context.stroke(
                    linePath,
                    with: .linearGradient(
                        Gradient(colors: [markerLineColor.opacity(0.35), markerLineColor.opacity(0.05)]),
                        startPoint: CGPoint(x: item.x, y: topY),
                        endPoint: CGPoint(x: item.x, y: bottomY),
                    ),
                    lineWidth: 0.75,
                )
            }

            // "Now" indicator — a full-height vertical line at the current
            // moment. The per-curve dot alone reads poorly against the filled
            // area, so the line answers "where are we now" at a glance. Drawn
            // behind the curves (Health-style) so the dose dots still sit on
            // top of it.
            let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
            let nowX = graphInset + CGFloat((nowMinutes - vStart) / vSpan) * graphWidth
            // Skip on compact thumbnails: a full-height line on a 96pt card reads
            // as a stray glitch, not a "you are here" cue.
            if !compact, nowMinutes >= 0, nowX >= graphInset, nowX <= graphInset + graphWidth {
                var nowLine = Path()
                nowLine.move(to: CGPoint(x: nowX, y: graphTop))
                nowLine.addLine(to: CGPoint(x: nowX, y: graphTop + graphHeight))
                context.stroke(
                    nowLine,
                    with: .color(.primary.opacity(0.4)),
                    lineWidth: compact ? 1 : 1.5,
                )
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
            if stackRedoses {
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
                    let color = Color(hex: substance.colorHex)
                    let substanceOffset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let scale = heightScale(for: substance) * yNorm

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
                    context.fill(fillPath, with: .color(color.opacity(0.15)))

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
                        with: .color(color),
                        lineWidth: compact ? 1.5 : 2,
                    )

                    let elapsed = currentTime.timeIntervalSince(substance.doseTimestamp) / 60
                    if showNowIndicator, elapsed >= 0, elapsed <= substance.totalMinutes {
                        let minutePos = substanceOffset + elapsed
                        let x = graphInset + CGFloat((minutePos - vStart) / vSpan) * graphWidth
                        let y = graphTop + graphHeight - CGFloat(intensity(at: elapsed, for: substance, params: pkParams(for: substance)) * scale) * graphHeight * 0.93
                        if x >= -5, x <= graphWidth + 5 {
                            let dotSize: CGFloat = compact ? 5 : 7
                            let dot = Path(ellipseIn: CGRect(
                                x: x - dotSize / 2,
                                y: y - dotSize / 2,
                                width: dotSize,
                                height: dotSize,
                            ))
                            context.fill(dot, with: .color(color))
                            context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                        }
                    }
                }
            }

            // Pass 2: Marker circles (drawn on top of substance curves)
            for item in markerSlots {
                let color = Color(hex: item.marker.colorHex)
                let circle = Path(ellipseIn: CGRect(
                    x: item.x - diamondSize,
                    y: item.cy - diamondSize,
                    width: diamondSize * 2,
                    height: diamondSize * 2,
                ))
                context.fill(circle, with: .color(color))
                context.stroke(circle, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
            }

            // Compact: duration-less doses rest as small colour-coded dots on the
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
                    context.fill(dot, with: .color(Color(hex: marker.colorHex)))
                    context.stroke(dot, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
                }
            }

            if !compact {
                drawTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphTop,
                    graphHeight: graphHeight,
                )
                drawRelativeTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphInset,
                    graphTop: graphTop,
                )
            }
        }
        .clipped()
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
            let params = pkParams(for: substance)
            let drawEnd = curveExtent(for: substance, params: params)
            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
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
            let params = pkParams(for: substance)
            let drawEnd = curveExtent(for: substance, params: params)

            let startX = graphInset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: false)

            let endX = graphInset + CGFloat((substanceOffset + drawEnd - visibleStart) / visibleSpan) * graphWidth
            path.addLine(to: CGPoint(x: endX, y: baseline))
            path.closeSubpath()
        }
    }

    // MARK: - Intensity (mechanistic Bateman PK curve)

    /// Absorption / elimination rate constants for a one-compartment Bateman
    /// curve, fit to a dose's subjective duration profile. Precomputed once per
    /// curve — the `estimateKa` Newton solve is far too costly to run per pixel.
    struct PKCurveParams {
        let ka: Double
        let ke: Double
        let cmax: Double
    }

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
    /// - **Absorption (`ka`)** is chosen so the peak lands at the centre of the
    ///   subjective peak plateau, clamped just inside `1/ke` so the curve stays
    ///   well-formed. A long plateau pushes the target peak late, driving
    ///   `ka → ke` and naturally yielding the broad, rounded `ke·t·e^(−ke·t)`
    ///   top — a sustained peak without the artificial flat trapezoid lid.
    func pkParams(for s: ActiveSubstanceState) -> PKCurveParams {
        let total = max(s.totalMinutes, 1)
        let peakCenter = (s.comeupEndMinutes + s.peakEndMinutes) / 2
        // Decay to 5% of peak by `total`; anchor the window on the peak centre
        // but never let it collapse to nothing.
        let decayWindow = max(total - min(peakCenter, total * 0.5), total * 0.25)
        let ke = log(20) / decayWindow
        // A feasible Bateman peak must satisfy tmax < 1/ke — clamp the target
        // just inside that bound.
        let tmaxTarget = min(max(peakCenter, 1), 0.85 / ke)
        // Cap absorption so a very short-duration substance can't fit an
        // unrealistically vertical rise: `ka ≤ 10·ke` keeps a visible, rounded
        // up-slope (min tmax ≈ ln10/(9·ke) ≈ 0.26/ke) instead of a wall.
        let ka = min(PKModel.estimateKa(timeToPeak: tmaxTarget, ke: ke), ke * 10)
        let cmax = max(PKModel.cmax(ke: ke, ka: ka), 1e-9)
        return PKCurveParams(ka: ka, ke: ke, cmax: cmax)
    }

    /// Normalized [0, 1] effect intensity at `minutes` past dose, from the
    /// fitted Bateman curve. Unbounded above `totalMinutes` — the curve decays
    /// naturally toward zero, so callers draw it to `curveExtent(for:)` and it
    /// tails smoothly to baseline rather than being cut off mid-descent.
    private func intensity(at minutes: Double, for _: ActiveSubstanceState, params: PKCurveParams) -> Double {
        guard minutes >= 0 else { return 0 }
        let c = PKModel.concentration(at: minutes, ke: params.ke, ka: params.ka)
        return min(1, max(0, c / params.cmax))
    }

    /// Minutes after the dose at which the fitted curve has decayed to ~1 % of
    /// its peak — the point past which nothing meaningful remains to draw. Used
    /// as the per-curve draw end so the descent tails smoothly to baseline,
    /// instead of being guillotined at `totalMinutes` (which sits at ~5 % and
    /// leaves a vertical cliff). Never shorter than `totalMinutes`; capped at
    /// the display window so a long elimination tail can't stretch the axis.
    private func curveExtent(for s: ActiveSubstanceState, params: PKCurveParams) -> Double {
        // 4 % of peak: low enough to read as "done", high enough that the axis
        // doesn't stretch across a long invisible near-zero tail. The residual
        // drop to baseline at this point is only a few px.
        let cut = PKModel.timeToFraction(0.04, ke: params.ke, ka: params.ka, maxMinutes: Self.maxDisplayMinutes)
        return min(max(cut, s.totalMinutes), Self.maxDisplayMinutes)
    }

    /// Append a smooth curve through `pts` using a uniform Catmull-Rom spline
    /// converted to cubic Bézier segments — renders the sampled PK points as a
    /// continuous biological shape instead of faceted line segments. When
    /// `startNew` is false the current point is assumed to be `pts[0]` (used by
    /// the fill path, which has already moved to the baseline start).
    private func addSmoothCurve(_ pts: [CGPoint], to path: inout Path, startNew: Bool) {
        guard pts.count >= 2 else {
            if let p = pts.first { startNew ? path.move(to: p) : path.addLine(to: p) }
            return
        }
        if startNew { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        for i in 0 ..< pts.count - 1 {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    /// Zero-phase one-pole low-pass over evenly-spaced samples — a discrete
    /// effect-site (PK/PD) filter. Frequent redoses produce a spiky summed
    /// *plasma* curve, but subjective *effect* lags and integrates it, so the
    /// sawtooth becomes one smooth session envelope. Running the filter forward
    /// then backward cancels phase lag so the peak doesn't drift in time.
    private func effectSiteSmoothed(_ v: [Double], dtMinutes: Double, tauMinutes: Double) -> [Double] {
        guard v.count > 2, dtMinutes > 0, tauMinutes > 0 else { return v }
        let alpha = 1 - exp(-dtMinutes / tauMinutes)
        var out = v
        for i in 1 ..< out.count { out[i] = out[i - 1] + alpha * (out[i] - out[i - 1]) }
        for i in stride(from: out.count - 2, through: 0, by: -1) { out[i] = out[i + 1] + alpha * (out[i] - out[i + 1]) }
        return out
    }

    // MARK: - Stacked Rendering

    /// Groups substance states by lowercased substance name, preserving original order.
    private var stackedGroups: [[ActiveSubstanceState]] {
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

    /// Raw summed intensity of a group at a given global time (minutes since
    /// earliestDose). Each dose contributes `intensity(localT) * doseIntensity`.
    ///
    /// The sum is intentionally **not** clamped here: clamping to 1.0 would pin
    /// overlapping redoses flat at the ceiling and carve an artificial dip
    /// between them (an implausible "M"). Instead the caller normalizes by the
    /// true combined peak (`peakCurveValue`), so superposed doses render as a
    /// single rounded envelope — what real serial-dose plasma curves look like.
    /// `params` holds the precomputed Bateman fit per dose, aligned to `group`.
    private func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState], params: [PKCurveParams]) -> Double {
        var sum = 0.0
        for (i, dose) in group.enumerated() {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let local = global - offset
            guard local >= 0 else { continue }
            sum += intensity(at: local, for: dose, params: params[i]) * dose.doseIntensity
        }
        return sum
    }

    private func stackedGroupRange(_ group: [ActiveSubstanceState]) -> (start: Double, end: Double) {
        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        for dose in group {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            start = min(start, offset)
            end = max(end, offset + curveExtent(for: dose, params: pkParams(for: dose)))
        }
        return (start, end)
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

        for group in stackedGroups {
            guard let first = group.first else { continue }
            let color = Color(hex: first.colorHex)
            let (gStart, gEnd) = stackedGroupRange(group)
            let gSpan = gEnd - gStart
            guard gSpan > 0 else { continue }
            let params = group.map { pkParams(for: $0) }

            // Sample the summed curve, then (for genuine redose stacks) pass it
            // through an effect-site low-pass so frequent redoses read as one
            // smooth session envelope rather than a spiky plasma sawtooth.
            let dt = gSpan / Double(steps)
            let tau = min(max(gSpan * 0.04, 12), 90)
            var vs: [Double] = []
            vs.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = gStart + Double(i) / Double(steps) * gSpan
                vs.append(stackedIntensity(atGlobalMinutes: t, group: group, params: params) * yNorm)
            }
            if group.count > 1 {
                vs = effectSiteSmoothed(vs, dtMinutes: dt, tauMinutes: tau)
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
            context.fill(fillPath, with: .color(color.opacity(0.15)))

            var strokePath = Path()
            addSmoothCurve(pts, to: &strokePath, startNew: true)
            context.stroke(strokePath, with: .color(color), lineWidth: compact ? 1.5 : 2)

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
                    context.stroke(tick, with: .color(color.opacity(0.75)), lineWidth: 1.5)
                }
            }

            // Current-time dot on the summed curve. Must use the SAME normalized
            // value as `point(at:)` above — `stackedIntensity * yNorm`, clamped —
            // or the dot detaches from the curve whenever `yNorm` shifts (e.g. a
            // dose is added/removed and the graph rescales to fill the height).
            let elapsedGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if showNowIndicator, elapsedGlobal >= gStart, elapsedGlobal <= gEnd {
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
                    context.fill(dot, with: .color(color))
                    context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Tick Marks

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
        let interval = Self.intervalForSpan(visibleSpan)

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

                // Small tick mark at top edge
                var topTick = Path()
                topTick.move(to: CGPoint(x: x, y: graphTop))
                topTick.addLine(to: CGPoint(x: x, y: graphTop - 3))
                context.stroke(topTick, with: .color(.primary.opacity(0.2)), lineWidth: 0.5)
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
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
        graphHeight: CGFloat,
    ) {
        let graphWidth = size.width - inset * 2
        let labelY = inset + graphHeight + labelAreaHeight / 2 + 2
        let calendar = Calendar.current

        let interval = Self.intervalForSpan(visibleSpan)

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

        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = inset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            if x >= 0, x <= size.width {
                let minute = calendar.component(.minute, from: tickDate)
                let hour = calendar.component(.hour, from: tickDate)
                let label: String = if minute == 0, hour == 0 {
                    "12 AM"
                } else if minute == 0 {
                    Self.timeHourFormatter.string(from: tickDate)
                } else {
                    Self.timeLabelFormatter.string(from: tickDate)
                }

                let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
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
    ) {
        let graphWidth = size.width - inset * 2
        let labelY = inset + 4
        // Determine hour step based on visible span
        let hourStep: Int
        let visibleHours = visibleSpan / 60
        if visibleHours <= 4 { hourStep = 1 }
        else if visibleHours <= 12 { hourStep = 2 }
        else if visibleHours <= 24 { hourStep = 4 }
        else { hourStep = 6 }

        // Always step in whole hours to avoid duplicates
        var hour = 0
        let maxHours = Int(ceil(dataSpan / 60))
        var lastLabelRight: CGFloat = -.infinity
        let minSpacing: CGFloat = 8

        while hour <= maxHours {
            let minutePos = Double(hour) * 60
            let x = inset + CGFloat((minutePos - visibleStart) / visibleSpan) * graphWidth

            if x >= -10, x <= size.width + 10 {
                let label = "\(hour)h"

                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.5))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat = if x < 15 {
                    x
                } else if x > size.width - 15 {
                    x - labelWidth
                } else {
                    x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minSpacing {
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
