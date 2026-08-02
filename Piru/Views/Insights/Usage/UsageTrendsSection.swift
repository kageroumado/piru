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

    /// Substance indices the user has hidden by tapping the legend.
    @State private var hidden: Set<Int> = []
    @State private var showsAll = false
    @State private var selectedDate: Date?

    private var visibleSeries: [UsageTrendSeries] {
        let shown = showsAll ? trends : Array(trends.prefix(UsageAnalytics.defaultTrendSubstances))
        let filtered = shown.filter { !hidden.contains($0.substanceIndex) }
        // Hiding every line would leave an empty plot with no way back, so the
        // legend can never zero the chart out.
        return filtered.isEmpty ? shown : filtered
    }

    var body: some View {
        UsageSectionCard(title: "Substance trends", subtitle: subtitle) {
            if trends.isEmpty {
                Text("Not enough history yet")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                UsageTrendsChart(
                    series: visibleSeries,
                    style: style,
                    weekly: range.usesWeeklyBuckets,
                    selectedDate: $selectedDate,
                )
                if let selectedDate {
                    UsageTrendsReadout(series: visibleSeries, style: style, date: selectedDate)
                }
                legend
            }
        }
        .onChange(of: range) {
            selectedDate = nil
            hidden = []
        }
    }

    private var subtitle: LocalizedStringKey {
        range.usesWeeklyBuckets
            ? "Entries per week, 4-week rolling average"
            : "Entries per week, 7-day rolling average"
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(showsAll ? trends : Array(trends.prefix(UsageAnalytics.defaultTrendSubstances))) { item in
                    legendChip(item)
                }
            }
            if trends.count > UsageAnalytics.defaultTrendSubstances {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsAll.toggle() }
                } label: {
                    Text(showsAll ? "Show fewer" : "Show all \(trends.count)")
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
            HStack(spacing: 4) {
                Circle()
                    .fill(style.color(item.substanceIndex))
                    .frame(width: 8, height: 8)
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
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Per week", point.value),
                        series: .value("Substance", item.substanceIndex),
                    )
                    .foregroundStyle(style.color(item.substanceIndex))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: 190)
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
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
            let last = item.points.last?.value ?? 0
            let first = item.points.first?.value ?? 0
            let rate = last.formatted(.number.precision(.fractionLength(0 ... 1)))
            if last > first + 0.01 {
                return String(localized: "\(name) rising to \(rate) per week")
            } else if last < first - 0.01 {
                return String(localized: "\(name) falling to \(rate) per week")
            }
            return String(localized: "\(name) steady at \(rate) per week")
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
    let date: Date

    var body: some View {
        let rows = series.compactMap { item -> (index: Int, value: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item.substanceIndex, point.value)
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
                    Text("\(row.value.formatted(.number.precision(.fractionLength(0 ... 1))))/wk")
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
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func nearestPoint(in item: UsageTrendSeries) -> UsageTrendPoint? {
        item.points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}
