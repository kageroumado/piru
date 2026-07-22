import SwiftData
import SwiftUI

/// The Active Now card's graph: one window of the **continuous timeline**,
/// spanning every currently-active dose — from shortly before the earliest one
/// to the end of the last curve. Time is continuous here: curves from earlier
/// sessions flow into the window instead of being cut at a session seam.
///
/// Rendered as a single evaluated ``TimelineWindowEvaluator/WindowPlot`` in one
/// `Canvas`, with wall-clock hour gridlines, a heavier midnight boundary,
/// baseline dose ticks, and the accent now-marker. Evaluation and memoization
/// ride ``TimelineWindowModel`` — the same curve math as the session graphs
/// (``TimelineCurveModel``), so the two can never disagree.
struct ActiveNowWindowGraph: View {
    let entries: [DoseEntry]
    let colors: [SubstanceColor]
    /// The live states (from ``ActiveSessionManager``) — they bound the window.
    let states: [ActiveSubstanceState]
    /// The minute tick from the host's `TimelineView` — drives the now-marker
    /// and (via hour rounding) the window's slow forward growth.
    let now: Date
    var height: CGFloat = 150

    @State private var model = TimelineWindowModel()

    /// Snapshot input window: no curve outlives 48 h,
    /// so 72 h of doses provably covers everything that can reach the window.
    private static let inputWindow: TimeInterval = 72 * 3_600
    private static let labelBand: CGFloat = 16

    /// Re-request identity for the window's evaluation: the window
    /// plus the model's snapshot revision, so a newly logged dose re-fires the
    /// request (which then no-ops on a memo hit).
    private struct PlotID: Hashable {
        let start: Date
        let end: Date
        let revision: Int
    }

    /// Content fingerprint of the snapshot inputs — drives the rebuild task on
    /// edits, not just adds/removes (mirrors the Journal's signatures).
    private var signature: Int {
        var hasher = Hasher()
        let cutoff = Date.now.addingTimeInterval(-Self.inputWindow)
        for entry in entries {
            guard entry.timestamp >= cutoff else { break }
            hasher.combine(entry.timestamp)
            hasher.combine(entry.substance)
            hasher.combine(entry.amount)
            hasher.combine(entry.unit)
            hasher.combine(entry.route)
            hasher.combine(entry.isBackgroundMed)
        }
        for color in colors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    var body: some View {
        let (start, end) = window
        let plot = model.plot(for: model.key(start: start, end: end))
        Canvas { context, size in
            drawChrome(context: context, size: size, start: start, end: end)
            if let plot {
                drawCurves(plot: plot, context: context, size: size)
            }
            drawNowMarker(context: context, size: size, start: start, end: end)
        }
        .frame(height: height)
        .task(id: signature) {
            let cutoff = Date.now.addingTimeInterval(-Self.inputWindow)
            let recent = Array(entries.prefix { $0.timestamp >= cutoff })
            await model.rebuild(entries: recent, colors: colors)
        }
        .task(id: PlotID(start: start, end: end, revision: model.revision)) {
            await model.requestPlot(start: start, end: end, sampleCount: sampleCount(start: start, end: end))
        }
        // The hosting card's phase bar / header speak the graph's story; inside
        // the card button the canvas would only double-read.
        .accessibilityHidden(true)
    }

    // MARK: - Window

    /// The drawn window: the earliest active dose (with a little lead-in)
    /// through the end of the last active curve, always covering at least an
    /// hour each side of now. Bounds are **hour-aligned** so the window — and
    /// with it the plot's memo key — is stable across the minute ticks, moving
    /// only when the clock crosses an hour or the dose set changes.
    private var window: (start: Date, end: Date) {
        let earliest = states.map(\.doseTimestamp).min() ?? now
        let latestEnd = states.map { TimelineWindowEvaluator.activityInterval(of: $0).end }.max() ?? now
        let rawStart = min(earliest.addingTimeInterval(-30 * 60), now.addingTimeInterval(-3_600))
        let rawEnd = max(latestEnd, now.addingTimeInterval(3_600))
        return (hourFloor(rawStart), hourCeil(rawEnd))
    }

    /// One sample per ~3 minutes, bounded
    /// so a multi-day window can't balloon the evaluation.
    private func sampleCount(start: Date, end: Date) -> Int {
        let minutes = end.timeIntervalSince(start) / 60
        return min(361, max(121, Int(minutes / 3) + 1))
    }

    private func hourFloor(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    private func hourCeil(_ date: Date) -> Date {
        let floor = hourFloor(date)
        return floor == date ? date : floor.addingTimeInterval(3_600)
    }

    /// Wall-clock hours between axis labels, chosen so the band holds ~5–8
    /// labels at card width regardless of the window's span.
    private func labelStepHours(spanHours: Double) -> Int {
        switch spanHours {
        case ..<9: 1
        case ..<17: 2
        case ..<27: 3
        default: 6
        }
    }

    // MARK: - Axis chrome

    private func drawChrome(context: GraphicsContext, size: CGSize, start: Date, end: Date) {
        let baselineY = size.height - Self.labelBand
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: baselineY))
        baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
        context.stroke(baseline, with: .color(Theme.secondaryLabel.opacity(0.12)), lineWidth: 1)

        let calendar = Calendar.current
        let step = labelStepHours(spanHours: span / 3_600)
        var mark = hourCeil(start)
        while mark <= end {
            defer { mark = mark.addingTimeInterval(3_600) }
            let hour = calendar.component(.hour, from: mark)
            guard hour % step == 0 else { continue }
            let x = size.width * CGFloat(mark.timeIntervalSince(start) / span)
            let isMidnight = hour == 0

            var line = Path()
            line.move(to: CGPoint(x: x, y: 2))
            line.addLine(to: CGPoint(x: x, y: baselineY))
            context.stroke(
                line,
                with: .color(Theme.secondaryLabel.opacity(isMidnight ? 0.4 : 0.14)),
                lineWidth: 1,
            )

            // The date at midnight (day boundary), the hour otherwise.
            let label = if isMidnight {
                Text(mark, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2.weight(.semibold))
            } else {
                Text(mark, format: .dateTime.hour())
                    .font(.caption2)
            }
            let resolved = context.resolve(label.foregroundStyle(Theme.secondaryLabel))
            let textSize = resolved.measure(in: CGSize(width: 100, height: Self.labelBand))
            // Clamp edge labels inside the canvas instead of slicing them.
            let clampedX = min(max(x, textSize.width / 2), size.width - textSize.width / 2)
            context.draw(
                resolved,
                at: CGPoint(x: clampedX, y: baselineY + Self.labelBand / 2 + 1),
                anchor: .center,
            )
        }
    }

    // MARK: - Curves

    private func drawCurves(plot: TimelineWindowEvaluator.WindowPlot, context: GraphicsContext, size: CGSize) {
        let baselineY = size.height - Self.labelBand
        let graphHeight = (baselineY - 4) * 0.92
        // Self-normalized: fill the height with the window's own tallest curve
        // (the session graphs' policy), never amplifying silence more than 20×.
        let yNorm = plot.peakValue > 0 ? min(1 / plot.peakValue, 20) : 1
        let sampleCount = plot.sampleCount
        guard sampleCount > 1, graphHeight > 0 else { return }

        for series in plot.series {
            let color = Color(hex: series.colorHex)

            var points: [CGPoint] = []
            points.reserveCapacity(sampleCount)
            for (index, value) in series.values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(sampleCount - 1)
                let y = baselineY - CGFloat(min(1, max(0, value * yNorm))) * graphHeight
                points.append(CGPoint(x: x, y: y))
            }

            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: baselineY))
            for point in points {
                fill.addLine(to: point)
            }
            fill.addLine(to: CGPoint(x: size.width, y: baselineY))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.16)))

            var stroke = Path()
            stroke.move(to: points[0])
            for point in points.dropFirst() {
                stroke.addLine(to: point)
            }
            context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: 2)

            // Baseline ticks at each dose time — where the curve was fed.
            for doseTime in series.doseTimes {
                let fraction = doseTime.timeIntervalSince(plot.start) / plot.end.timeIntervalSince(plot.start)
                let x = size.width * CGFloat(fraction)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: baselineY))
                tick.addLine(to: CGPoint(x: x, y: baselineY - 5))
                context.stroke(tick, with: .color(color.opacity(0.75)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Now marker

    private func drawNowMarker(context: GraphicsContext, size: CGSize, start: Date, end: Date) {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return }
        let x = size.width * CGFloat(min(max(now.timeIntervalSince(start) / span, 0), 1))
        let baselineY = size.height - Self.labelBand

        var line = Path()
        line.move(to: CGPoint(x: x, y: 7))
        line.addLine(to: CGPoint(x: x, y: baselineY))
        context.stroke(line, with: .color(Theme.accent.opacity(0.85)), lineWidth: 2)
        context.fill(
            Path(ellipseIn: CGRect(x: x - 2.5, y: 2, width: 5, height: 5)),
            with: .color(Theme.accent),
        )
    }
}
