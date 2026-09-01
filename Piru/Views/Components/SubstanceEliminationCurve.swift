import SwiftUI

/// The per-substance elimination curve — multi-dose one-compartment decay with
/// 50%/25% milestone lines, a "now" dot, and adaptive time-axis labels.
/// Extracted from ``InYourSystemView`` so the session detail's In Your Body
/// section renders the identical curve.
///
/// When ``projection`` is set **and the substance meaningfully accumulates**
/// (ratio ≥ 1.15), the curve extends past "now" with dashed projected future
/// doses at the detected regular interval, showing the steady-state trajectory.
/// A stats row below the graph shows the detected cadence, plateau, peak,
/// buildup×, and time to reach steady state.
struct SubstanceEliminationCurve: View {
    let active: ActiveSubstance
    /// What the surrounding row calls this substance. `ActiveSubstance.name` is
    /// always the canonical English name, so without this VoiceOver announces
    /// "Memantine" under a row the user sees as 美金刚.
    var displayName: String?
    var projection: SteadyStateProjection?

    private var showsProjection: Bool {
        guard let projection else { return false }
        return projection.result.accumulationRatio >= 1.15
    }

    /// All precomputed data the Canvas and stats need.
    private var curve: CurveData {
        CurveData(active: active, projection: showsProjection ? projection : nil)
    }

    var body: some View {
        let data = curve
        let color = active.color
        let halfLife = active.halfLifeMinutes

        VStack(spacing: 0) {
            curveCanvas(data: data, color: color, halfLife: halfLife)

            if showsProjection, let proj = projection {
                projectionStats(proj, color: color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Elimination curve for \(displayName ?? active.name)"))
        .accessibilityValue(Text("\(active.totalRemaining.doseFormatted) \(active.unit) remaining, \(Int(active.eliminatedFraction * 100))% eliminated, half-life \(Self.formatDuration(halfLife))"))
    }

    // MARK: - Canvas

    private func curveCanvas(data: CurveData, color: Color, halfLife: Double) -> some View {
        Canvas { context, size in
            let inset: CGFloat = 4
            let graphWidth = size.width - inset * 2
            let labelAreaHeight: CGFloat = 18
            let graphHeight = size.height - labelAreaHeight - inset
            guard graphHeight > 0 else { return }
            let baseline = inset + graphHeight
            let steps = data.curvePoints.count - 1
            guard steps > 0 else { return }

            func pointAt(_ i: Int) -> CGPoint {
                let x = inset + CGFloat(Double(i) / Double(steps)) * graphWidth
                let y = inset + graphHeight - CGFloat(data.curvePoints[i]) * graphHeight * 0.9
                return CGPoint(x: x, y: y)
            }

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

            // Split at "now" only when a projection continues the curve past it;
            // otherwise the actual decay draws to its end like any other curve.
            let splitStep = (data.hasProjection ? data.nowStep : nil).map { min($0, steps) } ?? steps

            // --- Actual portion (solid) ---
            var actualFill = Path()
            actualFill.move(to: CGPoint(x: inset, y: baseline))
            for i in 0 ... splitStep {
                actualFill.addLine(to: pointAt(i))
            }
            let splitX = pointAt(splitStep).x
            actualFill.addLine(to: CGPoint(x: splitX, y: baseline))
            actualFill.closeSubpath()
            context.fill(actualFill, with: .color(color.opacity(0.2)))

            var actualStroke = Path()
            for i in 0 ... splitStep {
                let p = pointAt(i)
                if i == 0 { actualStroke.move(to: p) } else { actualStroke.addLine(to: p) }
            }
            context.stroke(actualStroke, with: .color(color), lineWidth: 2)

            // --- Projected portion (dashed) ---
            if data.hasProjection, let ns = data.nowStep, ns < steps {
                var projFill = Path()
                projFill.move(to: CGPoint(x: splitX, y: baseline))
                for i in ns ... steps {
                    projFill.addLine(to: pointAt(i))
                }
                projFill.addLine(to: CGPoint(x: inset + graphWidth, y: baseline))
                projFill.closeSubpath()
                context.fill(projFill, with: .color(color.opacity(0.08)))

                var projStroke = Path()
                for i in ns ... steps {
                    let p = pointAt(i)
                    if i == ns { projStroke.move(to: p) } else { projStroke.addLine(to: p) }
                }
                context.stroke(projStroke, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                var nowLine = Path()
                nowLine.move(to: CGPoint(x: splitX, y: inset))
                nowLine.addLine(to: CGPoint(x: splitX, y: baseline))
                context.stroke(nowLine, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            // Current time dot
            if let c = data.currentNormalized {
                let x = inset + CGFloat(data.currentOffset / data.totalEndMinutes) * graphWidth
                let y = inset + graphHeight - CGFloat(c) * graphHeight * 0.9
                let dotSize: CGFloat = 7
                let dot = Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                context.fill(dot, with: .color(color))
                context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
            }

            // Time labels
            let endMinutes = data.totalEndMinutes
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
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("t½ = \(Self.formatDuration(halfLife))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(10)
        }
    }

    // MARK: - Projection stats

    private func projectionStats(_ proj: SteadyStateProjection, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projected · \(Self.cadenceText(proj.intervalHours))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(color.opacity(0.8))

            HStack(spacing: 0) {
                stat("Plateau", "\(proj.result.averageAmount.doseFormatted) \(proj.unit)")
                stat("Peak", "\(proj.result.peakAmount.doseFormatted) \(proj.unit)")
                stat("Buildup", "\(proj.result.accumulationRatio.formatted(.number.precision(.fractionLength(1))))×")
                stat("Reaches", Self.daysToSteadyText(proj.daysToSteady))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondaryLabel)
            Text(value)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    static func cadenceText(_ intervalHours: Double) -> String {
        if abs(intervalHours - 24) < 3 { return String(localized: "about daily") }
        if intervalHours >= 44, intervalHours <= 52 { return String(localized: "about every 2 days") }
        if intervalHours < 36 { return String(localized: "every ~\(Int(intervalHours.rounded())) h") }
        return String(localized: "every ~\((intervalHours / 24).formatted(.number.precision(.fractionLength(0 ... 1)))) days")
    }

    static func daysToSteadyText(_ days: Double) -> String {
        if days < 1 { return String(localized: "<1 day") }
        return String(localized: "~\(Int(days.rounded())) days")
    }

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

// MARK: - Precomputed curve data

/// Extracted so ``SubstanceEliminationCurve/body`` stays a pure `@ViewBuilder`
/// with no `var` mutation.
private struct CurveData {
    let curvePoints: [Double]
    let totalEndMinutes: Double
    let currentOffset: Double
    let currentNormalized: Double?
    let nowStep: Int?
    let hasProjection: Bool

    init(active: ActiveSubstance, projection: SteadyStateProjection?) {
        let halfLife = active.halfLifeMinutes
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = SubstanceEliminationCurve.estimateKa(for: active.name, ke: ke)
        let peakConc = PKModel.cmax(ke: ke, ka: ka)

        let sortedDoses = active.doses.sorted { $0.timestamp < $1.timestamp }
        let earliest = sortedDoses.first?.timestamp ?? .now
        let latestOffset = (sortedDoses.last?.timestamp.timeIntervalSince(earliest) ?? 0) / 60
        let tailMinutes = PKModel.timeToFraction(0.03, ke: ke, ka: ka, maxMinutes: halfLife * 8)
        let actualEndMinutes = max(1, latestOffset + tailMinutes)

        let realDoseOffsets: [(amount: Double, offset: Double)] = sortedDoses.map {
            ($0.amount, $0.timestamp.timeIntervalSince(earliest) / 60)
        }

        let currentOff = Date.now.timeIntervalSince(earliest) / 60
        currentOffset = currentOff

        // Build dose offsets including projected future doses
        var allDoses = realDoseOffsets
        let endMinutes: Double
        if let proj = projection, currentOff > 0 {
            hasProjection = true
            let intervalMin = proj.intervalHours * 60
            var nextDose = latestOffset + intervalMin
            while nextDose <= currentOff {
                nextDose += intervalMin
            }
            let projectionExtension = min(halfLife * 5, intervalMin * 8)
            let projEnd = currentOff + projectionExtension
            while nextDose <= projEnd {
                allDoses.append((proj.medianDose, nextDose))
                nextDose += intervalMin
            }
            endMinutes = max(actualEndMinutes, projEnd + tailMinutes * 0.3)
        } else {
            hasProjection = false
            endMinutes = actualEndMinutes
        }
        totalEndMinutes = endMinutes

        // Curve points
        let steps = hasProjection ? 180 : 120
        var rawPoints: [Double] = []
        rawPoints.reserveCapacity(steps + 1)
        var maxConc = 0.001
        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * endMinutes
            var c = 0.0
            if peakConc > 0 {
                for d in allDoses {
                    let elapsed = t - d.offset
                    if elapsed >= 0 {
                        c += d.amount * PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                    }
                }
            }
            rawPoints.append(c)
            maxConc = max(maxConc, c)
        }
        curvePoints = rawPoints.map { $0 / maxConc }

        // Now position
        if currentOff >= 0, currentOff <= endMinutes {
            nowStep = min(Int((currentOff / endMinutes) * Double(steps)), steps)
            if peakConc > 0, maxConc > 0 {
                var c = 0.0
                for d in realDoseOffsets {
                    let elapsed = currentOff - d.offset
                    if elapsed >= 0 {
                        c += d.amount * PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peakConc
                    }
                }
                currentNormalized = c / maxConc
            } else {
                currentNormalized = nil
            }
        } else {
            nowStep = nil
            currentNormalized = nil
        }
    }
}
