import Foundation

// MARK: - Snapshot inputs (Sendable — resolved once on the main actor)

/// The currency a substance's exposure is measured in. Clinical equivalents are
/// preferred because a prescriber already reasons in them; the common-dose
/// fallback (a multiple of the substance's own typical dose) is the honest
/// cross-substance unit when no clinical equivalence exists.
nonisolated enum ExposureCurrency: String, Sendable, Codable {
    /// Morphine milligram equivalents (linear opioids, CDC 2022).
    case mme
    /// Diazepam-equivalent milligrams (benzodiazepines).
    case diazepam
    /// Multiples of the substance's own common dose.
    case commonDose
    /// The raw logged mass — a mass-dosed substance with no ladder or equivalence.
    case milligrams
}

/// One substance in a clinical report: identity + the currency its doses are
/// summed in.
nonisolated struct ClinicalSubstance: Sendable {
    let name: String
    let displayName: String
    let colorHex: String
    /// The unit doses are shown in (the logged unit, or "MME"/"mg diazepam-eq").
    let unit: String
    let currency: ExposureCurrency
}

/// One dose reduced to the values the pure aggregation needs. Everything that
/// requires a `SubstanceLibrary`/equivalence lookup is resolved on the main actor
/// while building these; the aggregation itself is pure and off-main-ready.
nonisolated struct ClinicalDose: Sendable {
    /// Index into the report's `substances`.
    let substanceIndex: Int
    let timestamp: Date
    /// The dose expressed in its substance's exposure currency (MME, diazepam-mg,
    /// common-dose multiples, or mg). `nil` when it can't be expressed that way.
    let exposure: Double?
    /// PK rate constants for the body-load overlap pass; `nil` when unmodeled.
    let ke: Double?
    let ka: Double?
}

// MARK: - Report outputs

/// Days used vs days off across the window — the "how many days a week" question,
/// framed as a record (days used, longest break), never as failed abstinence.
nonisolated struct HolidayStats: Sendable {
    let totalDays: Int
    let daysUsed: Int
    /// Longest run of consecutive days with nothing logged, within the window.
    let longestBreakDays: Int
    /// Consecutive days with nothing logged, ending at the window's end (today).
    let currentBreakDays: Int

    var daysOff: Int {
        totalDays - daysUsed
    }
    var fractionUsed: Double {
        totalDays > 0 ? Double(daysUsed) / Double(totalDays) : 0
    }
}

/// One substance's cumulative exposure over the window, in its currency.
nonisolated struct ExposureStat: Sendable, Identifiable {
    let substanceIndex: Int
    let currency: ExposureCurrency
    /// Total exposure over the window, in `currency`.
    let total: Double
    /// The heaviest single day's exposure, in `currency` (the number a clinician
    /// checks against a daily threshold).
    let peakDay: Double
    /// Mean exposure per day across the whole window (total ÷ window days).
    let dailyMean: Double
    /// Running cumulative total at each dose, oldest → newest — the curve.
    let cumulative: [Point]

    var id: Int {
        substanceIndex
    }

    struct Point: Sendable, Identifiable {
        let id: Int
        let date: Date
        let total: Double
    }
}

/// Whether a substance's per-dose amount has trended up, down, or held over the
/// window — a tolerance/dependence signal, reported with its own uncertainty.
nonisolated struct EscalationStat: Sendable, Identifiable {
    enum Direction: String, Sendable { case rising, falling, steady }

    let substanceIndex: Int
    let direction: Direction
    /// Signed fractional change from the window's first third to its last third
    /// (median dose), e.g. `0.4` = +40%.
    let change: Double
    /// Median dose in the first / last third of the window (same currency).
    let earlyMedian: Double
    let lateMedian: Double
    let doseCount: Int

    var id: Int {
        substanceIndex
    }
}

/// Time two substances were both above the body-load threshold — co-exposure,
/// the window where an interaction can occur.
nonisolated struct OverlapStat: Sendable, Identifiable {
    let a: Int
    let b: Int
    /// Hours both were simultaneously active over the window.
    let hours: Double

    var id: String {
        "\(a)|\(b)"
    }
}

/// The whole clinical/patterns report for one window — the single value both the
/// Insights UI and the PDF clinician report render from.
nonisolated struct ClinicalReport: Sendable {
    let start: Date
    let end: Date
    let substances: [ClinicalSubstance]
    let holidays: HolidayStats
    let exposure: [ExposureStat]
    let escalation: [EscalationStat]
    let overlaps: [OverlapStat]

    var isEmpty: Bool {
        substances.isEmpty
    }

    /// Total opioid exposure across the window as morphine-mg-equivalents, and the
    /// mean per day — for the CDC daily-MME risk bands. `nil` when no opioids.
    var opioidMMEPerDay: Double? {
        classDailyMean(.mme)
    }

    /// Peak single-day MME — the number checked against CDC's 50/90 bands.
    var opioidPeakDayMME: Double? {
        classPeakDay(.mme)
    }

    var benzoDiazepamPerDay: Double? {
        classDailyMean(.diazepam)
    }

    private func classDailyMean(_ currency: ExposureCurrency) -> Double? {
        let rows = exposure.filter { $0.currency == currency }
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + $1.dailyMean }
    }

    private func classPeakDay(_ currency: ExposureCurrency) -> Double? {
        let rows = exposure.filter { $0.currency == currency }
        guard !rows.isEmpty else { return nil }
        // Same-class substances share the MME/DE scale, so their per-day peaks add.
        return rows.reduce(0) { $0 + $1.peakDay }
    }
}

// MARK: - Pure computation

nonisolated enum ClinicalStats {
    /// Doses whose PK curve exceeds this fraction of the dose count as "active"
    /// for the overlap pass — the same 3% floor the body-load readout uses.
    private static let activeFractionFloor = 0.03
    /// A substance needs this many doses before its trend is reported.
    private static let minimumEscalationDoses = 6
    /// …spanning at least this many days.
    private static let minimumEscalationSpanDays: Double = 21
    /// Change beyond ±this fraction reads as a real trend, not noise.
    private static let escalationThreshold = 0.15
    /// Overlap sample spacing (minutes) — hourly is fine for co-exposure hours.
    private static let overlapStepMinutes: Double = 60

    static func report(
        substances: [ClinicalSubstance],
        doses: [ClinicalDose],
        start: Date,
        end: Date,
        calendar: Calendar,
    ) -> ClinicalReport {
        ClinicalReport(
            start: start, end: end, substances: substances,
            holidays: holidays(doses: doses, start: start, end: end, calendar: calendar),
            exposure: exposure(substances: substances, doses: doses, start: start, end: end, calendar: calendar),
            escalation: escalation(substances: substances, doses: doses, start: start, end: end),
            overlaps: overlaps(substances: substances, doses: doses, start: start, end: end),
        )
    }

    // MARK: Holidays

    private static func holidays(doses: [ClinicalDose], start: Date, end: Date, calendar: Calendar) -> HolidayStats {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let totalDays = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)

        var used = Set<Date>()
        for dose in doses where dose.timestamp >= start && dose.timestamp <= end {
            used.insert(calendar.startOfDay(for: dose.timestamp))
        }

        var longestBreak = 0
        var run = 0
        var currentBreak = 0
        for offset in 0 ..< totalDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            if used.contains(day) {
                run = 0
            } else {
                run += 1
                longestBreak = max(longestBreak, run)
            }
        }
        // Current break: walk back from the end while days are unused.
        var back = 0
        while back < totalDays, let day = calendar.date(byAdding: .day, value: -back, to: endDay), !used.contains(day) {
            currentBreak += 1
            back += 1
        }

        return HolidayStats(totalDays: totalDays, daysUsed: used.count, longestBreakDays: longestBreak, currentBreakDays: currentBreak)
    }

    // MARK: Exposure

    private static func exposure(
        substances: [ClinicalSubstance], doses: [ClinicalDose],
        start: Date, end: Date, calendar: Calendar,
    ) -> [ExposureStat] {
        let windowDays = max(1.0, end.timeIntervalSince(start) / 86_400)
        var out: [ExposureStat] = []
        for (index, substance) in substances.enumerated() {
            let rows = doses
                .filter { $0.substanceIndex == index && $0.exposure != nil && $0.timestamp >= start && $0.timestamp <= end }
                .sorted { $0.timestamp < $1.timestamp }
            guard !rows.isEmpty else { continue }

            var runningTotal = 0.0
            var cumulative: [ExposureStat.Point] = []
            var perDay: [Date: Double] = [:]
            for (i, dose) in rows.enumerated() {
                let value = dose.exposure ?? 0
                runningTotal += value
                cumulative.append(ExposureStat.Point(id: i, date: dose.timestamp, total: runningTotal))
                perDay[calendar.startOfDay(for: dose.timestamp), default: 0] += value
            }
            out.append(ExposureStat(
                substanceIndex: index,
                currency: substance.currency,
                total: runningTotal,
                peakDay: perDay.values.max() ?? 0,
                dailyMean: runningTotal / windowDays,
                cumulative: cumulative,
            ))
        }
        return out.sorted { $0.total > $1.total }
    }

    // MARK: Escalation

    private static func escalation(substances: [ClinicalSubstance], doses: [ClinicalDose], start: Date, end: Date) -> [EscalationStat] {
        var out: [EscalationStat] = []
        for index in substances.indices {
            let rows = doses
                .filter { $0.substanceIndex == index && $0.exposure != nil && $0.timestamp >= start && $0.timestamp <= end }
                .sorted { $0.timestamp < $1.timestamp }
            guard rows.count >= minimumEscalationDoses,
                  let first = rows.first?.timestamp, let last = rows.last?.timestamp,
                  last.timeIntervalSince(first) / 86_400 >= minimumEscalationSpanDays
            else { continue }

            let third = rows.count / 3
            guard third >= 1 else { continue }
            let early = median(rows.prefix(third).compactMap(\.exposure))
            let late = median(rows.suffix(third).compactMap(\.exposure))
            guard let early, let late, early > 0 else { continue }

            let change = (late - early) / early
            let direction: EscalationStat.Direction =
                change > escalationThreshold ? .rising : (change < -escalationThreshold ? .falling : .steady)
            out.append(EscalationStat(
                substanceIndex: index, direction: direction, change: change,
                earlyMedian: early, lateMedian: late, doseCount: rows.count,
            ))
        }
        // Rising first, then by magnitude — escalation is the headline.
        return out.sorted { abs($0.change) > abs($1.change) }
    }

    // MARK: Overlap

    private static func overlaps(
        substances: [ClinicalSubstance], doses: [ClinicalDose], start: Date, end: Date,
    ) -> [OverlapStat] {
        let modeled = doses.filter { $0.ke != nil && $0.ka != nil && $0.timestamp <= end }
        guard !modeled.isEmpty, end > start else { return [] }

        let stepMinutes = overlapStepMinutes
        let hoursPerStep = stepMinutes / 60
        var pairHours: [Int: Double] = [:] // key = a * substances.count + b
        let count = substances.count

        var t = start
        while t <= end {
            // Which substances are active at t.
            var active = Set<Int>()
            for dose in modeled where dose.timestamp <= t {
                guard let ke = dose.ke, let ka = dose.ka else { continue }
                let elapsed = t.timeIntervalSince(dose.timestamp) / 60
                if PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka) > activeFractionFloor {
                    active.insert(dose.substanceIndex)
                }
            }
            if active.count >= 2 {
                let sorted = active.sorted()
                for i in 0 ..< sorted.count {
                    for j in (i + 1) ..< sorted.count {
                        pairHours[sorted[i] * count + sorted[j], default: 0] += hoursPerStep
                    }
                }
            }
            t = t.addingTimeInterval(stepMinutes * 60)
        }

        return pairHours
            .map { key, hours in OverlapStat(a: key / count, b: key % count, hours: hours) }
            .filter { $0.hours >= 1 }
            .sorted { $0.hours > $1.hours }
    }

    // MARK: Helpers

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
