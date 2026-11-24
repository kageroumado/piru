import Charts
import SwiftUI

/// One mechanism's recovery trajectory on the screen's shared frame, plus the name its line carries.
struct ToleranceRecoverySeries: Identifiable {
    let row: ToleranceRow
    let name: LocalizedStringResource
    /// The "no further doses" decay curve — drawn solid when nothing is scheduled, thin and dashed
    /// beneath the projection when a scheduled med feeds this class.
    let points: [ToleranceChartPoint]
    /// The curve with the scheduled med's future doses kept coming, when one feeds this class. Drawn as
    /// the main solid line; `nil` when no scheduled med contributes (then ``points`` is the main line).
    let projectedPoints: [ToleranceChartPoint]?
    /// The level the projection settles near (percent), when it settles inside the window.
    let settlesPercent: Double?
    /// The projection is still rising at the end of the window.
    let stillRising: Bool
    /// Days from now at which the line reads near baseline, when that point lies ahead and on the axis.
    let nearBaselineDay: Double?

    var id: ReceptorClasses.ReceptorClass {
        row.id
    }

    var color: Color {
        row.familyColor
    }

    /// Whether a scheduled med projects this class's curve.
    var isProjected: Bool {
        projectedPoints != nil
    }

    /// The level the line reads `day` days from now — the projected curve when a scheduled med feeds
    /// this class (so the scrub readout follows the solid line), otherwise the decay curve.
    func percent(atDay day: Double) -> Double {
        guard let projected = projectedPoints, let first = projected.first, let last = projected.last else {
            return row.tolerancePercent(afterMinutes: max(0, day) * 1_440)
        }
        if day <= first.day { return first.percent }
        if day >= last.day { return last.percent }
        for index in 1 ..< projected.count where projected[index].day >= day {
            let a = projected[index - 1]
            let b = projected[index]
            let t = (day - a.day) / max(1e-9, b.day - a.day)
            return a.percent + (b.percent - a.percent) * t
        }
        return last.percent
    }

    init(row: ToleranceRow, tier: UserProfile, frame: ToleranceChartFrame, projection: ToleranceStore.ToleranceProjection?) {
        self.row = row
        name = toleranceClassName(row.snapshot.receptorClass, tier: tier)
        let window = frame.time.endDays * 1_440
        points = row.recoveryCurve(overMinutes: window)
        if let projection {
            projectedPoints = projection.points
                .filter { $0.minutesFromNow <= window + 1 }
                .enumerated()
                .map { ToleranceChartPoint(id: $0.offset, day: $0.element.minutesFromNow / 1_440, percent: $0.element.percent) }
            settlesPercent = projection.settlesPercent
            stillRising = projection.settlesPercent == nil
        } else {
            projectedPoints = nil
            settlesPercent = nil
            stillRising = false
        }
        let crossing = row.minutesToNearBaseline.map { $0 / 1_440 }
        nearBaselineDay = crossing.flatMap { $0 > 0 && $0 <= frame.time.endDays ? $0 : nil }
    }
}

/// The frame every chart on the Modeled Tolerance screen shares: one time axis and one value axis, so a
/// mechanism's line sits in the same place on its card as in the overview.
struct ToleranceChartFrame: Equatable {
    let time: ToleranceChartScale.TimeAxis
    let value: ToleranceChartScale.ValueAxis

    init(rows: [ToleranceRow], projections: [ReceptorClasses.ReceptorClass: ToleranceStore.ToleranceProjection] = [:]) {
        // A projected class reaches its settle point (or the horizon, if still rising) so the settling is
        // on screen; the peak of each projected curve also lifts the value axis.
        let settleMinutes = rows.compactMap { projections[$0.id] }
            .map { $0.settleMinutes ?? ToleranceStore.projectionHorizonMinutes }
        let span = ToleranceChartScale.spanMinutes(
            nearBaselineMinutes: rows.map(\.minutesToNearBaseline), fadeMinutes: rows.map(\.fadeMinutes),
            settleMinutes: settleMinutes,
        )
        time = ToleranceChartScale.timeAxis(spanDays: span / 1_440)
        let decayPeak = rows.map { $0.snapshot.severity * 100 }.max() ?? 0
        let projectedPeak = rows.compactMap { projections[$0.id]?.points.map(\.percent).max() }.max() ?? 0
        value = ToleranceChartScale.valueAxis(peakPercent: max(decayPeak, projectedPeak))
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
                Text(scaleFootnote)
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

    /// The one statement of what the scale is, with a line about the projection when a scheduled med
    /// drives any plotted curve.
    private var scaleFootnote: String {
        let baseline = tolerancePercentText(ToleranceRow.nearBaselineSeverity * 100)
        if series.contains(where: \.isProjected) {
            return String(localized: "Compared with no tolerance, in the model. The solid line projects your scheduled My Meds doses; the dashed line is the model with no further doses. Under \(baseline) counts as near baseline.")
        }
        return String(localized: "Compared with no tolerance, in the model. The curves assume nothing more is logged. Under \(baseline) counts as near baseline.")
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
                    Text(tolerancePercentText(item.percent(atDay: selectedDay ?? 0)))
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
                // The no-further-doses decay: the main line normally, thin and dashed beneath the
                // projection when a scheduled med feeds this class.
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Days", point.day),
                        y: .value("Tolerance", point.percent),
                        series: .value("Mechanism", "\(String(reflecting: item.id))-decay"),
                    )
                    .foregroundStyle(item.color.opacity(item.isProjected ? Theme.Opacity.dimmed : 1))
                    .lineStyle(item.isProjected
                        ? StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3])
                        : StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                // The projection following the My Meds schedule — the main solid line when present.
                if let projected = item.projectedPoints {
                    ForEach(projected) { point in
                        LineMark(
                            x: .value("Days", point.day),
                            y: .value("Tolerance", point.percent),
                            series: .value("Mechanism", "\(String(reflecting: item.id))-projected"),
                        )
                        .foregroundStyle(item.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }
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
