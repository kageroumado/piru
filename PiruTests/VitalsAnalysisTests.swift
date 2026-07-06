import Foundation
import Testing
@testable import Piru

@Suite("VitalsAnalysis")
struct VitalsAnalysisTests {
    /// Build heart-rate samples at minute offsets relative to a base date.
    private func samples(_ pairs: [(minutes: Double, bpm: Double)], from base: Date) -> [HeartRateSample] {
        pairs.map { HeartRateSample(date: base.addingTimeInterval($0.minutes * 60), bpm: $0.bpm) }
    }

    // MARK: - doseResponse

    @Test
    func `at-dose baseline is the sample just before the dose; peak is the max within the window`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        // -5m → 66 (baseline), +10m → 80, +30m → 96 (peak), +60m → 88 (outside 45m window)
        let hr = samples([(-5, 66), (10, 80), (30, 96), (60, 88)], from: dose)
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.atDose == 66)
        #expect(response?.peak == 96)
        #expect(response?.delta == 30)
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
        #expect(response?.peak == 92)
    }

    @Test
    func `baseline ignores pre-dose samples older than the lookback`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        // -40m is older than the 20m lookback → ignored; baseline is the first in-window (72)
        let hr = samples([(-40, 55), (10, 72), (25, 100)], from: dose)
        #expect(VitalsAnalysis.doseResponse(doseAt: dose, in: hr)?.atDose == 72)
    }

    @Test
    func `negative delta when heart rate falls after the dose`() {
        let dose = Date(timeIntervalSinceReferenceDate: 0)
        let hr = samples([(-2, 100), (10, 80), (30, 70)], from: dose)
        let response = VitalsAnalysis.doseResponse(doseAt: dose, in: hr)
        #expect(response?.atDose == 100)
        #expect(response?.peak == 80)
        #expect(response?.delta == -20)
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
