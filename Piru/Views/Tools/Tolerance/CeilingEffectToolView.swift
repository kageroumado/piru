import Charts
import SwiftUI

/// The **Ceiling Effect** tool. It surfaces the handful of substances
/// whose kinetics are *non-linear* — where doubling the dose does not double the exposure — using the
/// curated ``SaturablePharmacology`` profiles and the ``PKModel/saturableCurve`` integrator.
///
/// ## What it shows
/// Each substance is one card: name and mechanism, a concentration-over-time chart with one curve per
/// example dose where clean human kinetics exist (alcohol's saturable elimination, gabapentin's
/// saturable absorption), and one short paragraph carrying what the chart cannot show — the enzyme
/// or carrier that saturates and the genetics or co-ingestants that move the ceiling. Codeine, tramadol
/// and GHB ship words only, because a drawn curve would imply precision the evidence lacks. The
/// gabapentin card is followed by the gabapentinoid contrast (gabapentin's falling bioavailability
/// against pregabalin's flat one), and every citation sits in a Sources section at the bottom.
struct CeilingEffectToolView: View {
    @State private var profile = UserProfileStore.shared
    /// Concentration-time charts keyed by substance name, recomputed when body weight changes (off the
    /// render path — each integrates the saturable ODE for every example dose).
    @State private var charts: [String: SaturablePharmacology.ConcentrationChart] = [:]

    var body: some View {
        List {
            Group {
                aboutSection
                let profiles = ProfileRun(SaturablePharmacology.profiles)
                ForEach(profiles.throughGabapentin) { profile in
                    Section { card(for: profile) }
                }
                // The gabapentinoid teaching pair sits right after gabapentin's absorption ceiling:
                // same α2δ target, opposite dose→exposure behavior (pregabalin is dose-linear, so
                // it isn't a ceiling profile of its own — it only makes sense as this contrast).
                // It stays outside the profiles' ForEach: two Sections from one element share
                // that element's id, which a lazy list on Android rejects as a duplicate key.
                if profiles.hasGabapentin {
                    Section { gabapentinoidComparisonCard }
                }
                ForEach(profiles.afterGabapentin) { profile in
                    Section { card(for: profile) }
                }
                sourcesSection
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .appNavigationBar("Ceiling Effect")
        .task(id: profile.effectiveWeightKg) { recomputeCurves() }
    }

    private func recomputeCurves() {
        let weight = profile.effectiveWeightKg
        var result: [String: SaturablePharmacology.ConcentrationChart] = [:]
        for p in SaturablePharmacology.profiles {
            if let k = p.kinetics, let chart = SaturablePharmacology.concentrationChart(for: k, weightKg: weight) {
                result[p.substanceName] = chart
            } else if let a = p.absorption, let chart = SaturablePharmacology.absorptionChart(for: a, weightKg: weight) {
                result[p.substanceName] = chart
            }
        }
        charts = result
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("When dose and effect aren't proportional", systemImage: "chart.line.uptrend.xyaxis")
                    .sectionLabel()
                Text("For most substances, twice the dose is roughly twice the exposure. For these, an enzyme or carrier runs out of capacity: exposure climbs faster than the dose, or an effect stops climbing. Estimates only.")
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - Card

    private func card(for sub: SaturablePharmacology.Profile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header(for: sub)
            if let chart = charts[sub.substanceName] {
                concentrationChart(chart, tint: tint(for: sub))
            }
            Text(sub.detail)
                .captionSecondary()
        }
        .padding(.vertical, Spacing.sm)
    }

    private func header(for sub: SaturablePharmacology.Profile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(sub.displayName)
                .cardTitle()
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.sm) {
                Image(systemName: mechanismIcon(sub.mechanism))
                    .font(.caption2)
                    .foregroundStyle(tint(for: sub))
                    .accessibilityHidden(true)
                Text(mechanismLabel(sub.mechanism))
                    .captionSecondary()
            }
        }
    }

    // MARK: - Gabapentinoid comparison card

    private var gabapentinoidComparisonCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Same class, opposite behavior")
                    .cardTitle()
                    .accessibilityAddTraits(.isHeader)
                Text("Share of the dose absorbed")
                    .captionSecondary()
            }

            gabapentinoidComparisonChart

            HStack(spacing: Spacing.xxl) {
                comparisonLegend(color: .blue, label: "Gabapentin")
                comparisonLegend(color: .green, label: "Pregabalin")
            }

            if let gabaBase = comparisonBase(SaturablePharmacology.GabapentinoidComparison.gabapentin),
               let preBase = comparisonBase(SaturablePharmacology.GabapentinoidComparison.pregabalin) {
                Text("Daily dose, in multiples of the lowest one measured: \(gabaBase) mg gabapentin, \(preBase) mg pregabalin.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// The lowest daily dose on a drug's line, the dose its "1×" stands for, as whole milligrams.
    private func comparisonBase(_ points: [SaturablePharmacology.GabapentinoidComparison.Point]) -> String? {
        points.map(\.doseMgPerDay).min().map { $0.formatted(.number.precision(.fractionLength(0))) }
    }

    /// Bioavailability (%) vs dose, normalized to each drug's starting dose so the *shape* contrast —
    /// gabapentin's saturating decline vs pregabalin's flat line — reads on a shared x-axis despite the
    /// two being dosed at very different milligrams.
    private var gabapentinoidComparisonChart: some View {
        let gaba = SaturablePharmacology.GabapentinoidComparison.gabapentin
        let pre = SaturablePharmacology.GabapentinoidComparison.pregabalin
        let gabaBase = gaba.map(\.doseMgPerDay).min() ?? 900
        let preBase = pre.map(\.doseMgPerDay).min() ?? 150
        let allMultiples = gaba.map { $0.doseMgPerDay / gabaBase } + pre.map { $0.doseMgPerDay / preBase }
        let doseTicks = CeilingChartScale.wholeMultiples(from: 1, through: (allMultiples.max() ?? 5).rounded(.up))
        return Chart {
            ForEach(gaba) { p in
                LineMark(
                    x: .value("Dose", p.doseMgPerDay / gabaBase),
                    y: .value("Bioavailability", p.bioavailabilityPct),
                    series: .value("Drug", "Gabapentin"),
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Dose", p.doseMgPerDay / gabaBase),
                    y: .value("Bioavailability", p.bioavailabilityPct),
                )
                .foregroundStyle(.blue)
                .symbolSize(36)
            }
            ForEach(pre) { p in
                LineMark(
                    x: .value("Dose", p.doseMgPerDay / preBase),
                    y: .value("Bioavailability", p.bioavailabilityPct),
                    series: .value("Drug", "Pregabalin"),
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Dose", p.doseMgPerDay / preBase),
                    y: .value("Bioavailability", p.bioavailabilityPct),
                )
                .foregroundStyle(.green)
                .symbolSize(36)
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)%").font(.caption2) }
                }
            }
        }
        .chartXScale(domain: 1 ... (doseTicks.last ?? 5))
        .chartXAxis {
            AxisMarks(values: doseTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(centered: false, anchor: axisTickLabelAnchor(index: value.index, count: value.count)) {
                    if let v = value.as(Double.self) { Text("\(Int(v))×").font(.caption2) }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 160)
        .accessibilityLabel("Bioavailability versus dose: gabapentin falls as the dose rises, pregabalin stays flat.")
    }

    private func comparisonLegend(color: Color, label: LocalizedStringResource) -> some View {
        HStack(spacing: Spacing.xs) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: 3)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        Section("Sources") {
            ForEach(SaturablePharmacology.profiles) { sub in
                sourceRow(label: sub.displayName, citation: sub.citation)
            }
            sourceRow(label: "Same class, opposite behavior", citation: SaturablePharmacology.GabapentinoidComparison.citation)
        }
    }

    private func sourceRow(label: LocalizedStringResource, citation: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.caption)
            Text(citation)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Quantitative chart (concentration over time, one curve per example dose)

    private func concentrationChart(_ chart: SaturablePharmacology.ConcentrationChart, tint: Color) -> some View {
        let curves = chart.curves
        let time = CeilingChartScale.timeTicks(windowMinutes: chart.windowMinutes)
        let peak = curves.flatMap { $0.points.map(\.level) }.max() ?? 1
        let levelTicks = CeilingChartScale.wholeMultiples(from: 1, through: peak.rounded(.down))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if let reference = curves.first {
                Text("Blood level, in multiples of the peak after \(String(localized: reference.label))")
                    .captionSecondary()
            }
            Chart {
                ForEach(Array(curves.enumerated()), id: \.element.id) { index, dose in
                    ForEach(dose.points.filter { $0.minutes <= time.endMinutes }) { point in
                        LineMark(
                            x: .value("Time", point.minutes / time.unitMinutes),
                            y: .value("Level", point.level),
                            series: .value("Dose", dose.doseMultiple),
                        )
                        .foregroundStyle(curveColor(tint, index: index, count: curves.count))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: time.ticks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel(centered: false, anchor: axisTickLabelAnchor(index: value.index, count: value.count)) {
                        if let count = value.as(Double.self) {
                            Text(time.usesDays ? "\(Int(count))d" : "\(Int(count))h")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0] + levelTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let multiple = value.as(Double.self), multiple > 0 {
                            Text("\(Int(multiple))×").font(.caption2)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... max(peak * 1.08, levelTicks.last ?? 1))
            .chartXScale(domain: 0 ... (time.ticks.last ?? 1))
            .chartLegend(.hidden)
            .frame(height: 170)
            .chartSummaryAccessibility(
                label: Text("Concentration over time"),
                value: Text("\(curves.count) doses plotted; the largest reaches about \(multipleText(chart.exposureMultipleAtMax))× the total exposure of one reference dose."),
            )

            doseLegend(curves: curves, tint: tint)
        }
    }

    /// A sequential shade ramp — lightest for the smallest dose, full tint for the largest.
    private func curveColor(_ tint: Color, index: Int, count: Int) -> Color {
        guard count > 1 else { return tint }
        let t = Double(index) / Double(count - 1)
        return tint.opacity(0.45 + 0.55 * t)
    }

    private func doseLegend(curves: [SaturablePharmacology.DoseCurve], tint: Color) -> some View {
        HStack(spacing: Spacing.xl) {
            ForEach(Array(curves.enumerated()), id: \.element.id) { index, dose in
                HStack(spacing: Spacing.xs) {
                    Capsule()
                        .fill(curveColor(tint, index: index, count: curves.count))
                        .frame(width: 14, height: 3)
                    Text(dose.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tint(for sub: SaturablePharmacology.Profile) -> Color {
        // Elimination is the danger (supralinear); activation is the relatively-safer effect ceiling;
        // absorption is the benign sublinear brake (extra drug just isn't absorbed).
        switch sub.mechanism {
        case .elimination: .orange
        case .activation: .teal
        case .absorption: .blue
        }
    }

    private func mechanismIcon(_ mechanism: SaturablePharmacology.Mechanism) -> String {
        switch mechanism {
        case .elimination: "chart.line.uptrend.xyaxis"
        case .activation: "chart.line.flattrend.xyaxis"
        case .absorption: "chart.line.downtrend.xyaxis"
        }
    }

    private func mechanismLabel(_ mechanism: SaturablePharmacology.Mechanism) -> LocalizedStringResource {
        switch mechanism {
        case .elimination: "Saturable elimination: exposure climbs faster than dose"
        case .activation: "Saturable activation: effect hits a ceiling"
        case .absorption: "Saturable absorption: exposure climbs slower than dose"
        }
    }

    /// Whole numbers shown as integers; otherwise one decimal below 10, integer at or above 10.
    private func multipleText(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return "\(Int(value.rounded()))" }
        return value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
}

/// The profiles split at gabapentin, so the gabapentinoid comparison can follow its card.
private struct ProfileRun {
    let throughGabapentin: [SaturablePharmacology.Profile]
    let afterGabapentin: [SaturablePharmacology.Profile]

    var hasGabapentin: Bool {
        throughGabapentin.last?.substanceName == "Gabapentin"
    }

    init(_ profiles: [SaturablePharmacology.Profile]) {
        let split = profiles.firstIndex { $0.substanceName == "Gabapentin" }.map { $0 + 1 } ?? profiles.count
        throughGabapentin = Array(profiles[..<split])
        afterGabapentin = Array(profiles[split...])
    }
}

/// Tick choices for the Ceiling Effect charts.
nonisolated enum CeilingChartScale {
    /// Most labels a multiples axis prints, so neighbors stay apart at phone width.
    private static let maxMultipleLabels = 6

    /// Whole multiples from `first` to at least `last`: `first`, then every multiple of the smallest
    /// step (1, 2, 5, 10…) that keeps the labels to six, ending on the first one at or past `last`.
    static func wholeMultiples(from first: Int, through last: Double) -> [Double] {
        let target = max(Double(first), last)
        var ticks: [Int] = []
        for step in [1, 2, 5, 10, 20, 50, 100] {
            let end = Int((target / Double(step)).rounded(.up)) * step
            ticks = [first] + stride(from: step, through: end, by: step).filter { $0 > first }
            if ticks.count <= maxMultipleLabels { break }
        }
        return ticks.map(Double.init)
    }

    /// The time ticks of a concentration chart: a count per tick in one unit, hours or days.
    struct TimeTicks: Equatable {
        /// Tick positions, in the axis's unit, from 0.
        let ticks: [Double]
        let usesDays: Bool

        /// Minutes in one unit of the axis.
        var unitMinutes: Double {
            usesDays ? 1_440 : 60
        }

        /// The end of the axis: the last tick, in minutes.
        var endMinutes: Double {
            (ticks.last ?? 0) * unitMinutes
        }
    }

    /// Round ticks across a window of `windowMinutes` from the dose, ending on the last whole step
    /// inside the window so the final gridline is the labeled end of the plot.
    static func timeTicks(windowMinutes: Double) -> TimeTicks {
        let axis = ToleranceChartScale.timeAxis(spanDays: windowMinutes / 1_440)
        let usesDays = axis.unit != .hours
        let unitMinutes: Double = usesDays ? 1_440 : 60
        let step = Double(axis.step) * axis.unit.days * 1_440 / unitMinutes
        let whole = max(1, ((windowMinutes / unitMinutes) / step + 1e-9).rounded(.down))
        return TimeTicks(ticks: (0 ... Int(whole)).map { Double($0) * step }, usesDays: usesDays)
    }
}
