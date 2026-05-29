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
    private var labelAreaHeight: CGFloat { compact ? 0 : 16 }

    /// Height reserved for relative time labels above the graph
    private var topLabelAreaHeight: CGFloat { compact ? 0 : 12 }

    /// Duration of actual substance activity (earliest dose to latest end)
    private var dataSpan: Double {
        var maxEnd: Double = 0
        for substance in substances {
            let offset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let end = offset + substance.totalMinutes
            maxEnd = max(maxEnd, end)
        }
        // Include markers in the span so they're positioned on the visible axis
        for marker in markers {
            let offset = marker.timestamp.timeIntervalSince(earliestDose) / 60
            maxEnd = max(maxEnd, offset + 60) // Give markers 1h of visual space
        }
        // Cap the window so a single long-half-life compound (e.g. levothyroxine,
        // ~7-day t½ → ~1000h of modelled activity) can't stretch the axis to
        // weeks and crush everything else into the left edge. Long tails are
        // clipped at the cap; pinch-to-zoom still works within it.
        return min(max(maxEnd, 1), Self.maxDisplayMinutes)
    }

    /// Hard cap on the timeline window (48h). Activity past this is clipped so
    /// the meaningful first two days stay legible.
    private static let maxDisplayMinutes: Double = 48 * 60

    /// Target number of time labels on the x-axis for consistency.
    private static let targetTickCount: Int = 8

    /// Choose a clean tick interval that yields ~8 labels for the given span.
    private static func intervalForSpan(_ span: Double) -> Double {
        let candidates: [Double] = [15, 30, 60, 120, 240, 480, 720, 1440]
        let ideal = span / Double(targetTickCount)
        return candidates.first { $0 >= ideal } ?? 1440
    }

    private var totalSpan: Double {
        guard !compact else { return dataSpan }
        let interval = Self.intervalForSpan(dataSpan)
        return ceil(dataSpan / interval) * interval
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
            let count = substances.filter { $0.substanceName.lowercased() == key }.count
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
                let steps = 48
                for i in 0...steps {
                    let t = s + Double(i) / Double(steps) * (e - s)
                    maxV = max(maxV, stackedIntensity(atGlobalMinutes: t, group: group))
                }
            }
            return max(maxV, 0.0001)
        } else {
            return max(substances.map { heightScale(for: $0) }.max() ?? 1, 0.0001)
        }
    }

    /// Multiplier mapping the tallest curve to full height (capped so a tiny
    /// floor value can't blow up beyond the graph).
    private var yNormalization: Double { min(1.0 / peakCurveValue, 20.0) }

    private var effectiveZoom: CGFloat {
        compact ? 1 : max(1, zoom)
    }

    private var visibleSpan: Double {
        totalSpan / Double(effectiveZoom)
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
                                let span = totalSpan
                                guard span > 0 else { return }
                                let newZoom = max(1.0, min(10.0, gestureStartZoom * value.magnification))
                                let oldVisibleSpan = span / Double(max(1, gestureStartZoom))
                                let newVisibleSpan = span / Double(newZoom)
                                let anchorX = Double(value.startAnchor.x)
                                let minuteAtAnchor = gestureStartPan + anchorX * oldVisibleSpan
                                let newPan = minuteAtAnchor - anchorX * newVisibleSpan
                                let maxPan = max(0, span - newVisibleSpan)
                                zoom = newZoom
                                panOffset = min(max(0, newPan), maxPan)
                            }
                            .onEnded { _ in
                                gestureStartZoom = zoom
                                gestureStartPan = panOffset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            zoom = 1.0
                            panOffset = 0
                            gestureStartZoom = 1.0
                            gestureStartPan = 0
                        }
                    }

                if zoom > 1.01 {
                    Slider(
                        value: $panOffset,
                        in: 0...max(0.001, maxPanOffset),
                        onEditingChanged: { editing in
                            if !editing {
                                gestureStartPan = panOffset
                            }
                        }
                    )
                    .tint(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: zoom > 1.01)
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

            // Pre-compute marker positions for two-pass rendering (lines behind, diamonds on top)
            let markerSlots: [(marker: DoseMarker, x: CGFloat, cy: CGFloat)]
            if !markers.isEmpty {
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
                    guard rawX >= -5 && rawX <= size.width + 5 else { return nil }
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
                    graphInset: graphInset
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
                        endPoint: CGPoint(x: item.x, y: bottomY)
                    ),
                    lineWidth: 0.75
                )
            }

            // "Now" indicator — a full-height vertical line at the current
            // moment. The per-curve dot alone reads poorly against the filled
            // area, so the line answers "where are we now" at a glance. Drawn
            // behind the curves (Health-style) so the dose dots still sit on
            // top of it.
            let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
            let nowX = graphInset + CGFloat((nowMinutes - vStart) / vSpan) * graphWidth
            if nowMinutes >= 0, nowX >= graphInset, nowX <= graphInset + graphWidth {
                var nowLine = Path()
                nowLine.move(to: CGPoint(x: nowX, y: graphTop))
                nowLine.addLine(to: CGPoint(x: nowX, y: graphTop + graphHeight))
                context.stroke(
                    nowLine,
                    with: .color(.primary.opacity(0.4)),
                    lineWidth: compact ? 1 : 1.5
                )
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
                    graphTop: graphTop
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
                        scale: scale
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
                        scale: scale
                    )
                    context.stroke(
                        strokePath,
                        with: .color(color),
                        lineWidth: compact ? 1.5 : 2
                    )

                    let elapsed = currentTime.timeIntervalSince(substance.doseTimestamp) / 60
                    if elapsed >= 0 && elapsed <= substance.totalMinutes {
                        let minutePos = substanceOffset + elapsed
                        let x = graphInset + CGFloat((minutePos - vStart) / vSpan) * graphWidth
                        let y = graphTop + graphHeight - CGFloat(intensity(at: elapsed, for: substance) * scale) * graphHeight * 0.93
                        if x >= -5 && x <= graphWidth + 5 {
                            let dotSize: CGFloat = compact ? 5 : 7
                            let dot = Path(ellipseIn: CGRect(
                                x: x - dotSize / 2,
                                y: y - dotSize / 2,
                                width: dotSize,
                                height: dotSize
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
                    height: diamondSize * 2
                ))
                context.fill(circle, with: .color(color))
                context.stroke(circle, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
            }

            if !compact {
                drawTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphTop,
                    graphHeight: graphHeight
                )
                drawRelativeTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphInset,
                    graphTop: graphTop
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
        scale: Double = 1.0
    ) -> Path {
        Path { path in
            let steps = compact ? 40 : 120
            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance) * scale) * graphHeight * 0.93
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
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
        scale: Double = 1.0
    ) -> Path {
        Path { path in
            let steps = compact ? 40 : 120
            let baseline = graphTop + graphHeight

            let startX = graphInset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance) * scale) * graphHeight * 0.93
                path.addLine(to: CGPoint(x: x, y: y))
            }

            let endX = graphInset + CGFloat((substanceOffset + substance.totalMinutes - visibleStart) / visibleSpan) * graphWidth
            path.addLine(to: CGPoint(x: endX, y: baseline))
            path.closeSubpath()
        }
    }

    // MARK: - Intensity

    private func intensity(at minutes: Double, for substance: ActiveSubstanceState) -> Double {
        guard minutes >= 0, minutes < substance.totalMinutes else { return 0 }

        let hasAfterglow = substance.afterglowEndMinutes != nil

        if minutes <= substance.onsetEndMinutes {
            let t = substance.onsetEndMinutes > 0 ? minutes / substance.onsetEndMinutes : 0
            return 0.15 * smoothStep(t)
        } else if minutes <= substance.comeupEndMinutes {
            let phaseLength = substance.comeupEndMinutes - substance.onsetEndMinutes
            let t = phaseLength > 0 ? (minutes - substance.onsetEndMinutes) / phaseLength : 1
            return 0.15 + 0.85 * smoothStep(t)
        } else if minutes <= substance.peakEndMinutes {
            return 1.0
        } else if minutes <= substance.offsetEndMinutes {
            let phaseLength = substance.offsetEndMinutes - substance.peakEndMinutes
            let t = phaseLength > 0 ? (minutes - substance.peakEndMinutes) / phaseLength : 1
            let floor = hasAfterglow ? 0.15 : 0.0
            return 1.0 - (1.0 - floor) * smoothStep(t)
        } else if let afterEnd = substance.afterglowEndMinutes, minutes <= afterEnd {
            let phaseLength = afterEnd - substance.offsetEndMinutes
            let t = phaseLength > 0 ? (minutes - substance.offsetEndMinutes) / phaseLength : 1
            return 0.15 * (1 - smoothStep(t))
        }
        return 0
    }

    private func smoothStep(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
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

    /// Summed intensity of a group at a given global time (minutes since earliestDose).
    /// Each dose contributes `intensity(localT) * doseIntensity`, and the sum is clamped
    /// to [0, 1] so the curve stays inside the graph bounds even when doses overlap heavily.
    private func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState]) -> Double {
        var sum = 0.0
        for dose in group {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let local = global - offset
            guard local >= 0, local < dose.totalMinutes else { continue }
            sum += intensity(at: local, for: dose) * dose.doseIntensity
        }
        return min(1.0, sum)
    }

    private func stackedGroupRange(_ group: [ActiveSubstanceState]) -> (start: Double, end: Double) {
        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        for dose in group {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            start = min(start, offset)
            end = max(end, offset + dose.totalMinutes)
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
        graphTop: CGFloat
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

            // Build a single stacked curve across the group's active window.
            func point(at i: Int) -> CGPoint {
                let t = gStart + Double(i) / Double(steps) * gSpan
                let x = graphInset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
                let v = min(1.0, stackedIntensity(atGlobalMinutes: t, group: group) * yNorm)
                let y = baseline - CGFloat(v) * graphHeight * 0.93
                return CGPoint(x: x, y: y)
            }

            var fillPath = Path()
            let startX = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
            fillPath.move(to: CGPoint(x: startX, y: baseline))
            for i in 0...steps { fillPath.addLine(to: point(at: i)) }
            let endX = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
            fillPath.addLine(to: CGPoint(x: endX, y: baseline))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(color.opacity(0.15)))

            var strokePath = Path()
            for i in 0...steps {
                let p = point(at: i)
                if i == 0 { strokePath.move(to: p) } else { strokePath.addLine(to: p) }
            }
            context.stroke(strokePath, with: .color(color), lineWidth: compact ? 1.5 : 2)

            // Small tick glyphs at each redose time along the baseline so the user
            // can see where additional doses contributed to the curve.
            if group.count > 1 && !compact {
                for dose in group {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let x = graphInset + CGFloat((offset - visibleStart) / visibleSpan) * graphWidth
                    guard x >= -5 && x <= graphWidth + 5 else { continue }
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: baseline))
                    tick.addLine(to: CGPoint(x: x, y: baseline - 5))
                    context.stroke(tick, with: .color(color.opacity(0.75)), lineWidth: 1.5)
                }
            }

            // Current-time dot on the summed curve.
            let elapsedGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if elapsedGlobal >= gStart && elapsedGlobal <= gEnd {
                let x = graphInset + CGFloat((elapsedGlobal - visibleStart) / visibleSpan) * graphWidth
                let y = baseline - CGFloat(stackedIntensity(atGlobalMinutes: elapsedGlobal, group: group)) * graphHeight * 0.93
                if x >= -5 && x <= graphWidth + 5 {
                    let dotSize: CGFloat = compact ? 5 : 7
                    let dot = Path(ellipseIn: CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
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
        graphInset: CGFloat
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

            if x >= graphInset && x <= size.width - graphInset {
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
        graphHeight: CGFloat
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

            if x >= 0 && x <= size.width {
                let minute = calendar.component(.minute, from: tickDate)
                let hour = calendar.component(.hour, from: tickDate)
                let label: String
                if minute == 0 && hour == 0 {
                    label = "12 AM"
                } else if minute == 0 {
                    label = Self.timeHourFormatter.string(from: tickDate)
                } else {
                    label = Self.timeLabelFormatter.string(from: tickDate)
                }

                let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat
                if x < 20 {
                    labelLeft = x
                } else if x > size.width - 20 {
                    labelLeft = x - labelWidth
                } else {
                    labelLeft = x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minLabelSpacing {
                    let anchor: UnitPoint
                    if x < 20 {
                        anchor = .leading
                    } else if x > size.width - 20 {
                        anchor = .trailing
                    } else {
                        anchor = .center
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
        graphTop: CGFloat
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
        var hour: Int = 0
        let maxHours = Int(ceil(dataSpan / 60))
        var lastLabelRight: CGFloat = -.infinity
        let minSpacing: CGFloat = 8

        while hour <= maxHours {
            let minutePos = Double(hour) * 60
            let x = inset + CGFloat((minutePos - visibleStart) / visibleSpan) * graphWidth

            if x >= -10 && x <= size.width + 10 {
                let label = "\(hour)h"

                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.5))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat
                if x < 15 {
                    labelLeft = x
                } else if x > size.width - 15 {
                    labelLeft = x - labelWidth
                } else {
                    labelLeft = x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minSpacing {
                    let anchor: UnitPoint
                    if x < 15 {
                        anchor = .leading
                    } else if x > size.width - 15 {
                        anchor = .trailing
                    } else {
                        anchor = .center
                    }
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    lastLabelRight = labelLeft + labelWidth
                }
            }
            hour += hourStep
        }
    }

}
