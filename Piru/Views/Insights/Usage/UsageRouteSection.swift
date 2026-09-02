import SwiftUI

/// The substance ranking: one horizontal bar per substance, segmented and
/// colored by route, ranked by either how *often* it was logged or by total
/// **common-dose units** — each dose counted as a multiple of that substance's
/// common dose.
///
/// The two rankings genuinely disagree. A gram-dosed botanical logged in small
/// sips tops the entry count while sitting mid-pack once each sip is weighed
/// against a common dose; a milligram stimulant redosed above common does the
/// reverse. Offering both, with the rows re-sorting between them, is the point —
/// the movement *is* the insight a raw count hides.
///
/// Drawn with shapes rather than `Chart { BarMark }`. A categorical bar chart
/// reserves no room for long substance names on a leading axis, so the labels
/// ended up sitting on top of their own bars; laying the row out directly also
/// makes each row a single, sensible VoiceOver element.
struct UsageRouteSection: View {
    let breakdown: UsageRouteBreakdown
    let style: UsageSubstanceStyle
    /// The Entries/Common-doses lens, owned globally by the Usage toolbar filter.
    let metric: UsageRankMetric

    var body: some View {
        if !breakdown.rows.isEmpty {
            UsageCollapsibleCard(
                title: "Most logged",
                storageKey: "routes",
            ) {
                UsageRankingContent(breakdown: breakdown, style: style, metric: metric)
            }
        }
    }
}

// MARK: - Content

/// Split out so the ranking's re-sort computation stays contained in its own
/// view rather than bloating the card.
private struct UsageRankingContent: View {
    let breakdown: UsageRouteBreakdown
    let style: UsageSubstanceStyle
    let metric: UsageRankMetric

    /// Rows in the active metric's order, truncated to the list length. In
    /// common-dose mode substances with no common-dose value sink below every
    /// substance that has one, in their entry-count order, so the "—" rows read
    /// as a labelled tail rather than salting the ranking.
    private var rankedRows: [UsageRouteRow] {
        let sorted: [UsageRouteRow] = switch metric {
        case .entries:
            breakdown.rows
        case .commonDoses:
            breakdown.rows.sorted { lhs, rhs in
                switch (lhs.commonTotal, rhs.commonTotal) {
                case let (l?, r?): l > r
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): lhs.total > rhs.total
                }
            }
        }
        return Array(sorted.prefix(UsageAnalytics.maximumRouteRows))
    }

    /// The largest active-metric value in the shown rows — the denominator every
    /// bar is drawn against.
    private var maxValue: Double {
        rankedRows.map { value($0) }.max() ?? 1
    }

    private func value(_ row: UsageRouteRow) -> Double {
        switch metric {
        case .entries: Double(row.total)
        case .commonDoses: row.commonTotal ?? 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(rankedRows) { row in
                    UsageRankRowView(
                        row: row,
                        metric: metric,
                        maxValue: maxValue,
                        colorByRoute: breakdown.routesAreMeaningful,
                        substanceColor: style.color(row.substanceIndex),
                        name: style.name(row.substanceIndex),
                    )
                }
            }
            // Re-sorting the bars when the metric flips is the whole feature, so
            // the reorder should be visibly animated rather than snapping.
            .animation(.easeInOut(duration: 0.35), value: metric)

            if breakdown.routesAreMeaningful {
                legend
            }
            if metric == .commonDoses {
                footnote
            }
        }
    }

    private var legend: some View {
        FlowLayout(spacing: Spacing.md) {
            ForEach(breakdown.distinctRoutes, id: \.self) { index in
                let route = UsageAxes.route(index)
                HStack(spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(route.tintColor)
                        .frame(width: 9, height: 9)
                    Text(route.localizedName)
                        .font(.caption2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Spacing.xxs)
    }

    private var footnote: some View {
        Text("Common-dose units count each dose as a multiple of its common dose. \(breakdown.commonDoseSubstances) of \(breakdown.rows.count) substances have one.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - One row

/// One substance's bar: name and value above, a proportional stack of segments
/// below. Colored by route when routes vary, else a single substance-colored bar.
private struct UsageRankRowView: View {
    let row: UsageRouteRow
    let metric: UsageRankMetric
    /// The busiest substance's value in the active metric — every bar is drawn
    /// relative to it, so bar length carries the ranking as well as the split.
    let maxValue: Double
    let colorByRoute: Bool
    let substanceColor: Color
    let name: String

    /// `true` when the active metric is common-dose units and this substance has
    /// none — drawn as an empty track and a dash, dimmed, so it reads as
    /// "not measurable this way", not "never taken".
    private var isUnavailable: Bool {
        metric == .commonDoses && row.commonTotal == nil
    }

    /// (routeIndex, value) segments in the active metric.
    private var segments: [(routeIndex: Int, value: Double)] {
        switch metric {
        case .entries: row.byRoute.map { ($0.routeIndex, Double($0.count)) }
        case .commonDoses: row.byRoute.map { ($0.routeIndex, $0.common) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Spacing.sm) {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(valueLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                HStack(spacing: 1) {
                    if isUnavailable {
                        Capsule()
                            .fill(Color(.quaternaryLabel).opacity(Theme.Opacity.dimmed))
                            .frame(width: max(4, width * 0.04))
                    } else {
                        ForEach(segments, id: \.routeIndex) { segment in
                            if segment.value > 0 {
                                Rectangle()
                                    .fill(colorByRoute ? UsageAxes.route(segment.routeIndex).tintColor : substanceColor)
                                    .frame(width: max(2, width * segment.value / max(maxValue, 0.0001)))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 11)
        }
        .opacity(isUnavailable ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(spoken))
    }

    private var valueLabel: String {
        switch metric {
        case .entries:
            "\(row.total)"
        case .commonDoses:
            row.commonTotal.map(UsageRankRowView.formatCommon) ?? "—"
        }
    }

    /// Whole numbers once past ten (388, not 388.0), one decimal below it.
    static func formatCommon(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1)))
    }

    private var spoken: String {
        switch metric {
        case .entries:
            let parts = row.byRoute.map { segment in
                let route = String(localized: UsageAxes.route(segment.routeIndex).localizedName)
                return String(localized: "\(segment.count) \(route)")
            }
            return String(localized: "\(row.total) entries: \(parts.joined(separator: ", "))")
        case .commonDoses:
            guard let total = row.commonTotal else {
                return String(localized: "No common dose defined")
            }
            return String(localized: "\(UsageRankRowView.formatCommon(total)) common-dose units across \(row.total) entries")
        }
    }
}
