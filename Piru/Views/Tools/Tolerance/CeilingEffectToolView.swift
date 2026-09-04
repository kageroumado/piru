import Charts
import SwiftUI

/// The **Ceiling Effect** tool (pharmacology axis, Stage 6). It surfaces the handful of substances
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
                ForEach(SaturablePharmacology.profiles) { profile in
                    Section { card(for: profile) }
                    // The gabapentinoid teaching pair sits right after gabapentin's absorption ceiling:
                    // same α2δ target, opposite dose→exposure behavior (pregabalin is dose-linear, so
                    // it isn't a ceiling profile of its own — it only makes sense as this contrast).
                    if profile.substanceName == "Gabapentin" {
                        Section { gabapentinoidComparisonCard }
                    }
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
            Text("Same class, opposite behavior")
                .cardTitle()
                .accessibilityAddTraits(.isHeader)

            gabapentinoidComparisonChart

            HStack(spacing: Spacing.xxl) {
                comparisonLegend(color: .blue, label: "Gabapentin")
                comparisonLegend(color: .green, label: "Pregabalin")
            }
        }
        .padding(.vertical, Spacing.sm)
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
        let maxMultiple = (allMultiples.max() ?? 5) + 0.3
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
        .chartXScale(domain: 1 ... maxMultiple)
        .chartXAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)×").font(.caption2) }
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
        let windowHours = chart.windowMinutes / 60
        let yMax = (chart.curves.flatMap { $0.points.map(\.level) }.max() ?? 1) * 1.08
        let usesDays = windowHours > 48
        let curves = chart.curves
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Chart {
                ForEach(Array(curves.enumerated()), id: \.element.id) { index, dose in
                    ForEach(dose.points) { point in
                        LineMark(
                            x: .value("Time", point.minutes / 60),
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
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(usesDays ? "\(Int((h / 24).rounded()))d" : "\(Int(h.rounded()))h")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... max(yMax, 1))
            .chartXScale(domain: 0 ... windowHours)
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
        case .elimination: "Saturable elimination — exposure climbs faster than dose"
        case .activation: "Saturable activation — effect hits a ceiling"
        case .absorption: "Saturable absorption — exposure climbs slower than dose"
        }
    }

    /// Whole numbers shown as integers; otherwise one decimal below 10, integer at or above 10.
    private func multipleText(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return "\(Int(value.rounded()))" }
        return value >= 10 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
}
