import Charts
import SwiftData
import SwiftUI

private struct PKParams {
    let ke: Double
    let ka: Double
    let halfLifeMinutes: Double
    let timeToPeakMinutes: Double
}

private struct CurveInputs: Equatable {
    let substanceA: String
    let substanceB: String
    let timeA: Date
    let timeB: Date
}

private struct MatchedDose {
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
}

private struct CurvePoint {
    let hours: Double
    let concentration: Double
}

private struct OverlapPoint {
    let hours: Double
    let minConcentration: Double
}

private struct ChartData {
    let pointsA: [CurvePoint]
    let pointsB: [CurvePoint]
    let overlap: [OverlapPoint]
    let totalHours: Double
}

@Observable @MainActor
private final class InteractionTimelineModel {
    let substanceA: String
    let substanceB: String
    var ingestTimeA: Date
    var ingestTimeB: Date

    private(set) var paramsA: PKParams?
    private(set) var paramsB: PKParams?
    private(set) var chartData: ChartData?
    private(set) var matchedA: MatchedDose?
    private(set) var matchedB: MatchedDose?
    private(set) var depression: CombinedDepressionResult?
    private(set) var attenuations: [EffectAttenuationResult] = []
    private var didAutoDetect = false
    private var computedFor: CurveInputs?

    init(substanceA: String, substanceB: String) {
        self.substanceA = substanceA
        self.substanceB = substanceB
        let now = Date.now
        ingestTimeA = now
        ingestTimeB = now
        let pA = Self.resolveParams(for: substanceA)
        let pB = Self.resolveParams(for: substanceB)
        paramsA = pA
        paramsB = pB
        if let pA, let pB {
            chartData = Self.generateCurveData(pA: pA, pB: pB, ingestTimeA: now, ingestTimeB: now)
        }
        let inputs = CurveInputs(substanceA: substanceA, substanceB: substanceB, timeA: now, timeB: now)
        attenuations = computeAttenuations(for: inputs)
        computedFor = inputs
    }

    var curveInputs: CurveInputs {
        CurveInputs(substanceA: substanceA, substanceB: substanceB, timeA: ingestTimeA, timeB: ingestTimeB)
    }

    var referenceTime: Date {
        min(ingestTimeA, ingestTimeB)
    }

    var missingData: [String] {
        var missing: [String] = []
        if paramsA == nil { missing.append(substanceA) }
        if paramsB == nil { missing.append(substanceB) }
        return missing
    }

    func recompute() {
        let inputs = curveInputs
        guard inputs != computedFor else { return }
        let pA = Self.resolveParams(for: inputs.substanceA)
        let pB = Self.resolveParams(for: inputs.substanceB)
        paramsA = pA
        paramsB = pB
        if let pA, let pB {
            chartData = Self.generateCurveData(
                pA: pA, pB: pB,
                ingestTimeA: inputs.timeA, ingestTimeB: inputs.timeB,
            )
        } else {
            chartData = nil
        }
        depression = computeDepression(for: inputs)
        attenuations = computeAttenuations(for: inputs)
        computedFor = inputs
    }

    func autoDetect(entries: [DoseEntry]) {
        guard !didAutoDetect else { return }
        didAutoDetect = true
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        if let entry = entries.first(where: {
            $0.substance.lowercased() == substanceA.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeA = entry.timestamp
            matchedA = MatchedDose(amount: entry.amount, unit: entry.unit, route: entry.route)
        }
        if let entry = entries.first(where: {
            $0.substance.lowercased() == substanceB.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeB = entry.timestamp
            matchedB = MatchedDose(amount: entry.amount, unit: entry.unit, route: entry.route)
        }
        depression = computeDepression(for: curveInputs)
    }

    private func computeAttenuations(for inputs: CurveInputs) -> [EffectAttenuationResult] {
        let entries = [
            DoseEntry(substance: inputs.substanceA, amount: matchedA?.amount ?? 1, unit: matchedA?.unit ?? "mg", route: matchedA?.route ?? .oral, timestamp: inputs.timeA),
            DoseEntry(substance: inputs.substanceB, amount: matchedB?.amount ?? 1, unit: matchedB?.unit ?? "mg", route: matchedB?.route ?? .oral, timestamp: inputs.timeB),
        ]
        return EffectAttenuation.analyze(entries: entries)
    }

    private func computeDepression(for inputs: CurveInputs) -> CombinedDepressionResult? {
        guard let a = matchedA, let b = matchedB else { return nil }
        let entries = [
            DoseEntry(substance: inputs.substanceA, amount: a.amount, unit: a.unit, route: a.route, timestamp: inputs.timeA),
            DoseEntry(substance: inputs.substanceB, amount: b.amount, unit: b.unit, route: b.route, timestamp: inputs.timeB),
        ]
        guard let result = CombinedDepression.analyze(entries: entries), result.totalCount >= 2 else { return nil }
        return result
    }

    private static func resolveParams(for name: String) -> PKParams? {
        let substance = SubstanceLibrary.lookup(name)
        guard let halfLife = substance?.halfLifeMinutes, halfLife > 0 else { return nil }

        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka: Double
        if let substance,
           let duration = substance.resolveDuration(for: substance.defaultRoute) {
            let timeToPeak = (duration.onset?.midpoint ?? 0) + (duration.comeup?.midpoint ?? 0)
            if timeToPeak > 0 {
                ka = PKModel.estimateKa(timeToPeak: timeToPeak, ke: ke)
            } else {
                ka = PKModel.defaultKa(ke: ke)
            }
        } else {
            ka = PKModel.defaultKa(ke: ke)
        }

        let tmax = PKModel.tmax(ke: ke, ka: ka)
        return PKParams(ke: ke, ka: ka, halfLifeMinutes: halfLife, timeToPeakMinutes: tmax)
    }

    private static func generateCurveData(
        pA: PKParams, pB: PKParams,
        ingestTimeA: Date, ingestTimeB: Date,
    ) -> ChartData {
        let referenceTime = min(ingestTimeA, ingestTimeB)
        let offsetAMinutes = ingestTimeA.timeIntervalSince(referenceTime) / 60
        let offsetBMinutes = ingestTimeB.timeIntervalSince(referenceTime) / 60

        let tailA = PKModel.timeToFraction(0.05, ke: pA.ke, ka: pA.ka, maxMinutes: pA.halfLifeMinutes * 7)
        let tailB = PKModel.timeToFraction(0.05, ke: pB.ke, ka: pB.ka, maxMinutes: pB.halfLifeMinutes * 7)
        let totalMinutes = max(offsetAMinutes + tailA, offsetBMinutes + tailB)
        let totalHours = totalMinutes / 60

        let cmaxA = PKModel.cmax(ke: pA.ke, ka: pA.ka)
        let cmaxB = PKModel.cmax(ke: pB.ke, ka: pB.ka)

        let steps = 200
        var pointsA: [CurvePoint] = []
        var pointsB: [CurvePoint] = []
        var overlap: [OverlapPoint] = []

        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * totalMinutes
            let hours = t / 60

            let elapsedA = t - offsetAMinutes
            let concA: Double = if elapsedA >= 0, cmaxA > 0 {
                max(0, PKModel.concentration(at: elapsedA, ke: pA.ke, ka: pA.ka) / cmaxA * 100)
            } else {
                0
            }

            let elapsedB = t - offsetBMinutes
            let concB: Double = if elapsedB >= 0, cmaxB > 0 {
                max(0, PKModel.concentration(at: elapsedB, ke: pB.ke, ka: pB.ka) / cmaxB * 100)
            } else {
                0
            }

            pointsA.append(CurvePoint(hours: hours, concentration: concA))
            pointsB.append(CurvePoint(hours: hours, concentration: concB))

            let minConc = min(concA, concB)
            if concA > 3, concB > 3 {
                overlap.append(OverlapPoint(hours: hours, minConcentration: minConc))
            }
        }

        return ChartData(pointsA: pointsA, pointsB: pointsB, overlap: overlap, totalHours: totalHours)
    }
}

struct InteractionTimelineView: View {
    let substanceA: String
    let substanceB: String
    let severity: InteractionSeverity
    let mechanism: String

    @Query private var allEntries: [DoseEntry]

    @State private var model: InteractionTimelineModel

    init(substanceA: String, substanceB: String, severity: InteractionSeverity, mechanism: String) {
        self.substanceA = substanceA
        self.substanceB = substanceB
        self.severity = severity
        self.mechanism = mechanism
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _allEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp > cutoff },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
        _model = State(initialValue: InteractionTimelineModel(substanceA: substanceA, substanceB: substanceB))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                if !model.missingData.isEmpty {
                    missingDataSection
                }

                if let data = model.chartData {
                    chartSection(data: data)
                    detailsCard(data: data)
                }

                analysisCard

                disclaimerFooter
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Interaction Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.curveInputs) { model.recompute() }
        .onAppear { model.autoDetect(entries: allEntries) }
    }

    private var hasRecentEntryA: Bool {
        allEntries.contains {
            $0.substance.lowercased() == substanceA.lowercased()
        }
    }

    private var hasRecentEntryB: Bool {
        allEntries.contains {
            $0.substance.lowercased() == substanceB.lowercased()
        }
    }

    // MARK: - Missing Data

    private var missingDataSection: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            ForEach(model.missingData, id: \.self) { name in
                Text("Half-life data unavailable for \(name)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themeCard()
    }

    // MARK: - Chart

    private let colorA = Color.blue
    private let colorB = Color.orange

    private func chartSection(data: ChartData) -> some View {
        let nowHours = Date.now.timeIntervalSince(model.referenceTime) / 3_600
        let showNowMarker = nowHours > 0.05 && nowHours < data.totalHours

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Chart {
                ForEach(data.pointsA, id: \.hours) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration),
                        series: .value("Substance", "A"),
                    )
                    .foregroundStyle(colorA)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                ForEach(data.pointsB, id: \.hours) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration),
                        series: .value("Substance", "B"),
                    )
                    .foregroundStyle(colorB)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if showNowMarker {
                    RuleMark(x: .value("Now", nowHours))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text("\(Int(h))h")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXScale(domain: 0 ... data.totalHours)
            .chartYScale(domain: 0 ... 105)
            .chartLegend(.hidden)
            .frame(height: 220)
            .chartSummaryAccessibility(
                label: Text("Concentration Curves"),
                value: {
                    let window = overlapWindow(in: data)
                    return window.map { w in
                        Text("\(substanceA) and \(substanceB) over time; both active from \(formatHours(w.start)) to \(formatHours(w.end)).")
                    } ?? Text("\(substanceA) and \(substanceB) over time; no overlapping active window.")
                }(),
            )

            HStack(spacing: Spacing.xxl) {
                legendItem(color: colorA, label: substanceA)
                legendItem(color: colorB, label: substanceB)
            }
            .font(.caption)
        }
        .padding()
        .themeCard()
    }

    private func legendItem(color: Color, label: String, filled: Bool = false) -> some View {
        HStack(spacing: Spacing.xs) {
            if filled {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 12, height: 8)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 12, height: 2)
            }
            Text(label)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
    }

    // MARK: - Details (time controls + PK info + overlap — one card)

    private var timePickerRange: ClosedRange<Date> {
        Date.now.addingTimeInterval(-48 * 3_600) ... Date.now.addingTimeInterval(12 * 3_600)
    }

    private func detailsCard(data: ChartData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            substanceDetailRow(
                name: substanceA, color: colorA, time: $model.ingestTimeA,
                hasRecentEntry: hasRecentEntryA, params: model.paramsA,
            )

            Divider().padding(.leading, 22)

            substanceDetailRow(
                name: substanceB, color: colorB, time: $model.ingestTimeB,
                hasRecentEntry: hasRecentEntryB, params: model.paramsB,
            )

            let window = overlapWindow(in: data)
            Divider().padding(.leading, 22)

            HStack(spacing: Spacing.md) {
                Image(systemName: window != nil ? "clock.arrow.2.circlepath" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(window != nil ? severity.labelColor : Color.successText)
                    .accessibilityHidden(true)
                if let window {
                    Text("Both active \(formatHours(window.start))–\(formatHours(window.end)) (\(formatHours(window.end - window.start)) overlap)")
                        .captionSecondary()
                } else {
                    Text("No active overlap at this timing")
                        .captionSecondary()
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.lg)
        }
        .themeCard()
    }

    private func substanceDetailRow(
        name: String, color: Color, time: Binding<Date>,
        hasRecentEntry: Bool, params: PKParams?,
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                LegendDot(color: color)
                Text(name)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 4)
                if hasRecentEntry {
                    Text(time.wrappedValue.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    DatePicker("", selection: time, in: timePickerRange)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            if let params {
                HStack(spacing: Spacing.xl) {
                    Label("t\u{00BD} \(formatDuration(params.halfLifeMinutes))", systemImage: "clock")
                    Label("Peak \(formatDuration(params.timeToPeakMinutes))", systemImage: "arrow.up")
                }
                .captionSecondary()
                .padding(.leading, Spacing.xxl)
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Analysis (warning + depression + attenuation — one card)

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Warning
            HStack(alignment: .top, spacing: Spacing.lg) {
                Image(systemName: severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(severity.labelColor)
                    .font(.body)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(severity.label): \(substanceA) + \(substanceB)")
                        .sectionLabel()
                        .foregroundStyle(severity.labelColor)
                    Text(mechanism)
                        .captionSecondary()
                }
            }
            .padding(Spacing.xxl)

            // Combined depression
            if let depression = model.depression, depression.hasMeaningfulLoad {
                Divider().padding(.leading, 36)
                depressionSection(depression)
                    .padding(Spacing.xxl)
            }

            // Effect attenuation
            ForEach(model.attenuations) { attenuation in
                Divider().padding(.leading, 36)
                attenuationSection(attenuation)
                    .padding(Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private func depressionSection(_ d: CombinedDepressionResult) -> some View {
        let bandColor = d.band?.labelColor ?? Theme.secondaryLabel
        let bandFill = d.band?.color ?? Theme.secondaryLabel
        let peakHours = max(0, d.peakDate.timeIntervalSince(model.referenceTime) / 3_600)
        let yMax = max(CombinedDepression.dangerousThreshold * 1.1, d.peakLoad * 1.1)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "lungs.fill")
                    .foregroundStyle(bandColor)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Combined depression peaks around \(peakClockTime(d.peakDate))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let level = d.levelLabel {
                    Text(level)
                        .capsuleChip(text: bandColor, fill: bandFill)
                }
            }

            Chart {
                ForEach(Array(d.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", point.minute / 60),
                        y: .value("Load", point.load),
                    )
                    .foregroundStyle(bandColor.opacity(Theme.Opacity.tintActive))
                    .interpolationMethod(.monotone)
                }
                ForEach(Array(d.points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.minute / 60),
                        y: .value("Load", point.load),
                    )
                    .foregroundStyle(bandColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                RuleMark(y: .value("Dangerous", CombinedDepression.dangerousThreshold))
                    .foregroundStyle(InteractionSeverity.dangerous.color.opacity(Theme.Opacity.dimmed))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(x: .value("Peak", peakHours))
                    .foregroundStyle(bandColor.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text("\(Int(h))h").font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... yMax)
            .frame(height: 100)

            Text(depressionCaveat(d))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func depressionCaveat(_ d: CombinedDepressionResult) -> String {
        let confidence = String(localized: d.confidence.label)
        if d.isFullyModeled {
            return String(localized: "Predicted from receptor occupancy · \(confidence).")
        }
        if d.modeledCount == 0 {
            return String(localized: "Estimated from effect curves · \(confidence).")
        }
        return String(localized: "\(d.modeledCount) of \(d.totalCount) substances from receptor occupancy, the rest estimated from effect curves · \(confidence).")
    }

    private func peakClockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func attenuationSection(_ a: EffectAttenuationResult) -> some View {
        let blockerPhrase = ListFormatter.localizedString(byJoining: a.blockers)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "arrow.down.right.circle")
                    .foregroundStyle(Theme.secondaryLabel)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Reduced effect (~\(a.reductionRangeText))")
                    .font(.subheadline.weight(.medium))
            }
            Text("\(blockerPhrase) blocks the \(String(localized: a.transporter.displayName)) that \(a.attenuated) needs to work.")
                .captionSecondary()
        }
    }

    // MARK: - Overlap Window

    private func overlapWindow(in data: ChartData) -> (start: Double, end: Double)? {
        guard let first = data.overlap.first, let last = data.overlap.last else { return nil }
        return (first.hours, last.hours)
    }

    // MARK: - Disclaimer (footer text, no card)

    private var disclaimerFooter: some View {
        Text("Estimate only — simplified one-compartment PK model with population-average half-lives. Real overlap depends on individual metabolism, dose, route, and tolerance. Not medical advice.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
    }

    // MARK: - Formatting

    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 60 {
            let m = Int(minutes)
            return String(localized: "\(m) min")
        }
        let hours = minutes / 60
        if hours < 24 {
            if hours == hours.rounded(.toNearestOrEven) {
                let h = Int(hours)
                return String(localized: "\(h)h")
            }
            return String(localized: "\(String(format: "%.1f", hours))h")
        }
        let days = hours / 24
        return String(localized: "\(String(format: "%.1f", days)) days")
    }

    private func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            let m = Int(hours * 60)
            return String(localized: "\(m)min")
        }
        if hours == hours.rounded(.toNearestOrEven) {
            let h = Int(hours)
            return String(localized: "\(h)h")
        }
        return String(localized: "\(String(format: "%.1f", hours))h")
    }
}
