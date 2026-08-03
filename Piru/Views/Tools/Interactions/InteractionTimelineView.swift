import Charts
import SwiftData
import SwiftUI

struct InteractionTimelineView: View {
    let substanceA: String
    let substanceB: String
    let severity: InteractionSeverity

    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]

    @State private var ingestTimeA: Date
    @State private var ingestTimeB: Date
    @State private var didAutoDetect = false

    // Resolved PK params + generated curves are cached in @State and refreshed
    // by `.task(id: curveInputs)` — one library lookup, Newton ka solve, and
    // 200-sample generation per input change instead of several per body eval.
    @State private var paramsA: PKParams?
    @State private var paramsB: PKParams?
    @State private var chartData: ChartData?
    @State private var computedFor: CurveInputs?

    // Real logged doses for the two substances (within 48 h), captured on auto-detect. The
    // combined-depression index is a dose-resolved readout, so it is only computed when both
    // depressants have an actual logged dose — never fabricated from names alone.
    @State private var matchedA: MatchedDose?
    @State private var matchedB: MatchedDose?
    @State private var depression: CombinedDepressionResult?
    @State private var attenuations: [EffectAttenuationResult] = []

    private struct MatchedDose {
        let amount: Double
        let unit: String
        let route: RouteOfAdministration
    }

    init(substanceA: String, substanceB: String, severity: InteractionSeverity) {
        self.substanceA = substanceA
        self.substanceB = substanceB
        self.severity = severity
        // Seed synchronously so the first frame already renders the chart,
        // exactly as when everything was computed inline in `body`.
        let now = Date.now
        let pA = Self.resolveParams(for: substanceA)
        let pB = Self.resolveParams(for: substanceB)
        _ingestTimeA = State(initialValue: now)
        _ingestTimeB = State(initialValue: now)
        _paramsA = State(initialValue: pA)
        _paramsB = State(initialValue: pB)
        if let pA, let pB {
            _chartData = State(initialValue: Self.generateCurveData(
                pA: pA, pB: pB,
                substanceA: substanceA, substanceB: substanceB,
                ingestTimeA: now, ingestTimeB: now,
            ))
        }
        _computedFor = State(initialValue: CurveInputs(
            substanceA: substanceA, substanceB: substanceB, timeA: now, timeB: now,
        ))
    }

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

    private var curveInputs: CurveInputs {
        CurveInputs(substanceA: substanceA, substanceB: substanceB, timeA: ingestTimeA, timeB: ingestTimeB)
    }

    private func recompute(for inputs: CurveInputs) {
        guard inputs != computedFor else { return }
        let pA = Self.resolveParams(for: inputs.substanceA)
        let pB = Self.resolveParams(for: inputs.substanceB)
        paramsA = pA
        paramsB = pB
        if let pA, let pB {
            chartData = Self.generateCurveData(
                pA: pA, pB: pB,
                substanceA: inputs.substanceA, substanceB: inputs.substanceB,
                ingestTimeA: inputs.timeA, ingestTimeB: inputs.timeB,
            )
        } else {
            chartData = nil
        }
        depression = computeDepression(for: inputs)
        attenuations = computeAttenuations(for: inputs)
        computedFor = inputs
    }

    /// Sign-flipped readout: if one substance is a transporter releaser and the other blocks reuptake
    /// at that transporter (e.g. MDMA + an SSRI), surface the predicted *reduced* effect — distinct from
    /// the danger warning. Built from the two matched doses; persistent (SSRI) blockers gate on
    /// co-presence, so explicit timestamps aren't required.
    private func computeAttenuations(for inputs: CurveInputs) -> [EffectAttenuationResult] {
        let entries = [
            DoseEntry(substance: inputs.substanceA, amount: matchedA?.amount ?? 1, unit: matchedA?.unit ?? "mg", route: matchedA?.route ?? .oral, timestamp: inputs.timeA),
            DoseEntry(substance: inputs.substanceB, amount: matchedB?.amount ?? 1, unit: matchedB?.unit ?? "mg", route: matchedB?.route ?? .oral, timestamp: inputs.timeB),
        ]
        return EffectAttenuation.analyze(entries: entries)
    }

    /// The combined CNS/respiratory-depression index for the pair, computed from the two real logged
    /// doses at the (possibly adjusted) ingestion times. Nil unless both substances are additive
    /// depressants *and* both have an actual logged dose — the index is a dose-resolved readout, so it
    /// is never fabricated from names alone (the dose-blind explorer keeps the concentration overlap).
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
        let substance = SubstanceLibrary.lookupByNameOrAlias(name)
        let halfLife = substance?.halfLifeMinutes ?? HalfLifeDatabase.halfLife(for: name)
        guard let halfLife, halfLife > 0 else { return nil }

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

    private var missingData: [String] {
        var missing: [String] = []
        if paramsA == nil { missing.append(substanceA) }
        if paramsB == nil { missing.append(substanceB) }
        return missing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !missingData.isEmpty {
                    missingDataSection
                }

                if let data = chartData {
                    chartSection(data: data)
                    timeControlsSection
                    overlapCard(data: data)
                }

                if let depression, depression.hasMeaningfulLoad {
                    depressionCard(depression)
                }

                ForEach(attenuations) { attenuation in
                    attenuationCard(attenuation)
                }

                warningCard
                if let pA = paramsA, let pB = paramsB {
                    substanceInfoCards(pA: pA, pB: pB)
                }

                disclaimerCard
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Interaction Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: curveInputs) { recompute(for: curveInputs) }
        .onAppear { autoDetectTimes() }
    }

    // MARK: - Auto-Detection

    private func autoDetectTimes() {
        guard !didAutoDetect else { return }
        didAutoDetect = true
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        if let entry = allEntries.first(where: {
            $0.substance.lowercased() == substanceA.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeA = entry.timestamp
            matchedA = MatchedDose(amount: entry.amount, unit: entry.unit, route: entry.route)
        }
        if let entry = allEntries.first(where: {
            $0.substance.lowercased() == substanceB.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeB = entry.timestamp
            matchedB = MatchedDose(amount: entry.amount, unit: entry.unit, route: entry.route)
        }
        depression = computeDepression(for: curveInputs)
    }

    private var hasRecentEntryA: Bool {
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        return allEntries.contains {
            $0.substance.lowercased() == substanceA.lowercased() && $0.timestamp > cutoff
        }
    }

    private var hasRecentEntryB: Bool {
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        return allEntries.contains {
            $0.substance.lowercased() == substanceB.lowercased() && $0.timestamp > cutoff
        }
    }

    // MARK: - Missing Data

    private var missingDataSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.secondaryLabel)
            ForEach(missingData, id: \.self) { name in
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

    private struct CurvePoint {
        let hours: Double
        let concentration: Double
        let substance: String
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

    /// Reference time for the chart x-axis (the earlier of the two ingestion times).
    private var referenceTime: Date {
        min(ingestTimeA, ingestTimeB)
    }

    private static func generateCurveData(
        pA: PKParams, pB: PKParams,
        substanceA: String, substanceB: String,
        ingestTimeA: Date, ingestTimeB: Date,
    ) -> ChartData {
        let referenceTime = min(ingestTimeA, ingestTimeB)
        let offsetAMinutes = ingestTimeA.timeIntervalSince(referenceTime) / 60
        let offsetBMinutes = ingestTimeB.timeIntervalSince(referenceTime) / 60

        let tailA = PKModel.timeToFraction(0.03, ke: pA.ke, ka: pA.ka, maxMinutes: pA.halfLifeMinutes * 8)
        let tailB = PKModel.timeToFraction(0.03, ke: pB.ke, ka: pB.ka, maxMinutes: pB.halfLifeMinutes * 8)
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

            pointsA.append(CurvePoint(hours: hours, concentration: concA, substance: substanceA))
            pointsB.append(CurvePoint(hours: hours, concentration: concB, substance: substanceB))

            let minConc = min(concA, concB)
            if concA > 3, concB > 3 {
                overlap.append(OverlapPoint(hours: hours, minConcentration: minConc))
            }
        }

        return ChartData(pointsA: pointsA, pointsB: pointsB, overlap: overlap, totalHours: totalHours)
    }

    private let colorA = Color.blue
    private let colorB = Color.orange

    private func chartSection(data: ChartData) -> some View {
        let nowHours = Date.now.timeIntervalSince(referenceTime) / 3_600
        let showNowMarker = nowHours > 0.05 && nowHours < data.totalHours
        let window = overlapWindow(in: data)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Concentration Curves")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Chart {
                ForEach(data.overlap, id: \.hours) { point in
                    AreaMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.minConcentration),
                    )
                    .foregroundStyle(severity.color.opacity(0.2))
                    .interpolationMethod(.monotone)
                }

                ForEach(data.pointsA, id: \.hours) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration),
                    )
                    .foregroundStyle(colorA)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                ForEach(data.pointsB, id: \.hours) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration),
                    )
                    .foregroundStyle(colorB)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if showNowMarker {
                    RuleMark(x: .value("Now", nowHours))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("Now")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
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
            .chartYScale(domain: 0 ... 105)
            .chartLegend(.hidden)
            .frame(height: 220)
            .chartSummaryAccessibility(
                label: Text("Concentration Curves"),
                value: window.map { w in
                    Text("\(substanceA) and \(substanceB) over time; both active from \(formatHours(w.start)) to \(formatHours(w.end)).")
                } ?? Text("\(substanceA) and \(substanceB) over time; no overlapping active window."),
            )

            HStack(spacing: 16) {
                legendItem(color: colorA, label: substanceA)
                legendItem(color: colorB, label: substanceB)
                legendItem(color: severity.color.opacity(0.4), label: String(localized: "Overlap"), filled: true)
            }
            .font(.caption)
        }
        .padding()
        .themeCard()
    }

    private func legendItem(color: Color, label: String, filled: Bool = false) -> some View {
        HStack(spacing: 4) {
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

    // MARK: - Time Controls

    private var timePickerRange: ClosedRange<Date> {
        Date.now.addingTimeInterval(-48 * 3_600) ... Date.now.addingTimeInterval(12 * 3_600)
    }

    private var timeControlsSection: some View {
        VStack(spacing: 12) {
            substanceTimeRow(name: substanceA, color: colorA, time: $ingestTimeA, hasRecentEntry: hasRecentEntryA)
            substanceTimeRow(name: substanceB, color: colorB, time: $ingestTimeB, hasRecentEntry: hasRecentEntryB)
        }
    }

    private func substanceTimeRow(name: String, color: Color, time: Binding<Date>, hasRecentEntry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if hasRecentEntry {
                    Text("From journal")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.10), in: Capsule())
                        .foregroundStyle(color)
                }
            }

            HStack {
                Text("Ingestion time")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                DatePicker("", selection: time, in: timePickerRange)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            Text(relativeTimeDescription(time.wrappedValue))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .themeCard()
    }

    private func relativeTimeDescription(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if abs(interval) < 60 { return String(localized: "Right now") }
        if interval > 0 {
            return String(localized: "\(formatDuration(interval / 60)) ago")
        } else {
            return String(localized: "In \(formatDuration(-interval / 60))")
        }
    }

    // MARK: - Overlap Window

    private func overlapWindow(in data: ChartData) -> (start: Double, end: Double)? {
        guard let first = data.overlap.first, let last = data.overlap.last else { return nil }
        return (first.hours, last.hours)
    }

    private func overlapCard(data: ChartData) -> some View {
        let window = overlapWindow(in: data)

        return VStack(alignment: .leading, spacing: 8) {
            if let window {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(severity.labelColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Both substances active")
                            .font(.subheadline.weight(.semibold))
                        Text("From \(formatHours(window.start)) to \(formatHours(window.end)) (\(formatHours(window.end - window.start)) overlap)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No active overlap")
                            .font(.subheadline.weight(.semibold))
                        Text("At this timing, the substances are not simultaneously active above threshold.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Combined Depression

    /// The Stage-3b readout: a single combined CNS/respiratory-depression load over the shared
    /// timeline, with the peak value and *when* it occurs marked. The danger signal becomes "your
    /// combined respiratory depression peaks at ~02:30," not "two depressant tags co-exist."
    private func depressionCard(_ d: CombinedDepressionResult) -> some View {
        let bandColor = d.band?.labelColor ?? Theme.secondaryLabel
        let peakHours = max(0, d.peakDate.timeIntervalSince(referenceTime) / 3_600)
        let yMax = max(CombinedDepression.dangerousThreshold * 1.1, d.peakLoad * 1.1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lungs.fill")
                    .foregroundStyle(bandColor)
                Text("Combined depression")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let level = d.levelLabel {
                    Text(level)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bandColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(bandColor)
                }
            }

            Text("Combined respiratory depression peaks around \(peakClockTime(d.peakDate)).")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)

            Chart {
                ForEach(Array(d.points.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", point.minute / 60),
                        y: .value("Load", point.load),
                    )
                    .foregroundStyle(bandColor.opacity(0.18))
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
                    .foregroundStyle(InteractionSeverity.dangerous.color.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(x: .value("Peak", peakHours))
                    .foregroundStyle(bandColor.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("Peak")
                            .font(.caption2)
                            .foregroundStyle(bandColor)
                    }
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
            .frame(height: 130)
            .chartSummaryAccessibility(
                label: Text("Combined depression over time"),
                value: Text("Peaks around \(peakClockTime(d.peakDate)); the dashed line marks the dangerous threshold."),
            )

            Text(depressionCaveat(d))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    /// House honesty caveat — confidence tier + how much of the stack used real occupancy vs the
    /// effect-curve surrogate ("predicted (model, confidence)", never "measured").
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

    // MARK: - Effect attenuation (sign-flipped readout)

    private func attenuationCard(_ a: EffectAttenuationResult) -> some View {
        let blockerPhrase = ListFormatter.localizedString(byJoining: a.blockers)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.right.circle")
                    .foregroundStyle(Theme.secondaryLabel)
                Text("Reduced effect")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("~\(a.reductionRangeText)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.secondaryLabel.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Text("\(blockerPhrase) blocks the \(String(localized: a.transporter.displayName)) that \(a.attenuated) needs to work, so \(a.attenuated) is predicted to feel ~\(a.reductionRangeText) weaker.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)

            Text("This is a reduced effect · predicted (model, \(String(localized: a.confidence.label))).")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Warning

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                .foregroundStyle(severity.labelColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(severity.label): \(substanceA) + \(substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(severity.labelColor)
                Text(warningDescription)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private var warningDescription: String {
        let results = InteractionChecker.checkBatch([substanceA, substanceB], against: [])
        return results.first?.description ?? String(localized: "Exercise caution when combining these substances.")
    }

    // MARK: - Substance Info

    private func substanceInfoCards(pA: PKParams, pB: PKParams) -> some View {
        VStack(spacing: 12) {
            substanceInfoRow(name: substanceA, params: pA, color: colorA)
            substanceInfoRow(name: substanceB, params: pB, color: colorB)
        }
    }

    private func substanceInfoRow(name: String, params: PKParams, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    Label("t\u{00BD} \(formatDuration(params.halfLifeMinutes))", systemImage: "clock")
                    Label("Peak \(formatDuration(params.timeToPeakMinutes))", systemImage: "arrow.up")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            }

            Spacer()
        }
        .padding()
        .themeCard()
    }

    // MARK: - Disclaimer

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Estimate Only", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)

            Text("This timeline uses a simplified one-compartment PK model with population-average half-lives. Real overlap depends on individual metabolism, dose, route, tolerance, and many other factors. This is not medical advice.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
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
