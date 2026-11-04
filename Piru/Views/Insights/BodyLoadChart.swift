import Charts
import SwiftData
import SwiftUI

// The "in your body over time" chart and its scrub readout: one lane per
// substance tracing its estimated in-body amount across a range, each
// normalized to its own peak, with the readout restoring the real amount in the
// substance's own unit. Rendered by ``InYourBodyView``'s chart section.

// MARK: - Chart

struct BodyLoadChart: View {
    let series: [BodyLoadTrail.Series]
    /// Each substance's dash and symbol, by display name; drawn only under
    /// Differentiate Without Color.
    let markers: [String: ChartSeriesMarker]
    let dates: [Date]
    @Binding var selectedDate: Date?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    /// Below this share of its peak a curve runs along its lane's floor, so no
    /// symbol goes there.
    private static let symbolFloor = 0.15
    /// How much of its lane a curve at its own peak fills; the rest is the gap
    /// above it, so neighboring peaks never touch.
    private static let laneFill = 0.8
    private static let laneHeight: CGFloat = 34
    private static let axisHeight: CGFloat = 24

    private func marker(_ item: BodyLoadTrail.Series) -> ChartSeriesMarker {
        markers[item.displayName] ?? ChartSeriesMarker(index: 0)
    }

    /// One lane per substance, in trail order (most logged first, at the top).
    /// A substance drawn in two unit families shares its lane.
    private var laneNames: [String] {
        var seen: Set<String> = []
        return series.map(\.displayName).filter { seen.insert($0).inserted }
    }

    /// Each lane's floor on the y scale, the top lane highest.
    private var laneFloors: [String: Double] {
        let names = laneNames
        return Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, Double(names.count - 1 - $0)) })
    }

    private func symbolPoints(_ item: BodyLoadTrail.Series) -> [BodyLoadTrail.Point] {
        guard differentiate else { return [] }
        let indices = ChartSeriesMarker.symbolIndices(
            dates: item.points.map(\.date),
            values: item.points.map(\.fraction),
            window: min(usageChartWindowSeconds, span.length),
            floor: Self.symbolFloor,
        )
        return indices.map { item.points[$0] }
    }

    private var span: (length: Double, windowStart: Date?) {
        guard let first = dates.first, let last = dates.last, last > first else { return (1, nil) }
        return (last.timeIntervalSince(first), last.addingTimeInterval(-usageChartWindowSeconds))
    }

    var body: some View {
        let floors = laneFloors
        let names = laneNames
        Chart {
            ForEach(series) { item in
                let floor = floors[item.displayName] ?? 0
                ForEach(item.points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Lane", floor),
                        yEnd: .value("Body load", floor + point.fraction * Self.laneFill),
                        series: .value("Substance", item.id),
                    )
                    .foregroundStyle(item.color.opacity(0.3))
                    .interpolationMethod(.linear)
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Body load", floor + point.fraction * Self.laneFill),
                        series: .value("Substance", item.id),
                    )
                    .foregroundStyle(item.color)
                    .lineStyle(marker(item).stroke(lineWidth: 1.5, differentiate: differentiate))
                    .interpolationMethod(.linear)
                }
                ForEach(symbolPoints(item)) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Body load", floor + point.fraction * Self.laneFill),
                    )
                    .foregroundStyle(item.color)
                    .symbol(marker(item).chartSymbol)
                    .symbolSize(40)
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
        .frame(height: CGFloat(names.count) * Self.laneHeight + Self.axisHeight)
        .chartXSelection(value: $selectedDate)
        .chartXScrollWindow(fullLength: span.length, window: usageChartWindowSeconds, initialX: span.windowStart)
        .chartYScale(domain: 0 ... Double(max(names.count, 1)))
        .chartYAxis {
            // A floor line under each lane, and the lane's name at its middle. The
            // names sit on the axis, which stays put while the range scrolls.
            AxisMarks(values: Array(floors.values)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
            }
            AxisMarks(position: .leading, values: names.compactMap { floors[$0].map { $0 + 0.5 } }) { value in
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let name = names.first(where: { floors[$0].map { $0 + 0.5 } == position }) {
                        Text(name)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: 88, alignment: .leading)
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
        .chartSummaryAccessibility(label: Text("Modeled levels over time"), value: Text(summary))
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
/// lanes drop.
struct BodyLoadReadout: View {
    let series: [BodyLoadTrail.Series]
    let markers: [String: ChartSeriesMarker]
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
                    ChartSeriesKey(
                        color: row.series.color,
                        marker: markers[row.series.displayName] ?? ChartSeriesMarker(index: 0),
                        size: .compact,
                    )
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
