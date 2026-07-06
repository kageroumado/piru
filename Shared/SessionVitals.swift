import SwiftUI

/// Fixed vitals colours — deliberately distinct from any substance colour and legible in
/// both light and dark. Shared by the timeline cardio lane and the entry-row HR chips so
/// they always match. HR is a warm crimson; BP a calm blue.
enum VitalsPalette {
    static let heart = Color(red: 0.898, green: 0.290, blue: 0.310)
    static let bloodPressure = Color(red: 0.231, green: 0.490, blue: 0.847)
}

/// A single heart-rate sample read from HealthKit (Apple Watch records these ~every 5 min).
nonisolated struct HeartRateSample: Hashable {
    let date: Date
    let bpm: Double
}

/// A single blood-pressure reading (systolic/diastolic) read from HealthKit. BP is sparse —
/// there is no continuous BP sensor, so these are occasional spot checks, not a curve.
nonisolated struct BloodPressureReading: Hashable {
    let date: Date
    let systolic: Double
    let diastolic: Double
}

/// Physiological vitals for one session's time window, overlaid on the timeline.
///
/// Empty arrays mean "no data" — the UI renders **nothing** rather than an empty axis, so a
/// day without an Apple Watch (or without a BP reading) shows no vitals chrome at all.
nonisolated struct SessionVitals: Hashable {
    var heartRate: [HeartRateSample]
    var bloodPressure: [BloodPressureReading]
    /// The user's resting heart rate near the session, for the "elevated vs resting" summary.
    var restingHeartRate: Double?

    var hasHeartRate: Bool {
        !heartRate.isEmpty
    }
    var hasBloodPressure: Bool {
        !bloodPressure.isEmpty
    }
    var isEmpty: Bool {
        heartRate.isEmpty && bloodPressure.isEmpty
    }

    static let empty = SessionVitals(heartRate: [], bloodPressure: [], restingHeartRate: nil)
}

/// One dose's heart-rate response, shown as an inline chip on its entry row:
/// HR at the moment of dosing → the peak reached within the response window.
nonisolated struct DoseHRResponse: Hashable {
    /// HR nearest the dose time (bpm, rounded).
    let atDose: Int
    /// Peak HR within the response window after the dose (bpm, rounded).
    let peak: Int
    /// `peak - atDose` (can be negative if HR fell).
    let delta: Int
    /// In-window bpm values, for the row's mini sparkline.
    let sparkline: [Double]
}

/// Session-wide heart-rate summary for the Summary card.
nonisolated struct HRSummary: Hashable {
    let average: Int
    let peak: Int
    /// Resting HR baseline, if known (for "elevated vs your resting N bpm").
    let resting: Int?
}

/// Pure heart-rate analysis over sample arrays — no HealthKit, no view state, so it's unit-testable.
nonisolated enum VitalsAnalysis {
    /// Default window in which to look for a dose's heart-rate response.
    static let responseWindow: TimeInterval = 45 * 60
    /// How far *before* the dose to accept a sample as the "at dose" baseline.
    static let baselineLookback: TimeInterval = 20 * 60

    /// The heart-rate response to a single dose, or `nil` if there are no samples in the window.
    static func doseResponse(
        doseAt: Date,
        in samples: [HeartRateSample],
        window: TimeInterval = responseWindow,
    ) -> DoseHRResponse? {
        guard !samples.isEmpty else { return nil }
        let end = doseAt.addingTimeInterval(window)
        let inWindow = samples.filter { $0.date >= doseAt && $0.date <= end }
        guard let peakSample = inWindow.max(by: { $0.bpm < $1.bpm }) else { return nil }

        // Baseline = the most recent sample just before the dose (within `baselineLookback`);
        // fall back to the first in-window sample when nothing precedes the dose.
        let baselineWindowStart = doseAt.addingTimeInterval(-baselineLookback)
        let before = samples
            .filter { $0.date <= doseAt && $0.date >= baselineWindowStart }
            .max(by: { $0.date < $1.date })
        let atSample = before ?? inWindow.min(by: { $0.date < $1.date })!

        let at = Int(atSample.bpm.rounded())
        let peak = Int(peakSample.bpm.rounded())
        return DoseHRResponse(atDose: at, peak: peak, delta: peak - at, sparkline: inWindow.map(\.bpm))
    }

    /// The session-wide heart-rate summary over `[start, end]`, or `nil` if no samples fall inside.
    static func summary(
        from start: Date,
        to end: Date,
        heartRate: [HeartRateSample],
        restingHeartRate: Double?,
    ) -> HRSummary? {
        let inWindow = heartRate.filter { $0.date >= start && $0.date <= end }
        guard !inWindow.isEmpty else { return nil }
        let bpms = inWindow.map(\.bpm)
        let average = Int((bpms.reduce(0, +) / Double(bpms.count)).rounded())
        let peak = Int((bpms.max() ?? 0).rounded())
        let resting = restingHeartRate.map { Int($0.rounded()) }
        return HRSummary(average: average, peak: peak, resting: resting)
    }
}
