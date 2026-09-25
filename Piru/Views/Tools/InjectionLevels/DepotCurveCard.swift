import Charts
import SwiftUI

/// The depot serum-level chart: the calibrated curve with its typical-range band,
/// injection ticks, the user's reference lines, and a "now" marker, headed by the
/// zoom menu. Pinch zooms continuously; the menu picks a preset.
///
/// ``DepotCurveCard`` wraps it in the tool's card; ``DepotLevelsSection`` places it
/// bare inside a list row, where the row is already the card; ``HormoneLevelsView``
/// renders the summed serum curve through it. The zoom state is passed as bindings so
/// the chart is decoupled from any one model (Specs/injection-levels-v3.md §2).
struct DepotCurveChart: View {
    let result: DepotCurveResult
    let analyte: Analyte
    var referenceLow: Double?
    var referenceHigh: Double?
    @Binding var chartRange: InjectionLevelsModel.ChartRange
    @Binding var pinchVisibleDays: Double?
    /// Overrides the header (e.g. "Estimated serum estradiol" for the summed curve);
    /// defaults to the Tool's "Estimated <hormone> level".
    var title: LocalizedStringResource?
    /// A citable laboratory reference region shaded behind the curve (the male total-T
    /// range) — a reference, not a target.
    var referenceBand: ClosedRange<Double>?

    /// The visible days at the start of a pinch, so the gesture scales from there.
    @State private var pinchBaseDays: Double?

    private var effectiveVisibleDays: Double? {
        pinchVisibleDays ?? chartRange.days
    }

    /// The whole logged span in days — the pinch's zoomed-out limit.
    private var totalSpanDays: Double {
        result.range.upperBound.timeIntervalSince(result.range.lowerBound) / PKModel.secondsPerDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(title ?? "Estimated \(String(localized: analyte.displayName)) level")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                rangeMenu
            }
            Chart {
                if let referenceBand {
                    RectangleMark(
                        yStart: .value("Reference low", referenceBand.lowerBound),
                        yEnd: .value("Reference high", referenceBand.upperBound),
                    )
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.08))
                }
                ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Low", point.bandLow),
                        yEnd: .value("High", point.bandHigh),
                    )
                    .foregroundStyle(Theme.accent.opacity(Theme.Opacity.tint))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Level", point.level))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(Array(result.injectionDates.enumerated()), id: \.offset) { _, date in
                    RuleMark(x: .value("Injection", date))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let low = referenceLow {
                    RuleMark(y: .value("Reference low", low))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                if let high = referenceHigh {
                    RuleMark(y: .value("Reference high", high))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                RuleMark(x: .value("Now", Date.now))
                    .foregroundStyle(Theme.accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 220)
            .chartYAxisLabel(analyte.canonicalUnit)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                }
            }
            .chartSummaryAccessibility(
                label: Text("Estimated level over time"),
                value: Text(String(localized: "Ranges from about \(Int(result.trough.rounded())) to \(Int(result.peak.rounded())) \(analyte.canonicalUnit) across the cycle")),
            )
            .gesture(pinchZoom)
        }
    }

    /// The zoom presets — a compact menu (the toolbar affordance), matching the
    /// insights charts. Picking one clears any pinch override.
    private var rangeMenu: some View {
        Menu {
            Picker("Range", selection: $chartRange) {
                ForEach(InjectionLevelsModel.ChartRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(chartRange.label)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .onChange(of: chartRange) { pinchVisibleDays = nil }
    }

    /// Pinch to zoom the visible window continuously between one week and the whole
    /// span, overriding the preset until one is tapped again.
    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseDays ?? (effectiveVisibleDays ?? totalSpanDays)
                if pinchBaseDays == nil { pinchBaseDays = base }
                let next = (base / value.magnification).clamped(to: 7 ... max(7, totalSpanDays))
                pinchVisibleDays = next
            }
            .onEnded { _ in pinchBaseDays = nil }
    }
}

/// A legend-less, non-interactive preview of a depot serum curve: the band + line
/// with the user's reference lines and a "now" marker, axis-hidden at a fixed height.
/// The Insights "Hormone Levels" card's inline chart (Specs/injection-levels-v3.md
/// §2.2) — the `usageChart` treatment applied to the depot band, reading the same
/// ``DepotCurveResult`` the full ``DepotCurveChart`` draws so the two never diverge.
struct DepotCurveMiniChart: View {
    let result: DepotCurveResult
    let analyte: Analyte
    var tint: Color = Theme.accent
    var referenceLow: Double?
    var referenceHigh: Double?
    var referenceBand: ClosedRange<Double>?
    var height: CGFloat = 76

    var body: some View {
        Chart {
            if let referenceBand {
                RectangleMark(
                    yStart: .value("Reference low", referenceBand.lowerBound),
                    yEnd: .value("Reference high", referenceBand.upperBound),
                )
                .foregroundStyle(Theme.secondaryLabel.opacity(0.08))
            }
            ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Low", point.bandLow),
                    yEnd: .value("High", point.bandHigh),
                )
                .foregroundStyle(tint.opacity(Theme.Opacity.tint))
                .interpolationMethod(.catmullRom)
            }
            ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("Level", point.level))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let low = referenceLow {
                RuleMark(y: .value("Reference low", low))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let high = referenceHigh {
                RuleMark(y: .value("Reference high", high))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            RuleMark(x: .value("Now", Date.now))
                .foregroundStyle(tint.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
        .accessibilityLabel(Text("Estimated \(String(localized: analyte.displayName)) level over time"))
        .accessibilityValue(Text(String(localized: "About \(Int(result.trough.rounded())) to \(Int(result.peak.rounded())) \(analyte.canonicalUnit) across the cycle")))
    }
}

/// ``DepotCurveChart`` in the Injection Levels tool's card.
struct DepotCurveCard: View {
    @Bindable var model: InjectionLevelsModel
    let result: DepotCurveResult
    let analyte: Analyte
    let referenceLow: Double?
    let referenceHigh: Double?

    var body: some View {
        DepotCurveChart(
            result: result,
            analyte: analyte,
            referenceLow: referenceLow,
            referenceHigh: referenceHigh,
            chartRange: $model.chartRange,
            pinchVisibleDays: $model.pinchVisibleDays,
        )
        .padding()
        .themeCard()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
