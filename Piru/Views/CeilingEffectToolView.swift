import Charts
import SwiftUI

/// The **Ceiling Effect** tool (pharmacology axis, Stage 6). It surfaces the handful of substances
/// whose kinetics are *non-linear* — where doubling the dose does not double the exposure — using the
/// curated ``SaturablePharmacology`` seed and the ``PKModel/saturableCurve`` integrator.
///
/// ## What it shows
/// - **Saturable elimination** (ethanol, phenytoin): a dose→exposure chart whose modeled curve bends
///   *up* away from a dashed proportional reference — the supralinear warning. Drawn only where clean
///   human Km/Vmax exist.
/// - **Saturable activation / qualitative** (codeine, GHB): a knee + direction in words, with no curve,
///   because a drawn curve would imply precision the evidence doesn't support (codeine's ceiling is
///   phenotype-limited; GHB has no clean human Km/Vmax).
///
/// Every figure is badged ``ConfidenceTier`` and the chart is labeled *relative shape, not absolute
/// concentration* — the house rule is "predicted (model, confidence)", never "measured".
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
                    // same α2δ target, opposite dose→exposure behaviour (pregabalin is dose-linear, so
                    // it isn't a ceiling profile of its own — it only makes sense as this contrast).
                    if profile.substanceName == "Gabapentin" {
                        Section { gabapentinoidComparisonCard }
                    }
                }
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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
            VStack(alignment: .leading, spacing: 8) {
                Label("When dose and effect aren't proportional", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                Text("For most substances, twice the dose means roughly twice the exposure. For these few, an enzyme runs out of capacity — so exposure can climb much faster than the dose (a warning), or an effect can stop climbing entirely (a ceiling). Shapes are model predictions, relative — not absolute concentrations.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                if profile.isWeightEstimated {
                    Label("Based on an estimated \(Int(UserProfileStore.defaultWeightKg)) kg body weight — set yours in Settings for accuracy.", systemImage: "scalemass")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Card

    private func card(for sub: SaturablePharmacology.Profile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(for: sub)

            if sub.isQuantitative, let chart = charts[sub.substanceName] {
                concentrationChart(chart, tint: tint(for: sub))
                exposureReadout(chart, for: sub)
            } else {
                qualitativeMarker(for: sub)
            }

            Text(sub.headline)
                .font(.subheadline.weight(.medium))

            Label {
                Text(sub.knee).font(.caption).foregroundStyle(Theme.secondaryLabel)
            } icon: {
                Image(systemName: "arrow.turn.right.up").foregroundStyle(tint(for: sub))
            }

            Text(sub.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            Text(sub.citation)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private func header(for sub: SaturablePharmacology.Profile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sub.displayName)
                    .font(.headline)
                Spacer()
                ConfidenceBadge(tier: sub.confidence)
            }
            HStack(spacing: 6) {
                Image(systemName: mechanismIcon(sub.mechanism))
                    .font(.caption2)
                    .foregroundStyle(tint(for: sub))
                Text(mechanismLabel(sub.mechanism))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - Gabapentinoid comparison card

    private var gabapentinoidComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Same class, opposite behavior")
                    .font(.headline)
                Spacer()
                ConfidenceBadge(tier: .high)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Gabapentin vs pregabalin — one absorbing target, two opposite dose curves")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            gabapentinoidComparisonChart

            HStack(spacing: 16) {
                comparisonLegend(color: .blue, label: "Gabapentin — falls with dose")
                comparisonLegend(color: .green, label: "Pregabalin — flat ~90%")
            }
            Text("Fraction reaching your blood (up the side) against dose (along the bottom, as a multiple of the usual starting dose).")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)

            Text(SaturablePharmacology.GabapentinoidComparison.headline)
                .font(.subheadline.weight(.medium))
            Text(SaturablePharmacology.GabapentinoidComparison.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text(SaturablePharmacology.GabapentinoidComparison.citation)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    /// Bioavailability (%) vs dose, normalized to each drug's starting dose so the *shape* contrast —
    /// gabapentin's saturating decline vs pregabalin's flat line — reads on a shared x-axis despite the
    /// two being dosed at very different milligrams.
    private var gabapentinoidComparisonChart: some View {
        let gaba = SaturablePharmacology.GabapentinoidComparison.gabapentin
        let pre = SaturablePharmacology.GabapentinoidComparison.pregabalin
        let gabaBase = gaba.first?.doseMgPerDay ?? 900
        let preBase = pre.first?.doseMgPerDay ?? 150
        let maxMultiple = (gaba.map { $0.doseMgPerDay / gabaBase }.max() ?? 5) + 0.3
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
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: 3)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Quantitative chart (concentration over time, one curve per example dose)

    private func concentrationChart(_ chart: SaturablePharmacology.ConcentrationChart, tint: Color) -> some View {
        let windowHours = chart.windowMinutes / 60
        let yMax = (chart.curves.flatMap { $0.points.map(\.level) }.max() ?? 1) * 1.08
        let usesDays = windowHours > 48
        let curves = chart.curves
        return VStack(alignment: .leading, spacing: 6) {
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

            doseLegend(curves: curves, tint: tint)
            Text(
                usesDays
                    ? "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in days."
                    : "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in hours.",
            )
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// A sequential shade ramp — lightest for the smallest dose, full tint for the largest.
    private func curveColor(_ tint: Color, index: Int, count: Int) -> Color {
        guard count > 1 else { return tint }
        let t = Double(index) / Double(count - 1)
        return tint.opacity(0.45 + 0.55 * t)
    }

    private func doseLegend(curves: [SaturablePharmacology.DoseCurve], tint: Color) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(curves.enumerated()), id: \.element.id) { index, dose in
                HStack(spacing: 4) {
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

    private func exposureReadout(_ chart: SaturablePharmacology.ConcentrationChart, for sub: SaturablePharmacology.Profile) -> some View {
        let dose = multipleText(chart.maxDoseMultiple)
        let exposure = multipleText(chart.exposureMultipleAtMax)
        let isAbsorption = sub.mechanism == .absorption
        return Text(
            isAbsorption
                ? "\(dose)× the dose is only about \(exposure)× the exposure — past the knee, extra drug mostly isn't absorbed."
                : "\(dose)× the dose isn't \(dose)× the exposure — the largest curve here holds about \(exposure)× the total exposure of one reference dose.",
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(isAbsorption ? .blue : .orange)
    }

    // MARK: - Qualitative marker

    private func qualitativeMarker(for sub: SaturablePharmacology.Profile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sub.mechanism == .activation ? "arrow.up.forward.circle" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(tint(for: sub))
            Text(
                sub.mechanism == .activation
                    ? "Ceiling on effect — described, not drawn (no precise dose knee)."
                    : "Steep, supralinear — described, not drawn (no reliable human kinetics).",
            )
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint(for: sub).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
