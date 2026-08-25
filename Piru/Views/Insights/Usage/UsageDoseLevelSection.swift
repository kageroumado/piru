import Charts
import SwiftUI

/// §4 — where the period's doses sat on each substance's own ladder, over time.
///
/// Two honesty rules from the spec are load-bearing here:
///
/// - The footnote always states **how many** of the period's entries could be
///   placed on a ladder. A dose logged in mL against a ladder written in mg is
///   not comparable, and neither is a substance the catalog doesn't carry; those
///   entries are excluded rather than guessed at.
/// - Below 30% coverage the whole section demotes itself to a collapsed
///   disclosure, because a chart built from a minority of the data reads as if
///   it described all of it.
struct UsageDoseLevelSection: View {
    let breakdown: UsageDoseLevelBreakdown
    let style: UsageSubstanceStyle
    let weekly: Bool

    var body: some View {
        if breakdown.resolvedEntries == 0 {
            EmptyView()
        } else if breakdown.isLowCoverage {
            UsageCollapsibleCard(
                title: "Dose levels",
                subtitle: "Only a minority of entries could be placed on a ladder",
                storageKey: "doseLevels",
                defaultExpanded: false,
            ) {
                content
            }
        } else {
            UsageSectionCard(title: "Dose levels", subtitle: "Where your doses sit on each substance's ladder") {
                content
            }
        }
    }

    private var content: some View {
        UsageDoseLevelContent(breakdown: breakdown, style: style, weekly: weekly)
    }
}

// MARK: - Content

/// Split out so its substance-selector state doesn't sit on the parent (and so
/// changing the selection re-evaluates only the chart, not the whole screen).
private struct UsageDoseLevelContent: View {
    let breakdown: UsageDoseLevelBreakdown
    let style: UsageSubstanceStyle
    let weekly: Bool

    /// `nil` = all substances pooled.
    @State private var selectedSubstance: Int?
    @State private var highlightedLevel: Int?

    private struct Slice: Identifiable {
        let date: Date
        let levelIndex: Int
        /// The level's display name — Swift Charts stacks by the plottable it is
        /// styled by, so the band identity has to be this string.
        let levelName: String
        let value: Double
        var id: String {
            "\(date.timeIntervalSince1970)-\(levelIndex)"
        }
    }

    private var buckets: [UsageDoseLevelBucket] {
        guard let selectedSubstance else { return breakdown.overall }
        return breakdown.bySubstance[selectedSubstance] ?? []
    }

    /// Pooled across substances the y-axis has to be a percentage — one
    /// substance's milligrams mean nothing against another's. Narrowed to a
    /// single substance, absolute counts are both meaningful and more useful.
    private var showsPercentages: Bool {
        selectedSubstance == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            substancePicker
            chart
            legend
            footnote
        }
    }

    private var substancePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "All"), isSelected: selectedSubstance == nil, color: Theme.accent) {
                    selectedSubstance = nil
                }
                ForEach(breakdown.selectableSubstances, id: \.self) { index in
                    chip(title: style.name(index), isSelected: selectedSubstance == index, color: style.color(index)) {
                        selectedSubstance = selectedSubstance == index ? nil : index
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func chip(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.25) : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color : Color(.quaternaryLabel)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var chart: some View {
        Chart(slices) { slice in
            // Stacked columns, not a stacked area: dose counts per bucket are
            // discrete, so a smooth interpolation between them would cross its
            // own bands into a tangle. One column per bucket reads cleanly.
            BarMark(
                x: .value("Date", slice.date, unit: weekly ? .weekOfYear : .day),
                y: .value(showsPercentages ? "Share" : "Entries", slice.value),
                stacking: .standard,
            )
            .foregroundStyle(by: .value("Level", slice.levelName))
            .opacity(highlightedLevel == nil || highlightedLevel == slice.levelIndex ? 1 : 0.18)
        }
        .chartForegroundStyleScale(domain: styleDomain, range: styleRange)
        .frame(height: 170)
        .chartXScrollWindow(fullLength: span.length, window: usageChartWindowSeconds, initialX: span.windowStart)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
                AxisValueLabel {
                    if showsPercentages, let fraction = value.as(Double.self) {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2)
                    } else {
                        Text(value.as(Double.self)?.formatted(.number.precision(.fractionLength(0))) ?? "")
                            .font(.caption2)
                    }
                }
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
        .chartLegend(.hidden)
        .chartSummaryAccessibility(label: Text("Dose levels over time"), value: Text(summary))
    }

    /// The stacked area's full x-span in seconds, and the start of the
    /// most-recent visible window so a windowed chart opens on the newest data.
    private var span: (length: Double, windowStart: Date?) {
        let dates = buckets.map(\.date)
        guard let first = dates.min(), let last = dates.max(), last > first else { return (1, nil) }
        return (last.timeIntervalSince(first), last.addingTimeInterval(-usageChartWindowSeconds))
    }

    private var slices: [Slice] {
        buckets.flatMap { bucket -> [Slice] in
            let total = max(bucket.total, 1)
            return UsageAxes.doseLevelOrder.compactMap { level in
                guard let count = bucket.counts[level], count > 0 else { return nil }
                return Slice(
                    date: bucket.date,
                    levelIndex: level,
                    levelName: levelName(level),
                    value: showsPercentages ? Double(count) / Double(total) : Double(count),
                )
            }
        }
    }

    private func levelName(_ level: Int) -> String {
        String(localized: UsageAxes.doseLevel(level).displayName)
    }

    /// Lightest → heaviest, which is also the order the bands stack in.
    private var styleDomain: [String] {
        UsageAxes.doseLevelOrder.map(levelName)
    }

    private var styleRange: [Color] {
        UsageAxes.doseLevelOrder.map { UsageAxes.doseLevel($0).swiftUIColor }
    }

    private var legend: some View {
        FlowLayout(spacing: 8) {
            ForEach(presentLevels, id: \.self) { level in
                let doseLevel = UsageAxes.doseLevel(level)
                let isDimmed = highlightedLevel != nil && highlightedLevel != level
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        highlightedLevel = highlightedLevel == level ? nil : level
                    }
                } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(doseLevel.swiftUIColor)
                            .frame(width: 9, height: 9)
                        Text(doseLevel.displayName)
                            .font(.caption2)
                        Text("\(count(of: level))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .opacity(isDimmed ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(doseLevel.displayName))
                .accessibilityValue(Text("\(count(of: level)) entries"))
                .accessibilityAddTraits(highlightedLevel == level ? [.isSelected] : [])
            }
        }
    }

    private var presentLevels: [Int] {
        UsageAxes.doseLevelOrder.filter { count(of: $0) > 0 }
    }

    private func count(of level: Int) -> Int {
        buckets.reduce(0) { $0 + ($1.counts[level] ?? 0) }
    }

    private var footnote: some View {
        Text("Based on \(breakdown.resolvedEntries) of \(breakdown.totalEntries) entries with dose data")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
    }

    private var summary: String {
        let total = presentLevels.reduce(0) { $0 + count(of: $1) }
        guard total > 0 else { return String(localized: "No dose levels resolved") }
        let parts = presentLevels.reversed().prefix(3).map { level in
            let percent = Int((Double(count(of: level)) / Double(total) * 100).rounded())
            return String(localized: "\(String(localized: UsageAxes.doseLevel(level).displayName)) \(percent) percent")
        }
        return parts.joined(separator: ", ")
    }
}
