import Foundation
import Observation

/// The retrospective serum-level model behind the Hormone Levels insight
/// (Specs/injection-levels-v3.md §3–§4). Unlike the prediction Tool it never
/// synthesizes a schedule: it reads the dose log grouped **per ester**, sums each
/// ester's own depot curve into the serum total, keeps the per-ester contributions
/// for the "assumed depot levels" display, and calibrates the whole sum to the
/// user's labs. It estimates a level; it never suggests a dose or a target.
@Observable
@MainActor
final class HormoneLevelsModel: DepotCalibrating {
    var analyte: Analyte = .estradiol

    /// Reference lines the user set (their own, never an app target). For
    /// testosterone these seed from `analyte` defaults but stay user-owned.
    var referenceLow: Double?
    var referenceHigh: Double?

    // Calibration knobs, mirrored from the shared `@AppStorage` the Tool persists.
    var personalMultiplier: Double = 1.0
    var autoCalibrateFromLabs: Bool = true
    var fitRates: Bool = true

    var chartRange: InjectionLevelsModel.ChartRange = .quarter
    var pinchVisibleDays: Double?

    var effectiveVisibleDays: Double? {
        pinchVisibleDays ?? chartRange.days
    }

    // MARK: Synced from the view

    private(set) var grouped = HormoneLevelsLog.Grouped()
    private(set) var measurements: [DepotCalibration.Measurement] = []

    var hasLabs: Bool { !measurements.isEmpty }
    var isLabDriven: Bool { autoCalibrateFromLabs && calibration != nil }
    var calibrationMeasurementCount: Int { measurements.count }

    /// The amplitude multiplier in effect — the lab-fit scale when lab-driven, else
    /// the hand-set personal multiplier.
    var effectiveMultiplier: Double {
        if let calibration, autoCalibrateFromLabs { return calibration.scale }
        return personalMultiplier
    }

    // MARK: Outputs

    /// The summed serum estimate (the analyte the user injects), with its band.
    private(set) var result: DepotCurveResult?
    /// One contribution series per modelable ester logged — the "assumed depot
    /// levels" breakdown, distinct from the serum sum.
    private(set) var perEster: [(ester: EsterPKRecord, points: [DepotCurveResult.Point])] = []
    /// Catalog-only esters logged (no curve) — drawn as labeled markers.
    private(set) var catalogMarkers: [(ester: EsterPKRecord, date: Date)] = []
    private(set) var calibration: DepotCalibration.Result?

    // MARK: Recompute key

    struct RecomputeKey: Equatable {
        let analyte: Analyte
        let referenceLow: Double?
        let referenceHigh: Double?
        let personalMultiplier: Double
        let autoCalibrateFromLabs: Bool
        let fitRates: Bool
        let visibleDays: Double?
        let logSignature: Int
        let labSignature: Int
    }

    var recomputeKey: RecomputeKey {
        RecomputeKey(
            analyte: analyte, referenceLow: referenceLow, referenceHigh: referenceHigh,
            personalMultiplier: personalMultiplier, autoCalibrateFromLabs: autoCalibrateFromLabs,
            fitRates: fitRates, visibleDays: effectiveVisibleDays,
            logSignature: logSignature, labSignature: signature(of: measurements.map { ($0.date, $0.value) }),
        )
    }

    private var logSignature: Int {
        var hasher = Hasher()
        for group in grouped.esterGroups {
            hasher.combine(group.ester.esterID)
            for (date, dose) in group.injections {
                hasher.combine(date.timeIntervalSinceReferenceDate.rounded())
                hasher.combine(dose)
            }
        }
        for marker in grouped.catalogOnlyMarkers {
            hasher.combine(marker.ester.esterID)
            hasher.combine(marker.date.timeIntervalSinceReferenceDate.rounded())
        }
        return hasher.finalize()
    }

    private func signature(of pairs: [(Date, Double)]) -> Int {
        var hasher = Hasher()
        for (date, value) in pairs {
            hasher.combine(date.timeIntervalSinceReferenceDate.rounded())
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    // MARK: Sync

    func sync(grouped: HormoneLevelsLog.Grouped, measurements: [DepotCalibration.Measurement]) {
        self.grouped = grouped
        self.measurements = measurements
    }

    // MARK: Compute

    func refresh() {
        catalogMarkers = grouped.catalogOnlyMarkers
        let groups = grouped.esterGroups.filter { !$0.injections.isEmpty && $0.ester.parameters != nil }
        guard !groups.isEmpty else { result = nil; perEster = []; calibration = nil; return }

        let allDates = grouped.allInjections.map(\.date)
        let (rangeStart, rangeEnd, cycleDays) = window(dates: allDates)

        // Population contributions (each ester keeps its own parameters).
        let populationContributions = groups.compactMap { group -> PKModel.DepotContribution? in
            group.ester.parameters.map { PKModel.DepotContribution(injections: group.injections, parameters: $0) }
        }

        // Global amplitude + rate fit against the summed curve (labs can't resolve
        // per-ester rates from a mixed log — §4 fits one scale, applied uniformly).
        let cal = autoCalibrateFromLabs
            ? DepotCalibration.calibrateSummed(contributions: populationContributions, measurements: measurements, fitRate: fitRates)
            : nil
        calibration = cal
        let scale = cal?.scale ?? max(0.05, personalMultiplier)
        let k1Scale = cal?.k1Scale ?? 1.0

        let calibrated: [(ester: EsterPKRecord, contribution: PKModel.DepotContribution)] = groups.compactMap { group in
            guard let population = group.ester.parameters else { return nil }
            let params = population.withK1Scale(k1Scale).withAmplitude(population.d * scale)
            return (group.ester, PKModel.DepotContribution(injections: group.injections, parameters: params))
        }

        let summed = PKModel.depotCurveSummed(contributions: calibrated.map(\.contribution), over: rangeStart ... rangeEnd)

        // The serum total's band is the widest of the mix — an honest uncertainty when
        // esters of different confidence combine.
        let worstConfidence = calibrated.map(\.ester.confidence).min(by: { confidenceRank($0) < confidenceRank($1) }) ?? "low"
        let totalBand = InjectionLevelsModel.bandFraction(confidence: worstConfidence, calibrated: cal != nil)
        let totalPoints = summed.total.map { point(date: $0.date, level: $0.value, band: totalBand) }

        perEster = zip(calibrated, summed.contributions).map { entry, series in
            let band = InjectionLevelsModel.bandFraction(confidence: entry.ester.confidence, calibrated: cal != nil)
            return (entry.ester, series.map { point(date: $0.date, level: $0.value, band: band) })
        }

        let cycleStart = rangeEnd.addingTimeInterval(-cycleDays * PKModel.secondsPerDay)
        let cyclePoints = totalPoints.filter { $0.date >= cycleStart }
        let trough = cyclePoints.map(\.level).min() ?? 0
        let peak = cyclePoints.map(\.level).max() ?? 0

        var timeInRange: Double?
        if let low = referenceLow, let high = referenceHigh, high > low, !cyclePoints.isEmpty {
            timeInRange = Double(cyclePoints.filter { $0.level >= low && $0.level <= high }.count) / Double(cyclePoints.count)
        }

        result = DepotCurveResult(
            points: totalPoints,
            injectionDates: allDates.filter { rangeStart ... rangeEnd ~= $0 },
            range: rangeStart ... rangeEnd,
            trough: trough, troughLow: max(0, trough * (1 - totalBand)), troughHigh: trough * (1 + totalBand),
            peak: peak, peakLow: max(0, peak * (1 - totalBand)), peakHigh: peak * (1 + totalBand),
            timeInRange: timeInRange,
        )
    }

    // MARK: Helpers

    private func point(date: Date, level: Double, band: Double) -> DepotCurveResult.Point {
        DepotCurveResult.Point(date: date, level: level, bandLow: max(0, level * (1 - band)), bandHigh: level * (1 + band))
    }

    private func confidenceRank(_ confidence: String) -> Int {
        switch confidence {
        case "high": 3
        case "medium": 2
        case "low": 1
        default: 0
        }
    }

    /// The visible span: the retrospective log with a short projection to one cycle
    /// past the last injection (or now), zoomed to the visible window. Earlier
    /// injections still contribute off-screen — the superposition sums all prior doses.
    private func window(dates: [Date]) -> (Date, Date, Double) {
        let now = Date.now
        let sorted = dates.sorted()
        let first = sorted.first ?? now
        let last = sorted.last ?? now
        let cycleDays = medianIntervalDays(sorted) ?? 14
        let end = max(last.addingTimeInterval(cycleDays * PKModel.secondsPerDay), now)
        let start = effectiveVisibleDays.map { days in
            max(first, end.addingTimeInterval(-days * PKModel.secondsPerDay))
        } ?? first
        return (start, end, cycleDays)
    }

    private func medianIntervalDays(_ dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }
        let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / PKModel.secondsPerDay }
            .filter { $0 > 0 }.sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }
}
