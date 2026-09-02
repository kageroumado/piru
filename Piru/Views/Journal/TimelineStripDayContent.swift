import SwiftData
import SwiftUI

/// The strip layout of one day: a single full-width canvas (hour gridlines,
/// axis, curves, connectors, the Now line) with the gutter marks, dose dots
/// and the glass bubble column layered over it. The curves get the lane from
/// the axis to 60 % of the width beyond it and run under the bubbles — the
/// eye reconstructs the covered part — except with strength scaling off, when
/// every curve reaches full amplitude and the lane also stops 8 pt short of
/// the bubbles so the peaks stay visible.
struct TimelineStripDayContent: View {
    let day: TimelineDayLayout
    let onEntryTap: (DoseEntry) -> Void
    let onSessionTap: (UUID) -> Void

    /// Horizontal inset of every bubble within its column, so a session
    /// envelope's edge stays visible around the bubbles it wraps.
    private static let bubbleInset: CGFloat = 8
    /// Clearance between a full-amplitude curve and the bubbles when the
    /// lane must stop short of them.
    private static let peakClearance: CGFloat = 8
    /// A curve's full amplitude, as a fraction of the width available beyond
    /// the axis — wider would add precision the model doesn't have.
    private static let maxAmplitudeFraction: CGFloat = 0.6
    /// The day tag's inset from the slice's top (below any break).
    private static let dayTagTop: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let bubbleWidth = TimelineDoseBubble.width(for: day.style.bubbleStyle)
            let columnWidth = bubbleWidth + 2 * Self.bubbleInset
            let columnX = geo.size.width - TimelineGutter.edgeInset - columnWidth
            let bubbleLeft = columnX + Self.bubbleInset

            ZStack(alignment: .topLeading) {
                strip(bubbleLeft: bubbleLeft)
                gutterMarks
                doseDots
                bubbleColumn(width: columnWidth)
                    .offset(x: columnX)
            }
        }
        .frame(height: day.totalHeight)
        .overlay(alignment: .topLeading) {
            TimelineDayHeader(date: day.date, isToday: day.isToday)
                .padding(.leading, TimelineGutter.edgeInset)
                .padding(.top, Self.dayTagTop + day.breakAbove)
        }
    }

    /// Slice-local y below which no gutter mark may start: the day tag and
    /// its breathing room.
    static func reservedTop(breakAbove: CGFloat) -> CGFloat {
        breakAbove + dayTagTop + TimelineGutterLabels.dayTagHeight
    }

    // MARK: Gutter marks

    /// Hour pills, dose capsules and the Now tag, each hanging from the
    /// strip's leading edge across the axis. Drawn under the dose dots, so a
    /// capsule is pinned by the dot in its slot.
    private var gutterMarks: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(day.hourTicks.enumerated()), id: \.offset) { _, tick in
                if let label = tick.label {
                    TimelineHourMark(text: label)
                        .offset(x: TimelineGutter.edgeInset, y: tick.y - TimelineGutterMarkMetrics.singleLineHeight / 2)
                }
            }
            ForEach(day.cardGroups.filter(\.showsTimeLabel)) { group in
                TimelineTimeCapsule(date: group.representativeTime)
                    .offset(x: TimelineGutter.edgeInset, y: group.centerY - TimelineGutterMarkMetrics.singleLineHeight / 2)
            }
            if let y = day.nowY {
                TimelineNowMark()
                    .offset(x: TimelineGutter.edgeInset, y: y - TimelineGutterMarkMetrics.singleLineHeight / 2)
            }
        }
    }

    /// Dose dots on the axis — the primary "something was taken here" mark,
    /// drawn above the capsules so a capsule hanging across the axis is
    /// pinned by its dot.
    private var doseDots: some View {
        ForEach(Array(day.doseDots.enumerated()), id: \.offset) { _, dot in
            Circle()
                .fill(dot.color)
                .frame(width: 8, height: 8)
                .padding(1.5)
                .background(Theme.background, in: Circle())
                .position(x: TimelineGutter.axisX, y: dot.y)
                .accessibilityHidden(true)
        }
    }

    // MARK: Bubble column

    private func bubbleColumn(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(day.envelopes) { envelope in
                SessionEnvelopeButton { onSessionTap(envelope.id) }
                    .frame(width: width, height: envelope.yEnd - envelope.yStart)
                    .offset(y: envelope.yStart)
            }

            GlassEffectContainer {
                ZStack(alignment: .topLeading) {
                    ForEach(day.cardGroups) { group in
                        VStack(spacing: TimelineDayLayout.cardSpacing) {
                            ForEach(group.items) { item in
                                TimelineDoseBubble(
                                    item: item,
                                    style: day.style.bubbleStyle,
                                    pkMode: day.style.pkMode,
                                ) { onEntryTap(item.entry) }
                            }
                        }
                        .padding(.horizontal, Self.bubbleInset)
                        .offset(y: group.topY)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: The strip canvas

    /// Height of one canvas tile. A slice at high zoom with compression off
    /// runs many thousands of points tall, and one full-width canvas that
    /// tall exceeds what Core Animation rasterizes — it silently draws
    /// nothing. Each tile draws the whole slice translated to its origin, so
    /// the tiles join seamlessly.
    private static let tileHeight: CGFloat = 1024

    private func strip(bubbleLeft: CGFloat) -> some View {
        let tileYs = Array(stride(from: CGFloat(0), to: max(day.totalHeight, 1), by: Self.tileHeight))
        return ForEach(tileYs, id: \.self) { tileY in
            Canvas { context, size in
                context.translateBy(x: 0, y: -tileY)
                drawStrip(
                    in: &context,
                    size: CGSize(width: size.width, height: day.totalHeight),
                    bubbleLeft: bubbleLeft,
                )
            }
            .frame(height: min(Self.tileHeight, day.totalHeight - tileY))
            .offset(y: tileY)
        }
    }

    private func drawStrip(in context: inout GraphicsContext, size: CGSize, bubbleLeft: CGFloat) {
        let mapHeight = day.mapHeight
        guard mapHeight > 0 else { return }

        let axisX = TimelineGutter.axisX
        var curveWidth = Self.maxAmplitudeFraction * (size.width - axisX)
        if !day.style.strengthScaling {
            curveWidth = min(curveWidth, bubbleLeft - Self.peakClearance - axisX)
        }
        curveWidth = max(0, curveWidth)

        // Hour gridlines across the lane; in a compressed gap they bunch
        // together, which is what says "time is squeezed here".
        for tick in day.hourTicks {
            var line = Path()
            line.move(to: CGPoint(x: axisX, y: tick.y))
            line.addLine(to: CGPoint(x: size.width, y: tick.y))
            context.stroke(line, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.5)
        }

        drawAxis(in: &context, size: size, axisX: axisX)

        // Per-substance curves — normalized to the substance's own
        // all-time peak so widths mean the same thing on every day and a
        // curve crosses day boundaries without a jump.
        for series in day.series {
            guard series.points.count > 1 else { continue }

            var fill = Path()
            fill.move(to: CGPoint(x: axisX, y: series.points[0].y))
            for p in series.points {
                fill.addLine(to: CGPoint(x: axisX + curveWidth * CGFloat(p.v), y: p.y))
            }
            fill.addLine(to: CGPoint(x: axisX, y: series.points[series.points.count - 1].y))
            fill.closeSubpath()
            context.fill(fill, with: .color(series.color.opacity(0.12)))

            var stroke = Path()
            for (i, p) in series.points.enumerated() {
                let pt = CGPoint(x: axisX + curveWidth * CGFloat(p.v), y: p.y)
                if i == 0 { stroke.move(to: pt) } else { stroke.addLine(to: pt) }
            }
            context.stroke(stroke, with: .color(series.color.opacity(0.75)), lineWidth: 1.5)
        }

        // Connectors from each dose's position on the axis to its bubble.
        for connector in day.connectors {
            var path = Path()
            path.move(to: CGPoint(x: axisX, y: connector.fromY))
            path.addLine(to: CGPoint(x: bubbleLeft, y: connector.toY))
            context.stroke(path, with: .color(connector.color.opacity(0.35)), lineWidth: 1)
        }

        if let y = day.nowY {
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: axisX, y: y))
            nowLine.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(nowLine, with: .color(Theme.accent.opacity(0.65)), lineWidth: 2.5)
        }

        // Only the strip's very top edge cuts curves mid-flight — fade
        // them into the background there. Day boundaries fade nothing;
        // the strip continues.
        if day.showsLiveEdge {
            let fadeHeight: CGFloat = 28
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: fadeHeight)),
                with: .linearGradient(
                    Gradient(colors: [Theme.background, Theme.background.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: fadeHeight),
                ),
            )
        }
    }

    /// Length of the axis fade into a break below the slice.
    private static let axisFadeLength: CGFloat = 40

    /// The time axis, running the slice below any break at its top (bubbles
    /// can spill past the mapped span; the axis keeps going so the strip
    /// reads as unbroken). The newest slice carries an arrowhead at the top —
    /// the axis runs past "now" to where the active doses wind down, and the
    /// arrow says it keeps going up from there. Above a break the axis fades
    /// to transparent, so skipped days read as a gap rather than a line.
    /// Faint up-chevrons along it are the ambient reminder that time on this
    /// strip flows upward.
    private func drawAxis(in context: inout GraphicsContext, size: CGSize, axisX: CGFloat) {
        let axisTop: CGFloat = day.breakAbove + (day.showsLiveEdge ? 16 : 0)
        let axisColor = Color.primary.opacity(day.showsLiveEdge ? 0.22 : 0.12)
        var axisLine = Path()
        axisLine.move(to: CGPoint(x: axisX, y: axisTop))
        axisLine.addLine(to: CGPoint(x: axisX, y: size.height))
        let shading: GraphicsContext.Shading = if day.fadesAxisBelow, size.height > axisTop + Self.axisFadeLength {
            .linearGradient(
                Gradient(stops: [
                    .init(color: axisColor, location: 0),
                    .init(color: axisColor, location: 1 - Self.axisFadeLength / (size.height - axisTop)),
                    .init(color: axisColor.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: axisX, y: axisTop),
                endPoint: CGPoint(x: axisX, y: size.height),
            )
        } else {
            .color(axisColor)
        }
        context.stroke(axisLine, with: shading, lineWidth: day.showsLiveEdge ? 1 : 0.7)
        if day.showsLiveEdge {
            var arrow = Path()
            arrow.move(to: CGPoint(x: axisX - 4.5, y: axisTop + 6))
            arrow.addLine(to: CGPoint(x: axisX, y: axisTop - 2))
            arrow.addLine(to: CGPoint(x: axisX + 4.5, y: axisTop + 6))
            context.stroke(arrow, with: .color(Color.primary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        var chevronY = size.height - 60
        while chevronY > axisTop + 40 {
            let clearOfDots = day.doseDots.allSatisfy { abs($0.y - chevronY) > 14 }
            let clearOfNow = day.nowY.map { abs($0 - chevronY) > 14 } ?? true
            if clearOfDots, clearOfNow {
                var chevron = Path()
                chevron.move(to: CGPoint(x: axisX - 3.5, y: chevronY + 3))
                chevron.addLine(to: CGPoint(x: axisX, y: chevronY - 2.5))
                chevron.addLine(to: CGPoint(x: axisX + 3.5, y: chevronY + 3))
                context.stroke(chevron, with: .color(Color.primary.opacity(0.16)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            chevronY -= 130
        }
    }
}

// MARK: - Session envelope

/// The tappable frame around a session's bubbles — an outline (the bubbles
/// carry their own glass) with a "Session ›" footer that opens the session.
struct SessionEnvelopeButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    // Chevron styled and inset identically to the bubbles'
                    // (bubble inset 8 + bubble padding 10), so the two columns
                    // of chevrons align.
                    HStack(spacing: 8) {
                        Text("Session")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 6)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
