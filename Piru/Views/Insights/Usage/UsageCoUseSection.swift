import SwiftUI

/// §6 — which substances get logged on the same day.
///
/// A ranked list, not a matrix: with a handful of substances a matrix is mostly
/// empty cells, and the answer the user wants ("what goes with what, how often")
/// is a sentence.
///
/// A pair must share at least ``UsageAnalytics/minimumCoUseDays`` days before it
/// appears — one coincidental overlap is not a pattern, and presenting it as one
/// would be the same overreach the rest of the app avoids.
struct UsageCoUseSection: View {
    let pairs: [UsageCoUsePair]
    let style: UsageSubstanceStyle
    let categories: [(categoryIndex: Int, count: Int)]

    @State private var categoryFilter: Int?

    private var filtered: [UsageCoUsePair] {
        guard let categoryFilter else { return pairs }
        // Either side matching keeps a supplement×stimulant pair visible under
        // both filters, which is what someone filtering to "Stimulant" means.
        return pairs.filter { pair in
            let refs = style.substances
            guard refs.indices.contains(pair.firstIndex), refs.indices.contains(pair.secondIndex) else { return false }
            return refs[pair.firstIndex].categoryIndex == categoryFilter
                || refs[pair.secondIndex].categoryIndex == categoryFilter
        }
    }

    var body: some View {
        if !pairs.isEmpty {
            UsageCollapsibleCard(
                title: "Used together",
                subtitle: "Substances logged on the same day",
                storageKey: "coUse",
            ) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if categories.count > 1 {
                        UsageCategoryFilterBar(categories: categories, selection: $categoryFilter)
                    }
                    if filtered.isEmpty {
                        Text("No pairs in this class")
                            .captionSecondary()
                    } else {
                        VStack(spacing: Spacing.lg) {
                            ForEach(filtered) { pair in
                                UsageCoUseRow(pair: pair, style: style)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One pair: two color dots, the two names, the day count, and a bar showing
/// what share of the days *either* was logged both were.
private struct UsageCoUseRow: View {
    let pair: UsageCoUsePair
    let style: UsageSubstanceStyle

    var body: some View {
        let firstName = style.name(pair.firstIndex)
        let secondName = style.name(pair.secondIndex)
        let overlapPercent = Int((pair.overlap * 100).rounded())

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                HStack(spacing: -3) {
                    LegendDot(color: style.color(pair.firstIndex), size: .large)
                    LegendDot(color: style.color(pair.secondIndex), size: .large)
                }
                Text("\(firstName) + \(secondName)")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(pair.days) days")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 4)
                    Capsule()
                        .fill(style.color(pair.firstIndex).opacity(0.75))
                        .frame(width: max(3, geometry.size.width * pair.overlap), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(firstName) with \(secondName)"))
        .accessibilityValue(Text("\(pair.days) days together, \(overlapPercent) percent of the days either was logged"))
    }
}
