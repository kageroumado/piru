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

    /// Substance indices the user has hidden by tapping the legend.
    @State private var hidden: Set<Int> = []
    @State private var showsAll = false
    @State private var selectedDate: Date?

    /// The lines eligible in the active metric. In common-dose mode a substance
    /// with no common-dose data would draw flat on zero and read as "unused", so
    /// it drops out of both the chart and the legend rather than lying.
    private var metricTrends: [UsageTrendSeries] {
        metric == .commonDoses ? trends.filter(\.hasCommonDoses) : trends
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
            if trends.isEmpty {
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
                        weekly: range.usesWeeklyBuckets,
                        metric: metric,
                        perWeek: range.trendPerWeek,
                        selectedDate: $selectedDate,
                    )
                    if let selectedDate {
                        UsageTrendsReadout(series: visibleSeries, style: style, metric: metric, perWeek: range.trendPerWeek, date: selectedDate)
                    }
                    legend
                }
            }
        }
        .onChange(of: range) {
            selectedDate = nil
            hidden = []
        }
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
                LegendDot(color: style.color(item.substanceIndex))
                    .opacity(isHidden ? 0.3 : 1)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
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
    let weekly: Bool
    let metric: UsageRankMetric
    /// Whether values read as a per-week rate (else per-day buckets on 7D).
    let perWeek: Bool
    @Binding var selectedDate: Date?

    private func value(_ point: UsageTrendPoint) -> Double {
        metric == .commonDoses ? point.commonValue : point.value
    }

    /// The chart's full x-span in seconds, and the start of the most-recent
    /// visible window, so a windowed chart opens on the newest data.
    private var span: (length: Double, windowStart: Date?) {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max(), last > first else { return (1, nil) }
        return (last.timeIntervalSince(first), last.addingTimeInterval(-usageChartWindowSeconds))
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
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: 190)
        .chartXSelection(value: $selectedDate)
        .chartXScrollWindow(fullLength: span.length, window: usageChartWindowSeconds, initialX: span.windowStart)
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
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel(format: weekly ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
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
    let metric: UsageRankMetric
    let perWeek: Bool
    let date: Date

    var body: some View {
        let rows = series.compactMap { item -> (index: Int, value: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item.substanceIndex, metric == .commonDoses ? point.commonValue : point.value)
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }

        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.caption.weight(.semibold))
            ForEach(rows, id: \.index) { row in
                HStack(spacing: 5) {
                    Circle()
                        .fill(style.color(row.index))
                        .frame(width: 6, height: 6)
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

    private func nearestPoint(in item: UsageTrendSeries) -> UsageTrendPoint? {
        item.points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}
