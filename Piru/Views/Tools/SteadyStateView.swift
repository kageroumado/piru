import SwiftUI

/// Pure steady-state pharmacokinetics for a fixed repeated-dosing schedule.
///
/// Builds on the same one-compartment oral model as the single-dose
/// ``HalfLifeCalculatorView``: it superimposes `PKModel.fractionRemainingInBody`
/// at a fixed interval, so the plateau is the existing curve summed — no new
/// pharmacology. Amounts are in the dose's own units (a body-content mass), which
/// needs no volume of distribution; the accumulation ratio is dimensionless and
/// depends only on the half-life and the interval.
nonisolated enum SteadyStateModel {
    struct Result: Equatable {
        let ke: Double
        let ka: Double
        let dose: Double
        let intervalMinutes: Double
        let halfLifeMinutes: Double

        /// Body-content curve while climbing to plateau, as `(minutes, amount)`.
        let curve: [CurvePoint]
        let totalMinutes: Double

        /// Body content just after / just before a dose at steady state, and the
        /// interval mean — all in the dose's units.
        let peakAmount: Double
        let troughAmount: Double
        let averageAmount: Double

        /// Trough-based accumulation ratio `1/(1 − e^(−ke·τ))` — how many single
        /// doses' worth accumulate. Depends only on half-life and interval.
        let accumulationRatio: Double
        /// Peak-to-trough swing as a percentage of the interval mean.
        let fluctuationPercent: Double

        /// Time to reach ~90% / ~95% / ~97% of steady state (a function of the
        /// half-life alone, not the dose or interval), in minutes.
        let time90: Double
        let time95: Double
        let time97: Double
    }

    struct CurvePoint: Equatable {
        let minutes: Double
        let amount: Double
    }

    /// `nil` when any input is non-positive.
    static func compute(dose: Double, halfLifeMinutes: Double, intervalMinutes: Double, ke: Double, ka: Double) -> Result? {
        guard dose > 0, halfLifeMinutes > 0, intervalMinutes > 0, ke > 0 else { return nil }

        // Fraction-of-steady-state approach depends only on half-life:
        // 1 − 2^(−t/t½). 90% at 3.32·t½, 95% at 4.32·t½, ~97% at 5·t½.
        let time90 = 3.3219 * halfLifeMinutes
        let time95 = 4.3219 * halfLifeMinutes
        let time97 = 5.0 * halfLifeMinutes

        let totalMinutes = max(time97 * 1.2, intervalMinutes * 6, intervalMinutes + 1)
        let doseCount = Int(totalMinutes / intervalMinutes) + 1

        /// Body content = Σ over already-taken doses of dose · fractionRemaining.
        func bodyContent(at t: Double) -> Double {
            var total = 0.0
            for n in 0 ..< doseCount {
                let elapsed = t - Double(n) * intervalMinutes
                if elapsed < 0 { break }
                total += dose * PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            }
            return total
        }

        let sampleCount = 600
        let step = totalMinutes / Double(sampleCount)
        var curve: [CurvePoint] = []
        curve.reserveCapacity(sampleCount + 1)
        for i in 0 ... sampleCount {
            let t = Double(i) * step
            curve.append(CurvePoint(minutes: t, amount: bodyContent(at: t)))
        }

        // Peak / trough over the final full interval (the plateau).
        let ssStart = totalMinutes - intervalMinutes
        var peak = 0.0
        var trough = Double.infinity
        let ssSteps = 240
        for i in 0 ... ssSteps {
            let t = ssStart + intervalMinutes * Double(i) / Double(ssSteps)
            let c = bodyContent(at: t)
            peak = max(peak, c)
            trough = min(trough, c)
        }
        if !trough.isFinite { trough = 0 }
        let average = (peak + trough) / 2
        let fluctuation = average > 0 ? (peak - trough) / average * 100 : 0
        let accumulation = 1 / (1 - exp(-ke * intervalMinutes))

        return Result(
            ke: ke, ka: ka, dose: dose,
            intervalMinutes: intervalMinutes, halfLifeMinutes: halfLifeMinutes,
            curve: curve, totalMinutes: totalMinutes,
            peakAmount: peak, troughAmount: trough, averageAmount: average,
            accumulationRatio: accumulation, fluctuationPercent: fluctuation,
            time90: time90, time95: time95, time97: time97,
        )
    }
}

/// Tools-tab screen estimating where a med taken on a fixed schedule settles.
///
/// Sibling to ``HalfLifeCalculatorView`` (single dose); reachable via
/// `PushRoute.tool(.steadyState)`. Reuses the same half-life resolution and
/// `PKModel` parameters, then projects a repeated schedule to its plateau.
struct SteadyStateView: View {
    @State private var substanceName = ""
    @State private var selectedSubstance: Substance?
    @State private var doseAmount: Double? = 20
    @State private var doseUnit: String = "mg"
    @State private var intervalHours: Double? = 24
    @State private var useCustomHalfLife = false
    @State private var customHalfLifeHours: Double?
    @State private var selectedRoute: RouteOfAdministration = .oral

    private var effectiveHalfLife: Double? {
        if useCustomHalfLife {
            guard let hours = customHalfLifeHours, hours > 0 else { return nil }
            return hours * 60
        }
        if let hl = selectedSubstance?.halfLifeMinutes { return hl }
        return HalfLifeDatabase.halfLife(for: substanceName)
    }

    private var pkParameters: (ke: Double, ka: Double)? {
        guard let halfLife = effectiveHalfLife, halfLife > 0 else { return nil }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        if let substance = selectedSubstance,
           let duration = substance.resolveDuration(for: selectedRoute) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            if timeToPeak > 0 {
                return (ke, PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke))
            }
        }
        return (ke, PKModel.defaultKa(ke: ke))
    }

    private var dose: Double {
        doseAmount ?? 0
    }

    private var steadyState: SteadyStateModel.Result? {
        guard let halfLife = effectiveHalfLife,
              let params = pkParameters,
              let hours = intervalHours, hours > 0, dose > 0 else { return nil }
        return SteadyStateModel.compute(
            dose: dose, halfLifeMinutes: halfLife, intervalMinutes: hours * 60,
            ke: params.ke, ka: params.ka,
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inputSection

                if let result = steadyState {
                    chartCard(result)
                    metricsCard(result)
                } else if selectedSubstance != nil, !useCustomHalfLife, selectedSubstance?.halfLifeMinutes == nil {
                    noDataCard
                }

                explanationCard
                relatedLinks
            }
            .padding()
        }
        .background(Theme.background)
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On a fixed schedule, each dose lands on the tail of the last and the level climbs until intake and clearance balance — steady state.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Values are body content in the dose's units, not a plasma concentration. Real accumulation varies with metabolism, dosing gaps, and metabolites.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SubstanceSearchField(text: $substanceName) { substance, _ in
                selectedSubstance = substance
                substanceName = substance.name
                doseUnit = substance.defaultUnit
                selectedRoute = substance.defaultRoute
            }

            if let sub = selectedSubstance, sub.routes.count > 1 {
                Picker("Route", selection: $selectedRoute) {
                    ForEach(sub.routes.map(\.route)) { r in
                        Text(r.displayName).tag(r)
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Dose each time")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 0) {
                        TextField("Amount", value: $doseAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(8)
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(["mg", "g", "µg", "mL", "IU", "drops", "puffs"], id: \.self) { u in
                                Button(u) { doseUnit = u }
                            }
                        } label: {
                            Text(doseUnit)
                                .padding(8)
                                .foregroundStyle(.primary)
                        }
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading) {
                    Text("Taken every")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 0) {
                        TextField("Hours", value: $intervalHours, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(8)
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(intervalPresets, id: \.hours) { preset in
                                Button(preset.label) { intervalHours = preset.hours }
                            }
                        } label: {
                            Image(systemName: "clock")
                                .padding(8)
                                .foregroundStyle(.primary)
                        }
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Toggle("Custom half-life", isOn: $useCustomHalfLife)
            if useCustomHalfLife {
                HStack {
                    TextField("Hours", value: $customHalfLifeHours, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("hours")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .padding()
        .themeCard()
    }

    private var intervalPresets: [(label: String, hours: Double)] {
        [
            (String(localized: "Every 4 hours"), 4),
            (String(localized: "Every 6 hours"), 6),
            (String(localized: "Every 8 hours"), 8),
            (String(localized: "Every 12 hours"), 12),
            (String(localized: "Once daily"), 24),
            (String(localized: "Twice daily"), 12),
            (String(localized: "Weekly"), 168),
        ]
    }

    // MARK: - Chart

    private func chartCard(_ r: SteadyStateModel.Result) -> some View {
        SteadyStateChart(result: r, unit: doseUnit)
            .frame(height: 230)
            .padding()
            .themeCard()
    }

    // MARK: - Metrics

    private func metricsCard(_ r: SteadyStateModel.Result) -> some View {
        let peakMultiple = r.dose > 0 ? r.peakAmount / r.dose : 1
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile(
                key: String(localized: "Steady state by"),
                value: formatDays(r.time95 / 1_440),
                sub: String(localized: "fully settled in \(formatDays(r.time97 / 1_440))"),
            )
            metricTile(
                key: String(localized: "Accumulation"),
                value: formatMultiple(peakMultiple),
                sub: String(localized: "at the peak, vs. one dose"),
            )
            metricTile(
                key: String(localized: "Plateau range"),
                value: "\(r.troughAmount.doseFormatted)–\(r.peakAmount.doseFormatted)",
                sub: String(localized: "\(doseUnit) · trough to peak"),
            )
            metricTile(
                key: String(localized: "Fluctuation"),
                value: "\(Int(r.fluctuationPercent.rounded()))%",
                sub: fluctuationLabel(r.fluctuationPercent),
            )
        }
        .padding()
        .themeCard()
    }

    private func metricTile(key: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(sub)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - No data / disclaimer / links

    private var noDataCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Half-life data not available for \(selectedSubstance?.name ?? "this substance").")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
            Button {
                useCustomHalfLife = true
            } label: {
                Label("Use Custom Half-Life", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themeCard()
    }

    private var relatedLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, 4)

            GlanceCard(icon: "hourglass", title: Text("Half-Life Calculator"), route: .tool(.calculator)) {
                Text("Model a single dose's decay over time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            GlanceCard(icon: "hourglass", title: Text("In Your System"), route: .insight(.inSystem)) {
                Text("See what's active in your body right now")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - Formatting

    /// A number followed by the locale-invariant multiplication sign — no
    /// catalog key needed.
    private func formatMultiple(_ m: Double) -> String {
        "\(m.formatted(.number.precision(.fractionLength(1))))×"
    }

    private func formatDays(_ days: Double) -> String {
        if days < 1 {
            let h = Int((days * 24).rounded())
            return String(localized: "\(h) hours")
        }
        return String(localized: "\(Int(days.rounded())) days")
    }

    private func fluctuationLabel(_ pct: Double) -> String {
        if pct < 40 { return String(localized: "smooth") }
        if pct < 120 { return String(localized: "moderate swing") }
        return String(localized: "spiky")
    }
}

/// The climbing-to-plateau body-content curve, with the steady-state band, the
/// single-dose reference line, and a "steady state reached" marker.
private struct SteadyStateChart: View {
    let result: SteadyStateModel.Result
    let unit: String

    var body: some View {
        Canvas { context, size in
            let r = result
            guard !r.curve.isEmpty else { return }

            let leftPad: CGFloat = 40
            let rightPad: CGFloat = 12
            let topPad: CGFloat = 14
            let labelArea: CGFloat = 24
            let plotW = size.width - leftPad - rightPad
            let plotH = size.height - topPad - labelArea
            guard plotW > 0, plotH > 0 else { return }

            let xMax = r.totalMinutes
            let peak = r.curve.map(\.amount).max() ?? r.peakAmount
            let yMax = max(peak * 1.12, r.dose * 1.25, 0.0001)
            let baseline = topPad + plotH

            func x(_ minutes: Double) -> CGFloat {
                leftPad + CGFloat(minutes / xMax) * plotW
            }
            func y(_ amount: Double) -> CGFloat {
                topPad + plotH - CGFloat(amount / yMax) * plotH
            }

            // Peak / trough guide lines — the only reference marks the graph keeps.
            let peakY = y(r.peakAmount)
            let troughY = y(r.troughAmount)
            for guideY in [peakY, troughY] {
                var line = Path()
                line.move(to: CGPoint(x: leftPad, y: guideY))
                line.addLine(to: CGPoint(x: leftPad + plotW, y: guideY))
                context.stroke(line, with: .color(Theme.accent.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            // Curve fill + stroke.
            var fill = Path()
            fill.move(to: CGPoint(x: x(0), y: baseline))
            var stroke = Path()
            for (i, point) in r.curve.enumerated() {
                let px = x(point.minutes)
                let py = y(point.amount)
                fill.addLine(to: CGPoint(x: px, y: py))
                if i == 0 { stroke.move(to: CGPoint(x: px, y: py)) } else { stroke.addLine(to: CGPoint(x: px, y: py)) }
            }
            fill.addLine(to: CGPoint(x: x(r.curve.last?.minutes ?? xMax), y: baseline))
            fill.closeSubpath()
            context.fill(fill, with: .color(Theme.accent.opacity(0.12)))
            context.stroke(stroke, with: .color(Theme.accent), lineWidth: 2.2)

            // Axis frame.
            var axes = Path()
            axes.move(to: CGPoint(x: leftPad, y: topPad))
            axes.addLine(to: CGPoint(x: leftPad, y: baseline))
            axes.addLine(to: CGPoint(x: leftPad + plotW, y: baseline))
            context.stroke(axes, with: .color(Theme.secondaryLabel.opacity(0.35)), lineWidth: 1)

            // Peak / trough values (numbers only), as y-axis readings.
            let valueFont = Font.system(size: 11, weight: .semibold, design: .rounded)
            for (value, atY) in [(r.peakAmount, peakY), (r.troughAmount, troughY)] {
                let text = context.resolve(Text(value.doseFormatted).font(valueFont).foregroundStyle(Theme.accent))
                context.draw(text, at: CGPoint(x: leftPad - 6, y: atY), anchor: .trailing)
            }

            // Y-axis label (the unit) at the top of the axis.
            let yTitle = context.resolve(
                Text(unit).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.secondaryLabel),
            )
            context.draw(yTitle, at: CGPoint(x: leftPad, y: topPad - 8), anchor: .center)

            // X-axis ticks + label.
            let useDays = xMax > 2 * 1_440
            let unitMinutes: Double = useDays ? 1_440 : 60
            let span = xMax / unitMinutes
            let stepUnits = niceStep(span, targetTicks: 5)
            let axisLabelWidth: CGFloat = 34
            var tickValue = stepUnits
            while tickValue * unitMinutes <= xMax {
                let tx = x(tickValue * unitMinutes)
                if tx < leftPad + plotW - axisLabelWidth {
                    let label = tickValue < 10 && tickValue.truncatingRemainder(dividingBy: 1) != 0
                        ? String(format: "%.1f", tickValue)
                        : String(Int(tickValue.rounded()))
                    let text = context.resolve(
                        Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondaryLabel),
                    )
                    context.draw(text, at: CGPoint(x: tx, y: baseline + labelArea / 2 + 2), anchor: .center)
                }
                tickValue += stepUnits
            }
            let axisLabel = context.resolve(
                Text(useDays ? "days" : "hours").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.secondaryLabel),
            )
            context.draw(axisLabel, at: CGPoint(x: leftPad + plotW, y: baseline + labelArea / 2 + 2), anchor: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Level over time"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        let summary = String(
            localized: "Climbs from one dose to a steady-state range of \(result.troughAmount.doseFormatted) to \(result.peakAmount.doseFormatted) \(unit), reached in about \(Int((result.time95 / 1_440).rounded())) days",
        )
        return Text(summary)
    }

    /// A 1/2/5·10ⁿ step covering `span` in roughly `targetTicks` ticks.
    private func niceStep(_ span: Double, targetTicks: Int) -> Double {
        guard span > 0 else { return 1 }
        let raw = span / Double(targetTicks)
        let magnitude = pow(10, floor(log10(raw)))
        let norm = raw / magnitude
        let stepNorm: Double = norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10
        return stepNorm * magnitude
    }
}
