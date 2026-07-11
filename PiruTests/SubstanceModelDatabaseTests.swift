import Foundation
import Testing
@testable import Piru

/// The mechanistic engine's per-substance params are built from the bundled pharmacology DB (PK +
/// transporter binding) plus a slim curated PD-override layer: `ke` from the measured half-life, `ka`
/// from Tmax, the DAT/NET/SERT weights from the measured functional EC₅₀/Kᵢ, `releaser` from whether a
/// transporter is engaged by release. These tests exercise that builder against real resolved
/// pharmacology and pin the resulting phenomenology (which the engine's golden tests then keep stable).
@MainActor
@Suite("SubstanceModelDatabase — data-driven params")
struct SubstanceModelDatabaseTests {
    private func params(_ name: String) -> SubstanceModelParams? {
        SubstanceModelDatabase.params(name: name, pharmacology: SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name))
    }

    private func sim(_ p: SubstanceModelParams, _ mg: Double) -> EffectTimeline {
        EffectEngine.simulate(EffectParams(), agents: [EffectAgent(params: p, doseMg: mg)], tMax: 12)
    }

    @Test
    func `A releaser stimulant is data-driven and keeps its curated crash`() throws {
        let amp = try #require(params("amphetamine"))
        #expect(amp.releaser) // DAT release EC₅₀ ⇒ releaser
        #expect(amp.ke > 0 && amp.ka > 0) // from measured half-life / Tmax
        #expect(amp.wDAT == 1) // DA-normalized
        #expect(amp.deplete == 1.0) // curated store-depletion scalar
        let o = sim(amp, 50)
        #expect((o.eu.min() ?? 0) < -0.3) // the signature deep crash survives
    }

    @Test
    func `A reuptake blocker is non-releaser with drive but little euphoria (rate hypothesis)`() throws {
        let mph = try #require(params("methylphenidate"))
        #expect(!mph.releaser)
        #expect(mph.deplete == 0)
        #expect(mph.koff == 8.0) // curated DAT dissociation
        let o = sim(mph, 60)
        #expect((o.eu.max() ?? 1) < 0.2) // occupies DAT without a "high"
        #expect((o.drive.max() ?? 0) > 1) // …but drives
    }

    /// Cross-lab EC₅₀ coherence: methylphenidate's DAT:NET mix is taken from ONE high-confidence assay
    /// (uptake IC₅₀ DAT 80 / NET 100 nM → wNET ≈ 0.8, a balanced DA/NE blocker), not by taking `.min()`
    /// per transporter across labs — which would straddle the DAT IC₅₀ and a rat NET Kᵢ (38 nM) and read
    /// as a runaway noradrenergic drug (wNET → the 4.0 cap). The coherent triple is the pharmacology.
    @Test
    func `The DAT:NET mix comes from one coherent assay, not a cross-lab minimum`() throws {
        let mph = try #require(params("methylphenidate"))
        #expect(mph.wDAT == 1) // DA-normalized
        #expect(mph.wNET > 0.5 && mph.wNET < 1.2) // the HIGH-confidence IC₅₀ ratio, not the capped cross-lab value
    }

    @Test
    func `A serotonergic releaser reads warmth-led with a sedation tail`() throws {
        let mdma = try #require(params("MDMA"))
        #expect(mdma.releaser)
        #expect(mdma.wSERT > mdma.wDAT) // 5-HT-dominant mix from the data
        let o = sim(mdma, 110)
        #expect((o.content.max() ?? 0) > 0.3) // warmth
        #expect((o.drive.min() ?? 0) < 0) // 5-HT sedation outlasts the catecholamine drive
    }

    @Test
    func `A strong cathinone is euphoric without a crash`() throws {
        let mmc = try #require(params("3-MMC"))
        #expect(mmc.releaser)
        let o = sim(mmc, 150)
        #expect((o.eu.max() ?? 0) > 0.7) // big euphoria
        #expect((o.eu.min() ?? 0) > -0.1) // returns to baseline calmly
    }

    @Test
    func `2-MMC borrows mephedrone PK via the reference pointer and stays modelable`() throws {
        let m = try #require(params("2-MMC"))
        #expect(m.releaser)
        #expect(m.ke > 0) // half-life borrowed from mephedrone (2-MMC has no PK of its own)
    }

    /// The mechanistic acid test: 2-MMC and mephedrone share the *same* borrowed PK, so they differ
    /// only in their measured transporter EC₅₀ triples. Mephedrone is the more potent serotonin releaser
    /// (SERT EC₅₀ 118 vs 2-MMC's 490 nM), and the model must turn that data difference into more felt
    /// warmth — i.e. the profile follows the pharmacology, not a hand-authored curve.
    @Test
    func `The isomer with tighter SERT reads warmer, from the data alone`() throws {
        let twoMMC = try #require(params("2-MMC"))
        let meph = try #require(params("mephedrone"))
        #expect(twoMMC.ke == meph.ke && twoMMC.ka == meph.ka) // identical borrowed PK
        #expect(meph.wSERT > twoMMC.wSERT) // mephedrone's tighter SERT EC₅₀ ⇒ higher weight
        // Compare at each one's own reference dose (amt ≈ 1) so magnitude is matched and only the mix differs.
        #expect((sim(meph, meph.refUnit).content.max() ?? 0) > (sim(twoMMC, twoMMC.refUnit).content.max() ?? 0))
    }

    @Test
    func `An opioid resolves via its curated µ drive — liking, no cardiovascular danger`() throws {
        let heroin = try #require(params("heroin"))
        #expect(heroin.mu > 0)
        let o = sim(heroin, 10)
        #expect((o.liking.max() ?? 0) > 0.3)
        #expect((o.dangerCV.max() ?? 1) == 0)
    }

    @Test
    func `Aliases resolve to the same canonical params`() throws {
        let a = try #require(params("Adderall"))
        let b = try #require(params("amphetamine"))
        #expect(a.deplete == b.deplete && a.releaser == b.releaser && a.refUnit == b.refUnit)
    }

    @Test
    func `An unmodelable substance resolves to nil (no faked curve)`() {
        #expect(params("LSD") == nil)
        #expect(params("vitamin d") == nil)
    }

    @Test
    func `Mechanistic lenses surface only for a stimulant or opioid`() {
        func triggers(_ name: String) -> Bool {
            guard let p = params(name) else { return false }
            return SubstanceModelDatabase.triggersMechanisticView(p)
        }
        #expect(triggers("amphetamine"))
        #expect(triggers("kratom")) // opioid µ
        #expect(!triggers("bromazepam")) // sedative adjunct alone ⇒ Tier 0
        #expect(!triggers("LSD"))
    }

    @Test
    func `Only the calibrated substances trigger Effect Estimates; simulate-only ones don't`() {
        // Calibrated set (aliases resolve to canonical).
        #expect(SubstanceModelDatabase.isCalibratedTrigger("amphetamine"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("Adderall"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("methylphenidate"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("Ritalin"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("3-MMC"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("2-MMC"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("mephedrone"))
        #expect(SubstanceModelDatabase.isCalibratedTrigger("4-MMC")) // ≡ mephedrone

        // Modelable but *not* calibrated — read as interacting agents, never a solo trigger.
        #expect(!SubstanceModelDatabase.isCalibratedTrigger("methamphetamine"))
        #expect(!SubstanceModelDatabase.isCalibratedTrigger("kratom"))
        #expect(!SubstanceModelDatabase.isCalibratedTrigger("MDMA"))
        #expect(!SubstanceModelDatabase.isCalibratedTrigger("heroin"))
    }

    @Test
    func `The view gates on a calibrated substance, not any modelable stimulant`() {
        func supports(_ names: [String]) -> Bool {
            let doses = names.map { MechanisticSessionModel.DoseInput(name: $0, amount: 50, route: .oral, hours: 0) }
            var pharm: [String: PharmacologyParameters] = [:]
            for name in names {
                pharm[SubstanceModelDatabase.normalize(name)] = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
            }
            return MechanisticSessionModel.supportsMechanisticView(doses, pharmacology: pharm)
        }
        // Methamphetamine / kratom alone: modelable, but not calibrated ⇒ no card (the reported bug).
        #expect(!supports(["methamphetamine"]))
        #expect(!supports(["kratom"]))
        // A calibrated substance anywhere in the session flips it on; the rest shape the curves.
        #expect(supports(["amphetamine"]))
        #expect(supports(["methamphetamine", "3-MMC"]))
    }
}
