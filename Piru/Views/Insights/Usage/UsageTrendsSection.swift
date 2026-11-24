import Charts
import SwiftUI

/// §3 — "how has my use of each substance changed?" One line per substance,
/// showing rolling frequency in entries per week.
///
/// The rolling window is 7 days on 7D/30D and 4 weeks on the longer ranges, but
/// the value is always normalized to *per week*, so the y-axis reads the same
/// whichever range is selected.
struct UsageTrendsSection: View {
    let trends: [UsageTrendSeries]
    let style: UsageSubstanceStyle
    let range: UsageTimeRange
    /// The Entries/Common-doses lens, owned globally by the Usage toolbar filter.
    /// Common doses weighs each dose by its typical size — the more representative
    /// view of use over time than how often it was logged — which is why the
    /// filter defaults to it.
    let metric: UsageRankMetric
    /// The selected range's span, which the x axis draws in full.
    let timeAxis: ClosedRange<Date>
    let coverage: UsageCommonDoseCoverage

    /// Substance indices the user has hidden by tapping the legend.
    @State private var hidden: Set<Int> = []
    @State private var showsAll = false
    @State private var selectedDate: Date?

    /// The lines with enough points to be a line. A journal younger than the
    /// rolling window has none: every average would lean on days before the
    /// journal began.
    private var drawableTrends: [UsageTrendSeries] {
        trends.filter { $0.points.count >= 2 }
    }

    /// The lines eligible in the active metric. In common-dose mode a substance
    /// with no common-dose data would draw flat on zero and read as "unused", so
    /// it drops out of both the chart and the legend rather than lying.
    private var metricTrends: [UsageTrendSeries] {
        metric == .commonDoses ? drawableTrends.filter(\.hasCommonDoses) : drawableTrends
    }

    /// Each line's dash and symbol by its rank among the eligible lines, so it
    /// keeps them while others are hidden.
    private var markers: [Int: ChartSeriesMarker] {
        Dictionary(
            metricTrends.enumerated().map { ($1.substanceIndex, ChartSeriesMarker(index: $0)) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    private var legendTrends: [UsageTrendSeries] {
        showsAll ? metricTrends : Array(metricTrends.prefix(UsageAnalytics.defaultTrendSubstances))
    }

    private var visibleSeries: [UsageTrendSeries] {
        let filtered = legendTrends.filter { !hidden.contains($0.substanceIndex) }
        // Hiding every line would leave an empty plot with no way back, so the
        // legend can never zero the chart out.
        return filtered.isEmpty ? legendTrends : filtered
    }

    var body: some View {
        UsageSectionCard(title: "Substance trends", subtitle: subtitle) {
            if drawableTrends.isEmpty {
                Text("Not enough history yet")
                    .captionSecondary()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xxl)
            } else {
                if metricTrends.isEmpty {
                    Text("No common dose defined for these substances")
                        .captionSecondary()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.xxl)
                } else {
                    UsageTrendsChart(
                        series: visibleSeries,
                        style: style,
                        markers: markers,
                        axis: UsageTimeAxis(domain: timeAxis),
                        metric: metric,
                        perWeek: range.trendPerWeek,
                        selectedDate: $selectedDate,
                    )
                    if let selectedDate {
                        UsageTrendsReadout(series: visibleSeries, style: style, markers: markers, metric: metric, perWeek: range.trendPerWeek, date: selectedDate)
                    }
                    legend
                    UsageCommonDoseCoverageNote(coverage: coverage)
                }
            }
        }
        .onChange(of: range) {
            selectedDate = nil
            hidden = []
        }
        #if DEBUG
        .task { selectedDate = ScreenshotTour.takeStagedSelection(.usageTrends) ?? selectedDate }
        #endif
    }

    private var subtitle: LocalizedStringKey {
        switch (metric, range) {
        case (.entries, .sevenDays): "Entries per day"
        case (.commonDoses, .sevenDays): "Common doses per day"
        case (.entries, .thirtyDays): "Entries per week, 7-day rolling average"
        case (.commonDoses, .thirtyDays): "Common doses per week, 7-day rolling average"
        case (.entries, _): "Entries per week, 4-week rolling average"
        case (.commonDoses, _): "Common doses per week, 4-week rolling average"
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            FlowLayout(spacing: Spacing.md) {
                ForEach(legendTrends) { item in
                    legendChip(item)
                }
            }
            if metricTrends.count > UsageAnalytics.defaultTrendSubstances {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsAll.toggle() }
                } label: {
                    Text(showsAll ? "Show fewer" : "Show all \(metricTrends.count)")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func legendChip(_ item: UsageTrendSeries) -> some View {
        let isHidden = hidden.contains(item.substanceIndex)
        let name = style.name(item.substanceIndex)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isHidden {
                    hidden.remove(item.substanceIndex)
                } else {
                    hidden.insert(item.substanceIndex)
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                ChartSeriesKey(
                    color: style.color(item.substanceIndex),
                    marker: markers[item.substanceIndex] ?? ChartSeriesMarker(index: 0),
                )
                .opacity(isHidden ? 0.3 : 1)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
                    .strikethrough(isHidden)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityValue(isHidden ? Text("Hidden") : Text("Shown"))
        .accessibilityHint(Text("Toggles this substance's line"))
        .accessibilityAddTraits(isHidden ? [] : [.isSelected])
    }
}

// MARK: - Chart

private struct UsageTrendsChart: View {
    let series: [UsageTrendSeries]
    let style: UsageSubstanceStyle
    let markers: [Int: ChartSeriesMarker]
    let axis: UsageTimeAxis
    let metric: UsageRankMetric
    /// Whether values read as a per-week rate (else per-day buckets on 7D).
    let perWeek: Bool
    @Binding var selectedDate: Date?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private func value(_ point: UsageTrendPoint) -> Double {
        metric == .commonDoses ? point.commonValue : point.value
    }

    private func marker(_ item: UsageTrendSeries) -> ChartSeriesMarker {
        markers[item.substanceIndex] ?? ChartSeriesMarker(index: 0)
    }

    private func symbolPoints(_ item: UsageTrendSeries) -> [UsageTrendPoint] {
        guard differentiate else { return [] }
        let indices = ChartSeriesMarker.symbolIndices(
            dates: item.points.map(\.date),
            values: item.points.map(value),
            window: min(usageChartWindowSeconds, axis.length),
        )
        return indices.map { item.points[$0] }
    }

    var body: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Per week", value(point)),
                        series: .value("Substance", item.substanceIndex),
                    )
                    .foregroundStyle(style.color(item.substanceIndex))
                    .lineStyle(marker(item).stroke(lineWidth: 2, differentiate: differentiate))
                    // Monotone: the curve stays between the values it joins. A
                    // looser spline swings past them and draws peaks and dips
                    // that no bucket holds.
                    .interpolationMethod(.monotone)
                }
                ForEach(symbolPoints(item)) { point in
                    PointMark(x: .value("Date", point.date), y: .value("Per week", value(point)))
                        .foregroundStyle(style.color(item.substanceIndex))
                        .symbol(marker(item).chartSymbol)
                        .symbolSize(40)
                }
            }
            if let selectedDate {
                // Solid, in the text color: the dashed gray of the gridlines
                // would hide which date the readout describes.
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .frame(height: 190)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: axis.domain)
        .chartXScrollWindow(fullLength: axis.length, window: usageChartWindowSeconds, initialX: axis.windowStart)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel(format: axis.tickFormat)
                    .font(.caption2)
            }
        }
        .chartSummaryAccessibility(label: Text("Substance trends"), value: Text(summary))
    }

    /// Spoken as "who is rising and who is falling", which is the question the
    /// chart exists to answer — a VoiceOver user gets the shape, not just a
    /// count of lines.
    private var summary: String {
        guard !series.isEmpty else { return String(localized: "No data") }
        let parts = series.prefix(4).map { item -> String in
            let name = style.name(item.substanceIndex)
            let last = item.points.last.map(value) ?? 0
            let first = item.points.first.map(value) ?? 0
            let rate = last.formatted(.number.precision(.fractionLength(0 ... 1)))
            if perWeek {
                if last > first + 0.01 {
                    return String(localized: "\(name) rising to \(rate) per week")
                } else if last < first - 0.01 {
                    return String(localized: "\(name) falling to \(rate) per week")
                }
                return String(localized: "\(name) steady at \(rate) per week")
            }
            if last > first + 0.01 {
                return String(localized: "\(name) rising to \(rate) per day")
            } else if last < first - 0.01 {
                return String(localized: "\(name) falling to \(rate) per day")
            }
            return String(localized: "\(name) steady at \(rate) per day")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Selection readout

/// The tooltip for `chartXSelection`: exact per-substance rates at the scrubbed
/// date.
private struct UsageTrendsReadout: View {
    let series: [UsageTrendSeries]
    let style: UsageSubstanceStyle
    let markers: [Int: ChartSeriesMarker]
    let metric: UsageRankMetric
    let perWeek: Bool
    let date: Date

    var body: some View {
        // Every line on the chart, zeros included, so a substance at nothing
        // that day still reads as tracked.
        let rows = series.compactMap { item -> (index: Int, value: Double)? in
            guard let point = item.point(nearest: date) else { return nil }
            return (item.substanceIndex, metric == .commonDoses ? point.commonValue : point.value)
        }
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.index < $1.index }
        let anyLogged = rows.contains { $0.value > 0 }

        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.caption.weight(.semibold))
            ForEach(anyLogged ? rows : [], id: \.index) { row in
                HStack(spacing: 5) {
                    ChartSeriesKey(
                        color: style.color(row.index),
                        marker: markers[row.index] ?? ChartSeriesMarker(index: 0),
                        size: .compact,
                    )
                    Text(style.name(row.index))
                        .font(.caption2)
                    Spacer(minLength: 8)
                    Text(perWeek
                        ? "\(row.value.formatted(.number.precision(.fractionLength(0 ... 1))))/wk"
                        : "\(row.value.formatted(.number.precision(.fractionLength(0 ... 1))))/day")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            if rows.isEmpty {
                // Before the lines begin: too little journal behind this date for an average.
                Text("Not enough history yet")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            } else if !anyLogged {
                Text("Nothing logged in this window")
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
}
