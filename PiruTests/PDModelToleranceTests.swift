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
    func `Clustered occupancy builds more shift than spaced; idle relaxes it`() {
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

    // MARK: - smoothstepGate

    @Test
    func `Smoothstep gate is zero below the threshold and one above the band`() {
        // C¹ ramp from threshold to threshold+width; the deep drive is magnitude × chronicity of these.
        #expect(PDModel.smoothstepGate(1.0, threshold: 2, width: 3) == 0) // below
        #expect(PDModel.smoothstepGate(2.0, threshold: 2, width: 3) == 0) // at the edge
        #expect(abs(PDModel.smoothstepGate(5.0, threshold: 2, width: 3) - 1) < 1e-9) // past the band
        // Smooth and monotone across the band.
        let mid = PDModel.smoothstepGate(3.5, threshold: 2, width: 3)
        #expect(mid > 0 && mid < 1)
        #expect(abs(mid - 0.5) < 1e-9) // smoothstep(0.5) = 0.5
    }

    @Test
    func `Magnitude gate soft-on near the heavy ceiling, chronicity gate near the duty knee`() {
        // §2 magnitude knobs: soft-on as escalation approaches 1, ~0 well below, full by ~1.5×.
        #expect(PDModel.smoothstepGate(0, threshold: 0.5, width: 1.0) == 0) // no reference dose
        #expect(PDModel.smoothstepGate(0.3, threshold: 0.5, width: 1.0) == 0) // therapeutic ≪ heavy
        #expect(PDModel.smoothstepGate(1.0, threshold: 0.5, width: 1.0) > 0) // at the heavy ceiling → counts
        #expect(abs(PDModel.smoothstepGate(1.5, threshold: 0.5, width: 1.0) - 1) < 1e-9) // full by ~1.5×
        // §2 chronicity knobs: a once-daily therapeutic duty (~0.15) sits below the knee.
        #expect(PDModel.smoothstepGate(0.15, threshold: 0.25, width: 0.35) == 0)
        #expect(abs(PDModel.smoothstepGate(0.6, threshold: 0.25, width: 0.35) - 1) < 1e-9) // full by ~0.6
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

    @Test
    func `Mechanism-aware cap: an agonist shows residual response uncapped, a releaser shows real tolerance capped`() {
        // §5 regression — the over-read the mechanism-aware cap fixes. A heavy AGONIST (opioid/GABA)
        // user at an elevated usual dose (high occupancy) with a big shift still feels a *residual*
        // ~half — uncapped, the physically exact usual-dose ratio.
        let agonist = PDModel.responseFraction(shiftFactor: 10, representativeOccupancy: 0.9, occupancyCap: nil)
        #expect(agonist > 0.4 && agonist < 0.7) // "roughly half", not "barely anything"

        // Capping the same agonist would pretend its escalated dose is a half-sat dose — throwing away
        // the escalation and OVER-stating tolerance (the bug). Uncapped shows strictly more residual.
        let agonistIfCapped = PDModel.responseFraction(shiftFactor: 10, representativeOccupancy: 0.9, occupancyCap: 0.5)
        #expect(agonist > agonistIfCapped)

        // A RELEASER saturates its transporter at recreational doses (occupancy ≈ 1); without the cap the
        // same shift washes out to "no tolerance". Capped at the ED50, a meaningful shift surfaces.
        let releaser = PDModel.responseFraction(shiftFactor: 10, representativeOccupancy: 0.96, occupancyCap: 0.5)
        #expect(releaser < 0.25) // real tolerance surfaced, not hidden by saturation
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

    // MARK: - competitiveOccupancy (Gaddum)

    @Test
    func `Competitive occupancy is Gaddum summation, exact for a single ligand`() {
        #expect(PDModel.competitiveOccupancy([]) == 0)
        // Single ligand: reduces exactly to its own occupancy (single-substance behaviour unchanged).
        #expect(abs(PDModel.competitiveOccupancy([0.5]) - 0.5) < 1e-9)
        #expect(abs(PDModel.competitiveOccupancy([0.9]) - 0.9) < 1e-9)
        // Two half-sat ligands competing at one site → 2/3, NOT the union's 0.75 (the §4 fix).
        #expect(abs(PDModel.competitiveOccupancy([0.5, 0.5]) - 2.0 / 3.0) < 1e-9)
        // A fully-saturating ligand pins the site at 1 regardless of the others (no divide-by-zero).
        #expect(PDModel.competitiveOccupancy([1.0, 0.5]) == 1.0)
        #expect(PDModel.competitiveOccupancy([2.0]) == 1.0) // over-unity input clamped
    }
}
