import SwiftUI

/// One 6 h slot of the continuous ribbon: a `Canvas` drawing the window's
/// evaluated curves plus its leading boundary line and axis label (the date at
/// midnight, the hour otherwise).
///
/// Samples come from ``TimelineRibbonModel``'s content-addressed memo — the
/// `.task` requests the window's evaluation off-main; until it lands the tile
/// draws just its axis chrome and the curves pop in (the same discipline as
/// ``TimelineGraphView``'s cache-or-compute path). Values at a tile's edges are
/// evaluated at the exact shared boundary instant, so adjacent tiles' strokes
/// and fills meet seamlessly.
struct TimelineRibbonTile: View {
    let model: TimelineRibbonModel
    let start: Date
    let end: Date
    let width: CGFloat
    let height: CGFloat
    let compact: Bool

    /// Re-request identity: the window plus the model's snapshot revision, so a
    /// newly logged dose re-fires the task (which then no-ops on a cache hit).
    private struct TaskID: Hashable {
        let start: Date
        let end: Date
        let revision: Int
    }

    private var isDayStart: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: start)
        return components.hour == 0 && components.minute == 0
    }

    var body: some View {
        let plot = model.plot(for: model.key(start: start, end: end))
        Canvas { context, size in
            drawChrome(context: context, size: size)
            if let plot {
                drawCurves(plot: plot, context: context, size: size)
            }
        }
        .frame(width: width, height: height)
        .task(id: TaskID(start: start, end: end, revision: model.revision)) {
            await model.requestPlot(start: start, end: end)
        }
        // The ribbon is summarized by its host (card button / screen); per-tile
        // canvases would only read as noise.
        .accessibilityHidden(true)
    }

    // MARK: - Axis chrome

    private func drawChrome(context: GraphicsContext, size: CGSize) {
        let labelBand = RibbonMetrics.labelBand(compact: compact)
        let baselineY = size.height - labelBand

        // Leading boundary — heavier at midnight so days read at a glance.
        var boundary = Path()
        boundary.move(to: CGPoint(x: 0.5, y: 2))
        boundary.addLine(to: CGPoint(x: 0.5, y: baselineY))
        context.stroke(
            boundary,
            with: .color(Theme.secondaryLabel.opacity(isDayStart ? 0.45 : 0.16)),
            lineWidth: 1,
        )

        // Baseline the curves rest on.
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: baselineY))
        baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
        context.stroke(baseline, with: .color(Theme.secondaryLabel.opacity(0.12)), lineWidth: 1)

        // Boundary label: the date at a day boundary, the hour otherwise.
        let label: Text = if isDayStart {
            Text(start, format: .dateTime.day().month(.abbreviated))
                .font(compact ? .system(size: 9, weight: .semibold) : .caption2.weight(.semibold))
        } else {
            Text(start, format: .dateTime.hour())
                .font(compact ? .system(size: 9) : .caption2)
        }
        context.draw(
            context.resolve(label.foregroundStyle(Theme.secondaryLabel)),
            at: CGPoint(x: 4, y: baselineY + labelBand / 2),
            anchor: .leading,
        )
    }

    // MARK: - Curves

    private func drawCurves(plot: TimelineWindowEvaluator.WindowPlot, context: GraphicsContext, size: CGSize) {
        let labelBand = RibbonMetrics.labelBand(compact: compact)
        let baselineY = size.height - labelBand
        let graphHeight = (baselineY - 3) * 0.93
        let yNorm = model.yNormalization
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

            // Fill down to the baseline; adjacent tiles continue the same fill
            // across their shared edge, so the vertical cut is invisible.
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
            context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: compact ? 1.5 : 2)

            // Baseline ticks at each dose time — where the curve was fed.
            for doseTime in series.doseTimes {
                let fraction = doseTime.timeIntervalSince(plot.start) / plot.end.timeIntervalSince(plot.start)
                let x = size.width * CGFloat(fraction)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: baselineY))
                tick.addLine(to: CGPoint(x: x, y: baselineY - (compact ? 4 : 5)))
                context.stroke(tick, with: .color(color.opacity(0.75)), lineWidth: 1.5)
            }
        }
    }
}
