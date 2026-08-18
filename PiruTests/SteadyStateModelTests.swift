import Foundation
import Testing
@testable import Piru

@Suite("SteadyStateModel")
struct SteadyStateModelTests {
    /// Build a result from a half-life/interval pair the way the view does.
    private func make(halfLifeMinutes: Double, intervalMinutes: Double, dose: Double = 20) -> SteadyStateModel.Result? {
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        let ka = PKModel.defaultKa(ke: ke)
        return SteadyStateModel.compute(
            dose: dose, halfLifeMinutes: halfLifeMinutes, intervalMinutes: intervalMinutes, ke: ke, ka: ka,
        )
    }

    // MARK: - Guards

    @Test
    func `Non-positive inputs return nil`() {
        #expect(make(halfLifeMinutes: 0, intervalMinutes: 1_440) == nil)
        #expect(make(halfLifeMinutes: 1_440, intervalMinutes: 0) == nil)
        #expect(make(halfLifeMinutes: 1_440, intervalMinutes: 1_440, dose: 0) == nil)
    }

    // MARK: - Accumulation ratio

    @Test
    func `Interval equal to half-life doubles the load`() throws {
        // ke·τ = ln2 ⟹ R = 1/(1 − e^(−ln2)) = 1/(1 − 0.5) = 2.
        let r = try #require(make(halfLifeMinutes: 1_440, intervalMinutes: 1_440))
        #expect(abs(r.accumulationRatio - 2) < 1e-6)
    }

    @Test
    func `Dosing far apart barely accumulates`() throws {
        // τ = 10·t½ ⟹ each dose all but gone before the next.
        let r = try #require(make(halfLifeMinutes: 120, intervalMinutes: 1_200))
        #expect(r.accumulationRatio < 1.01)
    }

    @Test
    func `Frequent dosing of a long half-life accumulates a lot`() throws {
        // Fluoxetine-like: t½ 96 h, once daily.
        let r = try #require(make(halfLifeMinutes: 96 * 60, intervalMinutes: 24 * 60))
        #expect(r.accumulationRatio > 5)
    }

    // MARK: - Time to steady state

    @Test
    func `Time to steady state is a multiple of the half-life only`() throws {
        let a = try #require(make(halfLifeMinutes: 600, intervalMinutes: 360))
        let b = try #require(make(halfLifeMinutes: 600, intervalMinutes: 1_440, dose: 500))
        // Independent of interval and dose.
        #expect(abs(a.time95 - b.time95) < 1e-6)
        #expect(abs(a.time95 - 4.3219 * 600) < 1e-2)
        #expect(a.time90 < a.time95 && a.time95 < a.time97)
    }

    // MARK: - Plateau shape

    @Test
    func `Peak exceeds trough and both are positive`() throws {
        let r = try #require(make(halfLifeMinutes: 1_440, intervalMinutes: 720))
        #expect(r.peakAmount > r.troughAmount)
        #expect(r.troughAmount > 0)
        #expect(r.averageAmount > r.troughAmount && r.averageAmount < r.peakAmount)
    }

    @Test
    func `Peak holds at least one fresh dose`() throws {
        // Right after a dose the body carries the trough plus a full new dose,
        // so the steady-state peak is at least one dose.
        let dose = 20.0
        let r = try #require(make(halfLifeMinutes: 1_440, intervalMinutes: 1_440, dose: dose))
        #expect(r.peakAmount >= dose * 0.98)
    }

    @Test
    func `Shorter interval swings less`() throws {
        let wide = try #require(make(halfLifeMinutes: 1_440, intervalMinutes: 1_440))
        let tight = try #require(make(halfLifeMinutes: 1_440, intervalMinutes: 360))
        #expect(tight.fluctuationPercent < wide.fluctuationPercent)
    }

    // MARK: - Curve

    @Test
    func `Curve climbs then plateaus inside the band`() throws {
        let r = try #require(make(halfLifeMinutes: 96 * 60, intervalMinutes: 24 * 60))
        #expect(!r.curve.isEmpty)
        let first = try #require(r.curve.first)
        let last = try #require(r.curve.last)
        // Starts near a single dose, ends up in the plateau range.
        #expect(first.amount < r.troughAmount)
        #expect(last.amount >= r.troughAmount * 0.98)
        #expect(last.amount <= r.peakAmount * 1.02)
    }
}
