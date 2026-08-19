import Charts
import SwiftData
import SwiftUI

/// Insights → In Your Body → Steady state. Where a *regularly* dosed substance
/// settles, projected from the log's own inferred cadence rather than a form the
/// user types into the Steady-State tool. For each substance dosed on a steady
/// enough schedule it feeds ``SteadyStateModel`` the median dose and median
/// interval and shows the accumulation curve and plateau.
///
/// Only substances with a regular cadence appear — steady state is meaningless
/// for one-off or bursty use, so an irregular log yields the empty state rather
/// than a confident plateau nobody is dosing toward.
struct SteadyStateProjectionView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var projections: [SteadyStateProjection] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !loaded {
                    ProgressView().padding(.top, 60)
                } else if projections.isEmpty {
                    ContentUnavailableView(
                        "No Steady Cadence Yet",
                        systemImage: "arrow.up.forward.circle",
                        description: Text("Steady state needs a regular schedule. Log a substance on a consistent cadence and its plateau appears here."),
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(projections) { projection in
                        SteadyStateProjectionCard(projection: projection)
                    }
                    disclaimer
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .task(id: EntriesFingerprint.make(allEntries, colors: substanceColors)) {
            projections = SteadyStateProjectionBuilder.compute(entries: allEntries, colorMap: substanceColors.colorMap)
            loaded = true
        }
    }

    private var disclaimer: some View {
        Text("A projection from your median dose and spacing, assuming you keep that cadence and linear kinetics. Body content in the dose's units, not a plasma level.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Card

struct SteadyStateProjectionCard: View {
    let projection: SteadyStateProjection

    private var result: SteadyStateModel.Result {
        projection.result
    }
    /// Whether the substance meaningfully accumulates, or clears between doses.
    private var accumulates: Bool {
        result.accumulationRatio >= 1.15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
            stats
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(projection.color)
                .frame(width: 9, height: 9)
            Text(projection.displayName)
                .font(.headline)
            Spacer()
            Text("\(projection.medianDose.doseFormatted) \(projection.unit) · \(cadenceText)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// The accumulation curve to plateau, in days.
    private var chart: some View {
        Chart {
            ForEach(Array(result.curve.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Day", point.minutes / 1_440),
                    y: .value("Body content", point.amount),
                )
                .foregroundStyle(projection.color.opacity(0.18))
                LineMark(
                    x: .value("Day", point.minutes / 1_440),
                    y: .value("Body content", point.amount),
                )
                .foregroundStyle(projection.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(y: .value("Plateau", result.averageAmount))
                .foregroundStyle(projection.color.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 130)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.4))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.4))
                AxisValueLabel {
                    if let day = value.as(Double.self) {
                        Text("\(Int(day))d").font(.caption2)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Accumulation curve for \(projection.displayName)"))
        .accessibilityValue(Text(summary))
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Plateau", "\(result.averageAmount.doseFormatted) \(projection.unit)")
            stat("Peak", "\(result.peakAmount.doseFormatted) \(projection.unit)")
            if accumulates {
                stat("Buildup", "\(result.accumulationRatio.formatted(.number.precision(.fractionLength(1))))×")
                stat("Reaches", daysToSteadyText)
            } else {
                stat("Between doses", clearsText)
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Copy

    private var cadenceText: String {
        let hours = projection.intervalHours
        if abs(hours - 24) < 3 { return String(localized: "about daily") }
        if hours >= 44, hours <= 52 { return String(localized: "about every 2 days") }
        if hours < 36 { return String(localized: "every ~\(Int(hours.rounded())) h") }
        return String(localized: "every ~\((hours / 24).formatted(.number.precision(.fractionLength(0 ... 1)))) days")
    }

    private var daysToSteadyText: String {
        let days = projection.daysToSteady
        if days < 1 { return String(localized: "<1 day") }
        return String(localized: "~\(Int(days.rounded())) days")
    }

    private var clearsText: String {
        String(localized: "clears, no buildup")
    }

    private var summary: String {
        let plateau = "\(result.averageAmount.doseFormatted) \(projection.unit)"
        if accumulates {
            let ratio = result.accumulationRatio.formatted(.number.precision(.fractionLength(1)))
            return String(localized: "Plateaus around \(plateau), \(ratio)× one dose, reached in \(daysToSteadyText)")
        }
        return String(localized: "Clears between doses; each peaks around \(plateau)")
    }
}

// MARK: - Data

struct SteadyStateProjection: Identifiable {
    let id: String
    let displayName: String
    let color: Color
    let unit: String
    /// Median logged dose (in `unit`) and median gap between doses (hours).
    let medianDose: Double
    let intervalHours: Double
    let result: SteadyStateModel.Result

    /// Days to ~95% of steady state.
    var daysToSteady: Double {
        result.time95 / 1_440
    }
}

// MARK: - Builder

enum SteadyStateProjectionBuilder {
    /// Window over which cadence is inferred — recent enough that a schedule the
    /// user has since abandoned doesn't project a phantom plateau.
    private static let lookbackDays: Double = 120
    /// Minimum doses before a cadence is trustworthy, and the interval CV above
    /// which a schedule is too irregular to project.
    private static let minimumDoses = 5
    private static let maximumIntervalCV = 0.8
    /// A cadence outside human dosing rhythm (hours) is noise, not a schedule.
    private static let intervalBounds = 3.0 ... 96.0

    private struct Group {
        var name: String
        var route: RouteOfAdministration
        var unit: String
        var amounts: [Double] = []
        var timestamps: [Date] = []
    }

    @MainActor
    static func compute(entries: [DoseEntry], colorMap: [String: Color]) -> [SteadyStateProjection] {
        let cutoff = Date.now.addingTimeInterval(-lookbackDays * 86_400)

        var groups: [String: Group] = [:]
        var substanceCache: [String: Substance?] = [:]
        func lookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let hit = substanceCache[key] { return hit }
            let result = SubstanceLibrary.timelineLookup(name)
            substanceCache[key] = result
            return result
        }

        for entry in entries where entry.timestamp >= cutoff {
            let substance = lookup(entry.substance)
            if entry.productDuration == nil, entry.namesUnmodeledForm { continue }
            let name = substance?.name ?? entry.substance
            let key = name.lowercased()
            if var group = groups[key] {
                guard let amount = DoseUnit.convert(entry.amount, from: entry.unit, to: group.unit) else { continue }
                group.amounts.append(amount)
                group.timestamps.append(entry.timestamp)
                groups[key] = group
            } else {
                groups[key] = Group(name: name, route: entry.route, unit: entry.unit, amounts: [entry.amount], timestamps: [entry.timestamp])
            }
        }

        var out: [SteadyStateProjection] = []
        for (_, group) in groups {
            guard let projection = build(group, colorMap: colorMap, substance: lookup(group.name)) else { continue }
            out.append(projection)
        }
        // Most-accumulating first — the buildup is the headline.
        return out.sorted { $0.result.accumulationRatio > $1.result.accumulationRatio }
    }

    @MainActor
    private static func build(_ group: Group, colorMap: [String: Color], substance: Substance?) -> SteadyStateProjection? {
        guard group.timestamps.count >= minimumDoses else { return nil }
        let sorted = group.timestamps.sorted()
        let intervals = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) / 3_600 }
        guard let medianInterval = median(intervals), intervalBounds.contains(medianInterval),
              let cv = coefficientOfVariation(intervals), cv < maximumIntervalCV,
              let medianDose = median(group.amounts), medianDose > 0
        else { return nil }

        guard let params = PKResolver.params(substance: substance, entryName: group.name, route: group.route),
              let result = SteadyStateModel.compute(
                  dose: medianDose, halfLifeMinutes: params.halfLifeMinutes,
                  intervalMinutes: medianInterval * 60, ke: params.ke, ka: params.ka,
              )
        else { return nil }

        return SteadyStateProjection(
            id: group.name.lowercased(),
            displayName: CustomSubstanceStore.shared.displayName(for: group.name, fallback: substance?.displayTitle),
            color: SubstancePalette.color(for: group.name, colorMap: colorMap),
            unit: group.unit,
            medianDose: medianDose,
            intervalHours: medianInterval,
            result: result,
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() / mean
    }
}
