import Charts
import SwiftData
import SwiftUI

// The "in your body over time" chart and its scrub readout: one line per
// substance tracing its estimated in-body amount across a range, each
// normalized to its own peak, with the readout restoring the real amount in the
// substance's own unit. Rendered by ``InYourBodyView``'s chart section.

// MARK: - Chart

struct BodyLoadChart: View {
    let series: [BodyLoadTrail.Series]
    let dates: [Date]
    @Binding var selectedDate: Date?

    private var span: (length: Double, windowStart: Date?) {
        guard let first = dates.first, let last = dates.last, last > first else { return (1, nil) }
        return (last.timeIntervalSince(first), last.addingTimeInterval(-usageChartWindowSeconds))
    }

    var body: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Body load", point.fraction),
                        series: .value("Substance", item.id),
                    )
                    .foregroundStyle(item.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
            }
            RuleMark(x: .value("Now", Date.now))
                .foregroundStyle(Theme.accent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: 200)
        .chartXSelection(value: $selectedDate)
        .chartXScrollWindow(fullLength: span.length, window: usageChartWindowSeconds, initialX: span.windowStart)
        .chartYScale(domain: 0 ... 1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
        }
        .chartSummaryAccessibility(label: Text("In your body over time"), value: Text(summary))
    }

    private var summary: String {
        guard !series.isEmpty else { return String(localized: "No data") }
        let parts = series.prefix(4).map { item -> String in
            let current = item.points.last?.amount ?? 0
            return String(localized: "\(item.displayName) now at \(current.doseFormatted) \(item.unit)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scrub readout

/// The tooltip for `chartXSelection`: the estimated real amount of each substance
/// in the body at the scrubbed instant — restoring the magnitude the normalized
/// lines drop.
struct BodyLoadReadout: View {
    let series: [BodyLoadTrail.Series]
    let date: Date

    var body: some View {
        let rows = series.compactMap { item -> (series: BodyLoadTrail.Series, amount: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item, point.amount)
        }
        .filter { $0.amount > 0 }
        .sorted { $0.amount > $1.amount }

        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour()))
                .font(.caption.weight(.semibold))
            ForEach(rows, id: \.series.id) { row in
                HStack(spacing: 5) {
                    Circle()
                        .fill(row.series.color)
                        .frame(width: 6, height: 6)
                    Text(row.series.displayName)
                        .font(.caption2)
                    Spacer(minLength: 8)
                    Text("\(row.amount.doseFormatted) \(row.series.unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            if rows.isEmpty {
                Text("Nothing in your body at this time")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.CornerRadius.inner)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func nearestPoint(in item: BodyLoadTrail.Series) -> BodyLoadTrail.Point? {
        item.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
