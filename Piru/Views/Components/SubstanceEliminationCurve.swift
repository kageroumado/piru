import SwiftUI

/// The per-substance elimination curve — multi-dose one-compartment decay with
/// 50%/25% milestone lines, a "now" dot, and adaptive time-axis labels.
/// Extracted from ``InYourSystemView`` so the session detail's In Your Body
/// section renders the identical curve.
struct SubstanceEliminationCurve: View {
    let active: ActiveSubstance

    var body: some View {
        let halfLife = active.halfLifeMinutes
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = Self.estimateKa(for: active.name, ke: ke)
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

        return Canvas { context, size in
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

            // Time labels. The interval is chosen so its unit matches how the
            // label reads (minutes < 1h, hours < ~2 days, days beyond) — else a
            // 6h tick over a 40h span prints "1d" four times in a row.
            let interval: Double = if endMinutes <= 60 { 15 } else if endMinutes <= 180 { 30 } else if endMinutes <= 360 { 60 } else if endMinutes <= 720 { 120 } else if endMinutes <= 1_440 { 240 } else if endMinutes <= 2_880 { 480 } else if endMinutes <= 5_760 { 1_440 } else if endMinutes <= 11_520 { 2_880 } else if endMinutes <= 40_320 { 5_760 } else { 10_080 }

            let labelY = inset + graphHeight + labelAreaHeight / 2 + 1
            var t = 0.0
            while t <= endMinutes {
                let x = inset + CGFloat(t / endMinutes) * graphWidth
                let text = if t == 0 { "0" } else if interval < 60 { "\(Int(t.rounded()))m" } else if interval < 1_440 { "\(Int((t / 60).rounded()))h" } else { "\(Int((t / 1_440).rounded()))d" }

                let resolved = context.resolve(
                    Text(text).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.5)),
                )
                context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: .center)
                t += interval
            }
        }
        .frame(height: 132)
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // A floating label rather than a header row, so it doesn't push the
            // curve down. "Elimination Curve" is dropped — self-evident from the
            // shape and the section it lives in.
            Text("t½ = \(Self.formatDuration(halfLife))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(10)
        }
        .accessibilityLabel(Text("Elimination curve for \(active.name)"))
        .accessibilityValue(Text("\(active.totalRemaining.doseFormatted) \(active.unit) remaining, \(Int(active.eliminatedFraction * 100))% eliminated, half-life \(Self.formatDuration(halfLife))"))
    }

    /// Absorption-rate estimate from the substance's oral time-to-peak, falling
    /// back to the model default. Shared by the curve and milestone projections.
    static func estimateKa(for substanceName: String, ke: Double) -> Double {
        if let substance = SubstanceLibrary.lookup(substanceName.lowercased()),
           let duration = substance.resolveDuration(for: .oral) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            if timeToPeak > 0 {
                return PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke)
            }
        }
        return PKModel.defaultKa(ke: ke)
    }

    static func formatDuration(_ minutes: Double) -> String {
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
