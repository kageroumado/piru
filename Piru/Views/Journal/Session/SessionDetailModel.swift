import Foundation
import SwiftData
import SwiftUI

/// The session detail's async-loaded data — the substance color map, the Apple
/// Health vitals overlay, and the mechanistic simulation. Held in an `@Observable`
/// model (filled from the view's `.task`s) so a load lands on exactly the sections
/// that read it, and the view's own `@State` stays limited to edit/UI concerns.
@MainActor
@Observable
final class SessionDetailModel {
    /// The simulated mechanistic timeline — nil until computed or when the
    /// session contains nothing the engine models.
    var mechanisticResult: MechanisticSessionModel.Result?

    /// Apple Health vitals for this session's window (nil until fetched / when empty).
    var sessionVitals: SessionVitals?
    /// Per-dose heart-rate response, keyed by `DoseEntry.id`, for the row chips.
    var doseHR: [UUID: DoseHRResponse] = [:]
    /// Session-wide heart-rate summary for the Summary card.
    var hrSummary: HRSummary?

    /// Substance → color, rebuilt only when the color assignments change.
    var colorMap: [String: Color] = [:]
    /// Flips true once `colorMap` is first populated, so `resolvedColor` stops
    /// falling back to the per-call map build after the warm-up frame.
    var colorMapReady = false

    func loadColorMap(colors: [SubstanceColor]) {
        colorMap = Array(colors).colorMap
        colorMapReady = true
    }

    /// Fetch Health vitals for this session and derive the chart overlay, the
    /// per-dose row chips, and the summary — or clear them when disabled. Attempts
    /// the read unconditionally (iOS never reports read access); an empty result
    /// simply leaves everything nil, so nothing about vitals shows.
    func loadVitals(session: Session, entries: [DoseEntry], windowEnd: Date, showSessionVitals: Bool) async {
        let start = session.startDate.addingTimeInterval(-VitalsAnalysis.baselineLookback)
        let end = windowEnd
        let fetched = await fetchVitals(session: session, entries: entries, from: start, to: end, showSessionVitals: showSessionVitals)
        guard !Task.isCancelled else { return }

        sessionVitals = fetched.isEmpty ? nil : fetched
        doseHR = VitalsAnalysis.doseResponses(for: entries.map { Self.hrWindow(for: $0) }, in: fetched.heartRate)
        hrSummary = VitalsAnalysis.summary(
            from: session.startDate, to: end,
            heartRate: fetched.heartRate, restingHeartRate: fetched.restingHeartRate,
        )
    }

    /// One dose described for the heart-rate analysis. The window comes from the same
    /// duration profile the timeline curve draws, so a dose's response is read over the
    /// stretch the app already says its effects arrive in — an insufflated line over
    /// minutes, an oral tablet over hours — rather than one fixed 45 minutes for both.
    /// A substance with no modeled duration (or a form we decline to model) carries nils
    /// and falls back to the default window.
    private static func hrWindow(for entry: DoseEntry) -> HRDoseWindow {
        let state = ActiveSubstanceState.from(entry: entry, colorHex: "000000")
        return HRDoseWindow(
            id: entry.id,
            at: entry.timestamp,
            substance: entry.substance,
            peakEndMinutes: state?.peakEndMinutes,
            comeUpEndMinutes: state?.comeupEndMinutes,
        )
    }

    private func fetchVitals(session: Session, entries: [DoseEntry], from start: Date, to end: Date, showSessionVitals: Bool) async -> SessionVitals {
        #if DEBUG
            // On-simulator visual verification without Health data. Never ships.
            if ProcessInfo.processInfo.arguments.contains("-piruFakeVitals") {
                return DebugVitals.synthetic(doses: entries.map(\.timestamp), start: session.startDate, end: end)
            }
        #endif
        guard showSessionVitals, HealthKitVitals.shared.isAvailable else { return .empty }
        // Pure read — authorization is requested only at the opt-in points (the
        // Apple Health onboarding step, the Apple Health settings screen, and the
        // discovery banner), never here. Presenting the HealthKit system sheet from
        // inside this already-presented session sheet is a double-presentation
        // conflict: the prompt flashes up and is instantly dismissed, so the
        // request never completes and re-fires on every open. Reading with no
        // access simply returns empty (iOS never reports read status), which
        // renders as nothing on the timeline.
        return await HealthKitVitals.shared.vitals(from: start, to: end)
    }

    /// Resolve + simulate the session off the main actor, memoized. Runs on any
    /// change to the dose signature.
    func computeMechanistic(
        supported: Bool,
        doses: [MechanisticSessionModel.DoseInput],
        pharmacology: [String: PharmacologyParameters],
        signature: Int,
    ) async {
        guard supported else {
            mechanisticResult = nil
            return
        }
        if let cached = MechanisticModelCache.shared.cached(signature) {
            mechanisticResult = cached
            return
        }
        let last = doses.map(\.hours).max() ?? 0
        let tMax = min(48, max(12, last + 12))
        let result = await Task.detached { MechanisticSessionModel.compute(doses: doses, pharmacology: pharmacology, tMax: tMax) }.value
        // `.task(id:)` cancels this on a signature change — don't let a stale
        // simulation land after the newer task has already assigned its result.
        guard !Task.isCancelled else { return }
        if let result { MechanisticModelCache.shared.insert(signature, result) }
        mechanisticResult = result
    }
}

#if DEBUG
    /// Synthetic vitals for on-simulator visual verification, gated behind the
    /// `-piruFakeVitals` launch argument. Never compiled into release builds. HR
    /// rises after each dose (stimulant/alcohol tachycardia) with a little wobble,
    /// plus a couple of blood-pressure spot checks.
    private enum DebugVitals {
        static func synthetic(doses: [Date], start: Date, end: Date) -> SessionVitals {
            let totalMinutes = end.timeIntervalSince(start) / 60
            guard totalMinutes > 0 else { return .empty }

            func smoothstep(_ x: Double) -> Double {
                let c = max(0, min(1, x))
                return c * c * (3 - 2 * c)
            }
            func bump(_ t: Double, at t0: Double, rise: Double, fall: Double) -> Double {
                guard t >= t0 else { return 0 }
                let x = t - t0
                return x < rise ? smoothstep(x / rise) : exp(-(x - rise) / fall)
            }

            let doseMinutes = doses.map { $0.timeIntervalSince(start) / 60 }
            var heartRate: [HeartRateSample] = []
            var minute = -VitalsAnalysis.baselineLookback / 60
            var index = 0
            while minute <= totalMinutes {
                var bpm = 64 - 0.01 * minute
                for (position, dose) in doseMinutes.enumerated() {
                    bpm += Double(9 + position * 4) * bump(minute, at: dose, rise: 30, fall: 160)
                }
                bpm += 2.4 * sin(Double(index) * 1.7) + 1.6 * sin(Double(index) * 0.9)
                heartRate.append(HeartRateSample(date: start.addingTimeInterval(minute * 60), bpm: bpm))
                minute += 5
                index += 1
            }

            var bloodPressure: [BloodPressureReading] = []
            if let first = doseMinutes.first {
                bloodPressure.append(BloodPressureReading(date: start.addingTimeInterval((first + 8) * 60), systolic: 118, diastolic: 76))
            }
            if totalMinutes > 90 {
                bloodPressure.append(BloodPressureReading(date: start.addingTimeInterval(totalMinutes * 0.5 * 60), systolic: 129, diastolic: 83))
            }
            return SessionVitals(heartRate: heartRate, bloodPressure: bloodPressure, restingHeartRate: 62)
        }
    }
#endif
