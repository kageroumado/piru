import Foundation
import Testing
@testable import Piru

/// Pure-model gate for the tolerance engine's **right-shift** core (`Specs/tolerance-faithful-model.md`
/// §1–2, Stage A). These exercise ``PDModel`` in isolation — no store, no DB — so the dynamics are
/// proven before any wiring: clustered occupancy drives a layer's ln-shift up while spacing/idle decays
/// it; the deep gate is off below the escalation threshold and on above it; the response-fraction gauge
/// is 1 at `S = 1` and decreasing in `S`; and the recovery forecast is monotone.
@Suite("PDModel right-shift dynamics")
struct PDModelToleranceTests {
    /// A uniformly-sampled occupancy series: `days` days at `dtMinutes`, each dosing day a flat
    /// `peak`-occupancy pulse for the first `activeHours`, then zero; dosing every `everyDays` days.
    static func occupancySeries(
        days: Int, dtMinutes: Double, peak: Double, activeHours: Double, everyDays: Int,
    ) -> [Double] {
        let stepsPerDay = Int((24 * 60) / dtMinutes)
        let activeSteps = Int((activeHours * 60) / dtMinutes)
        var series: [Double] = []
        series.reserveCapacity(days * stepsPerDay)
        for day in 0 ..< days {
            let dosing = day % everyDays == 0
            for step in 0 ..< stepsPerDay {
                series.append(dosing && step < activeSteps ? peak : 0)
            }
        }
        return series
    }

    /// Integrate one layer over an occupancy series with the closed-form ``PDModel/stepShift``.
    static func shiftEnd(
        occupancy: [Double], dtMinutes: Double, shiftMax: Double, tauMinutes: Double, drive: Double = 1,
    ) -> Double {
        var s = 0.0
        for o in occupancy {
            s = PDModel.stepShift(
                current: s, shiftMax: shiftMax, occupancy: o, drive: drive,
                dtMinutes: dtMinutes, tauMinutes: tauMinutes,
            )
        }
        return s
    }

    // MARK: - stepShift

    @Test
    func `Occupancy drives the layer up toward its ceiling`() {
        // A long, fully-occupied step converges to shiftMax · O · drive.
        let s = PDModel.stepShift(current: 0, shiftMax: 2.0, occupancy: 1, drive: 1, dtMinutes: 1_000_000, tauMinutes: 1_440)
        #expect(abs(s - 2.0) < 1e-6)
    }

    @Test
    func `With no occupancy the layer decays toward zero`() {
        let s = PDModel.stepShift(current: 1.5, shiftMax: 2.0, occupancy: 0, drive: 1, dtMinutes: 1_000_000, tauMinutes: 1_440)
        #expect(s < 1e-3)
    }

    @Test
    func `A disabled layer (shiftMax 0) only decays, never grows`() {
        let s = PDModel.stepShift(current: 0.4, shiftMax: 0, occupancy: 1, drive: 1, dtMinutes: 1_440, tauMinutes: 1_440)
        #expect(s < 0.4) // pulled toward target 0
        #expect(s >= 0)
        let fromZero = PDModel.stepShift(current: 0, shiftMax: 0, occupancy: 1, drive: 1, dtMinutes: 1_440, tauMinutes: 1_440)
        #expect(fromZero == 0)
    }

    @Test
    func `Guards: non-positive dt or tau is a no-op`() {
        #expect(PDModel.stepShift(current: 0.7, shiftMax: 2, occupancy: 1, drive: 1, dtMinutes: 0, tauMinutes: 100) == 0.7)
        #expect(PDModel.stepShift(current: 0.7, shiftMax: 2, occupancy: 1, drive: 1, dtMinutes: 30, tauMinutes: 0) == 0.7)
    }

    @Test
    func `Clustered occupancy builds more shift than spaced; idle relaxes it`() throws {
        let dt = 30.0
        let p = ReceptorClasses.parameters(for: .psychedelic5HT2A)
        let daily = Self.occupancySeries(days: 14, dtMinutes: dt, peak: 0.3, activeHours: 10, everyDays: 1)
        let weekly = Self.occupancySeries(days: 14, dtMinutes: dt, peak: 0.3, activeHours: 10, everyDays: 7)

        let dailyShift = Self.shiftEnd(occupancy: daily, dtMinutes: dt, shiftMax: p.adaptiveShiftMax, tauMinutes: p.tauAdaptiveMinutes)
        let weeklyShift = Self.shiftEnd(occupancy: weekly, dtMinutes: dt, shiftMax: p.adaptiveShiftMax, tauMinutes: p.tauAdaptiveMinutes)

        #expect(dailyShift > weeklyShift) // clustered dosing right-shifts more
        #expect(weeklyShift >= 0)
        #expect(dailyShift <= p.adaptiveShiftMax + 1e-9) // never exceeds the ceiling
    }

    // MARK: - deepGate

    @Test
    func `Deep gate is zero below the escalation threshold and one above the band`() {
        // Escalation factor = dose ÷ heavy ceiling; gate ramps from threshold (2×) to threshold+width (5×).
        #expect(PDModel.deepGate(escalation: 1.0, threshold: 2, width: 3) == 0) // at/below heavy
        #expect(PDModel.deepGate(escalation: 2.0, threshold: 2, width: 3) == 0) // at the edge
        #expect(abs(PDModel.deepGate(escalation: 5.0, threshold: 2, width: 3) - 1) < 1e-9) // past the band
        // Smooth and monotone across the band.
        let mid = PDModel.deepGate(escalation: 3.5, threshold: 2, width: 3)
        #expect(mid > 0 && mid < 1)
        #expect(abs(mid - 0.5) < 1e-9) // smoothstep(0.5) = 0.5
    }

    @Test
    func `Escalation at or below the heavy ceiling keeps the deep gate closed`() {
        #expect(PDModel.deepGate(escalation: 0, threshold: 2, width: 3) == 0) // no reference dose
        #expect(PDModel.deepGate(escalation: 1.5, threshold: 2, width: 3) == 0) // ordinary use
    }

    // MARK: - responseFraction

    @Test
    func `Response fraction is 1 at S=1 and decreases as S grows`() {
        let rested = PDModel.responseFraction(shiftFactor: 1, representativeOccupancy: 0.5)
        #expect(abs(rested - 1) < 1e-12)
        let shifted = PDModel.responseFraction(shiftFactor: 3, representativeOccupancy: 0.5)
        let moreShifted = PDModel.responseFraction(shiftFactor: 6, representativeOccupancy: 0.5)
        #expect(shifted < 1)
        #expect(moreShifted < shifted)
        #expect(moreShifted > 0)
    }

    @Test
    func `At low occupancy the gauge approaches 1/S`() {
        // r = O/(1−O) → 0 as O → 0, so (r+1)/(r+S) → 1/S.
        let frac = PDModel.responseFraction(shiftFactor: 4, representativeOccupancy: 0.001)
        #expect(abs(frac - 0.25) < 0.01)
    }

    @Test
    func `At high occupancy the gauge is buffered (saturation cushions the shift)`() {
        // A near-saturated receptor loses less response to the same shift than a barely-engaged one.
        let lowOcc = PDModel.responseFraction(shiftFactor: 4, representativeOccupancy: 0.05)
        let highOcc = PDModel.responseFraction(shiftFactor: 4, representativeOccupancy: 0.95)
        #expect(highOcc > lowOcc)
    }

    // MARK: - shiftDecayMinutes

    @Test
    func `Decay forecast lands at the target shift when stepped forward`() throws {
        let layers = [(s: 1.2, tau: 14_400.0), (s: 0.3, tau: 720.0)]
        let target = 2.0
        let mins = try #require(PDModel.shiftDecayMinutes(layers: layers, toShift: target))
        let landed = exp(layers.reduce(0) { $0 + $1.s * exp(-mins / $1.tau) })
        #expect(abs(landed - target) < 1e-3)
        #expect(mins > 0)
    }

    @Test
    func `Decay forecast: already-recovered is zero, sub-1 target is unreachable`() {
        // S = exp(0.2) ≈ 1.22 already below target 1.5 → 0.
        #expect(PDModel.shiftDecayMinutes(layers: [(0.2, 1_440)], toShift: 1.5) == 0)
        // Full reset to S < 1 is asymptotic (S → 1 only).
        #expect(PDModel.shiftDecayMinutes(layers: [(1.0, 1_440)], toShift: 0.9) == nil)
    }

    @Test
    func `Decay forecast is monotone: a bigger shift takes longer to relax`() throws {
        let shallow = try #require(PDModel.shiftDecayMinutes(layers: [(0.7, 1_440)], toShift: 1.2))
        let deep = try #require(PDModel.shiftDecayMinutes(layers: [(1.6, 1_440)], toShift: 1.2))
        #expect(deep > shallow)
    }

    // MARK: - combinedOccupancy

    @Test
    func `Combined occupancy is the probabilistic union`() {
        #expect(PDModel.combinedOccupancy([]) == 0)
        #expect(abs(PDModel.combinedOccupancy([0.5]) - 0.5) < 1e-9)
        #expect(abs(PDModel.combinedOccupancy([0.5, 0.5]) - 0.75) < 1e-9)
        #expect(PDModel.combinedOccupancy([1.0, 0.5]) == 1.0)
        #expect(PDModel.combinedOccupancy([2.0]) == 1.0) // over-unity input clamped
    }
}
