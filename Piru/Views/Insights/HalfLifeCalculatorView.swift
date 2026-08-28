import SwiftData
import SwiftUI

/// PK rate constants passed to subviews, replacing the unnamed tuple.
struct PKRateConstants: Equatable {
    let ke: Double
    let ka: Double
}

struct HalfLifeCalculatorView: View {
    @State private var substanceName = ""
    @State private var selectedSubstance: Substance?
    @State private var doseAmount: Double? = 100
    @State private var doseUnit: String = "mg"
    @State private var timeTaken: Date = .now
    @State private var useCustomHalfLife = false
    @State private var customHalfLifeHours: Double?
    @State private var selectedRoute: RouteOfAdministration = .oral
    @State private var halfLifeCount = 0

    private var effectiveHalfLife: Double? {
        if useCustomHalfLife {
            guard let hours = customHalfLifeHours, hours > 0 else { return nil }
            return hours * 60
        }
        return PKResolver.halfLifeMinutes(substance: selectedSubstance, entryName: substanceName)
    }

    private var rateConstants: PKRateConstants? {
        guard let halfLife = effectiveHalfLife, halfLife > 0 else { return nil }
        let params = PKResolver.rateConstants(
            halfLifeMinutes: halfLife,
            duration: selectedSubstance?.resolveDuration(for: selectedRoute),
        )
        return PKRateConstants(ke: params.ke, ka: params.ka)
    }

    private var dose: Double {
        doseAmount ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HalfLifeHeader(count: halfLifeCount)

                HalfLifeInputSection(
                    substanceName: $substanceName,
                    selectedSubstance: $selectedSubstance,
                    doseAmount: $doseAmount,
                    doseUnit: $doseUnit,
                    timeTaken: $timeTaken,
                    useCustomHalfLife: $useCustomHalfLife,
                    customHalfLifeHours: $customHalfLifeHours,
                    selectedRoute: $selectedRoute,
                )

                if let halfLife = effectiveHalfLife, dose > 0 {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        HalfLifeDecayChart(
                            halfLife: halfLife,
                            rateConstants: rateConstants,
                            dose: dose,
                            doseUnit: doseUnit,
                            timeTaken: timeTaken,
                        )
                        HalfLifeCurrentAmountCard(
                            remaining: remainingAmount(halfLife: halfLife),
                            dose: dose,
                            unit: doseUnit,
                        )
                    }
                    HalfLifeMilestonesSection(
                        halfLife: halfLife,
                        rateConstants: rateConstants,
                        dose: dose,
                        unit: doseUnit,
                    )
                } else if selectedSubstance != nil, !useCustomHalfLife, selectedSubstance?.halfLifeMinutes == nil {
                    HalfLifeNoDataCard(
                        substanceName: selectedSubstance?.name,
                        useCustomHalfLife: $useCustomHalfLife,
                    )
                }

                HalfLifeDisclaimerSection()
                HalfLifeRelatedLinks()
            }
            .padding()
        }
        .background(Theme.background)
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            halfLifeCount = SubstanceLibrary.all.count(where: { $0.halfLifeMinutes != nil })
        }
    }

    private func remainingAmount(halfLife: Double) -> Double {
        let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
        if let params = rateConstants {
            return dose * PKModel.fractionRemainingInBody(at: max(0, elapsed), ke: params.ke, ka: params.ka)
        }
        return dose * pow(0.5, max(0, elapsed) / halfLife)
    }
}

// MARK: - Header

private struct HalfLifeHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Calculator")
                .font(.headline)
            Spacer()
            Text("\(count) with half-life data")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

// MARK: - Input Section

private struct HalfLifeInputSection: View {
    @Binding var substanceName: String
    @Binding var selectedSubstance: Substance?
    @Binding var doseAmount: Double?
    @Binding var doseUnit: String
    @Binding var timeTaken: Date
    @Binding var useCustomHalfLife: Bool
    @Binding var customHalfLifeHours: Double?
    @Binding var selectedRoute: RouteOfAdministration

    var body: some View {
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
                    Text("Dose")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 0) {
                        TextField("Amount", value: $doseAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(8)
                        Divider()
                            .frame(height: 20)
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
                    Text("Time Taken")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    DatePicker("Time Taken", selection: $timeTaken)
                        .labelsHidden()
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
}

// MARK: - Decay Chart

private struct HalfLifeDecayChart: View {
    let halfLife: Double
    let rateConstants: PKRateConstants?
    let dose: Double
    let doseUnit: String
    let timeTaken: Date

    private var peakTime: Double {
        rateConstants.map { PKModel.tmax(ke: $0.ke, ka: $0.ka) } ?? 0
    }

    private func remainingAmount() -> Double {
        let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
        if let params = rateConstants {
            return dose * PKModel.fractionRemainingInBody(at: max(0, elapsed), ke: params.ke, ka: params.ka)
        }
        return dose * pow(0.5, max(0, elapsed) / halfLife)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Concentration Curve")
                .font(.headline)

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
                context.fill(fillPath, with: .color(Theme.accent.opacity(0.25)))
                context.stroke(strokePath, with: .color(Theme.accent), lineWidth: 2)

                // Peak line (Tmax)
                let peakX = inset + CGFloat(PKModel.tmax(ke: ke, ka: ka) / totalMinutes) * graphWidth
                var peakLine = Path()
                peakLine.move(to: CGPoint(x: peakX, y: inset + graphHeight * 0.1))
                peakLine.addLine(to: CGPoint(x: peakX, y: baseline))
                context.stroke(peakLine, with: .color(Theme.accent.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                // Half-life milestone lines
                for n in 1 ... 3 {
                    let fraction = pow(0.5, Double(n))
                    let y = inset + graphHeight - CGFloat(fraction) * graphHeight * 0.9
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: inset, y: y))
                    dashPath.addLine(to: CGPoint(x: inset + graphWidth, y: y))
                    context.stroke(dashPath, with: .color(Theme.secondaryLabel.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
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
                    context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Estimated Amount")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(remaining.doseFormatted)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(max(0, min(100, (1 - remaining / dose) * 100))))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("eliminated")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
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
        rateConstants.map { PKModel.tmax(ke: $0.ke, ka: $0.ka) } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.headline)

            if peakTime > 0 {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Peak concentration")
                            .font(.subheadline.weight(.medium))
                        Text("Reached after \(halfLifeFormatDuration(peakTime))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                }
            }

            ForEach(1 ... 4, id: \.self) { n in
                let fraction = pow(0.5, Double(n))
                let eliminatedPct = (1 - fraction) * 100
                let remaining = dose * fraction
                let timeMinutes: Double = if let params = rateConstants {
                    PKModel.timeToFraction(fraction, ke: params.ke, ka: params.ka, maxMinutes: halfLife * 8)
                } else {
                    peakTime + halfLife * Double(n)
                }

                HStack {
                    Image(systemName: "\(n).circle.fill")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("\(Int(eliminatedPct))% eliminated")
                            .font(.subheadline.weight(.medium))
                        Text("\(remaining.doseFormatted) \(unit) remaining after \(halfLifeFormatDuration(timeMinutes))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .themeCard()
    }
}

// MARK: - No Data Card

private struct HalfLifeNoDataCard: View {
    let substanceName: String?
    @Binding var useCustomHalfLife: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Half-life data not available for \(substanceName ?? "this substance").")
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
}

// MARK: - Disclaimer

private struct HalfLifeDisclaimerSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Estimate Only", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)

            Text("This calculator uses a one-compartment oral pharmacokinetic model with absorption and elimination phases. Absorption rates are estimated from known duration profiles (onset + comeup timing) when available, or use a default 4\u{00D7} elimination rate ratio. Population-average elimination half-lives are sourced from FDA-approved prescribing information, published pharmacokinetic studies (PubMed), and DrugBank. Half-lives for some research chemicals and novel substances are estimated from structurally similar compounds and may be less reliable.\n\nReal pharmacokinetics vary significantly based on individual metabolism, genetics, liver and kidney function, body composition, age, drug interactions, tolerance, and route of administration. Multi-compartment distribution, protein binding, active metabolites, and enterohepatic recirculation are not accounted for. Polydrug use may alter elimination rates unpredictably.\n\nThese figures are approximate population averages — not a substitute for clinical monitoring or professional medical advice. Always consult a qualified healthcare professional.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

// MARK: - Related Links

private struct HalfLifeRelatedLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, 4)

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
