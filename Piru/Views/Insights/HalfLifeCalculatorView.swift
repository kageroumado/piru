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
    @State private var timeTaken: Date = .now
    @State private var useCustomHalfLife = false
    @State private var customHalfLifeHours: String = ""

    private var effectiveHalfLife: Double? {
        if useCustomHalfLife {
            guard let hours = Double(customHalfLifeHours), hours > 0 else { return nil }
            return hours * 60
        }
        return selectedSubstance?.halfLifeMinutes
    }

    private var dose: Double {
        Double(doseAmount) ?? 0
    }

    private var colorMap: [String: Color] {
        substanceColors.colorMap
    }

    private var activeSubstances: [ActiveSubstance] {
        let now = Date.now
        var grouped: [String: (substance: Substance, doses: [ActiveSubstance.DoseInfo], totalDosed: Double, totalRemaining: Double)] = [:]

        for entry in allEntries {
            guard let substance = SubstanceLibrary.search(entry.substance).first,
                  substance.name.lowercased() == entry.substance.lowercased()
                      || substance.aliases.contains(where: { $0.lowercased() == entry.substance.lowercased() }),
                  let halfLife = substance.halfLifeMinutes,
                  halfLife > 0 else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0 else { continue }
            let remaining = entry.amount * pow(0.5, elapsed / halfLife)
            let fraction = remaining / entry.amount

            // Skip if less than ~3% remains (past 5 half-lives)
            guard fraction > 0.03 else { continue }

            let doseInfo = ActiveSubstance.DoseInfo(
                amount: entry.amount,
                remaining: remaining,
                timestamp: entry.timestamp
            )

            let key = substance.name
            if var existing = grouped[key] {
                existing.doses.append(doseInfo)
                existing.totalDosed += entry.amount
                existing.totalRemaining += remaining
                grouped[key] = existing
            } else {
                grouped[key] = (
                    substance: substance,
                    doses: [doseInfo],
                    totalDosed: entry.amount,
                    totalRemaining: remaining
                )
            }
        }

        return grouped.map { name, info in
            let unit = info.substance.defaultUnit
            let color = colorMap[name.lowercased()] ?? Theme.accent
            return ActiveSubstance(
                name: name,
                unit: unit,
                color: color,
                halfLifeMinutes: info.substance.halfLifeMinutes!,
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
                if !activeSubstances.isEmpty {
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
    }

    // MARK: - In Your System

    private var inYourSystemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Your System")
                .font(.headline)

            ForEach(activeSubstances) { active in
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
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(active.totalRemaining.doseFormatted)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(active.color)
                            Text(active.unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(active.eliminatedFraction * 100))% eliminated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(d.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    private var calculatorHeader: some View {
        HStack {
            Text("Calculator")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SubstanceSearchField(text: $substanceName) { substance in
                selectedSubstance = substance
                substanceName = substance.name
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Dose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Amount", text: $doseAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Time Taken")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Decay Chart

    private func decayChart(halfLife: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Elimination Curve")
                .font(.headline)

            Canvas { context, size in
                let inset: CGFloat = 4
                let graphWidth = size.width - inset * 2
                let labelAreaHeight: CGFloat = 22
                let graphHeight = size.height - labelAreaHeight

                let totalMinutes = halfLife * 5
                guard totalMinutes > 0, graphHeight > 0 else { return }

                // Fill path
                var fillPath = Path()
                let steps = 120
                let baseline = inset + graphHeight
                fillPath.move(to: CGPoint(x: inset, y: baseline))

                for i in 0...steps {
                    let t = Double(i) / Double(steps) * totalMinutes
                    let remaining = pow(0.5, t / halfLife)
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(remaining) * graphHeight * 0.9
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
                fillPath.addLine(to: CGPoint(x: inset + graphWidth, y: baseline))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(Theme.accent.opacity(0.15)))

                // Stroke path
                var strokePath = Path()
                for i in 0...steps {
                    let t = Double(i) / Double(steps) * totalMinutes
                    let remaining = pow(0.5, t / halfLife)
                    let x = inset + CGFloat(t / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(remaining) * graphHeight * 0.9
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
                    else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(strokePath, with: .color(Theme.accent), lineWidth: 2)

                // Half-life milestone lines
                for n in 1...4 {
                    let fraction = pow(0.5, Double(n))
                    let y = inset + graphHeight - CGFloat(fraction) * graphHeight * 0.9
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: inset, y: y))
                    dashPath.addLine(to: CGPoint(x: inset + graphWidth, y: y))
                    context.stroke(dashPath, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                }

                // Current time dot
                let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
                if elapsed >= 0 && elapsed <= totalMinutes {
                    let remaining = pow(0.5, elapsed / halfLife)
                    let x = inset + CGFloat(elapsed / totalMinutes) * graphWidth
                    let y = inset + graphHeight - CGFloat(remaining) * graphHeight * 0.9
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Current Amount

    private func currentAmountCard(halfLife: Double) -> some View {
        let elapsed = Date.now.timeIntervalSince(timeTaken) / 60
        let remaining = dose * pow(0.5, max(0, elapsed) / halfLife)
        let unit = selectedSubstance?.defaultUnit ?? "mg"

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Estimated Amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(remaining.doseFormatted)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int((1 - remaining / dose) * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("eliminated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Milestones

    private func milestonesSection(halfLife: Double) -> some View {
        let unit = selectedSubstance?.defaultUnit ?? "mg"
        return VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.headline)

            ForEach(1...4, id: \.self) { n in
                let eliminatedPct = (1 - pow(0.5, Double(n))) * 100
                let remaining = dose * pow(0.5, Double(n))
                let timeMinutes = halfLife * Double(n)

                HStack {
                    Image(systemName: "\(n).circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", eliminatedPct))% eliminated")
                            .font(.subheadline.weight(.medium))
                        Text("\(remaining.doseFormatted) \(unit) remaining after \(formatDuration(timeMinutes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var noDataCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Half-life data not available for this substance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Toggle \"Custom half-life\" to enter a value manually.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Disclaimer

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Estimate Only", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("This calculator uses a simple single-compartment model with population-average half-lives. Real pharmacokinetics vary based on individual metabolism, genetics, liver and kidney function, body composition, drug interactions, and route of administration. Absorption phases, bioavailability, and active metabolites are not accounted for. These figures are approximate — not a substitute for clinical monitoring.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
