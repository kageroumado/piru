import Foundation
import Testing
@testable import Piru

/// The 5-HT2B valvulopathy flag, gated end-to-end against the bundled DB.
///
/// This is the one binding-derived claim on the Pharmacology card that is a
/// safety statement rather than a description, so it is worth pinning to real
/// rows: the benzofurans are the substances people actually take that engage it,
/// and the failure modes run both ways — missing 6-APB, or crying wolf on a
/// micromolar row nobody's dose reaches.
@Suite("5-HT2B valvular antitarget")
struct ValvularAntitargetTests {
    private func hit(
        _ target: String, _ action: String,
        kiNm: Double? = nil, ec50Nm: Double? = nil, tier: Int? = nil,
    ) -> BindingHit {
        BindingHit(
            id: 0, substanceName: "x", target: target, action: action,
            kiNm: kiNm, ec50Nm: ec50Nm, ic50Nm: nil, species: nil,
            sourceSlug: "peer-review-primary", doi: nil, pmid: nil, affinityTier: tier,
        )
    }

    @Test
    func `Partial agonism counts and antagonism never does`() {
        // 25B-NBOMe's real row: partialAgonist, Ki 0.5 nM. Pergolide and
        // norfenfluramine are partial agonists too — it is the mechanism.
        #expect(MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "partialAgonist", kiNm: 0.5)]))
        #expect(MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "agonist", ec50Nm: 140)]))
        // Cariprazine, phentermine, viloxazine — all block it.
        #expect(!MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "antagonist", kiNm: 0.5)]))
    }

    @Test
    func `A micromolar row is not an antitarget`() {
        // 4-fluoroamphetamine, EC50 14.4 µM. Flagging this would put a heart-valve
        // warning on every compound ever assayed at the receptor.
        #expect(!MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "partialAgonist", ec50Nm: 14_400)]))
        // A curated row with no measurement speaks through its tier; one with
        // neither says nothing at all.
        #expect(MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "agonist", tier: 3)]))
        #expect(!MonoamineProfile.engagesValvularAntitarget([hit("5-HT2B", "agonist")]))
    }

    @Test
    @MainActor
    func `The benzofurans resolve the flag from the bundled DB`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        for name in ["6-APB", "5-APB", "6-APDB", "5-APDB"] {
            guard let sub = SubstanceStore.shared.lookup(name) else {
                Issue.record("\(name) missing from bundled DB"); continue
            }
            let bindings = SubstanceStore.shared.bindings(forSubstanceName: sub.name)
            #expect(
                MonoamineProfile.engagesValvularAntitarget(bindings),
                "\(name) is a benzofuran 5-HT2B agonist and must carry the valvulopathy flag",
            )
            // …and it must reach the card, which needs transporter data to build at all.
            let profile = MonoamineProfile.from(bindings: bindings, isSoldAsMDMA: false)
            #expect(profile?.engages5HT2B == true, "\(name) should surface the flag on the card")
        }
    }

    @Test
    @MainActor
    func `MDMA does not carry the flag`() async {
        // The comparison the card exists to let a reader make: MDMA is the
        // benzofurans' obvious reference point and does not engage 5-HT2B.
        await SubstanceStore.shared.ensureAllLoaded()
        guard let mdma = SubstanceStore.shared.lookup("MDMA") else {
            Issue.record("MDMA missing from bundled DB"); return
        }
        let bindings = SubstanceStore.shared.bindings(forSubstanceName: mdma.name)
        #expect(!MonoamineProfile.engagesValvularAntitarget(bindings))
    }
}
