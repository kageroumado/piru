import SwiftUI

/// §7 — "do I use on a schedule, or sporadically?"
///
/// Per substance: the mean gap between the days it was logged, and the
/// coefficient of variation of those gaps. Low CV means the gaps are all about
/// the same length — a routine. High CV means bursts and droughts.
///
/// Only substances with at least ``UsageAnalytics/minimumRegularityEntries``
/// entries appear; below that the statistic is describing noise.
struct UsageRegularitySection: View {
    let rows: [UsageRegularity]
    let style: UsageSubstanceStyle

    var body: some View {
        if !rows.isEmpty {
            UsageCollapsibleCard(
                title: "Regularity",
                subtitle: "How evenly spaced your doses are",
                storageKey: "regularity",
            ) {
                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        UsageRegularityRow(row: row, style: style)
                    }
                }
            }
        }
    }
}

private struct UsageRegularityRow: View {
    let row: UsageRegularity
    let style: UsageSubstanceStyle

    var body: some View {
        let name = style.name(row.substanceIndex)
        // Always one decimal: "every 1.0 days" is both the spec's own wording
        // and the only way to keep the phrase grammatical without inflecting a
        // fractional noun ("every 1 days").
        let interval = row.meanIntervalDays.formatted(.number.precision(.fractionLength(1)))
        let tier = row.tier

        // Two columns: name over its evenness bar on the left, the interval over
        // its tier right-aligned on the right — so "every 2.6 days" and "Irregular"
        // share one right edge instead of the ragged split-alignment they had.
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(style.color(row.substanceIndex))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 5)
                        Capsule()
                            .fill(color(for: tier))
                            .frame(width: max(4, geometry.size.width * row.fill), height: 5)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("every \(interval) days")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
                Text(tier.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text("\(String(localized: tier.displayName)), about every \(interval) days across \(row.entryCount) entries"))
    }

    /// Green through red as the gaps get less even. This encodes *evenness*,
    /// not virtue — a sporadic supplement and a sporadic recreational dose read
    /// the same here.
    private func color(for tier: UsageRegularityTier) -> Color {
        switch tier {
        case .veryRegular: .green
        case .somewhatRegular: .yellow
        case .irregular: .orange
        case .sporadic: .red
        }
    }
}
