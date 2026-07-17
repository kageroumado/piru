import Charts
import SwiftUI

/// One mechanism's recovery trajectory plus the legend metadata that names it.
struct ToleranceRecoverySeries: Identifiable {
    let id: ReceptorClasses.ReceptorClass
    let legendKey: String
    let name: LocalizedStringResource
    let color: Color
    let points: [ToleranceChartPoint]
    let recoveryPhrase: String
    let severity: Double
}

/// The always-on hero: every meaningfully-toleranced mechanism's recovery trajectory on one shared axis,
/// with a manual family-colored legend below. Shown in both detail modes.
struct ToleranceCombinedRecoverySection: View {
    let series: [ToleranceRecoverySeries]
    let axisDays: [Double]
    /// At least one mechanism's natural recovery window exceeds the shared 60-day cap — the caption then
    /// notes the chart is showing only the first 60 days.
    let isClipped: Bool

    private var caption: LocalizedStringResource {
        isClipped
            ? "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset. Showing the first 60 days."
            : "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset."
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery if you stop now")
                    .font(.headline)

                if series.isEmpty {
                    Text("Everything's rested — nothing recovering right now.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    ToleranceCombinedRecoveryChart(series: series, axisDays: axisDays)
                    ToleranceRecoveryLegend(series: series)
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct ToleranceRecoveryLegend: View {
    let series: [ToleranceRecoverySeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(series) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 9, height: 9)
                    Text(item.name)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    // Already a resolved, localized phrase from `durationPhrase` — show verbatim so it
                    // isn't re-looked-up as a catalog key.
                    Text(verbatim: item.recoveryPhrase)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }
}

/// The shared-axis recovery chart: one family-colored ``LineMark`` series per mechanism, each anchored
/// by a "now" ``PointMark`` at its current level, on a linear days X axis (gridlines) and a 0–100% Y axis
/// (gridlines at 0/100). Family colors are applied per series with a manual legend rendered by the
/// parent, so each line keeps its exact family hue.
struct ToleranceCombinedRecoveryChart: View {
    let series: [ToleranceRecoverySeries]
    let axisDays: [Double]

    var body: some View {
        Chart(series) { item in
            ForEach(item.points) { point in
                LineMark(
                    x: .value("Days", point.day),
                    y: .value("Tolerance", point.percent),
                    series: .value("Mechanism", item.legendKey),
                )
                .foregroundStyle(item.color)
                .interpolationMethod(.monotone)
            }
            if let start = item.points.first {
                PointMark(
                    x: .value("Days", start.day),
                    y: .value("Tolerance", start.percent),
                )
                .foregroundStyle(item.color)
                .symbolSize(40)
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(values: [0, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text(percent >= 100 ? "high" : "low")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDays) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let days = value.as(Double.self) {
                        Text(axisDayLabel(days: days))
                    }
                }
            }
        }
        .frame(height: 160)
        .chartSummaryAccessibility(
            label: Text("Recovery by mechanism"),
            value: Text("\(series.count) mechanisms plotted, each fading from its current tolerance toward none."),
        )
    }
}
