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

private struct ChartData {
    let pointsA: [CurvePoint]
    let pointsB: [CurvePoint]
    /// Hours from the first dose during which both curves are above
    /// ``InteractionOverlap/activeThreshold`` of their own peaks.
    let overlap: ClosedRange<Double>?
    /// Hours until the later curve falls to 5% of its peak.
    let totalHours: Double
    /// The hours the chart shows (``InteractionOverlap/visibleHours(totalHours:overlap:)``).
    let visibleHours: Double
    /// The substance whose curve runs past the chart's right edge, and the hour
    /// it falls to 5% of its peak; `nil` when both end on the chart.
    let continuing: (substance: Side, hours: Double)?

    enum Side { case a, b }
}

/// When two dose curves are both in the body, and how much of that the chart
/// shows. Pure functions over the one-compartment curve, so the window can be
/// tested without a substance database.
nonisolated enum InteractionOverlap {
    /// One dose's curve: its rate constants and its delay after the first dose.
    struct Curve {
        let ke: Double
        let ka: Double
        let offsetMinutes: Double
        private let peak: Double

        init(ke: Double, ka: Double, offsetMinutes: Double) {
            self.ke = ke
            self.ka = ka
            self.offsetMinutes = offsetMinutes
            peak = PKModel.cmax(ke: ke, ka: ka)
        }

        /// Concentration at `minutes` after the first dose, as a percentage of
        /// this curve's own peak.
        func percentOfPeak(at minutes: Double) -> Double {
            let elapsed = minutes - offsetMinutes
            guard elapsed >= 0, peak > 0 else { return 0 }
            return max(0, PKModel.concentration(at: elapsed, ke: ke, ka: ka) / peak * 100)
        }
    }

    /// A curve counts as active above this share of its own peak.
    static let activeThreshold: Double = 3

    /// Minutes from the first dose during which both curves are active, read
    /// minute by minute up to `horizonMinutes`; `nil` when they never are.
    static func window(_ a: Curve, _ b: Curve, horizonMinutes: Double) -> ClosedRange<Double>? {
        var start: Double?
        var end: Double?
        var minute = 0.0
        while minute <= horizonMinutes {
            if a.percentOfPeak(at: minute) > activeThreshold, b.percentOfPeak(at: minute) > activeThreshold {
                if start == nil { start = minute }
                end = minute
            }
            minute += 1
        }
        guard let start, let end else { return nil }
        return start ... end
    }

    /// The hours the chart shows: the overlap with half as much again after it
    /// (at least ``minimumVisibleHours``), so a short overlap beside a curve
    /// that lasts days still fills the chart. Both whole curves when they never
    /// overlap, or when the overlap is most of them.
    static func visibleHours(totalHours: Double, overlap: ClosedRange<Double>?) -> Double {
        guard let overlap else { return totalHours }
        let fitted = max(minimumVisibleHours, overlap.upperBound * 1.5)
        return fitted < totalHours * 0.8 ? fitted : totalHours
    }

    static let minimumVisibleHours: Double = 6
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
        guard let substance = SubstanceLibrary.lookup(name),
              let params = PKResolver.params(substance: substance, route: substance.defaultRoute)
        else { return nil }
        return PKParams(
            ke: params.ke, ka: params.ka, halfLifeMinutes: params.halfLifeMinutes,
            timeToPeakMinutes: PKModel.tmax(ke: params.ke, ka: params.ka),
        )
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
        let endA = offsetAMinutes + tailA
        let endB = offsetBMinutes + tailB
        let totalMinutes = max(endA, endB)
        let totalHours = totalMinutes / 60

        let curveA = InteractionOverlap.Curve(ke: pA.ke, ka: pA.ka, offsetMinutes: offsetAMinutes)
        let curveB = InteractionOverlap.Curve(ke: pB.ke, ka: pB.ka, offsetMinutes: offsetBMinutes)
        let overlap = InteractionOverlap.window(curveA, curveB, horizonMinutes: totalMinutes)
            .map { ($0.lowerBound / 60) ... ($0.upperBound / 60) }
        let visibleHours = InteractionOverlap.visibleHours(totalHours: totalHours, overlap: overlap)

        // Sampled over the hours shown, so a short window keeps its resolution.
        let steps = 200
        var pointsA: [CurvePoint] = []
        var pointsB: [CurvePoint] = []
        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * visibleHours * 60
            pointsA.append(CurvePoint(hours: t / 60, concentration: curveA.percentOfPeak(at: t)))
            pointsB.append(CurvePoint(hours: t / 60, concentration: curveB.percentOfPeak(at: t)))
        }

        let continuing: (substance: ChartData.Side, hours: Double)? = if visibleHours >= totalHours {
            nil
        } else {
            endA >= endB ? (.a, endA / 60) : (.b, endB / 60)
        }
        return ChartData(
            pointsA: pointsA, pointsB: pointsB, overlap: overlap,
            totalHours: totalHours, visibleHours: visibleHours, continuing: continuing,
        )
    }
}

/// The overlap timeline for one interacting pair. Its init stores four values and
/// builds nothing, so a result list can construct one per row as a link destination;
/// the model is built when the screen is shown.
struct InteractionTimelineView: View {
    let substanceA: String
    let substanceB: String
    let severity: InteractionSeverity
    let mechanism: String

    var body: some View {
        InteractionTimelineScreen(
            substanceA: substanceA, substanceB: substanceB,
            severity: severity, mechanism: mechanism,
        )
    }
}

private struct InteractionTimelineScreen: View {
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
                    TimelineMissingDataCard(names: model.missingData)
                }

                if let data = model.chartData {
                    TimelineChartCard(
                        data: data, substanceA: substanceA, substanceB: substanceB,
                        referenceTime: model.referenceTime,
                    )
                    TimelineDetailsCard(
                        data: data, severity: severity,
                        substanceA: substanceA, substanceB: substanceB,
                        timeA: $model.ingestTimeA, timeB: $model.ingestTimeB,
                        hasRecentEntryA: hasRecentEntryA, hasRecentEntryB: hasRecentEntryB,
                        paramsA: model.paramsA, paramsB: model.paramsB,
                    )
                }

                TimelineAnalysisCard(
                    substanceA: substanceA, substanceB: substanceB,
                    severity: severity, mechanism: mechanism,
                    depression: model.depression, attenuations: model.attenuations,
                    referenceTime: model.referenceTime,
                )

                TimelineDisclaimer()
            }
            .padding()
        }
        .skinBackdrop()
        .navigationTitle("Interaction Timeline")
        .inlineNavigationTitle()
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
}

// MARK: - Missing Data

private struct TimelineMissingDataCard: View {
    let names: [String]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.piru(.title2))
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            ForEach(names, id: \.self) { name in
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
}

// MARK: - Chart

private let colorA = Color.blue
private let colorB = Color.orange

private struct TimelineChartCard: View {
    let data: ChartData
    let substanceA: String
    let substanceB: String
    let referenceTime: Date

    var body: some View {
        let nowHours = Date.now.timeIntervalSince(referenceTime) / 3_600
        let showNowMarker = nowHours > 0.05 && nowHours < data.visibleHours
        let showsDays = data.visibleHours > 48

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Chart {
                // The window the screen is about, shaded under both curves.
                if let overlap = data.overlap {
                    RectangleMark(
                        xStart: .value("Overlap start", overlap.lowerBound),
                        xEnd: .value("Overlap end", min(overlap.upperBound, data.visibleHours)),
                        yStart: .value("Floor", 0.0),
                        yEnd: .value("Ceiling", 105.0),
                    )
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.12))
                }

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
                AxisMarks(values: showsDays ? .stride(by: 24) : .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Group {
                                if showsDays {
                                    Text("\(Int(h / 24))d")
                                } else {
                                    Text("\(Int(h))h")
                                }
                            }
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
            .chartXScale(domain: 0 ... data.visibleHours)
            .chartYScale(domain: 0 ... 105)
            .chartLegend(.hidden)
            .frame(height: 220)
            .chartSummaryAccessibility(
                label: Text("Concentration Curves"),
                value: data.overlap.map { w in
                    Text("\(substanceA) and \(substanceB) over time; both active from \(formatHours(w.lowerBound)) to \(formatHours(w.upperBound)).")
                } ?? Text("\(substanceA) and \(substanceB) over time; the model shows no overlapping window."),
            )

            HStack(spacing: Spacing.xxl) {
                legendItem(color: colorA, label: substanceA)
                legendItem(color: colorB, label: substanceB)
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Each curve is a percentage of its own peak.")
                if let continuing = data.continuing {
                    let name = continuing.substance == .a ? substanceA : substanceB
                    Text("\(name) runs past the chart, to ~\(formatDuration(continuing.hours * 60)).")
                }
            }
            .captionSecondary()
        }
        .padding()
        .themeCard()
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 12, height: 2)
            Text(label)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
    }
}

// MARK: - Details (time controls + PK info + overlap — one card)

private struct TimelineDetailsCard: View {
    let data: ChartData
    let severity: InteractionSeverity
    let substanceA: String
    let substanceB: String
    @Binding var timeA: Date
    @Binding var timeB: Date
    let hasRecentEntryA: Bool
    let hasRecentEntryB: Bool
    let paramsA: PKParams?
    let paramsB: PKParams?

    private var timePickerRange: ClosedRange<Date> {
        Date.now.addingTimeInterval(-48 * 3_600) ... Date.now.addingTimeInterval(12 * 3_600)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            substanceDetailRow(
                name: substanceA, color: colorA, time: $timeA,
                hasRecentEntry: hasRecentEntryA, params: paramsA,
            )

            Divider().padding(.leading, 22)

            substanceDetailRow(
                name: substanceB, color: colorB, time: $timeB,
                hasRecentEntry: hasRecentEntryB, params: paramsB,
            )

            let window = data.overlap
            Divider().padding(.leading, 22)

            HStack(spacing: Spacing.md) {
                // Neutral when the curves miss each other: the interaction is
                // documented either way, and a green mark here reads as "safe".
                Image(systemName: window != nil ? "clock.arrow.2.circlepath" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(window != nil ? severity.labelColor : Theme.secondaryLabel)
                    .accessibilityHidden(true)
                if let window {
                    Text("Both active \(formatHours(window.lowerBound))–\(formatHours(window.upperBound)) (\(formatHours(window.upperBound - window.lowerBound)) overlap)")
                        .captionSecondary()
                } else {
                    Text("No overlap shown by this model. The interaction may still apply.")
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
}

// MARK: - Analysis (warning + depression + attenuation — one card)

private struct TimelineAnalysisCard: View {
    let substanceA: String
    let substanceB: String
    let severity: InteractionSeverity
    let mechanism: String
    let depression: CombinedDepressionResult?
    let attenuations: [EffectAttenuationResult]
    let referenceTime: Date

    var body: some View {
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
            if let depression, depression.hasMeaningfulLoad {
                Divider().padding(.leading, 36)
                depressionSection(depression)
                    .padding(Spacing.xxl)
            }

            // Effect attenuation
            ForEach(attenuations) { attenuation in
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
        let peakHours = max(0, d.peakDate.timeIntervalSince(referenceTime) / 3_600)
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
            return String(localized: "Modeled from receptor occupancy · \(confidence).")
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
}

// MARK: - Disclaimer (footer text, no card)

private struct TimelineDisclaimer: View {
    var body: some View {
        Text("A one-compartment model with population-average half-lives. Real overlap depends on your metabolism, dose, route, and tolerance.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
    }
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
        return String(localized: "\(hours.formatted(.number.precision(.fractionLength(1))))h")
    }
    let days = hours / 24
    return String(localized: "\(days.formatted(.number.precision(.fractionLength(1)))) days")
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
    return String(localized: "\(hours.formatted(.number.precision(.fractionLength(1))))h")
}
