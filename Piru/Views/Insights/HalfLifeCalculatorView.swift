import SwiftData
import SwiftUI

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
    @State private var expandedSubstance: String?

    /// Cap on individual ingestion rows shown per active substance — a daily
    /// medication can accumulate dozens of in-system doses; show the most
    /// recent few and summarise the rest.
    private static let maxDosesShown = 10

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
        .background(Theme.background)
        .task(id: allEntries.count) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            cachedActiveSubstances = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)
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
        let isExpanded = expandedSubstance == active.name

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    expandedSubstance = isExpanded ? nil : active.name
                }
            } label: {
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

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

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

            // Show individual doses if more than one, capped so a substance with
            // dozens of recent ingestions (e.g. a daily medication) doesn't render
            // an unbounded list. The most recent `maxDosesShown` are shown.
            if active.doses.count > 1 {
                VStack(spacing: 4) {
                    ForEach(active.doses.prefix(Self.maxDosesShown)) { d in
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
                    if active.doses.count > Self.maxDosesShown {
                        HStack {
                            Text("+\(active.doses.count - Self.maxDosesShown) earlier")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Expandable elimination curve
            if isExpanded {
                eliminationGraph(for: active)
                    .padding(.top, 14)

                Button {
                    populateCalculator(from: active)
                } label: {
                    Label("Open in Calculator", systemImage: "function")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(active.color)
                .controlSize(.small)
                .padding(.top, 10)
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Elimination Graph

    private func eliminationGraph(for active: ActiveSubstance) -> some View {
        let halfLife = active.halfLifeMinutes
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = estimateKa(for: active.name, ke: ke)
        let peakConc = PKModel.cmax(ke: ke, ka: ka)
        let color = active.color

        let sortedDoses = active.doses.sorted { $0.timestamp < $1.timestamp }
        let earliest = sortedDoses.first?.timestamp ?? .now
        let latestOffset = (sortedDoses.last?.timestamp.timeIntervalSince(earliest) ?? 0) / 60
        let tailMinutes = PKModel.timeToFraction(0.03, ke: ke, ka: ka, maxMinutes: halfLife * 8)
        let endMinutes = max(1, latestOffset + tailMinutes)

        let doseOffsets: [(amount: Double, offset: Double)] = sortedDoses.map {
            ($0.amount, $0.timestamp.timeIntervalSince(earliest) / 60)
        }

        // Precompute curve points for Canvas (avoids capturing functions)
        let steps = 120
        var rawPoints: [Double] = []
        var maxConc = 0.001
        for i in 0...steps {
            let t = Double(i) / Double(steps) * endMinutes
            var c = 0.0
            if peakConc > 0 {
                for d in doseOffsets {
                    let elapsed = t - d.offset
                    if elapsed >= 0 {
                        c += d.amount * PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                    }
                }
            }
            rawPoints.append(c)
            maxConc = max(maxConc, c)
        }
        let curvePoints = rawPoints.map { $0 / maxConc }

        // Current time position
        let currentOffset = Date.now.timeIntervalSince(earliest) / 60
        let currentNormalized: Double? = {
            guard currentOffset >= 0, currentOffset <= endMinutes, peakConc > 0, maxConc > 0 else { return nil }
            var c = 0.0
            for d in doseOffsets {
                let elapsed = currentOffset - d.offset
                if elapsed >= 0 {
                    c += d.amount * PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                }
            }
            return c / maxConc
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Elimination Curve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                Text("t½ = \(formatDuration(halfLife))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color.opacity(0.8))
            }

            Canvas { context, size in
                let inset: CGFloat = 4
                let graphWidth = size.width - inset * 2
                let labelAreaHeight: CGFloat = 18
                let graphHeight = size.height - labelAreaHeight - inset
                guard graphHeight > 0 else { return }
                let baseline = inset + graphHeight

                // Half-life milestone lines (50%, 25%)
                for fraction in [0.5, 0.25] as [Double] {
                    let y = inset + graphHeight - CGFloat(fraction) * graphHeight * 0.9
                    var dash = Path()
                    dash.move(to: CGPoint(x: inset, y: y))
                    dash.addLine(to: CGPoint(x: inset + graphWidth, y: y))
                    context.stroke(dash, with: .color(color.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                    let label = Text("\(Int(fraction * 100))%")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(color.opacity(0.4))
                    context.draw(context.resolve(label), at: CGPoint(x: inset + graphWidth - 2, y: y - 1), anchor: .bottomTrailing)
                }

                // Fill path
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: inset, y: baseline))
                for (i, c) in curvePoints.enumerated() {
                    let x = inset + CGFloat(Double(i) / Double(steps)) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
                fillPath.addLine(to: CGPoint(x: inset + graphWidth, y: baseline))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(color.opacity(0.2)))

                // Stroke path
                var strokePath = Path()
                for (i, c) in curvePoints.enumerated() {
                    let x = inset + CGFloat(Double(i) / Double(steps)) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
                    else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(strokePath, with: .color(color), lineWidth: 2)

                // Current time dot
                if let c = currentNormalized {
                    let x = inset + CGFloat(currentOffset / endMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                    let dotSize: CGFloat = 7
                    let dot = Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                    context.fill(dot, with: .color(color))
                    context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                }

                // Time labels
                let interval: Double
                if endMinutes <= 60 { interval = 15 }
                else if endMinutes <= 180 { interval = 30 }
                else if endMinutes <= 360 { interval = 60 }
                else if endMinutes <= 720 { interval = 120 }
                else if endMinutes <= 2880 { interval = 360 }
                else if endMinutes <= 14400 { interval = 1440 }
                else if endMinutes <= 43200 { interval = 4320 }
                else if endMinutes <= 100800 { interval = 10080 }
                else { interval = 20160 }

                let labelY = inset + graphHeight + labelAreaHeight / 2 + 1
                var t = 0.0
                while t <= endMinutes {
                    let x = inset + CGFloat(t / endMinutes) * graphWidth
                    let text: String
                    if t == 0 { text = "0" }
                    else if t < 60 { text = "\(Int(t))m" }
                    else if t < 1440 { text = "\(Int(t / 60))h" }
                    else { text = "\(Int(t / 1440))d" }

                    let resolved = context.resolve(
                        Text(text).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.5))
                    )
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: .center)
                    t += interval
                }
            }
            .frame(height: 140)
        }
    }

    private func estimateKa(for substanceName: String, ke: Double) -> Double {
        if let substance = SubstanceLibrary.lookup(substanceName.lowercased()),
           let duration = substance.resolveDuration(for: .oral) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            if timeToPeak > 0 {
                return PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke)
            }
        }
        return PKModel.defaultKa(ke: ke)
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
        if elapsed < 60 { return String(localized: "Just now") }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return String(localized: "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours)h ago") }
        let days = hours / 24
        return String(localized: "\(days)d ago")
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
            remaining = dose * PKModel.fractionRemainingInBody(at: max(0, elapsed), ke: params.ke, ka: params.ka)
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
                let fraction = pow(0.5, Double(n))
                let eliminatedPct = (1 - fraction) * 100
                let remaining = dose * fraction
                let timeMinutes: Double = if let params = pkParameters {
                    PKModel.timeToFraction(fraction, ke: params.ke, ka: params.ka, maxMinutes: halfLife * 8)
                } else {
                    peakTime + halfLife * Double(n)
                }

                HStack {
                    Image(systemName: "\(n).circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("\(Int(eliminatedPct))% eliminated")
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
        if minutes < 60 {
            let m = Int(minutes)
            return String(localized: "\(m) min")
        }
        let hours = Int(round(minutes / 60))
        if hours < 24 { return String(localized: "\(hours) hours") }
        let days = Int(round(minutes / 1440))
        return String(localized: "\(days) days")
    }
}
