import Foundation
import Testing
@testable import Piru

/// The pure off-main body-load sampler behind the Insights "in your body over
/// time" graph. Operates on plain `Sendable` inputs (no SwiftData), so it tests
/// in isolation.
@Suite("BodyLevelsSampler")
struct BodyLevelsSamplerTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// One dose's `(ke, ka)` from a half-life, matching how the plan resolves it.
    private func rateConstants(halfLifeMinutes: Double) -> (ke: Double, ka: Double) {
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLifeMinutes)
        return (ke, PKModel.defaultKa(ke: ke))
    }

    private func dates(from start: Date, count: Int, stepMinutes: Double) -> [Date] {
        (0 ..< count).map { start.addingTimeInterval(Double($0) * stepMinutes * 60) }
    }

    @Test
    func `Body load is zero before the dose lands`() {
        let (ke, ka) = rateConstants(halfLifeMinutes: 180)
        // Dose at index 5; sample the whole span.
        let grid = dates(from: base, count: 20, stepMinutes: 30)
        let dose = BodyLoadDose(seriesIndex: 0, amount: 100, timestamp: grid[5], ke: ke, ka: ka)
        let out = BodyLevelsManager.sample(doses: [dose], dates: grid, seriesCount: 1)
        for i in 0 ..< 5 {
            #expect(out[0][i] == 0)
        }
        #expect(out[0][5] >= 0) // absorption may still be ~0 exactly at t=0
        #expect(out[0][8] > 0) // definitely circulating a bit later
    }

    @Test
    func `Body load decays monotonically well after the peak`() throws {
        let (ke, ka) = rateConstants(halfLifeMinutes: 120)
        let grid = dates(from: base, count: 60, stepMinutes: 15)
        let dose = BodyLoadDose(seriesIndex: 0, amount: 50, timestamp: grid[0], ke: ke, ka: ka)
        let out = BodyLevelsManager.sample(doses: [dose], dates: grid, seriesCount: 1)[0]
        // Peak is early (fast absorption); from a few hours out it only falls.
        let tail = Array(out[16...])
        for i in 1 ..< tail.count {
            #expect(tail[i] <= tail[i - 1] + 1e-9)
        }
        #expect(try #require(tail.last) < tail.first!)
    }

    @Test
    func `Repeated dosing accumulates only for a long half-life`() {
        // Two doses 24 h apart; sample just before the second dose.
        let day: Double = 24 * 60
        let grid = [base, base.addingTimeInterval((day - 1) * 60), base.addingTimeInterval(day * 60)]

        // Short t½ (3 h): fully cleared by 24 h, so the trough before dose 2 ≈ 0.
        let short = rateConstants(halfLifeMinutes: 180)
        let shortDoses = [
            BodyLoadDose(seriesIndex: 0, amount: 10, timestamp: grid[0], ke: short.ke, ka: short.ka),
            BodyLoadDose(seriesIndex: 0, amount: 10, timestamp: grid[2], ke: short.ke, ka: short.ka),
        ]
        let shortTrough = BodyLevelsManager.sample(doses: shortDoses, dates: grid, seriesCount: 1)[0][1]
        #expect(shortTrough < 0.5)

        // Long t½ (48 h): still substantially present at 24 h → visible carryover.
        let long = rateConstants(halfLifeMinutes: 48 * 60)
        let longDoses = [
            BodyLoadDose(seriesIndex: 0, amount: 10, timestamp: grid[0], ke: long.ke, ka: long.ka),
            BodyLoadDose(seriesIndex: 0, amount: 10, timestamp: grid[2], ke: long.ke, ka: long.ka),
        ]
        let longTrough = BodyLevelsManager.sample(doses: longDoses, dates: grid, seriesCount: 1)[0][1]
        #expect(longTrough > shortTrough)
        #expect(longTrough > 5) // more than half of one 10-unit dose still there
    }

    @Test
    func `Distinct series accumulate independently`() {
        let (ke, ka) = rateConstants(halfLifeMinutes: 240)
        let grid = dates(from: base, count: 10, stepMinutes: 60)
        let doses = [
            BodyLoadDose(seriesIndex: 0, amount: 100, timestamp: grid[0], ke: ke, ka: ka),
            BodyLoadDose(seriesIndex: 1, amount: 20, timestamp: grid[0], ke: ke, ka: ka),
        ]
        let out = BodyLevelsManager.sample(doses: doses, dates: grid, seriesCount: 2)
        #expect(out.count == 2)
        // Same kinetics, 5× the dose → series 0 is 5× series 1 at every sample.
        for i in 1 ..< grid.count {
            #expect(abs(out[0][i] - 5 * out[1][i]) < 1e-6)
        }
    }
}
