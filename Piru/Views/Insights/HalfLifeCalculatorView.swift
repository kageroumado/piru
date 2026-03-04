import SwiftData
import SwiftUI

// MARK: - Active Substance Model

private struct ActiveSubstance: Identifiable {
    let name: String
    let unit: String
    let color: Color
    let halfLifeMinutes: Double
    let totalDosed: Double
    let totalRemaining: Double
    let doses: [DoseInfo]

    var id: String { name }
    var eliminatedFraction: Double { 1 - totalRemaining / totalDosed }

    struct DoseInfo: Identifiable {
        let id = UUID()
        let amount: Double
        let remaining: Double
        let timestamp: Date
    }
}

// MARK: - View

struct HalfLifeCalculatorView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var substanceName = ""
    @State private var selectedSubstance: Substance?
    @State private var doseAmount: String = "100"
    @State private var doseUnit: String = "mg"
    @State private var timeTaken: Date = .now
    @State private var useCustomHalfLife = false
    @State private var customHalfLifeHours: String = ""
    @State private var cachedActiveSubstances: [ActiveSubstance] = []
    @State private var selectedRoute: RouteOfAdministration = .oral

    private var effectiveHalfLife: Double? {
        if useCustomHalfLife {
            guard let hours = Double(customHalfLifeHours), hours > 0 else { return nil }
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
                let ka = PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke)
                return (ke, ka)
            }
        }
        return (ke, PKModel.defaultKa(ke: ke))
    }

    private var dose: Double {
        Double(doseAmount) ?? 0
    }

    private func computeActiveSubstances() -> [ActiveSubstance] {
        let now = Date.now
        let colors = substanceColors.colorMap

        // Batch lookups: cache substance resolution so each unique name is looked up once
        var substanceCache: [String: Substance?] = [:]
        func cachedLookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = substanceCache[key] { return cached }
            let result = SubstanceLibrary.lookupByNameOrAlias(name)
            substanceCache[key] = result
            return result
        }

        // Resolve half-life with fallback: substance model → HalfLifeDatabase by name → HalfLifeDatabase by aliases
        var halfLifeCache: [String: Double] = [:]
        func resolveHalfLife(substance: Substance?, entryName: String) -> Double? {
            let key = entryName.lowercased()
            if let cached = halfLifeCache[key] { return cached }
            // 1. From library substance model
            if let hl = substance?.halfLifeMinutes, hl > 0 { halfLifeCache[key] = hl; return hl }
            // 2. From HalfLifeDatabase using entry name
            if let hl = HalfLifeDatabase.halfLife(for: entryName), hl > 0 { halfLifeCache[key] = hl; return hl }
            // 3. From HalfLifeDatabase using substance aliases
            if let substance {
                for alias in substance.aliases {
                    if let hl = HalfLifeDatabase.halfLife(for: alias), hl > 0 { halfLifeCache[key] = hl; return hl }
                }
            }
            return nil
        }

        var grouped: [String: (name: String, unit: String, halfLife: Double, doses: [ActiveSubstance.DoseInfo], totalDosed: Double, totalRemaining: Double)] = [:]

        for entry in allEntries {
            let substance = cachedLookup(entry.substance)
            guard let halfLife = resolveHalfLife(substance: substance, entryName: entry.substance) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0 else { continue }

            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka: Double
            if let sub = substance,
               let duration = sub.resolveDuration(for: entry.route) {
                let ttp = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
                ka = ttp > 0 ? PKModel.estimateKa(timeToPeak: ttp, ke: ke) : PKModel.defaultKa(ke: ke)
            } else {
                ka = PKModel.defaultKa(ke: ke)
            }
            let peakConc = PKModel.cmax(ke: ke, ka: ka)
            let remaining = peakConc > 0 ? entry.amount * PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc : 0
            let fraction = remaining / entry.amount

            guard fraction > 0.03 else { continue }

            let doseInfo = ActiveSubstance.DoseInfo(
                amount: entry.amount,
                remaining: remaining,
                timestamp: entry.timestamp
            )

            let key = substance?.name ?? entry.substance
            if var existing = grouped[key] {
                existing.doses.append(doseInfo)
                existing.totalDosed += entry.amount
                existing.totalRemaining += remaining
                grouped[key] = existing
            } else {
                grouped[key] = (
                    name: key,
                    unit: substance?.defaultUnit ?? "mg",
                    halfLife: halfLife,
                    doses: [doseInfo],
                    totalDosed: entry.amount,
                    totalRemaining: remaining
                )
            }
        }

        return grouped.map { name, info in
            let color = colors[name.lowercased()] ?? Theme.accent
            return ActiveSubstance(
                name: name,
                unit: info.unit,
                color: color,
                halfLifeMinutes: info.halfLife,
                totalDosed: info.totalDosed,
                totalRemaining: info.totalRemaining,
                doses: info.doses.sorted { $0.timestamp > $1.timestamp }
            )
        }
        .sorted { $0.eliminatedFraction < $1.eliminatedFraction }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !cachedActiveSubstances.isEmpty {
                    inYourSystemSection
                }

                calculatorHeader
                inputSection

                if let halfLife = effectiveHalfLife, dose > 0 {
                    decayChart(halfLife: halfLife)
                    currentAmountCard(halfLife: halfLife)
                    milestonesSection(halfLife: halfLife)
                } else if selectedSubstance != nil && !useCustomHalfLife && selectedSubstance?.halfLifeMinutes == nil {
                    noDataCard
                }

                disclaimerSection
            }
            .padding()
        }
        .task(id: allEntries.count) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            cachedActiveSubstances = computeActiveSubstances()
        }
    }

    // MARK: - In Your System

    private var inYourSystemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Your System")
                .font(.headline)

            ForEach(cachedActiveSubstances) { active in
                activeSubstanceCard(active)
            }
        }
    }

    private func activeSubstanceCard(_ active: ActiveSubstance) -> some View {
        Button {
            populateCalculator(from: active)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(active.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(timeAgoText(active.doses.first?.timestamp))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(active.totalRemaining.doseFormatted)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(active.color)
                            Text(active.unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Text("\(Int(active.eliminatedFraction * 100))% eliminated")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                // Decay progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(active.color.opacity(0.15))
                            .frame(height: 4)
                        Capsule()
                            .fill(active.color)
                            .frame(width: geo.size.width * (1 - active.eliminatedFraction), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.top, 10)

                // Show individual doses if more than one
                if active.doses.count > 1 {
                    VStack(spacing: 4) {
                        ForEach(active.doses) { d in
                            HStack {
                                Text("\(d.amount.doseFormatted) \(active.unit)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryLabel)
                                Spacer()
                                Text(d.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryLabel)
                                Text("\(d.remaining.doseFormatted) \(active.unit) left")
                                    .font(.caption2)
                                    .foregroundStyle(active.color.opacity(0.8))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
            .themeCard()
        }
        .buttonStyle(.plain)
    }

    private func populateCalculator(from active: ActiveSubstance) {
        substanceName = active.name
        selectedSubstance = SubstanceLibrary.search(active.name).first
        doseAmount = active.totalDosed.doseFormatted
        // Use the most recent dose timestamp
        if let latest = active.doses.first?.timestamp {
            timeTaken = latest
        }
        doseUnit = SubstanceLibrary.lookup(active.name.lowercased())?.defaultUnit ?? "mg"
        useCustomHalfLife = false
        customHalfLifeHours = ""
    }

    private func timeAgoText(_ date: Date?) -> String {
        guard let date else { return "" }
        let elapsed = Date.now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(Int(minutes))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours))h ago" }
        let days = hours / 24
        return "\(Int(days))d ago"
    }

    // MARK: - Calculator Header

    private var halfLifeCount: Int {
        SubstanceLibrary.all.filter { $0.halfLifeMinutes != nil }.count
    }

    private var calculatorHeader: some View {
        HStack {
            Text("Calculator")
                .font(.headline)
            Spacer()
            Text("\(halfLifeCount) with half-life data")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SubstanceSearchField(text: $substanceName) { substance in
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
                        TextField("Amount", text: $doseAmount)
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
                    DatePicker("", selection: $timeTaken)
                        .labelsHidden()
                }
            }

            Toggle("Custom half-life", isOn: $useCustomHalfLife)
            if useCustomHalfLife {
                HStack {
                    TextField("Hours", text: $customHalfLifeHours)
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

    // MARK: - Decay Chart

    private func decayChart(halfLife: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Concentration Curve")
                .font(.headline)

            Canvas { context, size in
                guard let params = pkParameters else { return }
                let ke = params.ke
                let ka = params.ka

                let inset: CGFloat = 4
                let graphWidth = size.width - inset * 2
                let labelAreaHeight: CGFloat = 22
                let graphHeight = size.height - labelAreaHeight

                let peakConc = PKModel.cmax(ke: ke, ka: ka)
                let totalMinutes = PKModel.timeToFraction(0.03, ke: ke, ka: ka, maxMinutes: halfLife * 8)
                guard totalMinutes > 0, graphHeight > 0, peakConc > 0 else { return }

                // Fill path
                var fillPath = Path()
                let steps = 120
                let baseline = inset + graphHeight
                fillPath.move(to: CGPoint(x: inset, y: baseline))

                for i in 0...steps {
                    let t = Double(i) / Double(steps) * totalMinutes
                    let c = PKModel.concentration(at: t, ke: ke, ka: ka) / peakConc
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
                fillPath.addLine(to: CGPoint(x: inset + graphWidth, y: baseline))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(Theme.accent.opacity(0.25)))

                // Stroke path
                var strokePath = Path()
                for i in 0...steps {
                    let t = Double(i) / Double(steps) * totalMinutes
                    let c = PKModel.concentration(at: t, ke: ke, ka: ka) / peakConc
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
                    else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(strokePath, with: .color(Theme.accent), lineWidth: 2)

                // Peak line (Tmax)
                let peakTime = PKModel.tmax(ke: ke, ka: ka)
                let peakX = inset + CGFloat(peakTime / totalMinutes) * graphWidth
                var peakLine = Path()
                peakLine.move(to: CGPoint(x: peakX, y: inset + graphHeight * 0.1))
                peakLine.addLine(to: CGPoint(x: peakX, y: baseline))
                context.stroke(peakLine, with: .color(Theme.accent.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                // Half-life milestone lines
                for n in 1...3 {
                    let fraction = pow(0.5, Double(n))
                    let y = inset + graphHeight - CGFloat(fraction) * graphHeight * 0.9
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: inset, y: y))
                    dashPath.addLine(to: CGPoint(x: inset + graphWidth, y: y))
                    context.stroke(dashPath, with: .color(Theme.secondaryLabel.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                }

                // Current time dot
                let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
                if elapsed >= 0 && elapsed <= totalMinutes {
                    let c = PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                    let x = inset + CGFloat(elapsed / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    let dotSize: CGFloat = 7
                    let dot = Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                    context.fill(dot, with: .color(Theme.accent))
                    context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                }

                // Time labels
                let interval: Double
                if totalMinutes <= 60 { interval = 15 }
                else if totalMinutes <= 180 { interval = 30 }
                else if totalMinutes <= 360 { interval = 60 }
                else if totalMinutes <= 720 { interval = 120 }
                else if totalMinutes <= 2880 { interval = 360 }
                else { interval = 1440 }

                let labelY = inset + graphHeight + labelAreaHeight / 2 + 2
                var t = 0.0
                while t <= totalMinutes {
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let label: String
                    if t == 0 { label = "0" }
                    else if t < 60 { label = "\(Int(t))m" }
                    else if t < 1440 { label = "\(Int(t / 60))h" }
                    else { label = "\(Int(t / 1440))d" }

                    let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
                    context.draw(context.resolve(text), at: CGPoint(x: x, y: labelY), anchor: .center)
                    t += interval
                }
            }
            .frame(height: 200)
        }
        .padding()
        .themeCard()
    }

    // MARK: - Current Amount

    private func currentAmountCard(halfLife: Double) -> some View {
        let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
        let remaining: Double
        if let params = pkParameters {
            let peakConc = PKModel.cmax(ke: params.ke, ka: params.ka)
            remaining = peakConc > 0 ? dose * PKModel.concentration(at: max(0, elapsed), ke: params.ke, ka: params.ka) / peakConc : 0
        } else {
            remaining = dose * pow(0.5, max(0, elapsed) / halfLife)
        }
        let unit = doseUnit

        return HStack {
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

    // MARK: - Milestones

    private func milestonesSection(halfLife: Double) -> some View {
        let unit = doseUnit
        let peakTime = pkParameters.map { PKModel.tmax(ke: $0.ke, ka: $0.ka) } ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.headline)

            if peakTime > 0 {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("Peak concentration")
                            .font(.subheadline.weight(.medium))
                        Text("Reached after \(formatDuration(peakTime))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                }
            }

            ForEach(1...4, id: \.self) { n in
                let eliminatedPct = (1 - pow(0.5, Double(n))) * 100
                let remaining = dose * pow(0.5, Double(n))
                let timeMinutes = peakTime + halfLife * Double(n)

                HStack {
                    Image(systemName: "\(n).circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", eliminatedPct))% eliminated")
                            .font(.subheadline.weight(.medium))
                        Text("\(remaining.doseFormatted) \(unit) remaining after \(formatDuration(timeMinutes))")
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

    // MARK: - Disclaimer

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Estimate Only", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)

            Text("This calculator uses a one-compartment oral pharmacokinetic model with absorption and elimination phases. Absorption rates are estimated from known duration profiles (onset + comeup timing) when available, or use a default 4\u{00D7} elimination rate ratio. Population-average elimination half-lives are sourced from FDA-approved prescribing information, published pharmacokinetic studies (PubMed), DrugBank, and established pharmacology references (Goodman & Gilman's, Stahl's Essential Psychopharmacology). Half-lives for some research chemicals and novel substances are estimated from structurally similar compounds and may be less reliable.\n\nReal pharmacokinetics vary significantly based on individual metabolism, genetics, liver and kidney function, body composition, age, drug interactions, tolerance, and route of administration. Multi-compartment distribution, protein binding, active metabolites, and enterohepatic recirculation are not accounted for. Polydrug use may alter elimination rates unpredictably.\n\nThese figures are approximate population averages — not a substitute for clinical monitoring or professional medical advice. Always consult a qualified healthcare professional.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 60 { return "\(Int(minutes)) min" }
        let hours = minutes / 60
        if hours < 24 {
            return hours == hours.rounded() ? "\(Int(hours)) hours" : String(format: "%.1f hours", hours)
        }
        let days = hours / 24
        return days == days.rounded() ? "\(Int(days)) days" : String(format: "%.1f days", days)
    }
}
