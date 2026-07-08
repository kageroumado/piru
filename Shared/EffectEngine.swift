// EffectEngine — Swift port of model-hc.mjs (the mechanistic effect-curve engine).
// PURE, substance-agnostic, Sendable value types. No SwiftData / SwiftUI / Foundation-UI deps.
// Golden-master validated against the JS reference (see validate.swift). Ports 1:1 — variable names
// and equations match model-hc.mjs so the SPEC maps onto both. Foundation only for exp/tanh/log.
import Foundation

// MARK: - Per-substance pharmacology parameters (the curated DATA layer)

/// Multi-receptor antagonist half-occupancy constants (model units ∝ Ki). Currently mirtazapine.
nonisolated struct ReceptorAffinities: Equatable {
    var h1, a2, c2C, c2A: Double?
    init(h1: Double? = nil, a2: Double? = nil, c2C: Double? = nil, c2A: Double? = nil) {
        self.h1 = h1; self.a2 = a2; self.c2C = c2C; self.c2A = c2A
    }
}

/// Pharmacology of one substance. Pure data — no logic. A curated set covers the modeled ~100;
/// uncurated substances resolve to their nearest analogue in the classification layer.
nonisolated struct SubstanceModelParams: Equatable {
    // PK
    var ke: Double // elimination rate (1/h)
    var ka: Double // absorption rate (1/h)
    var refUnit: Double // reference / "common" dose in the substance's native unit
    // transporter release-or-inhibition weights (∝ 1/EC50, DA-normalized)
    var wDAT: Double
    var wNET: Double
    var wSERT: Double
    var deplete: Double // vesicular store-depletion susceptibility
    var releaser: Bool // substrate releaser (true) vs reuptake blocker (false)
    var koff: Double? // DAT dissociation rate; nil → EffectParams.koffFast
    // non-transporter mechanisms (0 / nil ⇒ inert)
    var mu: Double // µ-opioid drive
    var muEff: Double // µ-opioid intrinsic efficacy (partial < 1, full ≈ 1)
    var gaba: Double // benzodiazepine GABA-A drive
    var cae: Double // catecholaminergic-activity-enhancer potency
    var resp: Double // opioid respiratory-depression drive
    var rec: ReceptorAffinities? // multi-receptor antagonist (mirtazapine)

    init(
        ke: Double,
        ka: Double,
        refUnit: Double,
        wDAT: Double = 0,
        wNET: Double = 0,
        wSERT: Double = 0,
        deplete: Double = 0,
        releaser: Bool = false,
        koff: Double? = nil,
        mu: Double = 0,
        muEff: Double = 1,
        gaba: Double = 0,
        cae: Double = 0,
        resp: Double = 0,
        rec: ReceptorAffinities? = nil,
    ) {
        self.ke = ke; self.ka = ka; self.refUnit = refUnit
        self.wDAT = wDAT; self.wNET = wNET; self.wSERT = wSERT
        self.deplete = deplete; self.releaser = releaser; self.koff = koff
        self.mu = mu; self.muEff = muEff; self.gaba = gaba; self.cae = cae
        self.resp = resp; self.rec = rec
    }
}

// MARK: - Engine tuning parameters (DEFAULTS)

/// Global model constants (ports `DEFAULTS`). One shared instance drives every substance.
nonisolated struct EffectParams {
    /// absorption / ROA
    var nAbs = 3.0
    // redose urge + abuse-liability envelope
    var tauUrgeUp = 0.03, tauUrgeDn = 0.7, wEscape = 1.3, wWant = 1.6
    var tauLiabUp = 0.05, tauLiabDn = 6.0, kIncent = 1.5, kRateLiab = 2.5
    // VTA disinhibition
    var kMu = 0.4, kGaba = 0.5, gMu = 2.6, gGaba = 0.6, kFire = 2.2, kBlockSyn = 1.2, kPhDis = 0.8
    var sedOp = 0.9, sedBz = 1.4, anxio = 1.6, opWarm = 1.1
    var phBase = 0.15, phRate = 0.10, phSharp = 2.0, phFlat = 0.18
    var kCae = 0.6, gCae = 1.8, kPhCae = 0.9
    var g2C = 0.5, g2A = 0.25, a2NE = 1.2, sedH1 = 2.4
    // liking loop + KOR
    var gLike = 3.0, kLike = 0.6, tauLkPred = 3.0, kHed = 0.8
    var kDynDA = 0.04, kDynOp = 0.15, dynTh = 3.0, tauDyn = 10.0, kKORda = 0.5, gKOR = 1.4
    var respMax = 3.0, respKd = 0.5
    // DA controller + forcings
    var Emax = 12.0, Kd = 5.0, fScale = 3.0, koffFast = 18.0
    var kappaF = 1.0, tauF = 0.12
    var kappaS = 0.6, tauSbuild = 1.6, tauSrelax = 1.4
    var drainGain = 3.0, Smax = 12.0, synthMax = 1.0, suppr = 1.0, wDep = 0.6
    var depKnee = 2.5
    var wLeth = 0.6
    var kAcc = 0.8, tauAcc = 4.0, accel = 2.0
    var kPi = 2.5, tauMood = 4.0, wAnx = 0.6
    var tauSTrace = 2.0, xiSoft = 0.9
    var kPhRate = 0.3, kPhEff = 5.0, tauPh = 0.25, kPhGate = 0.4
    var tauSertB = 0.5, tauSertR = 1.4
    var kappaSERT = 1.6, lambdaCont = 1.1, kEuCont = 1.0, sigmaSed = 0.7
    var wCortDA = 0.4, drivePeak = 4.0
    var dangerMax = 4.0, cvKd = 1.2, kCV = 0.9, tauCVrec = 6.0
    var tauDrive = 1.1, adaptDrive = 0.75
    var cReward = 1.0, cDrive = 0.6, cCrash = 1.0
    var gR = 1.0, gE = 0.6, gJ = 0.25
    var thetaW = 0.05, thetaC = 0.05
    init() {}
}

// MARK: - Session input

/// One substance-instance in a session: its params, its doses (time h, amount = mg/refUnit), and ROA.
nonisolated struct EffectAgent {
    var params: SubstanceModelParams
    var doses: [(t: Double, amt: Double)]
    var ka: Double? // ROA override (nil → params.ka)
    var kR: Double // ROA redistribution (0 oral, high smoked/IV)
    var nAbs: Double?
    init(
        params: SubstanceModelParams,
        doses: [(t: Double, amt: Double)],
        ka: Double? = nil,
        kR: Double = 0,
        nAbs: Double? = nil,
    ) {
        self.params = params; self.doses = doses; self.ka = ka; self.kR = kR; self.nAbs = nAbs
    }
    /// Convenience: one substance dosed `doseMg` at each time in `at`. Folds `amt = doseMg/refUnit`
    /// (the JS `u`) into each dose, so concentration = Σ (mg/refUnit)·kernel — matching `simulate`.
    init(
        params: SubstanceModelParams,
        doseMg: Double,
        at times: [Double] = [0],
        ka: Double? = nil,
        kR: Double = 0,
        nAbs: Double? = nil,
    ) {
        self.params = params
        self.doses = times.map { (t: $0, amt: doseMg / params.refUnit) }
        self.ka = ka; self.kR = kR; self.nAbs = nAbs
    }
}

// MARK: - Output (struct-of-arrays)

/// The felt-effect timeline. Every array is sampled on `t` (hours). Ports the JS return object.
nonisolated struct EffectTimeline {
    var t: [Double] = []
    var eu: [Double] = [] // Feeling
    var rush: [Double] = [] // deu
    var reward: [Double] = []
    var drive: [Double] = []
    var content: [Double] = [] // warmth
    var danger: [Double] = [] // total harm
    var dangerCV: [Double] = [] // cardiovascular pressor
    var dangerResp: [Double] = [] // opioid respiratory
    var anx: [Double] = []
    var composite: [Double] = []
    var wanting: [Double] = []
    var compul: [Double] = []
    var incent: [Double] = []
    var liking: [Double] = []
    var hedPE: [Double] = []
    var dyn: [Double] = []
    var tonic: [Double] = []
    var phasic: [Double] = []
    var disinhib: [Double] = []
    var htSed: [Double] = []
    var jerk: [Double] = []
    var fda: [Double] = []
    var fne: [Double] = []
    var f5: [Double] = []
    var D: [Double] = []
    var Dne: [Double] = []
    var S5: [Double] = []
    var recH1: [Double] = []
    var rec2C: [Double] = []
    var reca2: [Double] = []
}

// MARK: - The engine

nonisolated enum EffectEngine {
    @inline(__always)
    static func relu(_ x: Double, _ b: Double = 0.10) -> Double {
        x / (1 + exp(-x / b))
    }

    /// Transit-compartment (+ optional 2-compartment redistribution) unit-bolus impulse response,
    /// normalized to peak 1. Ports `absKernel`.
    static func absKernel(
        ka: Double,
        ke: Double,
        nAbs: Int,
        dt: Double,
        n: Int,
        k12: Double = 0,
        k21: Double = 0,
    ) -> [Double] {
        var g = [Double](repeating: 0, count: nAbs); g[0] = 1
        var cc = 0.0, cp = 0.0
        var out = [Double](repeating: 0, count: n + 1)
        for i in 0 ... n {
            out[i] = cc
            let dcc = ka * g[nAbs - 1] - ke * cc - k12 * cc + k21 * cp
            let dcp = k12 * cc - k21 * cp
            var dg = [Double](repeating: 0, count: nAbs)
            dg[0] = -ka * g[0]
            for j in 1 ..< nAbs {
                dg[j] = ka * (g[j - 1] - g[j])
            }
            for j in 0 ..< nAbs {
                g[j] += dg[j] * dt
            }
            cc += dcc * dt; cp += dcp * dt
        }
        let pk = out.max() ?? 1
        return out.map { $0 / (pk == 0 ? 1 : pk) }
    }

    /// Simulate a multi-substance session. Ports `simulateSession`. Substance-agnostic.
    static func simulate(_ P: EffectParams, agents: [EffectAgent], tMax: Double = 12) -> EffectTimeline {
        let dt = 0.5 / 60.0
        let n = Int((tMax / dt).rounded())
        func hill(_ x: Double) -> Double {
            P.Emax * x / (x + P.Kd)
        }
        func invU(_ z: Double) -> Double {
            z * exp(1 - z / P.drivePeak)
        }

        // per-agent PK precompute
        struct Ag { let dg: SubstanceModelParams; let cRaw: [Double]; let koff: Double; let kon: Double; var Odat: Double }
        var A: [Ag] = agents.map { a in
            let dg = a.params
            let ka = a.ka ?? dg.ka
            let nAbs = a.nAbs.map { max(1, Int($0.rounded())) } ?? 3
            let kR = a.kR
            let kern = absKernel(ka: ka, ke: dg.ke, nAbs: nAbs, dt: dt, n: n, k12: kR, k21: kR * 0.22)
            var cRaw = [Double](repeating: 0, count: n + 1)
            let doses = a.doses.isEmpty ? [(t: 0.0, amt: 1.0)] : a.doses
            for d in doses {
                let off = Int((d.t / dt).rounded())
                // A dose can fall before the window (`off < 0` — e.g. its time was
                // edited earlier than the session origin, making `d.t` negative) or
                // after it (`off > n`). Clamp the write span to valid indices so we
                // never subscript out of bounds; the kernel index `i - off` then
                // also stays within `0 ... n`. A pre-window dose still contributes
                // its decayed tail from t = 0; a wholly-after dose contributes none.
                let lo = max(0, off)
                let hi = min(n, off + n)
                guard lo <= hi else { continue }
                for i in lo ... hi {
                    cRaw[i] += d.amt * kern[i - off]
                }
            }
            let koff = dg.koff ?? P.koffFast
            return Ag(dg: dg, cRaw: cRaw, koff: koff, kon: koff / P.Kd, Odat: 0)
        }

        // states
        var Cf = 0.0, Cs = 0.0, Dep = 0.0, Acc = 0.0, mood = 0.0, Cd = 0.0, sTrace = 0.0, Csert = 0.0
        var Apool = 1.0, Ph = 0.0, elevPrev = 0.0, Eru = 0.0, Liab = 0.0, Dyn = 0.0, LkPred = 0.0
        var out = EffectTimeline()
        var rushSrc: [Double] = []

        for i in 0 ... n {
            let tt = Double(i) * dt
            let storeAvail = max(0, 1 - Dep / P.Smax)
            var Ofree = 1.0, Oblock = 0.0
            for a in A {
                Ofree -= a.Odat; if !a.dg.releaser { Oblock += a.Odat }
            }
            if Ofree < 0 { Ofree = 0 }; if Oblock > 1 { Oblock = 1 }
            let effGate = max(0, 1 - Oblock)

            var elevDrug = 0.0, cvRelease = 0.0, sumNET = 0.0, sumSERT = 0.0, sumDAT = 0.0, drain = 0.0, effluxPh = 0.0
            var sumMu = 0.0, sumGaba = 0.0, muEff = 0.0, sumCae = 0.0, OH1 = 0.0, Oa2 = 0.0, O2C = 0.0, O2A = 0.0, sumResp = 0.0
            for k in A.indices {
                let a = A[k]
                let c = a.cRaw[i], xDA = a.dg.wDAT * c
                var od = a.Odat + (a.kon * xDA * Ofree - a.koff * a.Odat) * dt
                if od < 0 { od = 0 }
                A[k].Odat = od
                elevDrug += P.Emax * od * (a.dg.releaser ? storeAvail * effGate : 1)
                cvRelease += a.dg.wNET * c; sumNET += a.dg.wNET * c; sumSERT += a.dg.wSERT * c; sumDAT += a.dg.wDAT * c
                drain += a.dg.deplete * P.drainGain * c * storeAvail * (a.dg.releaser ? effGate : 1)
                effluxPh += (a.dg.releaser ? 1 : 0) * P.kPhEff * c * effGate
                if a.dg.mu != 0 { sumMu += a.dg.mu * c; if a.dg.muEff > muEff { muEff = a.dg.muEff } }
                sumGaba += a.dg.gaba * c
                sumCae += a.dg.cae * c
                sumResp += a.dg.resp * c
                if let r = a.dg.rec {
                    if let v = r.h1 { OH1 += c / (c + v) }
                    if let v = r.a2 { Oa2 += c / (c + v) }
                    if let v = r.c2C { O2C += c / (c + v) }
                    if let v = r.c2A { O2A += c / (c + v) }
                }
            }
            if OH1 > 1 { OH1 = 1 }; if Oa2 > 1 { Oa2 = 1 }; if O2C > 1 { O2C = 1 }; if O2A > 1 { O2A = 1 }

            let Omu = muEff * sumMu / (sumMu + P.kMu)
            let Ogaba = sumGaba / (sumGaba + P.kGaba)
            let Gdis = 1 + P.gMu * Omu + P.gGaba * Ogaba + P.g2C * O2C + P.g2A * O2A
            let Ocae = sumCae / (sumCae + P.kCae), Gcae = 1 + P.gCae * Ocae
            let elevNE = hill(sumNET + P.a2NE * Oa2)
            let s = hill(sumSERT)

            Dyn += (P.kDynDA * relu(elevDrug + P.kFire * (Gdis - 1) - P.dynTh) + P.kDynOp * Omu - Dyn / P.tauDyn) * dt
            let elev = (elevDrug + P.kFire * (Gdis - 1) * storeAvail * (1 + P.kBlockSyn * Oblock)) / (1 + P.kKORda * Dyn)
            let Lk = P.gLike * Omu - P.gKOR * Dyn
            LkPred += (Lk - LkPred) / P.tauLkPred * dt
            let hPE = Lk - LkPred

            Apool = max(0, min(1, Apool + (-P.kCV * cvRelease * Apool + (1 - Apool) / P.tauCVrec) * dt))
            Cf += (P.kappaF * elev - Cf) / P.tauF * dt
            let target = P.kappaS * elev
            Cs += (target - Cs) / (target > Cs ? P.tauSbuild : P.tauSrelax) * dt
            Acc += (P.kAcc * Dep - Acc / P.tauAcc) * dt
            let synthGate = 1 / (1 + P.suppr * elev)
            let synth = (P.synthMax + P.accel * Acc * synthGate) * tanh(Dep / 0.4) * synthGate
            Dep = max(0, Dep + (drain - synth) * dt)
            let prec = elev / (elev + P.kPi)
            mood += (prec - mood) / P.tauMood * dt
            let anxRPE = relu(mood - prec)
            sTrace += (s - sTrace) / P.tauSTrace * dt
            Csert += (s - Csert) / (s > Csert ? P.tauSertB : P.tauSertR) * dt

            let brake = 1 / (1 + P.kappaSERT * s * (1 - O2C))
            let rushV = (elev - Cf) * brake
            Eru += (rushV > Eru ? (rushV - Eru) / P.tauUrgeUp : -Eru / P.tauUrgeDn) * dt
            let rate = (elev - elevPrev) / dt; elevPrev = elev
            Ph += (P.kPhRate * relu(rate) + effluxPh + P.kPhDis * (Gdis - 1) + P.kPhCae * (Gcae - 1) - Ph / P.tauPh) * dt
            let phasicGate = Ph / (Ph + P.kPhGate)
            let rewardPos = relu(elev - Cs) * phasicGate
            let rateSat = relu(rate) / (relu(rate) + P.kRateLiab)
            Liab += (rateSat > Liab ? (rateSat - Liab) / P.tauLiabUp : -Liab / P.tauLiabDn) * dt
            let incentive = Liab * (elev / (elev + P.kIncent)) * brake * max(0, 1 + P.kHed * hPE)
            let overComp = relu(Cs - elev)
            let crashSoft = 1 / (1 + P.xiSoft * sTrace)
            let collapse = Dep * Dep * Dep / (Dep * Dep * Dep + P.depKnee * P.depKnee * P.depKnee)
            let crashMag = P.wDep * (Dep + overComp + P.wAnx * anxRPE) * collapse * crashSoft / (1 + P.anxio * (Ogaba + 0.5 * Omu + O2A))
            let contentV = P.lambdaCont * relu(s - Csert) + P.opWarm * Omu
            let euV = (rewardPos + P.kEuCont * contentV + P.kLike * Lk) - crashMag
            let cortex = elevNE + P.wCortDA * elev
            Cd += (cortex - Cd) / P.tauDrive * dt
            let driveV = invU(relu(cortex - P.adaptDrive * Cd)) - P.sigmaSed * s - P.wLeth * Dep - P.sedOp * Omu - P.sedBz * Ogaba - P.sedH1 * OH1
            let cvEff = cvRelease * Apool
            let dangerCV = P.dangerMax * cvEff / (cvEff + P.cvKd)
            let dangerResp = P.respMax * sumResp / (sumResp + P.respKd)
            let dangerV = dangerCV + dangerResp
            let comp = P.cReward * relu(euV) + P.cDrive * driveV - P.cCrash * relu(-euV)
            let tonicDA = elev
            let phasicDA = Gcae * Gdis * (P.phBase + P.phRate * relu(rate)) * (1 + P.phSharp * Oblock) / (1 + P.phFlat * effluxPh)
            let htSedV = P.sigmaSed * s

            if i % 2 == 0 {
                out.t.append(tt); out.D.append(1 + elev); out.Dne.append(1 + elevNE); out.S5.append(s)
                out.fda.append(1 + P.fScale * sumDAT); out.fne.append(1 + P.fScale * sumNET); out.f5.append(1 + P.fScale * sumSERT)
                out.rush.append(P.gR * rushV); out.reward.append(P.gE * rewardPos); out.eu.append(P.gE * euV)
                out.drive.append(driveV); out.content.append(P.gE * P.kEuCont * contentV); out.danger.append(dangerV); out.anx.append(P.gE * crashMag)
                out.composite.append(comp); out.wanting.append(relu(P.gR * rushV - P.thetaW))
                out.compul.append(P.wWant * incentive + P.wEscape * P.gR * relu(Eru - rushV)); rushSrc.append(P.gR * rushV)
                out.incent.append(P.wWant * incentive)
                out.tonic.append(1 + tonicDA); out.phasic.append(phasicDA); out.htSed.append(P.gE * htSedV); out.disinhib.append(Gdis - 1)
                out.recH1.append(OH1); out.rec2C.append(O2C); out.reca2.append(Oa2)
                out.liking.append(P.gE * P.kLike * Lk); out.hedPE.append(P.gE * P.kLike * hPE); out.dyn.append(Dyn)
                out.dangerCV.append(dangerCV); out.dangerResp.append(dangerResp)
            }
        }
        // jerk = centered derivative of rushSrc
        let N = out.t.count, dh = N > 1 ? out.t[1] - out.t[0] : dt
        out.jerk = (0 ..< N).map { k in
            let km = max(0, k - 1), kp = min(N - 1, k + 1)
            return P.gJ * (rushSrc[kp] - rushSrc[km]) / (Double(kp - km) * dh)
        }
        return out
    }
}
