import Charts
import SwiftUI

/// One mechanism's recovery trajectory on the screen's shared frame, plus the name its line carries.
struct ToleranceRecoverySeries: Identifiable {
    let row: ToleranceRow
    let name: LocalizedStringResource
    let points: [ToleranceChartPoint]
    /// Days from now at which the line reads near baseline, when that point lies ahead and on the axis.
    let nearBaselineDay: Double?

    var id: ReceptorClasses.ReceptorClass {
        row.id
    }

    var color: Color {
        row.familyColor
    }

    init(row: ToleranceRow, tier: UserProfile, frame: ToleranceChartFrame) {
        self.row = row
        name = toleranceClassName(row.snapshot.receptorClass, tier: tier)
        points = row.recoveryCurve(overMinutes: frame.time.endDays * 1_440)
        let crossing = row.minutesToNearBaseline.map { $0 / 1_440 }
        nearBaselineDay = crossing.flatMap { $0 > 0 && $0 <= frame.time.endDays ? $0 : nil }
    }
}

/// The frame every chart on the Modeled Tolerance screen shares: one time axis and one value axis, so a
/// mechanism's line sits in the same place on its card as in the overview.
struct ToleranceChartFrame: Equatable {
    let time: ToleranceChartScale.TimeAxis
    let value: ToleranceChartScale.ValueAxis

    init(rows: [ToleranceRow]) {
        let span = ToleranceChartScale.spanMinutes(
            nearBaselineMinutes: rows.map(\.minutesToNearBaseline), fadeMinutes: rows.map(\.fadeMinutes),
        )
        time = ToleranceChartScale.timeAxis(spanDays: span / 1_440)
        value = ToleranceChartScale.valueAxis(peakPercent: rows.map { $0.snapshot.severity * 100 }.max() ?? 0)
    }
}

/// The always-on hero: every plotted mechanism's recovery trajectory on one shared axis, the level of
/// each now or at the scrubbed instant, and the one statement of what the scale is. Shown in both
/// detail modes.
struct ToleranceCombinedRecoverySection: View {
    let series: [ToleranceRecoverySeries]
    let frame: ToleranceChartFrame

    /// The scrubbed instant, in days from now.
    @State private var selectedDay: Double?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Less effect from a usual dose")
                    .captionSecondary()
                ToleranceCurvesChart(series: series, frame: frame, selectedDay: selectedDay)
                    .chartXSelection(value: $selectedDay)
                    .frame(height: 170)
                    .chartSummaryAccessibility(label: Text("Recovery by mechanism"), value: Text(summary))
                ToleranceRecoveryLegend(series: series, selectedDay: selectedDay, timeUnit: frame.time.unit)
                Text("Compared with no tolerance, in the model. The curves assume nothing more is logged. Under \(tolerancePercentText(ToleranceRow.nearBaselineSeverity * 100)) counts as near baseline.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, Spacing.sm)
        }
        #if DEBUG
        .task {
            if let date = ScreenshotTour.takeStagedSelection(.tolerance) {
                selectedDay = date.timeIntervalSince(DebugClock.now) / 86_400
            }
        }
        #endif
    }

    private var summary: String {
        ListFormatter.localizedString(byJoining: series.map { item in
            String(localized: "\(String(localized: item.name)) \(tolerancePercentText(item.row.snapshot.severity * 100)) now")
        })
    }
}

/// The lines' key and readout in one: each mechanism's level now, or at the scrubbed instant while a
/// point on the chart is selected. Both states have the same rows, so scrubbing never moves the layout.
struct ToleranceRecoveryLegend: View {
    let series: [ToleranceRecoverySeries]
    let selectedDay: Double?
    let timeUnit: ToleranceChartScale.TimeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(series) { item in
                HStack(spacing: Spacing.md) {
                    LegendDot(color: item.color, size: .large)
                    Text(item.name)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    Text(tolerancePercentText(item.row.tolerancePercent(afterMinutes: (selectedDay ?? 0) * 1_440)))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    private var title: String {
        guard let selectedDay, selectedDay > 0 else { return String(localized: "Now") }
        return ToleranceBaselineDate.text(
            for: Date.now.addingTimeInterval(selectedDay * 86_400),
            precision: timeUnit == .hours ? .minute : .day,
        )
    }
}

/// Where a bottom-axis label sits against its tick. The first starts at its tick and the last ends at
/// its tick, so both stay inside the plot's edges and the end of the axis is always printed; the ones
/// between are centered under their ticks.
func axisTickLabelAnchor(index: Int, count: Int) -> UnitPoint {
    switch index {
    case 0: .topLeading
    case count - 1: .topTrailing
    default: .top
    }
}

/// Recovery curves on the screen's shared frame: one family-colored line per mechanism from its "now"
/// dot, the dashed near-baseline line, and a ring with a drop line to the time axis where each curve
/// crosses it. The overview draws every plotted mechanism; a card draws its own.
struct ToleranceCurvesChart: View {
    let series: [ToleranceRecoverySeries]
    let frame: ToleranceChartFrame
    /// The scrubbed instant, in days from now.
    var selectedDay: Double?

    private static let nearBaselinePercent = ToleranceRow.nearBaselineSeverity * 100

    var body: some View {
        Chart {
            RuleMark(y: .value("Near baseline", Self.nearBaselinePercent))
                .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Days", point.day),
                        y: .value("Tolerance", point.percent),
                        series: .value("Mechanism", String(reflecting: item.id)),
                    )
                    .foregroundStyle(item.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                if let crossing = item.nearBaselineDay {
                    RuleMark(
                        x: .value("Days", crossing),
                        yStart: .value("Tolerance", 0),
                        yEnd: .value("Tolerance", Self.nearBaselinePercent),
                    )
                    .foregroundStyle(item.color.opacity(Theme.Opacity.dimmed))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("Days", crossing),
                        y: .value("Tolerance", Self.nearBaselinePercent),
                    )
                    .foregroundStyle(item.color)
                    .symbol(.circle.strokeBorder(lineWidth: 2))
                    .symbolSize(54)
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
            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: 0 ... frame.time.endDays)
        .chartYScale(domain: 0 ... frame.value.top)
        .chartYAxis {
            AxisMarks(values: frame.value.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(tolerancePercentText(percent))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: frame.time.minorGridDays) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
            AxisMarks(values: frame.time.tickDays) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(centered: false, anchor: axisTickLabelAnchor(index: value.index, count: value.count)) {
                    if let days = value.as(Double.self) {
                        Text(toleranceTimeTickLabel(frame.time, days: days))
                    }
                }
            }
        }
    }
}
