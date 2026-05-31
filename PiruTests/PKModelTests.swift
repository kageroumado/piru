import Foundation
import Testing
@testable import Piru

@Suite("PKModel")
struct PKModelTests {
    // MARK: - ke (elimination rate constant)

    @Test
    func `ke from caffeine half-life (300 min)`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        // ke = ln(2) / 300 ≈ 0.00231
        #expect(abs(ke - log(2) / 300) < 1e-10)
    }

    @Test
    func `ke from zero half-life returns zero`() {
        #expect(PKModel.ke(fromHalfLifeMinutes: 0) == 0)
    }

    @Test
    func `ke from negative half-life returns zero`() {
        #expect(PKModel.ke(fromHalfLifeMinutes: -100) == 0)
    }

    // MARK: - defaultKa

    @Test
    func `Default ka is 4x ke`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        #expect(PKModel.defaultKa(ke: ke) == 4 * ke)
    }

    // MARK: - concentration

    @Test
    func `Concentration at t=0 is zero`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentration(at: 0, ke: ke, ka: ka) == 0)
    }

    @Test
    func `Concentration rises then falls`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let early = PKModel.concentration(at: 30, ke: ke, ka: ka)
        let peak = PKModel.concentration(at: PKModel.tmax(ke: ke, ka: ka), ke: ke, ka: ka)
        let late = PKModel.concentration(at: 1_000, ke: ke, ka: ka)
        #expect(early > 0)
        #expect(peak > early)
        #expect(late < peak)
        #expect(late > 0)
    }

    @Test
    func `Concentration with negative time returns zero`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentration(at: -10, ke: ke, ka: ka) == 0)
    }

    @Test
    func `Concentration with zero ke returns zero`() {
        #expect(PKModel.concentration(at: 60, ke: 0, ka: 0.01) == 0)
    }

    @Test
    func `Concentration with zero ka returns zero`() {
        #expect(PKModel.concentration(at: 60, ke: 0.01, ka: 0) == 0)
    }

    @Test
    func `Concentration handles ka ≈ ke singularity`() {
        let ke = 0.005
        let ka = ke + 1e-12 // Nearly identical
        let c = PKModel.concentration(at: 100, ke: ke, ka: ka)
        #expect(c > 0)
        #expect(c.isFinite)
    }

    @Test
    func `Concentration is always non-negative`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 60)
        let ka = PKModel.defaultKa(ke: ke)
        for t in stride(from: 0.0, through: 5_000, by: 50) {
            #expect(PKModel.concentration(at: t, ke: ke, ka: ka) >= 0)
        }
    }

    // MARK: - tmax (time of peak)

    @Test
    func `Tmax is positive for valid parameters`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t = PKModel.tmax(ke: ke, ka: ka)
        #expect(t > 0)
    }

    @Test
    func `Tmax returns zero when ka <= ke`() {
        #expect(PKModel.tmax(ke: 0.01, ka: 0.005) == 0)
        #expect(PKModel.tmax(ke: 0.01, ka: 0.01) == 0)
    }

    @Test
    func `Tmax returns zero for invalid parameters`() {
        #expect(PKModel.tmax(ke: 0, ka: 0.01) == 0)
        #expect(PKModel.tmax(ke: -1, ka: 0.01) == 0)
        #expect(PKModel.tmax(ke: 0.01, ka: 0) == 0)
    }

    @Test
    func `Faster absorption means earlier peak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let kaFast = 10 * ke
        let kaSlow = 3 * ke
        let tmaxFast = PKModel.tmax(ke: ke, ka: kaFast)
        let tmaxSlow = PKModel.tmax(ke: ke, ka: kaSlow)
        #expect(tmaxFast < tmaxSlow)
    }

    // MARK: - cmax

    @Test
    func `Cmax is the maximum concentration value`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let peak = PKModel.cmax(ke: ke, ka: ka)
        // Check nearby points are lower
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        let before = PKModel.concentration(at: tPeak - 10, ke: ke, ka: ka)
        let after = PKModel.concentration(at: tPeak + 10, ke: ke, ka: ka)
        #expect(peak >= before)
        #expect(peak >= after)
    }

    @Test
    func `Cmax is positive for valid parameters`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.cmax(ke: ke, ka: ka) > 0)
    }

    // MARK: - estimateKa

    @Test
    func `Estimated ka produces tmax close to target`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let targetTmax: Double = 60 // 1 hour to peak
        let ka = PKModel.estimateKa(timeToPeak: targetTmax, ke: ke)
        let actualTmax = PKModel.tmax(ke: ke, ka: ka)
        // Should converge within 1 minute
        #expect(abs(actualTmax - targetTmax) < 1.0)
    }

    @Test
    func `estimateKa falls back with zero timeToPeak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 0, ke: ke)
        #expect(ka == PKModel.defaultKa(ke: ke))
    }

    @Test
    func `estimateKa falls back with negative timeToPeak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: -10, ke: ke)
        #expect(ka == PKModel.defaultKa(ke: ke))
    }

    @Test
    func `estimateKa falls back with zero ke`() {
        let ka = PKModel.estimateKa(timeToPeak: 60, ke: 0)
        #expect(ka == 0)
    }

    @Test
    func `estimateKa always returns ka > ke`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        for ttp in [10.0, 30, 60, 120, 240] {
            let ka = PKModel.estimateKa(timeToPeak: ttp, ke: ke)
            #expect(ka >= ke)
        }
    }

    // MARK: - timeToFraction

    @Test
    func `Time to 3% is after peak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t3pct = PKModel.timeToFraction(0.03, ke: ke, ka: ka)
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        #expect(t3pct > tPeak)
    }

    @Test
    func `Time to 50% is before time to 3%`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t50 = PKModel.timeToFraction(0.5, ke: ke, ka: ka)
        let t3 = PKModel.timeToFraction(0.03, ke: ke, ka: ka)
        #expect(t50 < t3)
    }

    @Test
    func `Concentration at timeToFraction is approximately the target`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let fraction = 0.1
        let t = PKModel.timeToFraction(fraction, ke: ke, ka: ka)
        let peak = PKModel.cmax(ke: ke, ka: ka)
        let actual = PKModel.concentration(at: t, ke: ke, ka: ka)
        // Should be within 1% of target
        #expect(abs(actual - peak * fraction) / (peak * fraction) < 0.01)
    }

    @Test
    func `timeToFraction returns zero for invalid parameters`() {
        #expect(PKModel.timeToFraction(0.5, ke: 0, ka: 0) == 0)
    }

    // MARK: - Real-world substance parameters

    @Test(
        .tags(.pharmacokinetics),
    )
    func `Caffeine PK curve is realistic`() {
        // Caffeine: half-life ~5 hours (300 min), time-to-peak ~45 min oral
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 45, ke: ke)
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        let t5hl = PKModel.timeToFraction(0.03, ke: ke, ka: ka)

        // Peak should be around 45 min
        #expect(abs(tPeak - 45) < 2)
        // Should be mostly eliminated after ~5 half-lives (25 hours = 1500 min)
        #expect(t5hl < 2_000)
        #expect(t5hl > 1_000)
    }
}

extension Tag {
    @Tag static var pharmacokinetics: Self
}
