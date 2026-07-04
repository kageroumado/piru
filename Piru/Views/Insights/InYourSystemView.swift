import SwiftData
import SwiftUI

/// "In your system" — a read-only glance at what's still active in the body,
/// with a per-substance elimination curve. Split out from
/// ``HalfLifeCalculatorView`` (`Tool.calculator`) so each screen has a single
/// responsibility; a cross-link row at the bottom jumps to the calculator.
struct InYourSystemView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var cachedActiveSubstances: [ActiveSubstance] = []
    @State private var expandedSubstance: String?

    /// Cap on individual ingestion rows shown per active substance — a daily
    /// medication can accumulate dozens of in-system doses; show the most
    /// recent few and summarise the rest.
    private static let maxDosesShown = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if cachedActiveSubstances.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        activeList
                    }
                }

                calculatorLink
            }
            .padding()
        }
        .background(Theme.background)
        .task(id: EntriesFingerprint.make(allEntries, colors: substanceColors)) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            cachedActiveSubstances = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)
        }
    }

    // MARK: - Active list

    private var activeList: some View {
        VStack(spacing: 12) {
            ForEach(cachedActiveSubstances) { active in
                activeSubstanceCard(active)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.secondaryLabel)
            Text("Nothing active right now")
                .font(.headline)
            Text("Substances you log will appear here while they're still estimated to be in your body.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal)
        .themeCard()
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
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Cross-link

    private var calculatorLink: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, 4)

            GlanceCard(icon: "function", title: Text("Half-Life Calculator"), route: .tool(.calculator)) {
                Text("Model a single dose's decay over time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
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
        for i in 0 ... steps {
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
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) } else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
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
                let interval: Double = if endMinutes <= 60 { 15 } else if endMinutes <= 180 { 30 } else if endMinutes <= 360 { 60 } else if endMinutes <= 720 { 120 } else if endMinutes <= 2_880 { 360 } else if endMinutes <= 14_400 { 1_440 } else if endMinutes <= 43_200 { 4_320 } else if endMinutes <= 100_800 { 10_080 } else { 20_160 }

                let labelY = inset + graphHeight + labelAreaHeight / 2 + 1
                var t = 0.0
                while t <= endMinutes {
                    let x = inset + CGFloat(t / endMinutes) * graphWidth
                    let text = if t == 0 { "0" } else if t < 60 { "\(Int(t))m" } else if t < 1_440 { "\(Int(t / 60))h" } else { "\(Int(t / 1_440))d" }

                    let resolved = context.resolve(
                        Text(text).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.5)),
                    )
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: .center)
                    t += interval
                }
            }
            .frame(height: 140)
            .accessibilityLabel(Text("Elimination curve for \(active.name)"))
            .accessibilityValue(Text("\(active.totalRemaining.doseFormatted) \(active.unit) remaining, \(Int(active.eliminatedFraction * 100))% eliminated, half-life \(formatDuration(halfLife))"))
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

    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 60 {
            let m = Int(minutes)
            return String(localized: "\(m) min")
        }
        let hours = Int(round(minutes / 60))
        if hours < 24 { return String(localized: "\(hours) hours") }
        let days = Int(round(minutes / 1_440))
        return String(localized: "\(days) days")
    }
}
