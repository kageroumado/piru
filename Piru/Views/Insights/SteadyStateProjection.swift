import Charts
import SwiftData
import SwiftUI

// Steady-state projection from the log's own inferred cadence: the shared
// ``SteadyStateProjectionCard`` plus the ``SteadyStateProjectionBuilder`` that
// mines each regularly-dosed substance's median dose and interval and feeds
// ``SteadyStateModel``. Rendered inside ``InYourBodyView``'s steady-state
// section. Only substances with a regular cadence yield a projection —
// steady state is meaningless for one-off or bursty use.

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
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            chart
            stats
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            LegendDot(color: projection.color, size: .large)
            Text(projection.displayName)
                .cardTitle()
            Spacer()
            Text("\(projection.medianDose.doseFormatted) \(projection.unit) · \(cadenceText)")
                .captionSecondary()
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
                .foregroundStyle(projection.color.opacity(Theme.Opacity.tintActive))
                LineMark(
                    x: .value("Day", point.minutes / 1_440),
                    y: .value("Body content", point.amount),
                )
                .foregroundStyle(projection.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(y: .value("Plateau", result.averageAmount))
                .foregroundStyle(projection.color.opacity(Theme.Opacity.dimmed))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Where the log stands today: on a settled schedule, the modeled amount
            // now across the plateau; on a younger one, how far along the climb it is.
            if accumulates, projection.isSettled {
                RuleMark(y: .value("Now", projection.currentAmount))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Now \(projection.currentAmount.doseFormatted) \(projection.unit)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
            } else if accumulates {
                RuleMark(x: .value("Now", projection.elapsedMinutes / 1_440))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("Now")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
            }
        }
        .frame(height: 130)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
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
                if projection.isSettled {
                    stat("Reached", settledText)
                } else {
                    stat("Reaches", daysToSteadyText)
                }
            } else {
                stat("Between doses", clearsText)
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(value)
                .sectionLabel()
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

    /// The plateau was reached by this date at the latest: the log's cadence starts
    /// no later than its first dose in the lookback window.
    private var settledText: String {
        let date = projection.settledBy.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "by \(date)")
    }

    private var clearsText: String {
        String(localized: "clears, no buildup")
    }

    private var summary: String {
        let plateau = "\(result.averageAmount.doseFormatted) \(projection.unit)"
        if accumulates {
            let ratio = result.accumulationRatio.formatted(.number.precision(.fractionLength(1)))
            if projection.isSettled {
                let now = "\(projection.currentAmount.doseFormatted) \(projection.unit)"
                return String(localized: "Plateaus around \(plateau), \(ratio)× one dose, reached \(settledText); now \(now)")
            }
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
    /// The group's earliest dose in the builder's lookback window.
    let firstDose: Date
    /// Minutes from ``firstDose`` to the moment the projection was built.
    let elapsedMinutes: Double
    /// The modeled amount in the body when the projection was built, summed over the
    /// logged doses still above ``ActiveSubstanceCalculator/activeFloor`` with the
    /// projection's own rate constants, in `unit`.
    let currentAmount: Double

    /// Days to ~95% of steady state.
    var daysToSteady: Double {
        result.time95 / 1_440
    }

    /// Whether the logged schedule has run long enough to reach ~95% of its plateau.
    var isSettled: Bool {
        elapsedMinutes >= result.time95
    }

    /// The latest date the plateau was reached by, counting from ``firstDose``.
    var settledBy: Date {
        firstDose.addingTimeInterval(result.time95 * 60)
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
        /// The group's first dose; every later one is expressed in its unit.
        var unitOf: DoseQuantity
        var amounts: [Double] = []
        var timestamps: [Date] = []
    }

    @MainActor
    static func compute(entries: [DoseEntry], colorMap: [String: Color], now: Date = .now) -> [SteadyStateProjection] {
        let cutoff = now.addingTimeInterval(-lookbackDays * 86_400)

        var groups: [String: Group] = [:]
        var substanceCache: [String: Substance?] = [:]
        func lookup(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let hit = substanceCache[key] { return hit }
            let result = SubstanceLibrary.lookup(name)
            substanceCache[key] = result
            return result
        }

        for entry in entries where entry.timestamp >= cutoff && entry.timestamp <= now {
            let substance = lookup(entry.substance)
            guard let dose = substance?.quantity(of: entry) ?? entry.quantity else { continue }
            if entry.productDuration == nil, entry.namesUnmodeledForm { continue }
            let name = substance?.name ?? entry.substance
            let key = name.lowercased()
            if var group = groups[key] {
                guard let amount = dose.value(inUnitOf: group.unitOf) else { continue }
                group.amounts.append(amount)
                group.timestamps.append(entry.timestamp)
                groups[key] = group
            } else {
                groups[key] = Group(
                    name: name, route: entry.route, unit: entry.unit, unitOf: dose,
                    amounts: [entry.amount], timestamps: [entry.timestamp],
                )
            }
        }

        var out: [SteadyStateProjection] = []
        for (_, group) in groups {
            guard let projection = build(group, colorMap: colorMap, substance: lookup(group.name), now: now) else { continue }
            out.append(projection)
        }
        // Most-accumulating first — the buildup is the headline.
        return out.sorted { $0.result.accumulationRatio > $1.result.accumulationRatio }
    }

    @MainActor
    private static func build(_ group: Group, colorMap: [String: Color], substance: Substance?, now: Date) -> SteadyStateProjection? {
        guard group.timestamps.count >= minimumDoses else { return nil }
        let sorted = group.timestamps.sorted()
        let intervals = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) / 3_600 }
        guard let medianInterval = median(intervals), intervalBounds.contains(medianInterval),
              let cv = coefficientOfVariation(intervals), cv < maximumIntervalCV,
              let medianDose = median(group.amounts), medianDose > 0
        else { return nil }

        guard let params = PKResolver.params(substance: substance, route: group.route),
              let result = SteadyStateModel.compute(
                  dose: medianDose, halfLifeMinutes: params.halfLifeMinutes,
                  intervalMinutes: medianInterval * 60, ke: params.ke, ka: params.ka,
              )
        else { return nil }

        // Counted as the Modeled as Active card counts it, so the two print one number.
        let currentAmount = zip(group.amounts, group.timestamps).reduce(0.0) { total, dose in
            let fraction = PKModel.fractionRemainingInBody(at: now.timeIntervalSince(dose.1) / 60, ke: params.ke, ka: params.ka)
            return fraction > ActiveSubstanceCalculator.activeFloor ? total + dose.0 * fraction : total
        }
        let firstDose = sorted[0]

        return SteadyStateProjection(
            id: group.name.lowercased(),
            displayName: CustomSubstanceStore.shared.displayName(for: group.name, fallback: substance?.displayTitle),
            color: SubstancePalette.color(for: group.name, colorMap: colorMap),
            unit: group.unit,
            medianDose: medianDose,
            intervalHours: medianInterval,
            result: result,
            firstDose: firstDose,
            elapsedMinutes: now.timeIntervalSince(firstDose) / 60,
            currentAmount: currentAmount,
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
