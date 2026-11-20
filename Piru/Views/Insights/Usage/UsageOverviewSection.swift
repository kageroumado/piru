import Charts
import SwiftUI

/// §1 — four cards answering "what does my usage look like right now, compared
/// to recently?": the period's entry count against the one before it, how many
/// distinct substances (and how many are new), the daily average with the
/// busiest weekday, and where the period's doses sit on the ladder. The window
/// they cover is named once above them, since the range itself lives in the
/// toolbar menu.
struct UsageOverviewSection: View {
    let overview: UsageOverview
    let range: UsageTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(windowName)
                .cardTitle()
                .accessibilityAddTraits(.isHeader)
            row { periodCard; substancesCard }
            row { averageCard; intensityCard }
        }
    }

    private var windowName: LocalizedStringResource {
        if let days = range.days {
            "Last \(days) days"
        } else {
            "All time"
        }
    }

    /// Two cards side by side at one height: the row takes its tallest card's
    /// height and the other stretches to it, so their titles share a baseline.
    private func row(@ViewBuilder _ cards: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Spacing.xl) { cards() }
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Entries

    private var periodCard: some View {
        UsageOverviewCard(
            title: "Entries",
            value: "\(overview.entryCount)",
            caption: changeText,
            captionColor: changeColor,
            accessibilityValue: changeAccessibility,
        ) {
            UsageSparkline(values: overview.sparkline)
        }
    }

    /// The change against the previous period, or nothing when that period
    /// is empty: a comparison with nothing says nothing.
    private var changeText: Text? {
        guard let change = overview.percentChange else { return nil }
        let percent = Int((abs(change) * 100).rounded())
        let rangeLabel = String(localized: range.displayName)
        // Composed as one already-localized `String` rather than concatenated
        // `Text`s: `Text + Text` is deprecated, and the arrow is a
        // glyph, not a word, so it belongs inside the localized value.
        let composed = change >= 0
            ? String(localized: "↑ \(percent)% vs previous \(rangeLabel)")
            : String(localized: "↓ \(percent)% vs previous \(rangeLabel)")
        return Text(composed)
    }

    private var changeAccessibility: String {
        guard let change = overview.percentChange else {
            return String(localized: "\(overview.entryCount) entries")
        }
        let percent = Int((abs(change) * 100).rounded())
        let direction = change >= 0
            ? String(localized: "up \(percent) percent")
            : String(localized: "down \(percent) percent")
        return String(localized: "\(overview.entryCount) entries, \(direction) versus the previous period")
    }

    private var changeColor: Color {
        // Neither direction is "good" or "bad" here — this screen is a record,
        // not a scoreboard — so the trend keeps the secondary label color and
        // only the arrow carries the direction.
        Theme.secondaryLabel
    }

    // MARK: Unique substances

    /// "N first recorded this period" only when some of the period's
    /// substances were also recorded before it; when every one is new the
    /// caption would repeat the headline number.
    private var showsNewSubstances: Bool {
        overview.newSubstances > 0 && overview.newSubstances < overview.uniqueSubstances
    }

    private var substancesCard: some View {
        UsageOverviewCard(
            title: "Substances",
            value: "\(overview.uniqueSubstances)",
            caption: showsNewSubstances ? Text("\(overview.newSubstances) first recorded this period") : nil,
            captionColor: Theme.secondaryLabel,
            accessibilityValue: showsNewSubstances
                ? String(localized: "\(overview.uniqueSubstances) distinct substances, \(overview.newSubstances) first recorded this period")
                : String(localized: "\(overview.uniqueSubstances) distinct substances"),
        ) {
            EmptyView()
        }
    }

    // MARK: Average per day

    private var averageCard: some View {
        UsageOverviewCard(
            title: "Per day",
            value: overview.averagePerDay.formatted(.number.precision(.fractionLength(0 ... 1))),
            caption: busiestWeekdayName.map { Text("Most entries: \($0)") },
            captionColor: Theme.secondaryLabel,
            accessibilityValue: busiestWeekdayName.map {
                String(localized: "\(averageSpoken) entries per day, most active on \($0)")
            } ?? String(localized: "\(averageSpoken) entries per day"),
        ) {
            EmptyView()
        }
    }

    private var averageSpoken: String {
        overview.averagePerDay.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private var busiestWeekdayName: String? {
        guard let weekday = overview.busiestWeekday else { return nil }
        let symbols = Calendar.current.standaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return nil }
        return symbols[weekday - 1]
    }

    // MARK: Dose intensity

    private var intensityCard: some View {
        UsageOverviewCard(
            title: "Dose level",
            value: intensityValue,
            caption: intensityCaption,
            captionColor: Theme.secondaryLabel,
            accessibilityValue: intensityAccessibility,
        ) {
            EmptyView()
        }
    }

    private var intensityValue: String {
        guard let intensity = overview.doseIntensity else { return "—" }
        return "\(Int((intensity * 100).rounded()))%"
    }

    private var intensityCaption: Text? {
        guard overview.doseIntensity != nil else {
            return Text("No dose ladders matched")
        }
        if overview.heavyCount > 0 {
            return Text("at common or above · \(overview.heavyCount) heavy")
        }
        return Text("at common or above")
    }

    private var intensityAccessibility: String {
        guard let intensity = overview.doseIntensity else {
            return String(localized: "No entries could be placed on a dose ladder")
        }
        let percent = Int((intensity * 100).rounded())
        return String(
            localized: "\(percent) percent of \(overview.doseResolvedCount) placed doses were common or above, \(overview.heavyCount) heavy",
        )
    }
}

// MARK: - One card

/// One overview tile: a headline number, an optional caption, and optional
/// inline art (the sparkline).
private struct UsageOverviewCard<Art: View>: View {
    let title: LocalizedStringKey
    let value: String
    var caption: Text?
    var captionColor: Color = Theme.secondaryLabel
    let accessibilityValue: String
    @ViewBuilder var art: () -> Art

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .captionSecondary()
            Text(value)
                .font(.piru(.title2, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                caption
                    .font(.caption2)
                    .foregroundStyle(captionColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            art()
        }
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.xl)
        .themeCard(cornerRadius: Theme.CornerRadius.container)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
    }
}

// MARK: - Sparkline

/// Seven equal buckets across the selected range. Deliberately axis-free — it
/// is a shape, not a readout, and the card's headline number carries the value.
struct UsageSparkline: View {
    let values: [Int]

    private struct Point: Identifiable {
        let index: Int
        let value: Int
        var id: Int {
            index
        }
    }

    var body: some View {
        let points = values.enumerated().map { Point(index: $0.offset, value: $0.element) }
        let peak = values.max() ?? 0

        Chart(points) { point in
            AreaMark(
                x: .value("Bucket", point.index),
                y: .value("Entries", point.value),
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom,
                ),
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Bucket", point.index),
                y: .value("Entries", point.value),
            )
            .foregroundStyle(Theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... Double(max(peak, 1)))
        .frame(height: 26)
        .chartSummaryAccessibility(
            label: Text("Trend"),
            value: Text("\(values.map(String.init).joined(separator: ", ")) entries across seven equal slices of the period."),
        )
    }
}
