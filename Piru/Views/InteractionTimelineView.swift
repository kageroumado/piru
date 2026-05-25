import Charts
import SwiftData
import SwiftUI

struct InteractionTimelineView: View {
    let substanceA: String
    let substanceB: String
    let severity: InteractionSeverity

    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]

    @State private var ingestTimeA: Date = .now
    @State private var ingestTimeB: Date = .now
    @State private var didAutoDetect = false

    private struct PKParams {
        let ke: Double
        let ka: Double
        let halfLifeMinutes: Double
        let timeToPeakMinutes: Double
    }

    private func resolveParams(for name: String) -> PKParams? {
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

    private var paramsA: PKParams? { resolveParams(for: substanceA) }
    private var paramsB: PKParams? { resolveParams(for: substanceB) }

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

                if let pA = paramsA, let pB = paramsB {
                    chartSection(pA: pA, pB: pB)
                    timeControlsSection
                    overlapCard(pA: pA, pB: pB)
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
        .onAppear { autoDetectTimes() }
    }

    // MARK: - Auto-Detection

    private func autoDetectTimes() {
        guard !didAutoDetect else { return }
        didAutoDetect = true
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
        if let entry = allEntries.first(where: {
            $0.substance.lowercased() == substanceA.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeA = entry.timestamp
        }
        if let entry = allEntries.first(where: {
            $0.substance.lowercased() == substanceB.lowercased() && $0.timestamp > cutoff
        }) {
            ingestTimeB = entry.timestamp
        }
    }

    private var hasRecentEntryA: Bool {
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
        return allEntries.contains {
            $0.substance.lowercased() == substanceA.lowercased() && $0.timestamp > cutoff
        }
    }

    private var hasRecentEntryB: Bool {
        let cutoff = Date.now.addingTimeInterval(-48 * 3600)
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

    private struct CurvePoint: Identifiable {
        let id = UUID()
        let hours: Double
        let concentration: Double
        let substance: String
    }

    private struct OverlapPoint: Identifiable {
        let id = UUID()
        let hours: Double
        let minConcentration: Double
    }

    /// Reference time for the chart x-axis (the earlier of the two ingestion times).
    private var referenceTime: Date {
        min(ingestTimeA, ingestTimeB)
    }

    private func generateCurveData(pA: PKParams, pB: PKParams) -> (pointsA: [CurvePoint], pointsB: [CurvePoint], overlap: [OverlapPoint], totalHours: Double) {
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

        for i in 0...steps {
            let t = Double(i) / Double(steps) * totalMinutes
            let hours = t / 60

            let elapsedA = t - offsetAMinutes
            let concA: Double
            if elapsedA >= 0 && cmaxA > 0 {
                concA = max(0, PKModel.concentration(at: elapsedA, ke: pA.ke, ka: pA.ka) / cmaxA * 100)
            } else {
                concA = 0
            }

            let elapsedB = t - offsetBMinutes
            let concB: Double
            if elapsedB >= 0 && cmaxB > 0 {
                concB = max(0, PKModel.concentration(at: elapsedB, ke: pB.ke, ka: pB.ka) / cmaxB * 100)
            } else {
                concB = 0
            }

            pointsA.append(CurvePoint(hours: hours, concentration: concA, substance: substanceA))
            pointsB.append(CurvePoint(hours: hours, concentration: concB, substance: substanceB))

            let minConc = min(concA, concB)
            if concA > 3 && concB > 3 {
                overlap.append(OverlapPoint(hours: hours, minConcentration: minConc))
            }
        }

        return (pointsA, pointsB, overlap, totalHours)
    }

    private let colorA = Color.blue
    private let colorB = Color.orange

    private func chartSection(pA: PKParams, pB: PKParams) -> some View {
        let data = generateCurveData(pA: pA, pB: pB)
        let nowHours = Date.now.timeIntervalSince(referenceTime) / 3600
        let showNowMarker = nowHours > 0.05 && nowHours < data.totalHours

        return VStack(alignment: .leading, spacing: 8) {
            Text("Concentration Curves")
                .font(.headline)

            Chart {
                ForEach(data.overlap) { point in
                    AreaMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.minConcentration)
                    )
                    .foregroundStyle(severity.color.opacity(0.2))
                    .interpolationMethod(.monotone)
                }

                ForEach(data.pointsA) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration)
                    )
                    .foregroundStyle(colorA)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                ForEach(data.pointsB) { point in
                    LineMark(
                        x: .value("Time", point.hours),
                        y: .value("Conc", point.concentration)
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
            .chartYScale(domain: 0...105)
            .chartLegend(.hidden)
            .frame(height: 220)

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
        Date.now.addingTimeInterval(-48 * 3600)...Date.now.addingTimeInterval(12 * 3600)
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
                        .background(color.opacity(0.15), in: Capsule())
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

    private func overlapWindow(pA: PKParams, pB: PKParams) -> (start: Double, end: Double)? {
        let data = generateCurveData(pA: pA, pB: pB)
        guard let first = data.overlap.first, let last = data.overlap.last else { return nil }
        return (first.hours, last.hours)
    }

    private func overlapCard(pA: PKParams, pB: PKParams) -> some View {
        let window = overlapWindow(pA: pA, pB: pB)

        return VStack(alignment: .leading, spacing: 8) {
            if let window {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(severity.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Both substances active")
                            .font(.subheadline.weight(.semibold))
                        Text("From \(formatHours(window.start)) to \(formatHours(window.end)) (\(formatHours(window.end - window.start)) overlap)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No active overlap")
                            .font(.subheadline.weight(.semibold))
                        Text("At this timing, the substances are not simultaneously active above threshold.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Warning

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                .foregroundStyle(severity.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(severity.label): \(substanceA) + \(substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(severity.color)
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
