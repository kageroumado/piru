import SwiftUI

/// Tools-tab screen estimating where a med taken on a fixed schedule settles.
///
/// Sibling to ``HalfLifeCalculatorView`` (single dose); reachable via
/// `PushRoute.tool(.steadyState)`. Reuses the same half-life resolution and
/// `PKModel` parameters, then projects a repeated schedule to its plateau.
struct SteadyStateView: View {
    @State private var inputs = SteadyStateInputs()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SteadyStateInputSection(inputs: inputs)

                if let result = inputs.result {
                    SteadyStateChartCard(result: result, unit: inputs.doseUnit)
                    SteadyStateMetricsCard(result: result, unit: inputs.doseUnit)
                } else if inputs.isMissingHalfLife {
                    SteadyStateNoDataCard(substanceName: inputs.selectedSubstance?.name) {
                        inputs.useCustomHalfLife = true
                    }
                }

                SteadyStateExplanationCard()
                SteadyStateRelatedLinks()
            }
            .padding()
        }
        .background(Theme.background)
        .onChange(of: inputs.recomputeKey) { inputs.refresh() }
    }
}

// MARK: - Explanation

private struct SteadyStateExplanationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("On a fixed schedule doses overlap and the level climbs until intake and clearance balance: steady state.")
                .captionSecondary()
            Text("Values are body content in the dose's units.")
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

// MARK: - Input

private struct SteadyStateInputSection: View {
    @Bindable var inputs: SteadyStateInputs

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SubstanceSearchField(text: $inputs.substanceName) { substance, _ in
                inputs.select(substance)
            }

            if let sub = inputs.selectedSubstance, sub.routes.count > 1 {
                Picker("Route", selection: $inputs.selectedRoute) {
                    ForEach(sub.routes.map(\.route)) { r in
                        Text(r.displayName).tag(r)
                    }
                }
            }

            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading) {
                    Text("Dose each time")
                        .captionSecondary()
                    HStack(spacing: 0) {
                        TextField("Amount", value: $inputs.doseAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(Spacing.md)
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(["mg", "g", "µg", "mL", "IU", "drops", "puffs"], id: \.self) { u in
                                Button(u) { inputs.doseUnit = u }
                            }
                        } label: {
                            Text(inputs.doseUnit)
                                .padding(Spacing.md)
                                .foregroundStyle(.primary)
                        }
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
                }

                VStack(alignment: .leading) {
                    Text("Taken every")
                        .captionSecondary()
                    HStack(spacing: 0) {
                        TextField("Hours", value: $inputs.intervalHours, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(Spacing.md)
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(intervalPresets, id: \.hours) { preset in
                                Button(preset.label) { inputs.intervalHours = preset.hours }
                            }
                        } label: {
                            Image(systemName: "clock")
                                .padding(Spacing.md)
                                .foregroundStyle(.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
                }
            }

            Toggle("Custom half-life", isOn: $inputs.useCustomHalfLife)
            if inputs.useCustomHalfLife {
                HStack {
                    TextField("Hours", value: $inputs.customHalfLifeHours, format: .number)
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
}

// MARK: - Chart

private struct SteadyStateChartCard: View {
    let result: SteadyStateModel.Result
    let unit: String

    var body: some View {
        SteadyStateChart(result: result, unit: unit)
            .frame(height: 230)
            .padding()
            .themeCard()
    }
}

// MARK: - Metrics

private struct SteadyStateMetricsCard: View {
    let result: SteadyStateModel.Result
    let unit: String

    private var peakMultiple: Double {
        result.dose > 0 ? result.peakAmount / result.dose : 1
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xl) {
            SteadyStateMetricTile(
                key: String(localized: "Steady state by"),
                value: formatDays(result.time95 / 1_440),
                sub: String(localized: "fully settled in \(formatDays(result.time97 / 1_440))"),
            )
            SteadyStateMetricTile(
                key: String(localized: "Accumulation"),
                value: formatMultiple(peakMultiple),
                sub: String(localized: "at the peak, vs. one dose"),
            )
            SteadyStateMetricTile(
                key: String(localized: "Plateau range"),
                value: "\(result.troughAmount.doseFormatted)–\(result.peakAmount.doseFormatted)",
                sub: String(localized: "\(unit) · trough to peak"),
            )
            SteadyStateMetricTile(
                key: String(localized: "Fluctuation"),
                value: "\(Int(result.fluctuationPercent.rounded()))%",
                sub: fluctuationLabel(result.fluctuationPercent),
            )
        }
        .padding()
        .themeCard()
    }

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

private struct SteadyStateMetricTile: View {
    let key: String
    let value: String
    let sub: String

    var body: some View {
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
        .padding(Spacing.xl)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }
}

// MARK: - No data / links

private struct SteadyStateNoDataCard: View {
    let substanceName: String?
    let onUseCustomHalfLife: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .accessibilityHidden(true)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Half-life data not available for \(substanceName ?? "this substance").")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
            Button(action: onUseCustomHalfLife) {
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
}

private struct SteadyStateRelatedLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, Spacing.xs)

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
                context.stroke(line, with: .color(Theme.accent.opacity(Theme.Opacity.muted)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
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
            context.fill(fill, with: .color(Theme.accent.opacity(Theme.Opacity.tint)))
            context.stroke(stroke, with: .color(Theme.accent), lineWidth: 2.2)

            // Axis frame.
            var axes = Path()
            axes.move(to: CGPoint(x: leftPad, y: topPad))
            axes.addLine(to: CGPoint(x: leftPad, y: baseline))
            axes.addLine(to: CGPoint(x: leftPad + plotW, y: baseline))
            context.stroke(axes, with: .color(Theme.secondaryLabel.opacity(Theme.Opacity.muted)), lineWidth: 1)

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
