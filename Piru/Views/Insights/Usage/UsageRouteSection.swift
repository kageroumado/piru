import SwiftUI

/// §5 — how administration routes vary per substance. One horizontal stacked
/// bar per substance, segmented and colored by route, with the bar's total
/// length proportional to how often that substance was logged.
///
/// The section is hidden entirely below two distinct routes: with a single
/// route every bar would be one solid color, which answers nothing.
///
/// Drawn with shapes rather than `Chart { BarMark }`. A categorical bar chart
/// reserves no room for long substance names on a leading axis, so the labels
/// ended up sitting on top of their own bars; laying the row out directly also
/// makes each row a single, sensible VoiceOver element.
struct UsageRouteSection: View {
    let breakdown: UsageRouteBreakdown
    let style: UsageSubstanceStyle

    var body: some View {
        if breakdown.isMeaningful {
            UsageCollapsibleCard(
                title: "Routes",
                subtitle: "How each substance was taken",
                storageKey: "routes",
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(breakdown.rows) { row in
                        UsageRouteRowView(
                            row: row,
                            name: style.name(row.substanceIndex),
                            maxTotal: breakdown.rows.first?.total ?? row.total,
                        )
                    }
                    legend
                }
            }
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 8) {
            ForEach(breakdown.distinctRoutes, id: \.self) { index in
                let route = UsageAxes.route(index)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(route.tintColor)
                        .frame(width: 9, height: 9)
                    Text(route.localizedName)
                        .font(.caption2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 2)
    }
}

/// One substance's bar: name and count above, a proportional stack of
/// route-colored segments below.
private struct UsageRouteRowView: View {
    let row: UsageRouteRow
    let name: String
    /// The busiest substance's count — every bar is drawn relative to it, so
    /// bar length carries the "how often" comparison as well as the split.
    let maxTotal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(row.total)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                let scale = geometry.size.width * CGFloat(row.total) / CGFloat(max(maxTotal, 1))
                HStack(spacing: 1) {
                    ForEach(row.byRoute, id: \.routeIndex) { segment in
                        Rectangle()
                            .fill(UsageAxes.route(segment.routeIndex).tintColor)
                            .frame(width: max(2, scale * CGFloat(segment.count) / CGFloat(max(row.total, 1))))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(spoken))
    }

    private var spoken: String {
        let parts = row.byRoute.map { segment in
            let route = String(localized: UsageAxes.route(segment.routeIndex).localizedName)
            return String(localized: "\(segment.count) \(route)")
        }
        let split = parts.joined(separator: ", ")
        return String(localized: "\(row.total) entries: \(split)")
    }
}
