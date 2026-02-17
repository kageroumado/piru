import SwiftUI

struct TimelineGraphView: View {
    let substances: [ActiveSubstanceState]
    let currentTime: Date
    let compact: Bool

    // Zoom & pan state (only active when !compact)
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: Double = 0
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var gestureStartPan: Double = 0

    private var earliestDose: Date {
        substances.map(\.doseTimestamp).min() ?? currentTime
    }

    /// Height reserved for time labels below the graph
    private var labelAreaHeight: CGFloat { compact ? 0 : 22 }

    private var totalSpan: Double {
        var maxEnd: Double = 0
        for substance in substances {
            let offset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let end = offset + substance.totalMinutes
            maxEnd = max(maxEnd, end)
        }
        return maxEnd
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
            let graphInset: CGFloat = 4
            let graphWidth = size.width - graphInset * 2
            let graphHeight = size.height - labelAreaHeight

            let vStart = visibleStart
            let vSpan = visibleSpan
            guard vSpan > 0, graphHeight > 0 else { return }

            for substance in substances {
                let color = Color(hex: substance.colorHex)
                let substanceOffset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60

                let fillPath = intensityFillPath(
                    for: substance,
                    substanceOffset: substanceOffset,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    inset: graphInset
                )
                context.fill(fillPath, with: .color(color.opacity(0.15)))

                let strokePath = intensityStrokePath(
                    for: substance,
                    substanceOffset: substanceOffset,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    inset: graphInset
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
                    let y = graphInset + graphHeight - CGFloat(intensity(at: elapsed, for: substance)) * graphHeight * 0.9
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
        inset: CGFloat
    ) -> Path {
        Path { path in
            let steps = 120
            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = inset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = inset + graphHeight - CGFloat(intensity(at: t, for: substance)) * graphHeight * 0.9
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
        inset: CGFloat
    ) -> Path {
        Path { path in
            let steps = 120
            let baseline = inset + graphHeight

            let startX = inset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            for i in 0...steps {
                let t = Double(i) / Double(steps) * substance.totalMinutes
                let x = inset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = inset + graphHeight - CGFloat(intensity(at: t, for: substance)) * graphHeight * 0.9
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
            return 0.05 * smoothStep(t)
        } else if minutes <= substance.comeupEndMinutes {
            let phaseLength = substance.comeupEndMinutes - substance.onsetEndMinutes
            let t = phaseLength > 0 ? (minutes - substance.onsetEndMinutes) / phaseLength : 1
            return 0.05 + 0.95 * smoothStep(t)
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

        let interval: Double
        if visibleSpan <= 60 { interval = 15 }
        else if visibleSpan <= 180 { interval = 30 }
        else if visibleSpan <= 360 { interval = 60 }
        else if visibleSpan <= 720 { interval = 120 }
        else { interval = 240 }

        let firstMark = visibleStart <= 0 ? 0 : ceil(visibleStart / interval) * interval
        let visibleEnd = visibleStart + visibleSpan
        var t = firstMark
        while t <= visibleEnd {
            let x = inset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
            let label: String
            if t == 0 {
                label = "0"
            } else if t < 60 {
                label = "\(Int(t))m"
            } else {
                let hours = t / 60
                label = hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
            }

            let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
            context.draw(context.resolve(text), at: CGPoint(x: x, y: labelY), anchor: .center)
            t += interval
        }
    }
}
