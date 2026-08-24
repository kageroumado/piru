import Foundation
import Testing
@testable import Piru

@Suite("VitalsAnalysis")
struct VitalsAnalysisTests {
    /// Build heart-rate samples at minute offsets relative to a base date.
    private func samples(_ pairs: [(minutes: Double, bpm: Double)], from base: Date) -> [HeartRateSample] {
        pairs.map { HeartRateSample(date: base.addingTimeInterval($0.minutes * 60), bpm: $0.bpm) }
    }

    /// Build samples with a workout flag on each.
    private func samples(_ triples: [(minutes: Double, bpm: Double, workout: Bool)], from base: Date) -> [HeartRateSample] {
        triples.map {
            HeartRateSample(date: base.addingTimeInterval($0.minutes * 60), bpm: $0.bpm, isWorkout: $0.workout)
        }
    }

    // MARK: - doseResponse

    @Test
    func `at-dose baseline is the sample just before the dose; the extreme is the furthest from it`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        // -5m → 66 (baseline), +10m → 80, +30m → 96 (extreme), +60m → 88 (outside 45m window)
        let hr = samples([(-5, 66), (10, 80), (30, 96), (60, 88)], from: dose)
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.atDose == 66)
        #expect(response?.extreme == 96)
        #expect(response?.delta == 30)
        #expect(response?.direction == .rose)
        #expect(response?.sparkline == [80, 96]) // only the in-window samples
    }

    @Test
    func `nil when no samples fall in the response window`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(-30, 70), (90, 100)], from: dose) // both outside [0, 45]
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: hr) == nil)
    }

    @Test
    func `empty samples → nil`() {
        #expect(VitalsAnalysis.doseResponse(doseAt: Date(timeIntervalSinceReferenceDate: 0), in: []) == nil)
    }

    @Test
    func `baseline falls back to the first in-window sample when nothing precedes the dose`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(5, 74), (20, 92)], from: dose) // no pre-dose sample
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.atDose == 74)
        #expect(response?.extreme == 92)
    }

    @Test
    func `baseline ignores pre-dose samples older than the lookback`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        // -40m is older than the 20m lookback → ignored; baseline is the first in-window (72)
        let hr = samples([(-40, 55), (10, 72), (25, 100)], from: dose)
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: hr)?.atDose == 72)
    }

    /// The propranolol case: nothing about a rate-lowering dose is described by the
    /// highest sample of its window, so the extreme is picked by distance from baseline.
    @Test
    func `a dose that lowers heart rate reports its nadir, not the window maximum`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(-2, 100), (10, 80), (30, 70)], from: dose)
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.atDose == 100)
        #expect(response?.extreme == 70)
        #expect(response?.delta == -30)
        #expect(response?.direction == .fell)
    }

    @Test
    func `a move inside the noise floor is reported as unchanged`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(-2, 66), (10, 70), (30, 69)], from: dose)
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.delta == 4)
        #expect(response?.direction == .unchanged)
    }

    @Test
    func `a single in-window sample describes nothing, so no response`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: samples([(-2, 66), (10, 110)], from: dose)) == nil)
    }

    @Test
    func `samples bunched into less than the minimum span are rejected`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        // Two samples 4 minutes apart describe those 4 minutes, not the dose.
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: samples([(-2, 66), (5, 100), (9, 104)], from: dose)) == nil)
    }

    /// A run raises heart rate past anything in the library, so leaving it in would hand the
    /// dose that happens to own the window a response it had nothing to do with.
    @Test
    func `workout samples are excluded from a dose's response`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples(
            [(-2, 66, false), (10, 70, false), (20, 148, true), (25, 152, true), (35, 71, false)],
            from: dose,
        )
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.extreme == 71)
        #expect(response?.direction == .unchanged)
        #expect(response?.sparkline == [70, 71])
    }

    @Test
    func `a window that is all workout leaves no response at all`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(-2, 66, false), (10, 150, true), (25, 158, true), (40, 145, true)], from: dose)
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: hr) == nil)
    }

    // MARK: - doseResponses (session-wide)

    private func window(_ id: UUID, _ minutes: Double, _ substance: String, peak: Double?, comeUp: Double?, from base: Date) -> HRDoseWindow {
        HRDoseWindow(
            id: id, at: base.addingTimeInterval(minutes * 60), substance: substance,
            peakEndMinutes: peak, comeUpEndMinutes: comeUp,
        )
    }

    @Test
    func `a dose's window stops at the next dose, so one rise is not counted twice`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let first = UUID(), second = UUID()
        let doses = [
            window(first, 0, "Caffeine", peak: 120, comeUp: 30, from: base),
            window(second, 40, "Caffeine", peak: 120, comeUp: 30, from: base),
        ]
        // The whole climb happens after the second dose; the first dose's window ends at +40m.
        let hr = samples([(-2, 62), (10, 63), (30, 64), (50, 90), (70, 104)], from: base)
        let out = VitalsAnalysis.doseResponses(for: doses, in: hr)
        #expect(out[first]?.direction == .unchanged)
        #expect(out[second]?.delta == 40)
        #expect(out[second]?.direction == .rose)
    }

    @Test
    func `a dose taken while another substance is still coming up names it as a confounder`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let mdma = UUID(), caffeine = UUID()
        let doses = [
            window(mdma, 0, "MDMA", peak: 180, comeUp: 60, from: base),
            window(caffeine, 30, "Caffeine", peak: 120, comeUp: 30, from: base),
        ]
        let hr = samples([(-2, 62), (10, 70), (25, 84), (40, 92), (70, 110)], from: base)
        let out = VitalsAnalysis.doseResponses(for: doses, in: hr)
        #expect(out[mdma]?.confounders.isEmpty == true)
        #expect(out[caffeine]?.confounders == ["MDMA"])
        #expect(out[caffeine]?.isConfounded == true)
    }

    @Test
    func `a re-dose of the same substance is not its own confounder`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let first = UUID(), second = UUID()
        let doses = [
            window(first, 0, "Caffeine", peak: 120, comeUp: 60, from: base),
            window(second, 30, "caffeine", peak: 120, comeUp: 60, from: base),
        ]
        let hr = samples([(-2, 62), (10, 70), (40, 92), (70, 110)], from: base)
        #expect(VitalsAnalysis.doseResponses(for: doses, in: hr)[second]?.confounders.isEmpty == true)
    }

    @Test
    func `an earlier dose that has finished coming up no longer confounds`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let early = UUID(), late = UUID()
        let doses = [
            window(early, 0, "Caffeine", peak: 120, comeUp: 20, from: base),
            window(late, 60, "MDMA", peak: 180, comeUp: 60, from: base),
        ]
        let hr = samples([(-2, 62), (10, 66), (40, 68), (75, 96), (100, 104)], from: base)
        #expect(VitalsAnalysis.doseResponses(for: doses, in: hr)[late]?.confounders.isEmpty == true)
    }

    @Test
    func `the window comes from the dose's own peak, clamped to the floor and the cap`() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let fast = UUID(), slow = UUID()
        // A 5-minute peak is floored to 30m: the +25m sample is still in window.
        let fastOut = VitalsAnalysis.doseResponses(
            for: [window(fast, 0, "Cocaine", peak: 5, comeUp: 5, from: base)],
            in: samples([(-2, 66), (10, 90), (25, 108)], from: base),
        )
        #expect(fastOut[fast]?.extreme == 108)

        // An 8-hour peak is capped at 3h: the +200m sample falls outside.
        let slowOut = VitalsAnalysis.doseResponses(
            for: [window(slow, 0, "Lisdexamfetamine", peak: 480, comeUp: 90, from: base)],
            in: samples([(-2, 66), (60, 88), (170, 92), (200, 140)], from: base),
        )
        #expect(slowOut[slow]?.extreme == 92)
    }

    // MARK: - summary

    @Test
    func `averages and peaks the samples in the window, rounds, and carries resting`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3_600)
        let hr = samples([(0, 60), (20, 80), (40, 100)], from: start) // avg 80, peak 100
        let summary = VitalsAnalysis.summary(from: start, to: end, heartRate: hr, restingHeartRate: 62.4)
        #expect(summary?.average == 80)
        #expect(summary?.peak == 100)
        #expect(summary?.resting == 62)
    }

    @Test
    func `excludes samples outside the window`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3_600)
        let hr = samples([(-10, 200), (10, 70), (50, 90), (120, 200)], from: start)
        let summary = VitalsAnalysis.summary(from: start, to: end, heartRate: hr, restingHeartRate: nil)
        #expect(summary?.average == 80)
        #expect(summary?.peak == 90)
        #expect(summary?.resting == nil)
    }

    @Test
    func `nil when no samples fall in the window`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(VitalsAnalysis.summary(from: start, to: start.addingTimeInterval(3_600), heartRate: [], restingHeartRate: 60) == nil)
    }

    /// A wrist sensor bursts to seconds-apart samples during movement, so counting samples
    /// equally would report the average of the busiest minutes rather than of the session.
    @Test
    func `the average is time-weighted, not sample-weighted`() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3_600)
        // A ~55-minute stretch at 60 bpm, then four samples a minute apart at 120.
        let hr = samples([(0, 60), (55, 60), (56, 120), (57, 120), (58, 120), (59, 120)], from: start)
        let summary = VitalsAnalysis.summary(from: start, to: end, heartRate: hr, restingHeartRate: nil)
        // Sample-weighted would be 100; time-weighted lands near the 60 bpm the hour was spent at.
        #expect(try #require(summary?.average) < 80)
        #expect(summary?.peak == 120) // a real recorded beat is still reported
    }

    @Test
    func `the summary keeps workout samples and reports how long the workout ran`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3_600)
        let hr = samples(
            [(0, 60, false), (10, 62, false), (20, 150, true), (30, 155, true), (40, 64, false)],
            from: start,
        )
        let summary = VitalsAnalysis.summary(from: start, to: end, heartRate: hr, restingHeartRate: nil)
        #expect(summary?.peak == 155) // the session's real maximum, workout and all
        #expect(summary?.workoutMinutes == 10) // only the stretch *between* two workout samples
    }

    @Test
    func `no workout means no workout minutes`() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(0, 60), (20, 80), (40, 100)], from: start)
        let summary = VitalsAnalysis.summary(from: start, to: start.addingTimeInterval(3_600), heartRate: hr, restingHeartRate: nil)
        #expect(summary?.workoutMinutes == 0)
    }

    // MARK: - SessionVitals

    @Test
    func `SessionVitals.isEmpty reflects both series`() {
        #expect(SessionVitals.empty.isEmpty)
        let withHR = SessionVitals(heartRate: [HeartRateSample(date: .init(timeIntervalSinceReferenceDate: 0), bpm: 70)], bloodPressure: [], restingHeartRate: nil)
        #expect(!withHR.isEmpty)
        #expect(withHR.hasHeartRate)
        #expect(!withHR.hasBloodPressure)
    }
}
