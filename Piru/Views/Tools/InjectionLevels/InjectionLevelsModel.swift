import Foundation
import Observation

/// The depot serum-level curve the ``InjectionLevelsView`` draws, plus the metrics
/// read off it. Pure value type so the view stays cheap to re-render.
struct DepotCurveResult: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let date: Date
        /// Calibrated (or population) predicted level, canonical unit.
        let level: Double
        /// Typical-range band around the level.
        let bandLow: Double
        let bandHigh: Double
    }

    let points: [Point]
    let injectionDates: [Date]
    let range: ClosedRange<Date>

    /// Estimated trough / peak over the last modeled cycle, with band edges.
    let trough: Double
    let troughLow: Double
    let troughHigh: Double
    let peak: Double
    let peakLow: Double
    let peakHigh: Double

    /// Fraction of the last cycle spent between the user's reference lines, or `nil`
    /// when the user has not set both.
    let timeInRange: Double?

    var maxBandHigh: Double {
        points.map(\.bandHigh).max() ?? peakHigh
    }
}

/// The Injection Levels tool's inputs and the curve projected from them
/// (Specs/injection-levels-tool.md §6). Follows the ``SteadyStateInputs`` pattern:
/// ``result`` is **stored**, recomputed by ``refresh()`` only when ``recomputeKey``
/// changes — the superposition loop is O(samples × doses) and must not run in `body`.
///
/// The tool predicts a concentration from doses the user enters or logged. It never
/// recommends a dose, an interval, or a level to aim for; reference lines are the
/// user's own.
@Observable
@MainActor
final class InjectionLevelsModel {
    // MARK: Inputs

    var analyte: Analyte = .estradiol
    var selectedEsterID: String?
    var doseMg: Double? = 5
    var intervalDays: Double? = 14
    /// Log-first: prefer the dose log when it has qualifying injections.
    var useLogHistory: Bool = true
    var referenceLow: Double?
    var referenceHigh: Double?

    /// Personal amplitude multiplier — the "run high / run low" knob. When
    /// ``autoCalibrateFromLabs`` is on and labs exist, the lab fit drives amplitude
    /// and this is displayed as the fitted scale; otherwise the user sets it by hand
    /// (someone who knows they metabolize differently but hasn't tested yet). Applied
    /// as `d = d_pop · multiplier`. Persisted by the view via `@AppStorage`.
    var personalMultiplier: Double = 1.0
    /// Whether to let the user's lab results set the calibration automatically. Off
    /// hands the amplitude to ``personalMultiplier`` even when labs exist.
    var autoCalibrateFromLabs: Bool = true
    /// Whether a ≥2-lab calibration also fits the terminal rate `k1`, not just amplitude.
    var fitRates: Bool = true

    // MARK: Synced from the view's SwiftData queries

    /// Qualifying injections pulled from the dose log (date, mg), or empty.
    private(set) var loggedInjections: [(date: Date, doseMg: Double)] = []
    /// The ester the user logs most often for this analyte, if their doses name one
    /// — the log-first default so the curve opens on the ester they actually inject
    /// rather than the alphabetical first.
    private(set) var preferredEsterID: String?
    /// One-shot guard: once the source (log vs manual) has been defaulted from real
    /// data, never override the user's later choice.
    private var sourceDefaulted = false
    /// One-shot guard: the ester is defaulted alphabetically before the log syncs,
    /// then upgraded once to the ester the user actually logs — after which a manual
    /// pick stands.
    private var esterDefaulted = false
    /// Lab measurements for the active analyte, canonical unit, calibration-included.
    private(set) var calibrationMeasurements: [DepotCalibration.Measurement] = []
    /// Whether the log has any qualifying injections for the active analyte.
    var hasLogHistory: Bool {
        !loggedInjections.isEmpty
    }

    // MARK: Outputs

    private(set) var result: DepotCurveResult?
    private(set) var calibration: DepotCalibration.Result?

    /// The selected ester's DB record, resolved live from the store.
    var selectedEster: EsterPKRecord? {
        guard let id = selectedEsterID else { return nil }
        return SubstanceStore.shared.esterPK(forEsterID: id)
    }

    /// The esters available for the active analyte, for the picker.
    var availableEsters: [EsterPKRecord] {
        SubstanceStore.shared.estersForAnalyte(analyte.key)
    }

    /// Whether the user has any lab measurements included in calibration.
    var hasLabs: Bool {
        !calibrationMeasurements.isEmpty
    }

    /// Whether the current curve is driven by a lab fit (auto on + labs present).
    var isLabDriven: Bool {
        autoCalibrateFromLabs && calibration != nil
    }

    /// The amplitude multiplier currently in effect — the lab-fit scale when
    /// lab-driven, otherwise the user's manual personal multiplier. What the
    /// calibration control displays.
    var effectiveMultiplier: Double {
        if let cal = calibration, autoCalibrateFromLabs { return cal.scale }
        return personalMultiplier
    }

    // MARK: Recompute key

    struct RecomputeKey: Equatable {
        let analyte: Analyte
        let esterID: String?
        let doseMg: Double?
        let intervalDays: Double?
        let useLogHistory: Bool
        let referenceLow: Double?
        let referenceHigh: Double?
        let personalMultiplier: Double
        let autoCalibrateFromLabs: Bool
        let fitRates: Bool
        let logSignature: Int
        let labSignature: Int
    }

    var recomputeKey: RecomputeKey {
        RecomputeKey(
            analyte: analyte, esterID: selectedEsterID, doseMg: doseMg,
            intervalDays: intervalDays, useLogHistory: useLogHistory,
            referenceLow: referenceLow, referenceHigh: referenceHigh,
            personalMultiplier: personalMultiplier,
            autoCalibrateFromLabs: autoCalibrateFromLabs, fitRates: fitRates,
            logSignature: signature(of: loggedInjections.map { ($0.date, $0.doseMg) }),
            labSignature: signature(of: calibrationMeasurements.map { ($0.date, $0.value) }),
        )
    }

    private func signature(of pairs: [(Date, Double)]) -> Int {
        var hasher = Hasher()
        for (date, value) in pairs {
            hasher.combine(date.timeIntervalSinceReferenceDate.rounded())
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    // MARK: Sync from view

    /// Adopt the qualifying injections and lab results the view read from SwiftData.
    /// `injections` are already filtered to the active analyte (IM/SC, mg-convertible).
    func sync(
        injections: [(date: Date, doseMg: Double)],
        measurements: [DepotCalibration.Measurement],
        preferredEsterID: String? = nil,
    ) {
        loggedInjections = injections.sorted { $0.date < $1.date }
        calibrationMeasurements = measurements
        self.preferredEsterID = preferredEsterID
    }

    /// Pick the analyte's default ester if none is selected (or the current one no
    /// longer belongs to the analyte) — the ester the user logs most, else the first.
    /// Log-first source default: prefer the log the moment it has data (one-shot, so
    /// a later manual toggle stands), and never offer manual-only as "log".
    func selectDefaultsIfNeeded() {
        let esters = availableEsters
        let preferred = preferredEsterID.flatMap { id in esters.first { $0.esterID == id }?.esterID }
        if selectedEsterID == nil || !esters.contains(where: { $0.esterID == selectedEsterID }) {
            selectedEsterID = preferred ?? esters.first?.esterID
            if preferred != nil { esterDefaulted = true }
        } else if !esterDefaulted, let preferred, preferred != selectedEsterID {
            // The log synced after the first (alphabetical) default — upgrade once to
            // the ester the user actually logs. A later manual pick sets it too.
            selectedEsterID = preferred
            esterDefaulted = true
        }
        if hasLogHistory {
            if !sourceDefaulted { useLogHistory = true; sourceDefaulted = true }
        } else {
            useLogHistory = false
        }
    }

    // MARK: Compute

    func refresh() {
        guard let ester = selectedEster, let population = ester.parameters else {
            result = nil; calibration = nil; return
        }

        let injections = injectionsForCurve(ester: ester, population: population)
        guard !injections.isEmpty else { result = nil; calibration = nil; return }

        // Calibrate to the user's labs when allowed; otherwise fall to the manual
        // personal multiplier. The lab fit is amplitude-only for one result, and
        // amplitude + terminal rate for two or more (when rate-fit is on).
        let cal = autoCalibrateFromLabs
            ? DepotCalibration.calibrate(
                population: population,
                injections: injections,
                measurements: calibrationMeasurements,
                fitRate: fitRates,
            )
            : nil
        calibration = cal
        let params: PKModel.DepotParameters = if let cal {
            population.withK1Scale(cal.k1Scale).withAmplitude(cal.calibratedAmplitude)
        } else {
            population.withAmplitude(population.d * max(0.05, personalMultiplier))
        }

        let (rangeStart, rangeEnd, cycleDays) = window(injections: injections)
        let curve = PKModel.depotCurve(
            injections: injections, over: rangeStart ... rangeEnd, parameters: params,
        )

        let band = bandFraction(confidence: ester.confidence, calibrated: cal != nil)
        let points = curve.map { pt in
            DepotCurveResult.Point(
                date: pt.date, level: pt.pgPerML,
                bandLow: max(0, pt.pgPerML * (1 - band)),
                bandHigh: pt.pgPerML * (1 + band),
            )
        }

        // Trough / peak over the last full cycle.
        let cycleStart = rangeEnd.addingTimeInterval(-cycleDays * PKModel.secondsPerDay)
        let cyclePoints = points.filter { $0.date >= cycleStart }
        let trough = cyclePoints.map(\.level).min() ?? 0
        let peak = cyclePoints.map(\.level).max() ?? 0

        var timeInRange: Double?
        if let low = referenceLow, let high = referenceHigh, high > low, !cyclePoints.isEmpty {
            let inRange = cyclePoints.filter { $0.level >= low && $0.level <= high }.count
            timeInRange = Double(inRange) / Double(cyclePoints.count)
        }

        result = DepotCurveResult(
            points: points,
            injectionDates: injections.map(\.date).filter { rangeStart ... rangeEnd ~= $0 },
            range: rangeStart ... rangeEnd,
            trough: trough, troughLow: max(0, trough * (1 - band)), troughHigh: trough * (1 + band),
            peak: peak, peakLow: max(0, peak * (1 - band)), peakHigh: peak * (1 + band),
            timeInRange: timeInRange,
        )
    }

    // MARK: Curve inputs

    private func injectionsForCurve(ester _: EsterPKRecord, population: PKModel.DepotParameters) -> [(date: Date, doseMg: Double)] {
        if useLogHistory, hasLogHistory { return loggedInjections }
        return synthesizedSchedule(population: population)
    }

    /// A regular schedule anchored so "now" sits at steady state: doses every
    /// `interval` for enough cycles to plateau, then one projected cycle ahead.
    private func synthesizedSchedule(population: PKModel.DepotParameters) -> [(date: Date, doseMg: Double)] {
        guard let dose = doseMg, dose > 0, let interval = intervalDays, interval > 0 else { return [] }
        // Cycles needed to reach steady state: ~5 terminal half-lives, capped.
        let terminalHalfLife = log(2) / max(population.k1, 1e-6) // days
        let cycles = min(max(Int((5 * terminalHalfLife / interval).rounded(.up)), 6), 60)
        let now = Date.now
        let start = now.addingTimeInterval(-Double(cycles) * interval * PKModel.secondsPerDay)
        var injections: [(date: Date, doseMg: Double)] = []
        var n = 0
        let horizon = now.addingTimeInterval(interval * PKModel.secondsPerDay)
        while true {
            let date = start.addingTimeInterval(Double(n) * interval * PKModel.secondsPerDay)
            if date > horizon { break }
            injections.append((date, dose))
            n += 1
        }
        return injections
    }

    /// The date span to draw and the length of one modeled cycle (days).
    private func window(injections: [(date: Date, doseMg: Double)]) -> (Date, Date, Double) {
        let dates = injections.map(\.date).sorted()
        let first = dates.first ?? .now
        let last = dates.last ?? .now
        let cycleDays = medianIntervalDays(dates) ?? intervalDays ?? 14
        // End one cycle past the last injection (or now, whichever is later) so the
        // current/next trough is visible.
        let end = max(last.addingTimeInterval(cycleDays * PKModel.secondsPerDay), Date.now)
        return (first, end, cycleDays)
    }

    private func medianIntervalDays(_ dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }
        let gaps = zip(dates.dropFirst(), dates).map { ($0.timeIntervalSince($1)) / PKModel.secondsPerDay }
            .filter { $0 > 0 }.sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }

    /// Typical-range band as a fraction of the level. Pre-calibration reflects
    /// inter-individual variation (wide on purpose — the invitation to calibrate);
    /// post-calibration reflects only shape + assay + within-individual noise
    /// (Specs/injection-levels-tool.md §4). Mapped from the ester's confidence tier.
    private func bandFraction(confidence: String, calibrated: Bool) -> Double {
        switch (confidence, calibrated) {
        case ("high", false): 0.25
        case ("high", true): 0.18
        case ("medium", false): 0.45
        case ("medium", true): 0.22
        case (_, false): 0.50
        case (_, true): 0.25
        }
    }
}
