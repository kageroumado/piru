import SwiftUI

/// Fixed vitals colors — deliberately distinct from any substance color and legible in
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
    /// Whether the sample falls inside a recorded workout. A run raises heart rate by more
    /// than any dose in the library, so a workout inside a dose's window would otherwise be
    /// read as that dose's response — the single largest confound in the whole overlay.
    var isWorkout = false
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

/// Which way a dose's heart rate moved. ``unchanged`` means the move stayed inside
/// ``VitalsAnalysis/noiseFloor`` — the wander a wrist sensor shows from posture and
/// movement alone — so the numbers are shown without claiming a response.
nonisolated enum HRDirection: Hashable {
    case rose
    case fell
    case unchanged
}

/// One dose's heart-rate response, shown as an inline chip on its entry row:
/// HR at the moment of dosing → the extreme reached within the response window.
nonisolated struct DoseHRResponse: Hashable {
    /// HR nearest the dose time (bpm, rounded).
    let atDose: Int
    /// The furthest HR from ``atDose`` within the response window (bpm, rounded) —
    /// the peak for a dose that raised heart rate, the nadir for one that lowered it.
    /// A beta blocker's whole signal is the drop, so the extreme is chosen by distance
    /// from baseline rather than by magnitude.
    let extreme: Int
    /// `extreme - atDose` (negative when heart rate fell).
    let delta: Int
    let direction: HRDirection
    /// Other substances still in their come-up across this dose's window — whatever the
    /// numbers show is theirs as much as this dose's.
    let confounders: [String]
    /// In-window bpm values, for the row's mini sparkline.
    let sparkline: [Double]

    var isConfounded: Bool {
        !confounders.isEmpty
    }
}

/// One dose handed to the batch analysis: when it was taken, how long its own effects
/// take to arrive, and what it is called.
nonisolated struct HRDoseWindow: Hashable {
    let id: UUID
    let at: Date
    let substance: String
    /// Minutes from the dose to the end of its modeled peak — the stretch a cardiovascular
    /// response would land in. Nil for a substance with no modeled duration.
    let peakEndMinutes: Double?
    /// Minutes from the dose to the end of its modeled come-up — the stretch in which this
    /// dose is still *changing* the body, so a later dose landing inside it can't claim its
    /// own reading cleanly. Nil for a substance with no modeled duration.
    let comeUpEndMinutes: Double?
}

/// Session-wide heart-rate summary for the Summary card.
nonisolated struct HRSummary: Hashable {
    let average: Int
    let peak: Int
    /// Resting HR baseline, if known (for "elevated vs your resting N bpm").
    let resting: Int?
    /// Minutes of the window spent in a recorded workout. Both figures above include it —
    /// they describe the session as it happened — so this is what stops a post-run peak
    /// from reading as something a dose did.
    var workoutMinutes = 0
}

/// Pure heart-rate analysis over sample arrays — no HealthKit, no view state, so it's unit-testable.
nonisolated enum VitalsAnalysis {
    /// Response window for a dose whose substance has no modeled duration.
    static let responseWindow: TimeInterval = 45 * 60
    /// Floor on a duration-derived window, so a fast substance's few-minute peak still
    /// spans enough of a ~5-minute-cadence sample series to describe anything.
    static let minimumWindow: TimeInterval = 30 * 60
    /// Cap on a duration-derived window: past three hours the reading stops being *this*
    /// dose's response and becomes the afternoon's.
    static let maximumWindow: TimeInterval = 3 * 3_600
    /// How far *before* the dose to accept a sample as the "at dose" baseline.
    static let baselineLookback: TimeInterval = 20 * 60
    /// Swing a wrist sensor shows at rest from posture, movement and breathing alone.
    /// A delta under this is reported as measured but not as a response.
    static let noiseFloor = 8
    /// Fewest in-window samples that can describe a change rather than assert one.
    static let minimumSamples = 2
    /// Shortest first-to-last span of in-window samples worth reading. Two samples a
    /// minute apart describe that minute, not the dose.
    static let minimumSpan: TimeInterval = 10 * 60

    /// Per-dose heart-rate responses for a whole session, keyed by dose id.
    ///
    /// Two things the single-dose call can't do on its own, and the reason the session
    /// goes through here: each dose's window is cut short at the **next** dose, so one
    /// rise is never counted as three separate responses to a re-dose; and a dose taken
    /// while something else is still coming up carries that substance in
    /// ``DoseHRResponse/confounders`` rather than quietly taking credit for it.
    static func doseResponses(for doses: [HRDoseWindow], in samples: [HeartRateSample]) -> [UUID: DoseHRResponse] {
        guard !samples.isEmpty, !doses.isEmpty else { return [:] }
        let readable = samples.filter { !$0.isWorkout }
        let ordered = doses.sorted { $0.at < $1.at }
        var out: [UUID: DoseHRResponse] = [:]
        for (index, dose) in ordered.enumerated() {
            let modeled = dose.peakEndMinutes.map { min(max($0 * 60, minimumWindow), maximumWindow) }
            var end = dose.at.addingTimeInterval(modeled ?? responseWindow)
            if index + 1 < ordered.count {
                end = min(end, ordered[index + 1].at)
            }
            // Same-substance re-doses are left out: the reading is still that substance's,
            // and naming it as its own confounder says nothing the row doesn't already show.
            let confounders = ordered[..<index]
                .filter { earlier in
                    earlier.substance.caseInsensitiveCompare(dose.substance) != .orderedSame
                        && (earlier.comeUpEndMinutes.map { earlier.at.addingTimeInterval($0 * 60) > dose.at } ?? false)
                }
                .map(\.substance)
            if let response = response(doseAt: dose.at, until: end, in: readable, confounders: uniqued(confounders)) {
                out[dose.id] = response
            }
        }
        return out
    }

    /// The heart-rate response to a single dose over a fixed window, or `nil` when the
    /// samples in it are too few or too bunched to describe one.
    static func doseResponse(
        doseAt: Date,
        in samples: [HeartRateSample],
        window: TimeInterval = responseWindow,
    ) -> DoseHRResponse? {
        response(
            doseAt: doseAt, until: doseAt.addingTimeInterval(window),
            in: samples.filter { !$0.isWorkout }, confounders: [],
        )
    }

    private static func response(
        doseAt: Date,
        until end: Date,
        in samples: [HeartRateSample],
        confounders: [String],
    ) -> DoseHRResponse? {
        guard end > doseAt else { return nil }
        let inWindow = samples
            .filter { $0.date >= doseAt && $0.date <= end }
            .sorted { $0.date < $1.date }
        guard inWindow.count >= minimumSamples,
              let first = inWindow.first, let last = inWindow.last,
              last.date.timeIntervalSince(first.date) >= minimumSpan
        else { return nil }

        // Baseline = the most recent sample just before the dose (within `baselineLookback`);
        // fall back to the first in-window sample when nothing precedes the dose.
        let baselineWindowStart = doseAt.addingTimeInterval(-baselineLookback)
        let before = samples
            .filter { $0.date <= doseAt && $0.date >= baselineWindowStart }
            .max(by: { $0.date < $1.date })
        let atSample = before ?? first

        let at = Int(atSample.bpm.rounded())
        // Furthest from baseline in either direction, so a dose that lowered heart rate
        // reports its nadir instead of the meaningless highest sample of the window.
        let extremeSample = inWindow.max { abs($0.bpm - atSample.bpm) < abs($1.bpm - atSample.bpm) }!
        let extreme = Int(extremeSample.bpm.rounded())
        let delta = extreme - at
        let direction: HRDirection = abs(delta) < noiseFloor ? .unchanged : (delta > 0 ? .rose : .fell)
        return DoseHRResponse(
            atDose: at, extreme: extreme, delta: delta, direction: direction,
            confounders: confounders, sparkline: inWindow.map(\.bpm),
        )
    }

    /// Time covered by workout samples, measured the same gap-capped way the average is
    /// weighted: only a stretch *between two* workout samples counts, so one stray flagged
    /// sample contributes nothing.
    private static func workoutSpan(of samples: [HeartRateSample]) -> TimeInterval {
        zip(samples, samples.dropFirst())
            .filter { $0.isWorkout && $1.isWorkout }
            .reduce(0) { $0 + min($1.1.date.timeIntervalSince($1.0.date), maximumSampleGap) }
    }

    /// Order-preserving dedup, so "overlaps Caffeine, Caffeine" can't happen.
    private static func uniqued(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Longest gap between samples that still counts as measured time in the average.
    /// Past it the watch simply wasn't looking, and stretching two readings across the
    /// hole would let a single pre-nap sample outweigh an hour of the session.
    static let maximumSampleGap: TimeInterval = 15 * 60

    /// The session-wide heart-rate summary over `[start, end]`, or `nil` if no samples fall inside.
    ///
    /// The average is **time-weighted**. A wrist sensor bursts to seconds-apart samples during
    /// movement and idles at five-minute intervals at rest, so counting every sample equally
    /// reports the average of whatever the user was doing most actively rather than the average
    /// of the session. The peak is the plain maximum: a real beat the watch recorded is worth
    /// reporting even when a staircase, not the dose, caused it.
    ///
    /// Workout samples stay in both figures — this describes the session, not the doses — and
    /// are reported separately as ``HRSummary/workoutMinutes``. The per-dose chips are the
    /// place a workout must not appear, and ``doseResponses(for:in:)`` drops it there.
    static func summary(
        from start: Date,
        to end: Date,
        heartRate: [HeartRateSample],
        restingHeartRate: Double?,
    ) -> HRSummary? {
        let inWindow = heartRate
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        guard let firstSample = inWindow.first else { return nil }
        let peak = Int((inWindow.map(\.bpm).max() ?? 0).rounded())
        let resting = restingHeartRate.map { Int($0.rounded()) }

        var weighted = 0.0
        var weight = 0.0
        for (previous, next) in zip(inWindow, inWindow.dropFirst()) {
            let span = min(next.date.timeIntervalSince(previous.date), maximumSampleGap)
            weighted += (previous.bpm + next.bpm) / 2 * span
            weight += span
        }
        let average = weight > 0 ? weighted / weight : firstSample.bpm
        return HRSummary(
            average: Int(average.rounded()), peak: peak, resting: resting,
            workoutMinutes: Int((workoutSpan(of: inWindow) / 60).rounded()),
        )
    }
}
