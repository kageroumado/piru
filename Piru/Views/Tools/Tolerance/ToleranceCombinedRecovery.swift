import Charts
import SwiftUI

/// One mechanism's recovery trajectory plus the legend metadata that names it.
struct ToleranceRecoverySeries: Identifiable {
    let id: ReceptorClasses.ReceptorClass
    let legendKey: String
    let name: LocalizedStringResource
    let color: Color
    let points: [ToleranceChartPoint]
}

/// The always-on hero: every meaningfully-toleranced mechanism's recovery trajectory on one shared axis,
/// with a manual family-colored legend below. Shown in both detail modes.
struct ToleranceCombinedRecoverySection: View {
    let series: [ToleranceRecoverySeries]
    let axisDays: [Double]
    /// The shared window the curves span, in days.
    let windowDays: Double

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Modeled tolerance over time")
                    .cardTitle()

                if series.isEmpty {
                    Text("Nothing modeled.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    ToleranceCombinedRecoveryChart(series: series, axisDays: axisDays, windowDays: windowDays)
                    ToleranceRecoveryLegend(series: series)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }
}

struct ToleranceRecoveryLegend: View {
    let series: [ToleranceRecoverySeries]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(series) { item in
                HStack(spacing: Spacing.md) {
                    LegendDot(color: item.color, size: .large)
                    Text(item.name)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

/// The shared-axis recovery chart: one family-colored ``LineMark`` series per mechanism, each anchored
/// by a "now" ``PointMark`` at its current level, on a linear days X axis (gridlines) and a 0–100% Y axis
/// (gridlines at 0/100). Family colors are applied per series with a manual legend rendered by the
/// parent, so each line keeps its exact family hue.
///
/// A window longer than ``visibleDays`` opens on its first three weeks and pans sideways, the way the
/// Insights charts do (``ChartXScrollWindow``), so a months-long tail doesn't squeeze the fast
/// mechanisms into a single line at the left edge.
struct ToleranceCombinedRecoveryChart: View {
    let series: [ToleranceRecoverySeries]
    let axisDays: [Double]
    let windowDays: Double

    /// How much of a long window is on screen at once.
    static let visibleDays = 21.0

    private var scrolls: Bool {
        windowDays > Self.visibleDays * 1.05
    }

    var body: some View {
        chart
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
                value: Text("\(series.count) mechanisms plotted from their modeled level now."),
            )
    }

    @ViewBuilder
    private var chart: some View {
        if scrolls {
            marks
                .chartXScale(domain: 0 ... windowDays)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: Self.visibleDays)
        } else {
            marks
        }
    }

    private var marks: some View {
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
    }
}
