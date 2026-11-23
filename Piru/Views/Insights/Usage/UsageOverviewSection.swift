import SwiftUI

/// §1 — "what does my usage look like in this window?": four figures in one
/// card — how many entries, how many distinct substances, the daily average,
/// and the share of placed doses at common or above. The window is named once
/// above the card, since the range itself lives in the toolbar menu.
struct UsageOverviewSection: View {
    let overview: UsageOverview
    let range: UsageTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(range.windowName)
                .cardTitle()
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xl) {
                    figures
                }
                Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.lg) {
                    GridRow { entries; substances }
                    GridRow { perDay; intensity }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard(cornerRadius: Theme.CornerRadius.container)
        }
    }

    @ViewBuilder
    private var figures: some View {
        entries
        substances
        perDay
        intensity
    }

    private var entries: some View {
        UsageFigure(value: "\(overview.entryCount)", label: "entries")
            .accessibilityValue(Text(changeAccessibility))
    }

    private var substances: some View {
        UsageFigure(value: "\(overview.uniqueSubstances)", label: "substances")
            .accessibilityValue(Text(substancesAccessibility))
    }

    private var perDay: some View {
        UsageFigure(value: overview.window.averagePerDayText, label: "per day")
            .accessibilityValue(Text("\(overview.window.averagePerDayText) entries per day"))
    }

    private var intensity: some View {
        UsageFigure(value: intensityValue, label: "at common or above")
            .accessibilityValue(Text(intensityAccessibility))
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

    private var substancesAccessibility: String {
        overview.newSubstances > 0 && overview.newSubstances < overview.uniqueSubstances
            ? String(localized: "\(overview.uniqueSubstances) distinct substances, \(overview.newSubstances) first recorded this period")
            : String(localized: "\(overview.uniqueSubstances) distinct substances")
    }

    private var intensityValue: String {
        guard let intensity = overview.doseIntensity else { return "—" }
        return "\(Int((intensity * 100).rounded()))%"
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

/// One figure in the overview card: the number, its unit under it.
private struct UsageFigure: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(.piru(.title2, design: .rounded, weight: .semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}
