import Foundation
import Testing
@testable import Piru

@Suite("MonoamineProfile")
struct MonoamineProfileTests {
    private func bind(
        _ target: String,
        _ action: String,
        ec50: Double? = nil,
        ic50: Double? = nil,
    ) -> BindingHit {
        BindingHit(
            id: 0,
            substanceName: "x",
            target: target,
            action: action,
            kiNm: nil,
            ec50Nm: ec50,
            ic50Nm: ic50,
            species: "rat",
            sourceSlug: "peer-review-primary",
            doi: nil,
            pmid: nil,
        )
    }

    @Test
    func `mephedrone-like release triple reads as a balanced empathogenic releaser`() throws {
        let rows = [
            bind("DAT", "releasingAgent", ec50: 49.1),
            bind("NET", "releasingAgent", ec50: 62.7),
            bind("SERT", "releasingAgent", ec50: 118.3),
        ]
        let p = try #require(MonoamineProfile.from(bindings: rows, substanceName: "Mephedrone"))
        #expect(p.mechanism == .releaser)
        #expect(p.basis == .release)
        // DAT:SERT = 118.3 / 49.1 ≈ 2.41 → balanced/empathogen band.
        let ratio = try #require(p.datSertRatio)
        #expect(abs(ratio - 2.41) < 0.05)
        // Mid spectrum, not at an extreme.
        let pos = try #require(p.leanPosition)
        #expect(pos > 0.25 && pos < 0.6)
        #expect(!p.engages5HT2B)
        #expect(!p.misSoldAsMDMA)
    }

    @Test
    func `MDPV-like uptake triple reads as a strongly dopaminergic SERT-sparing blocker`() throws {
        let rows = [
            bind("DAT", "reuptakeInhibitor", ic50: 4.1),
            bind("NET", "reuptakeInhibitor", ic50: 26),
            bind("SERT", "reuptakeInhibitor", ic50: 3_349),
        ]
        let p = try #require(MonoamineProfile.from(bindings: rows, substanceName: "MDPV"))
        #expect(p.mechanism == .blocker)
        #expect(p.basis == .uptake)
        // DAT:SERT ≈ 817 → far dopaminergic end.
        let pos = try #require(p.leanPosition)
        #expect(pos > 0.9)
    }

    @Test
    func `a serotonin-leaning benzofuran with a 5-HT2B agonist row sits left and flags valvulopathy`() throws {
        let rows = [
            bind("DAT", "releasingAgent", ec50: 31),
            bind("NET", "releasingAgent", ec50: 21),
            bind("SERT", "releasingAgent", ec50: 19),
            bind("5-HT2B", "agonist", ec50: 280),
        ]
        let p = try #require(MonoamineProfile.from(bindings: rows, substanceName: "5-APB"))
        // DAT:SERT = 19/31 ≈ 0.61 < 0.8 → serotonin-leaning, left of center.
        let pos = try #require(p.leanPosition)
        #expect(pos < 0.25)
        #expect(p.engages5HT2B)
    }

    @Test
    func `eutylone is flagged mis-sold-as-MDMA, a releaser cathinone is not`() throws {
        let blocker = [bind("DAT", "reuptakeInhibitor", ic50: 120), bind("SERT", "reuptakeInhibitor", ic50: 1_100)]
        let eutylone = try #require(MonoamineProfile.from(bindings: blocker, substanceName: "Eutylone"))
        #expect(eutylone.misSoldAsMDMA)

        let releaserRows = [bind("DAT", "releasingAgent", ec50: 49), bind("SERT", "releasingAgent", ec50: 118)]
        let mephedrone = try #require(MonoamineProfile.from(bindings: releaserRows, substanceName: "Mephedrone"))
        #expect(!mephedrone.misSoldAsMDMA)
    }

    @Test
    func `a releaser that also shows uptake inhibition is still a releaser, not a hybrid`() throws {
        // 6-APB: Brandt release triple AND Rickli uptake IC50s — a substrate releaser competes as an
        // uptake inhibitor too, so the uptake rows must not demote it to "hybrid".
        let rows = [
            bind("DAT", "releasingAgent", ec50: 10),
            bind("NET", "releasingAgent", ec50: 14),
            bind("SERT", "releasingAgent", ec50: 36),
            bind("NET", "reuptakeInhibitor", ic50: 190),
            bind("DAT", "reuptakeInhibitor", ic50: 3_300),
            bind("SERT", "reuptakeInhibitor", ic50: 930),
        ]
        let p = try #require(MonoamineProfile.from(bindings: rows, substanceName: "6-APB"))
        #expect(p.mechanism == .releaser)
        #expect(p.basis == .release)
        // Release-basis DAT:SERT = 36/10 = 3.6 → dopamine-leaning.
        let ratio = try #require(p.datSertRatio)
        #expect(abs(ratio - 3.6) < 0.1)
    }

    @Test
    func `a hybrid (DAT blocker + SERT releaser) reads as mixed`() throws {
        let rows = [
            bind("DAT", "reuptakeInhibitor", ic50: 400),
            bind("SERT", "releasingAgent", ec50: 330),
        ]
        let p = try #require(MonoamineProfile.from(bindings: rows, substanceName: "Butylone"))
        #expect(p.mechanism == .hybrid)
    }

    @Test
    func `no DAT/NET/SERT rows → no profile (non-monoamine substances get no card)`() {
        let rows = [bind("MOR", "agonist", ec50: 3.4), bind("5-HT2A", "agonist", ec50: 74)]
        #expect(MonoamineProfile.from(bindings: rows, substanceName: "Morphine") == nil)
    }
}
