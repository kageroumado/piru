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
    private var labelAreaHeight: CGFloat { compact ? 0 : 22 }

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
        return max(maxEnd, 1)
    }

    /// Base label interval from the full data span — used only for stable left padding.
    private var baseLabelInterval: Double {
        Self.intervalForSpan(dataSpan)
    }

    /// Choose a tick interval (minutes) for a given visible span
    private static func intervalForSpan(_ span: Double) -> Double {
        if span <= 60 { return 15 }          // ≤1h: every 15min
        else if span <= 180 { return 30 }    // ≤3h: every 30min
        else if span <= 420 { return 60 }    // ≤7h: every 1h
        else if span <= 720 { return 120 }   // ≤12h: every 2h
        else if span <= 1440 { return 240 }  // ≤24h: every 4h
        else if span <= 2880 { return 480 }  // ≤48h: every 8h
        else if span <= 4320 { return 720 }  // ≤72h: every 12h
        else { return 1440 }                 // >72h: every 24h
    }

    /// Minutes of left padding to extend graph to the previous clock boundary.
    /// Only applies in non-compact mode where time labels are shown.
    private var leftPaddingMinutes: Double {
        guard !compact else { return 0 }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: earliestDose)
        let minute = calendar.component(.minute, from: earliestDose)
        let totalMinutes = Double(hour * 60 + minute)
        // Use a capped interval for left padding — never more than 60 min of dead space
        let paddingInterval = min(baseLabelInterval, 60.0)
        let flooredMinutes = floor(totalMinutes / paddingInterval) * paddingInterval
        return totalMinutes - flooredMinutes
    }

    private var totalSpan: Double {
        dataSpan + leftPaddingMinutes
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

    /// Height scale factor for a substance (0.3...1.0). Single doses get full height.
    private func heightScale(for substance: ActiveSubstanceState) -> Double {
        let key = substance.substanceName.lowercased()
        guard let maxDose = maxDoseBySubstance[key], maxDose > 0 else { return 1.0 }
        // Only scale if there are multiple doses of this substance
        let count = substances.filter { $0.substanceName.lowercased() == key }.count
        guard count > 1 else { return 1.0 }
        return max(0.3, substance.amount / maxDose)
    }

    private var effectiveZoom: CGFloat {
        compact ? 1 : max(1, zoom)
    }

    private var visibleSpan: Double {
        totalSpan / Double(effectiveZoom)
    }

    private var visibleStart: Double {
        guard !compact else { return 0 }
        let maxPan = max(0, totalSpan - visibleSpan)
        // When zoomed, skip past the left padding so it doesn't waste space
        let minPan = zoom > 1.01 ? leftPaddingMinutes : 0.0
        return min(max(minPan, panOffset), maxPan)
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
            let graphInset: CGFloat = 4
            let graphWidth = size.width - graphInset * 2
            let graphHeight = size.height - labelAreaHeight - graphInset * 2

            let vStart = visibleStart
            let vSpan = visibleSpan
            guard vSpan > 0, graphHeight > 0 else { return }

            let padding = leftPaddingMinutes
            let diamondSize: CGFloat = compact ? 5 : 7

            // Pre-compute marker positions for two-pass rendering (lines behind, diamonds on top)
            let markerSlots: [(marker: DoseMarker, x: CGFloat, cy: CGFloat)]
            if !markers.isEmpty {
                let slotSpacing: CGFloat = diamondSize * 2.8
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

                let midY = graphInset + graphHeight * 0.5
                markerSlots = slots.compactMap { item in
                    let markerOffset = item.marker.timestamp.timeIntervalSince(earliestDose) / 60 + padding
                    let rawX = graphInset + CGFloat((markerOffset - vStart) / vSpan) * graphWidth
                    guard rawX >= -5 && rawX <= size.width + 5 else { return nil }
                    let x = max(graphInset + diamondSize * 0.7 + 1, rawX)

                    let cy: CGFloat
                    if item.slot == 0 {
                        cy = midY
                    } else if item.slot % 2 == 1 {
                        cy = midY - CGFloat((item.slot + 1) / 2) * slotSpacing
                    } else {
                        cy = midY + CGFloat(item.slot / 2) * slotSpacing
                    }
                    let clampedCy = min(max(cy, graphInset + diamondSize + 2), graphInset + graphHeight - diamondSize - 2)
                    return (marker: item.marker, x: x, cy: clampedCy)
                }
            } else {
                markerSlots = []
            }

            // Pass 1: Marker dashed lines (drawn behind substance curves)
            for item in markerSlots {
                let color = Color(hex: item.marker.colorHex)
                var dashPath = Path()
                dashPath.move(to: CGPoint(x: item.x, y: graphInset + graphHeight))
                dashPath.addLine(to: CGPoint(x: item.x, y: item.cy + diamondSize))
                context.stroke(
                    dashPath,
                    with: .color(color.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }

            // Substance curves
            for substance in substances {
                let color = Color(hex: substance.colorHex)
                let substanceOffset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60 + padding
                let scale = heightScale(for: substance)

                let fillPath = intensityFillPath(
                    for: substance,
                    substanceOffset: substanceOffset,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    inset: graphInset,
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
                    inset: graphInset,
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
                    let y = graphInset + graphHeight - CGFloat(intensity(at: elapsed, for: substance) * scale) * graphHeight * 0.9
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

            // Pass 2: Marker diamonds (drawn on top of substance curves)
            for item in markerSlots {
                let color = Color(hex: item.marker.colorHex)
                var diamond = Path()
                diamond.move(to: CGPoint(x: item.x, y: item.cy - diamondSize))
                diamond.addLine(to: CGPoint(x: item.x + diamondSize * 0.7, y: item.cy))
                diamond.addLine(to: CGPoint(x: item.x, y: item.cy + diamondSize))
                diamond.addLine(to: CGPoint(x: item.x - diamondSize * 0.7, y: item.cy))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(color))
                context.stroke(diamond, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
            }

            if !compact {
                drawTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphInset,
                    graphHeight: graphHeight
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
        inset: CGFloat,
        scale: Double = 1.0
    ) -> Path {
        Path { path in
            let steps = compact ? 40 : 120
            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = inset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = inset + graphHeight - CGFloat(intensity(at: t, for: substance) * scale) * graphHeight * 0.9
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
        inset: CGFloat,
        scale: Double = 1.0
    ) -> Path {
        Path { path in
            let steps = compact ? 40 : 120
            let baseline = inset + graphHeight

            let startX = inset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = inset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = inset + graphHeight - CGFloat(intensity(at: t, for: substance) * scale) * graphHeight * 0.9
                path.addLine(to: CGPoint(x: x, y: y))
            }

            let endX = inset + CGFloat((substanceOffset + substance.totalMinutes - visibleStart) / visibleSpan) * graphWidth
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
        let graphOrigin = earliestDose.addingTimeInterval(-leftPaddingMinutes * 60)
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
        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = inset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            if x >= 0 && x <= size.width {
                let minute = calendar.component(.minute, from: tickDate)
                let hour = calendar.component(.hour, from: tickDate)
                let label: String
                if minute == 0 && hour == 0 {
                    // Midnight — show as day separator only (no date text, just the time)
                    label = "12 AM"
                } else if minute == 0 {
                    label = Self.timeHourFormatter.string(from: tickDate)
                } else {
                    label = Self.timeLabelFormatter.string(from: tickDate)
                }

                let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
                let resolved = context.resolve(text)
                // Use leading/trailing anchor near edges to prevent clipping
                let anchor: UnitPoint
                if x < 20 {
                    anchor = .leading
                } else if x > size.width - 20 {
                    anchor = .trailing
                } else {
                    anchor = .center
                }
                context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
        }
    }
}
