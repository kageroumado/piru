import Foundation
import Testing
@testable import Piru

/// Golden-master characterization tests for the mechanistic effect engine.
/// The reference parameters live here (not in the curated DB) so these pin the ENGINE math itself —
/// they must stay in lockstep with the JS reference (`piru-effect-model/model-hc.mjs`) and the numbers
/// in `SPEC.md` §7. If the engine drifts, these break.
@Suite("EffectEngine golden-master")
struct EffectEngineTests {
    private static let LN2 = log(2.0)

    /// Port of the JS `DRUG` table — the calibrated reference substances.
    private static let drug: [String: SubstanceModelParams] = [
        "amp": .init(ke: LN2 / 10.0, ka: 2.0, refUnit: 50, wDAT: 1.0, wNET: 1.8, wSERT: 0.0, deplete: 1.0, releaser: true),
        "mph": .init(ke: LN2 / 3.0, ka: 1.2, refUnit: 60, wDAT: 1.0, wNET: 0.9, wSERT: 0.0, deplete: 0.0, releaser: false, koff: 8.0),
        "mmc3": .init(ke: LN2 / 2.0, ka: 5.0, refUnit: 80, wDAT: 1.0, wNET: 1.7, wSERT: 0.32, deplete: 0.12, releaser: true),
        "mdma": .init(ke: LN2 / 7.0, ka: 2.0, refUnit: 90, wDAT: 0.6, wNET: 1.2, wSERT: 2.8, deplete: 0.10, releaser: true),
        "mdpv": .init(ke: LN2 / 2.0, ka: 2.0, refUnit: 15, wDAT: 1.0, wNET: 0.9, wSERT: 0.02, deplete: 0.0, releaser: false, koff: 3.0),
        "bpap": .init(ke: LN2 / 5.0, ka: 1.5, refUnit: 1, releaser: false, cae: 1.1),
        "mirtaz": .init(ke: LN2 / 24.0, ka: 1.2, refUnit: 30, releaser: false, rec: .init(h1: 0.03, a2: 0.6, c2C: 0.6, c2A: 0.9)),
        "heroin": .init(ke: LN2 / 2.5, ka: 6.0, refUnit: 10, releaser: false, mu: 1.0, muEff: 0.97, resp: 1.4),
    ]
    private static let roa: [String: (Double, Double)] = ["oral": (1, 0), "snort": (3.5, 2.5), "smoke": (10, 6), "rectal": (3, 1.5)]
    private let params = EffectParams()

    private func sim(_ d: String, _ mg: Double, roa: String = "oral", tMax: Double = 12, at times: [Double] = [0]) -> EffectTimeline {
        let dg = Self.drug[d]!
        let (m, kR) = Self.roa[roa]!
        let agent = EffectAgent(params: dg, doseMg: mg, at: times, ka: m > 1 ? dg.ka * m : nil, kR: kR)
        return EffectEngine.simulate(params, agents: [agent], tMax: tMax)
    }
    private func peak(_ a: [Double]) -> Double {
        a.max() ?? 0
    }
    private func trough(_ a: [Double]) -> Double {
        a.min() ?? 0
    }
    private func value(_ o: EffectTimeline, _ k: KeyPath<EffectTimeline, [Double]>, at h: Double) -> Double {
        let arr = o[keyPath: k]
        var best = 0, bestD = Double.greatestFiniteMagnitude
        for (i, tt) in o.t.enumerated() {
            let d = abs(tt - h); if d < bestD { bestD = d; best = i }
        }
        return arr[best]
    }
    private func isClose(_ a: Double, _ b: Double, _ tol: Double = 0.02) -> Bool {
        abs(a - b) <= tol
    }

    @Test
    func `Amphetamine — mild euphoria then a deep crash; cardiovascular danger, no respiratory`() {
        let o = sim("amp", 50)
        #expect(isClose(peak(o.eu), 0.42))
        #expect(isClose(trough(o.eu), -0.73))
        #expect(isClose(peak(o.dangerCV), 1.43))
        #expect(peak(o.dangerResp) == 0)
        #expect(isClose(peak(o.liking), 0, 0.001)) // stimulant = wanting, not liking
    }

    @Test
    func `3-MMC (strong serotonergic cathinone) — big euphoria, no crash`() {
        let o = sim("mmc3", 150)
        #expect(isClose(peak(o.eu), 1.65))
        #expect(trough(o.eu) > -0.1) // returns to baseline calmly (Ramaekers)
    }

    @Test
    func `Oral methylphenidate — robotic: drive without euphoria`() {
        #expect(isClose(peak(sim("mph", 60).eu), 0.09))
    }

    @Test
    func `MDMA — moderate euphoria, sedated (5-HT) drive`() {
        let o = sim("mdma", 110)
        #expect(isClose(peak(o.eu), 1.19))
        #expect(trough(o.drive) < 0) // 5-HT sedation outlasts the catecholamine drive
    }

    @Test
    func `MDPV smoked — a SUSTAINED compulsion plateau (the flakka binge)`() {
        let o = sim("mdpv", 20, roa: "smoke")
        #expect(isClose(value(o, \.compul, at: 1), 0.68))
        #expect(isClose(value(o, \.compul, at: 2), 0.35))
        #expect(isClose(value(o, \.compul, at: 3), 0.26))
        #expect(isClose(value(o, \.compul, at: 6), 0.14))
    }

    @Test
    func `Heroin — µ-opioid liking + respiratory (not cardiovascular) danger`() {
        let o = sim("heroin", 10)
        #expect(isClose(peak(o.liking), 0.71, 0.04))
        #expect(isClose(peak(o.dangerResp), 2.21, 0.05))
        #expect(peak(o.dangerCV) == 0)
    }

    @Test
    func `BPAP (catecholaminergic activity enhancer) — the amphetamine mirror: phasic gain, flat tonic`() {
        let o = sim("bpap", 1)
        #expect(isClose(peak(o.tonic.map { $0 - 1 }), 0, 0.03)) // NO tonic flood
        #expect(isClose(peak(o.phasic), 0.32, 0.05)) // phasic raised
    }

    @Test
    func `Mirtazapine — H1 saturates first at low dose (why 3.75-7.5mg is a sleep aid)`() {
        let low = sim("mirtaz", 3), high = sim("mirtaz", 30)
        #expect(isClose(peak(low.recH1), 0.77, 0.03))
        #expect(isClose(peak(low.rec2C), 0.14, 0.03)) // H1 (0.77) ≫ 5-HT2C (0.14) at 3mg
        #expect(peak(low.recH1) > peak(low.rec2C))
        #expect(isClose(peak(high.rec2C), 0.63, 0.03)) // 5-HT2C recruited at higher dose
    }

    @Test
    func `Single-agent reduces to the same math regardless of construction`() throws {
        // amt = doseMg/refUnit folded into the dose == the explicit-doses form
        let dg = try #require(Self.drug["amp"])
        let a = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doseMg: 50)], tMax: 12)
        let b = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doses: [(t: 0, amt: 50 / dg.refUnit)])], tMax: 12)
        #expect(peak(a.eu) == peak(b.eu))
    }
}
