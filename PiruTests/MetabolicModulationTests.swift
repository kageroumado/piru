import Foundation
import Testing
@testable import Piru

/// Stage 4c — the metabolic-modulation readout. Exercises ``MetabolicModulation``: the curated
/// modulator catalog (grapefruit/smoking/co-active drugs/MDMA self-edge) joined against the bundled
/// DB's metabolism table on the substrate side, surfacing direction + qualitative strength (never a
/// fabricated fold-change). (`Specs/pharmacology-axis-meta-plan.md`, Stage 4c.)
@Suite("MetabolicModulation")
@MainActor
struct MetabolicModulationTests {
    static func metab(_ enzyme: String, _ pct: Double? = nil) -> SubstanceStore.MetabolismHit {
        SubstanceStore.MetabolismHit(
            id: 0, enzyme: enzyme, fractionOfClearancePct: pct,
            metaboliteName: nil, metaboliteActive: nil, metabolitePotencyVsParentPct: nil,
            sourceSlug: "test", doi: nil, pmid: nil, notes: nil,
        )
    }

    // MARK: - Enzyme parsing (pure)

    @Test
    func `Multi-enzyme cells parse to every named enzyme`() {
        #expect(MetabolicModulation.Enzyme.all(inDBString: "CYP2C19, CYP3A4") == [.cyp2c19, .cyp3a4])
        #expect(MetabolicModulation.Enzyme.all(inDBString: "CYP2D6 (major)") == [.cyp2d6])
    }

    @Test
    func `Similar enzyme tokens do not cross-match`() {
        // "CYP2C19" must not be read as CYP2C9.
        #expect(MetabolicModulation.Enzyme.all(inDBString: "CYP2C19") == [.cyp2c19])
        // Generic / non-curated rows yield nothing.
        #expect(MetabolicModulation.Enzyme.all(inDBString: "UGT2B7").isEmpty)
    }

    // MARK: - Major-enzyme detection (pure)

    @Test
    func `Unquantified pathways count as major; minor quantified ones do not`() {
        let enzymes = MetabolicModulation.majorEnzymes(metabolism: [
            Self.metab("CYP3A4", 70), // major
            Self.metab("CYP2D6", nil), // unquantified → major
            Self.metab("CYP1A2", 10), // minor → dropped
            Self.metab("UGT2B7", 90), // not curated → ignored
        ])
        #expect(enzymes == [.cyp3a4, .cyp2d6])
    }

    // MARK: - Pure match

    @Test
    func `effects matches catalog modulators to substrate enzymes`() throws {
        let grapefruit = try #require(MetabolicModulation.catalog.first { $0.id == "grapefruit" })
        let effects = MetabolicModulation.effects(
            substrateName: "Demo", substrateEnzymes: [.cyp3a4], modulators: [grapefruit],
        )
        let effect = try #require(effects.first)
        #expect(effect.substrate == "Demo")
        #expect(effect.enzyme == .cyp3a4)
        #expect(effect.direction == .inhibits)
        #expect(effect.raisesLevels)
    }

    // MARK: - Educational + checker surfaces

    @Test
    func `Educational effects exclude co-active drugs but keep context + self-edge`() {
        let metabolism = SubstanceStore.shared.metabolism(forSubstanceName: "MDMA")
        let effects = MetabolicModulation.educationalEffects(forSubstance: "MDMA", metabolism: metabolism)
        // MDMA is a CYP1A2 substrate → smoking education; and carries its own 2D6 self-edge.
        #expect(effects.contains { $0.modulatorID == "smoking" })
        #expect(effects.contains { $0.origin == .selfEdge })
        // No logged-drug (substance-origin) modulator should appear in the static card.
        #expect(!effects.contains { $0.origin == .substance })
    }

    @Test
    func `Checker pairs a selected modulator with a selected substrate`() throws {
        let effects = MetabolicModulation.checkerEffects(among: ["Ritonavir", "Midazolam"])
        let effect = try #require(effects.first)
        #expect(effect.substrate == "Midazolam")
        #expect(effect.modulatorID == "ritonavir")
        // Self-edges and context flags are not part of a combination check.
        #expect(!effects.contains { $0.origin != .substance })
    }

    @Test
    func `Checker is silent for two unrelated substrates`() {
        // Two CYP3A4 substrates that neither inhibit nor induce → no modulation between them.
        let effects = MetabolicModulation.checkerEffects(among: ["Midazolam", "Triazolam"])
        #expect(effects.isEmpty)
    }

    // MARK: - Contraceptive-efficacy caution

    @Test
    func `Modafinil and armodafinil are CYP3A4 inducers and flag a contraceptive caution`() throws {
        for name in ["Modafinil", "modafinil", "Provigil", "Armodafinil", "Nuvigil"] {
            let caution = try #require(
                MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: name),
                "expected a caution for \(name)",
            )
            #expect(caution.enzyme == .cyp3a4)
            #expect(caution.direction == .induces)
        }
    }

    @Test
    func `The contraceptive caution generalizes to every moderate-or-stronger 3A4 inducer`() {
        // It is a class property of being a 3A4 inducer, not a modafinil special case.
        for name in ["Rifampicin", "Carbamazepine", "St John's Wort"] {
            #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: name) != nil, "\(name)")
        }
    }

    @Test
    func `Non-inducers (inhibitors, unrelated drugs) get no contraceptive caution`() {
        // A 3A4 *inhibitor* raises levels — it must not fire the induction caution.
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Ritonavir") == nil)
        // A 1A2 inducer is not a 3A4 inducer.
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Caffeine") == nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Midazolam") == nil)
    }

    @Test
    func `A co-present modafinil lowers a CYP3A4 substrate's levels in the checker`() throws {
        // The new catalog entry also enriches the interaction checker, not just the detail caution.
        let effects = MetabolicModulation.checkerEffects(among: ["Modafinil", "Midazolam"])
        let mod = try #require(effects.first { $0.modulatorID == "modafinil" })
        #expect(mod.substrate == "Midazolam")
        #expect(!mod.raisesLevels) // induction → lower levels
    }
}
