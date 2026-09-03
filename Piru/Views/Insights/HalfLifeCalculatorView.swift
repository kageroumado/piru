import SwiftData
import SwiftUI

struct HalfLifeCalculatorView: View {
    @State private var model = HalfLifeCalculatorModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HalfLifeHeader(count: model.halfLifeCount)

                HalfLifeInputSection(model: model)

                if let halfLife = model.effectiveHalfLife, model.dose > 0 {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        HalfLifeDecayChart(
                            halfLife: halfLife,
                            rateConstants: model.rateConstants,
                            dose: model.dose,
                            doseUnit: model.doseUnit,
                            timeTaken: model.timeTaken,
                        )
                        HalfLifeCurrentAmountCard(
                            remaining: model.remainingAmount(),
                            dose: model.dose,
                            unit: model.doseUnit,
                        )
                    }
                    HalfLifeMilestonesSection(
                        halfLife: halfLife,
                        rateConstants: model.rateConstants,
                        dose: model.dose,
                        unit: model.doseUnit,
                    )
                } else if model.isMissingHalfLife {
                    HalfLifeNoDataCard(substanceName: model.selectedSubstance?.name) {
                        model.useCustomHalfLife = true
                    }
                }

                HalfLifeDisclaimerSection()
                HalfLifeRelatedLinks()
            }
            .padding()
        }
        .background(Theme.background)
        .task { await model.loadHalfLifeCount() }
    }
}

// MARK: - Header

private struct HalfLifeHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Calculator")
                .cardTitle()
            Spacer()
            Text("\(count) with half-life data")
                .captionSecondary()
        }
    }
}

// MARK: - Input Section

private struct HalfLifeInputSection: View {
    @Bindable var model: HalfLifeCalculatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SubstanceSearchField(text: $model.substanceName) { substance, _ in
                model.select(substance)
            }

            if let sub = model.selectedSubstance, sub.routes.count > 1 {
                Picker("Route", selection: $model.selectedRoute) {
                    ForEach(sub.routes.map(\.route)) { r in
                        Text(r.displayName).tag(r)
                    }
                }
            }

            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading) {
                    Text("Dose")
                        .captionSecondary()
                    HStack(spacing: 0) {
                        TextField("Amount", value: $model.doseAmount, format: .number)
                            .decimalKeyboard()
                            .padding(Spacing.md)
                        Divider()
                            .frame(height: 20)
                        Menu {
                            ForEach(["mg", "g", "µg", "mL", "IU", "drops", "puffs"], id: \.self) { u in
                                Button(u) { model.doseUnit = u }
                            }
                        } label: {
                            Text(model.doseUnit)
                                .padding(Spacing.md)
                                .foregroundStyle(.primary)
                        }
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
                }

                VStack(alignment: .leading) {
                    Text("Time Taken")
                        .captionSecondary()
                    DatePicker("Time Taken", selection: $model.timeTaken)
                        .labelsHidden()
                }
            }

            Toggle("Custom half-life", isOn: $model.useCustomHalfLife)
            if model.useCustomHalfLife {
                HStack {
                    TextField("Hours", value: $model.customHalfLifeHours, format: .number)
                        .decimalKeyboard()
                        .textFieldStyle(.roundedBorder)
                    Text("hours")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Decay Chart

private struct HalfLifeDecayChart: View {
    let halfLife: Double
    let rateConstants: PKRateConstants?
    let dose: Double
    let doseUnit: String
    let timeTaken: Date

    private var peakTime: Double {
        HalfLifeCalculation.peakTime(rateConstants: rateConstants)
    }

    private func remainingAmount() -> Double {
        HalfLifeCalculation.remainingAmount(
            dose: dose,
            elapsedMinutes: Date.now.timeIntervalSince(timeTaken) / 60,
            halfLifeMinutes: halfLife,
            rateConstants: rateConstants,
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Concentration Curve")
                .cardTitle()

            Canvas { context, size in
                guard let params = rateConstants else { return }
                let ke = params.ke
                let ka = params.ka

                let inset: CGFloat = 4
                let graphWidth = size.width - inset * 2
                let labelAreaHeight: CGFloat = 22
                let graphHeight = size.height - labelAreaHeight

                let peakConc = PKModel.cmax(ke: ke, ka: ka)
                let totalMinutes = PKModel.timeToFraction(0.03, ke: ke, ka: ka, maxMinutes: halfLife * 8)
                guard totalMinutes > 0, graphHeight > 0, peakConc > 0 else { return }

                let steps = 120
                let baseline = inset + graphHeight

                // Fill and stroke share one sampling pass.
                var fillPath = Path()
                var strokePath = Path()
                fillPath.move(to: CGPoint(x: inset, y: baseline))

                for i in 0 ... steps {
                    let t = Double(i) / Double(steps) * totalMinutes
                    let c = PKModel.concentration(at: t, ke: ke, ka: ka) / peakConc
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) } else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                fillPath.addLine(to: CGPoint(x: inset + graphWidth, y: baseline))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(Theme.accent.opacity(Theme.Opacity.emphasis)))
                context.stroke(strokePath, with: .color(Theme.accent), lineWidth: 2)

                // Peak line (Tmax)
                let peakX = inset + CGFloat(PKModel.tmax(ke: ke, ka: ka) / totalMinutes) * graphWidth
                var peakLine = Path()
                peakLine.move(to: CGPoint(x: peakX, y: inset + graphHeight * 0.1))
                peakLine.addLine(to: CGPoint(x: peakX, y: baseline))
                context.stroke(peakLine, with: .color(Theme.accent.opacity(Theme.Opacity.muted)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                // Half-life milestone lines
                for n in 1 ... 3 {
                    let fraction = pow(0.5, Double(n))
                    let y = inset + graphHeight - CGFloat(fraction) * graphHeight * 0.9
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: inset, y: y))
                    dashPath.addLine(to: CGPoint(x: inset + graphWidth, y: y))
                    context.stroke(dashPath, with: .color(Theme.secondaryLabel.opacity(Theme.Opacity.muted)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                }

                // Current time dot
                let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
                if elapsed >= 0, elapsed <= totalMinutes {
                    let c = PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                    let x = inset + CGFloat(elapsed / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    let dotSize: CGFloat = 7
                    let dot = Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                    context.fill(dot, with: .color(Theme.accent))
                    context.stroke(dot, with: .color(.white.opacity(Theme.Opacity.strong)), lineWidth: 1)
                }

                // Time labels
                let interval: Double = if totalMinutes <= 60 { 15 } else if totalMinutes <= 180 { 30 } else if totalMinutes <= 360 { 60 } else if totalMinutes <= 720 { 120 } else if totalMinutes <= 2_880 { 360 } else { 1_440 }

                let labelY = inset + graphHeight + labelAreaHeight / 2 + 2
                var t = 0.0
                while t <= totalMinutes {
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let label = if t == 0 { "0" } else if t < 60 { "\(Int(t))m" } else if t < 1_440 { "\(Int(t / 60))h" } else { "\(Int(t / 1_440))d" }

                    let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
                    context.draw(context.resolve(text), at: CGPoint(x: x, y: labelY), anchor: .center)
                    t += interval
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("Concentration curve"))
            .accessibilityValue(Text("Peak after \(halfLifeFormatDuration(peakTime)), \(remainingAmount().doseFormatted) of \(dose.doseFormatted) \(doseUnit) remaining now"))
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Current Amount Card

private struct HalfLifeCurrentAmountCard: View {
    let remaining: Double
    let dose: Double
    let unit: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Current Estimated Amount")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(remaining.doseFormatted)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(Int(max(0, min(100, (1 - remaining / dose) * 100))))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("eliminated")
                    .captionSecondary()
            }
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Milestones Section

private struct HalfLifeMilestonesSection: View {
    let halfLife: Double
    let rateConstants: PKRateConstants?
    let dose: Double
    let unit: String

    private var peakTime: Double {
        HalfLifeCalculation.peakTime(rateConstants: rateConstants)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Milestones")
                .cardTitle()

            if peakTime > 0 {
                HalfLifePeakRow(peakTime: peakTime)
            }

            ForEach(HalfLifeCalculation.milestones(halfLifeMinutes: halfLife, rateConstants: rateConstants)) { milestone in
                HalfLifeMilestoneRow(milestone: milestone, dose: dose, unit: unit)
            }
        }
        .padding()
        .themeCard()
    }
}

private struct HalfLifePeakRow: View {
    let peakTime: Double

    var body: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("Peak concentration")
                    .font(.subheadline.weight(.medium))
                Text("Reached after \(halfLifeFormatDuration(peakTime))")
                    .captionSecondary()
            }
            Spacer()
        }
    }
}

private struct HalfLifeMilestoneRow: View {
    let milestone: HalfLifeCalculation.Milestone
    let dose: Double
    let unit: String

    private var eliminatedPct: Double {
        (1 - milestone.fraction) * 100
    }

    private var remaining: Double {
        dose * milestone.fraction
    }

    var body: some View {
        HStack {
            Image(systemName: "\(milestone.id).circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("\(Int(eliminatedPct))% eliminated")
                    .font(.subheadline.weight(.medium))
                Text("\(remaining.doseFormatted) \(unit) remaining after \(halfLifeFormatDuration(milestone.minutes))")
                    .captionSecondary()
            }
            Spacer()
        }
    }
}

// MARK: - No Data Card

private struct HalfLifeNoDataCard: View {
    let substanceName: String?
    let onUseCustomHalfLife: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
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

// MARK: - Disclaimer

private struct HalfLifeDisclaimerSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Estimate only", systemImage: "info.circle")
                .sectionLabel()
                .foregroundStyle(Theme.secondaryLabel)

            Text("Population-average half-lives in a one-compartment model.")
                .captionSecondary()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

// MARK: - Related Links

private struct HalfLifeRelatedLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, Spacing.xs)

            GlanceCard(icon: "chart.line.flattrend.xyaxis", title: Text("Steady State"), route: .tool(.steadyState)) {
                Text("Taking this daily? See where the level settles")
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

// MARK: - Shared Helper

private func halfLifeFormatDuration(_ minutes: Double) -> String {
    if minutes < 60 {
        let m = Int(minutes)
        return String(localized: "\(m) min")
    }
    let hours = Int(round(minutes / 60))
    if hours < 24 { return String(localized: "\(hours) hours") }
    let days = Int(round(minutes / 1_440))
    return String(localized: "\(days) days")
}
