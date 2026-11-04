import Foundation
import Testing
@testable import Piru

/// Golden-master characterization tests for the mechanistic effect engine.
/// The reference parameters live here (not in the curated DB) so these pin the ENGINE math itself —
/// they must stay in lockstep with the JS reference, which lives in the separate `piru-effect-model`
/// repo: `model-hc.mjs` for the math and `SPEC.md` §7 ("Validated Behaviors") for the numbers.
/// Neither file is in this repo; if the engine drifts from them, these break.
@Suite("EffectEngine golden-master")
struct EffectEngineTests {
    private static let LN2 = log(2.0)

    /// Port of the JS `DRUG` table — the calibrated reference substances.
    private static let drug: [String: SubstanceModelParams] = [
        "amp": .init(ke: LN2 / 10.0, ka: 2.0, refDoseMg: 50, wDAT: 1.0, wNET: 1.8, wSERT: 0.0, deplete: 1.0, releaser: true),
        "mph": .init(ke: LN2 / 3.0, ka: 1.2, refDoseMg: 60, wDAT: 1.0, wNET: 0.9, wSERT: 0.0, deplete: 0.0, releaser: false, koff: 8.0),
        "mmc3": .init(ke: LN2 / 2.0, ka: 5.0, refDoseMg: 80, wDAT: 1.0, wNET: 1.7, wSERT: 0.32, deplete: 0.12, releaser: true),
        "mdma": .init(ke: LN2 / 7.0, ka: 2.0, refDoseMg: 90, wDAT: 0.6, wNET: 1.2, wSERT: 2.8, deplete: 0.10, releaser: true),
        "mdpv": .init(ke: LN2 / 2.0, ka: 2.0, refDoseMg: 15, wDAT: 1.0, wNET: 0.9, wSERT: 0.02, deplete: 0.0, releaser: false, koff: 3.0),
        "bpap": .init(ke: LN2 / 5.0, ka: 1.5, refDoseMg: 1, releaser: false, cae: 1.1),
        "mirtaz": .init(ke: LN2 / 24.0, ka: 1.2, refDoseMg: 30, releaser: false, rec: .init(h1: 0.03, a2: 0.6, c2C: 0.6, c2A: 0.9)),
        "heroin": .init(ke: LN2 / 2.5, ka: 6.0, refDoseMg: 10, releaser: false, mu: 1.0, muEff: 0.97, resp: 1.4),
        // Dosed in grams, like the JS table's `refUnit: 3`.
        "kratom": .init(ke: LN2 / 4.0, ka: 1.5, refDoseMg: 3, wNET: 0.25, wSERT: 0.15, releaser: false, mu: 0.55, muEff: 0.5),
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
        #expect(isClose(peak(o.eu), 0.55))
        #expect(isClose(trough(o.eu), -0.73))
        #expect(isClose(peak(o.dangerCV), 1.71))
        #expect(peak(o.dangerResp) == 0)
        #expect(isClose(peak(o.liking), 0, 0.001)) // stimulant = wanting, not liking
    }

    @Test
    func `Kratom beside amphetamine leaves the comedown in place`() throws {
        let amp = try EffectAgent(params: #require(Self.drug["amp"]), doseMg: 30, at: [0, 3.5])
        let kratom = try EffectAgent(params: #require(Self.drug["kratom"]), doseMg: 3, at: [0, 4])
        let both = EffectEngine.simulate(params, agents: [amp, kratom], tMax: 14)
        #expect(isClose(trough(both.eu), -0.21))
        // Kratom alone has no crash for the divisor to act on.
        let alone = EffectEngine.simulate(params, agents: [kratom], tMax: 14)
        #expect(trough(alone.eu) >= 0)
    }

    @Test
    func `3-MMC (strong serotonergic cathinone) — big euphoria, no crash`() {
        let o = sim("mmc3", 150)
        #expect(isClose(peak(o.eu), 1.90))
        #expect(trough(o.eu) > -0.1) // returns to baseline calmly (Ramaekers)
    }

    @Test
    func `Oral methylphenidate — robotic: drive without euphoria`() {
        #expect(isClose(peak(sim("mph", 60).eu), 0.20))
    }

    @Test
    func `MDMA — moderate euphoria, sedated (5-HT) drive`() {
        let o = sim("mdma", 110)
        #expect(isClose(peak(o.eu), 1.77))
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
        // amt = doseMg/refDoseMg folded into the dose == the explicit-doses form
        let dg = try #require(Self.drug["amp"])
        let a = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doseMg: 50)], tMax: 12)
        let b = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doses: [(t: 0, amt: 50 / dg.refDoseMg)])], tMax: 12)
        #expect(peak(a.eu) == peak(b.eu))
    }

    @Test
    func `Doses outside the window don't crash — before it contributes a tail, after it contributes nothing`() throws {
        // Regression: editing a dose earlier than the session origin makes its
        // time negative, which used to index cRaw[negative] and trap. A dose
        // after tMax must simply contribute nothing.
        let dg = try #require(Self.drug["mdma"])
        // A dose 2h *before* t=0: no crash, and it still leaves a decayed tail in
        // the window (some non-zero euphoria at t=0).
        let before = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doses: [(t: -2, amt: 1)])], tMax: 12)
        #expect(before.eu.count == before.t.count)
        #expect(peak(before.eu) > 0)
        // A dose *after* the window contributes nothing — effectively zero (only
        // ODE-integration floating-point noise remains).
        let after = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doses: [(t: 20, amt: 1)])], tMax: 12)
        #expect(peak(after.eu) < 1e-6)
        // A pre-window dose alongside an in-window one still simulates cleanly.
        let mixed = EffectEngine.simulate(params, agents: [EffectAgent(params: dg, doses: [(t: -1, amt: 1), (t: 2, amt: 1)])], tMax: 12)
        #expect(peak(mixed.eu) > 0)
    }

    @MainActor
    @Test
    func `Oral driving concentration peaks near its Bateman Tmax`() throws {
        let pharmacology = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "3-MMC")
        let dg = try #require(SubstanceModelDatabase.params(name: "3-MMC", pharmacology: pharmacology))
        let dt = 0.5 / 60.0
        let n = Int((12 / dt).rounded())
        let curve = EffectEngine.drivingKernel(params: dg, ka: dg.ka, kR: 0, nAbs: 3, dt: dt, n: n)
        let peakIndex = try #require(curve.indices.max(by: { curve[$0] < curve[$1] }))
        let batemanTmax = log(dg.ka / dg.ke) / (dg.ka - dg.ke)
        #expect(abs(Double(peakIndex) * dt - batemanTmax) <= 5 / 60.0)
    }

    @Test
    func `Route target follows route ka while curated heroin keeps its original kernel`() throws {
        let mmc = try #require(Self.drug["mmc3"])
        let dt = 0.5 / 60.0
        let n = Int((12 / dt).rounded())
        let routeKa = mmc.ka * 3.5
        let route = EffectEngine.drivingKernel(params: mmc, ka: routeKa, kR: 2.5, nAbs: 3, dt: dt, n: n)
        let routePeak = try #require(route.indices.max(by: { route[$0] < route[$1] }))
        let inferredTarget = log(routeKa / mmc.ke) / (routeKa - mmc.ke)
        #expect(abs(Double(routePeak) * dt - inferredTarget) <= 5 / 60.0)

        let heroin = try #require(Self.drug["heroin"])
        let unchanged = EffectEngine.drivingKernel(params: heroin, ka: heroin.ka, kR: 0, nAbs: 3, dt: dt, n: n)
        let original = EffectEngine.absKernel(ka: heroin.ka, ke: heroin.ke, nAbs: 3, dt: dt, n: n)
        #expect(unchanged == original)
    }
}
