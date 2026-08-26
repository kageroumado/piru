import Foundation
import Testing
@testable import Piru

/// Stage 4c — the metabolic-modulation readout. Exercises ``MetabolicModulation``: the
/// `enzyme_modulators` rules (grapefruit/smoking/co-active drugs/MDMA self-edge) joined against the
/// bundled DB's metabolism table on the substrate side, surfacing direction + qualitative strength
/// (never a fabricated fold-change). (`Specs/pharmacology-axis-meta-plan.md`, Stage 4c.)
///
/// The catalog is a database table, so these gate the rows rather than restating their values: that
/// every rule decodes, that every rule has copy and every copy has a rule, that a rule's enzyme is one
/// the metabolism table actually names, and that origin decides which surface a rule reaches.
@Suite("MetabolicModulation")
@MainActor
struct MetabolicModulationTests {
    let store: SubstanceStore

    init() {
        store = SubstanceStore.shared
    }

    static func metab(_ enzyme: String, _ pct: Double? = nil) -> SubstanceStore.MetabolismHit {
        SubstanceStore.MetabolismHit(
            id: 0, enzyme: enzyme, fractionOfClearancePct: pct,
            metaboliteName: nil, metaboliteSubstanceName: nil,
            metaboliteActive: nil, metabolitePotencyVsParentPct: nil,
            metabolitePotencyBasis: nil, metabolitePotencyTarget: nil,
            metaboliteMechanismVsParent: .unknown,
            metaboliteHalfLifeMinutes: nil, formationFractionPct: nil,
            route: nil, conditionalCombinationID: nil,
            sourceSlug: "test", doi: nil, pmid: nil,
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

    // MARK: - The curated table itself

    @Test
    func `Every curated rule decodes and every rule has copy`() {
        // Both directions: a row the app has no sentence for is dropped at load and
        // would vanish silently, and a `ModulatorID` case with no row is copy for a
        // rule that no longer ships. Either drift breaks this.
        let loaded = Set(store.enzymeModulators().map(\.id))
        #expect(loaded == Set(MetabolicModulation.ModulatorID.allCases))
    }

    @Test
    func `Origin decides whether a rule carries matchers`() {
        // A context flag is never logged as a dose, so it must not be identifiable
        // by name; a drug rule is useless without names to recognize it by.
        for modulator in store.enzymeModulators() {
            switch modulator.origin {
            case .context:
                #expect(modulator.matchers.isEmpty, "\(modulator.id.rawValue) is a context flag with matchers")
            case .substance, .selfEdge:
                #expect(!modulator.matchers.isEmpty, "\(modulator.id.rawValue) has no matchers to recognize it by")
            }
        }
    }

    @Test
    func `Matchers are stored lowercased so name folding can hit them`() {
        // `PharmacologyNameKey.canonical` lowercases before comparing, so an
        // upper-case matcher row would be permanently unreachable.
        for modulator in store.enzymeModulators() {
            for matcher in modulator.matchers {
                #expect(matcher == matcher.lowercased(), "\(modulator.id.rawValue): \(matcher)")
            }
        }
    }

    @Test
    func `Every rule names an enzyme some substance is actually cleared by`() {
        // The substrate side is derived, not curated — a rule pointing at an enzyme
        // no metabolism row names can never fire and would be invisible dead data.
        let named = Set(
            ["MDMA", "Midazolam", "Caffeine", "Codeine", "Diazepam", "Bupropion", "Ibuprofen"]
                .flatMap { MetabolicModulation.majorEnzymes(metabolism: store.metabolism(forSubstanceName: $0)) },
        )
        for modulator in store.enzymeModulators() {
            #expect(named.contains(modulator.enzyme), "no sampled substrate is cleared by \(modulator.enzyme.rawValue)")
        }
    }

    // MARK: - Pure match

    @Test
    func `effects matches catalog modulators to substrate enzymes`() throws {
        let grapefruit = try #require(store.enzymeModulators().first { $0.id == .grapefruit })
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
        let metabolism = store.metabolism(forSubstanceName: "MDMA")
        let effects = MetabolicModulation.educationalEffects(
            forSubstance: "MDMA", metabolism: metabolism, catalog: store.enzymeModulators(),
        )
        // MDMA is a CYP1A2 substrate → smoking education; and carries its own 2D6 self-edge.
        #expect(effects.contains { $0.modulatorID == .smoking })
        #expect(effects.contains { $0.origin == .selfEdge })
        // No logged-drug (substance-origin) modulator should appear in the static card.
        #expect(!effects.contains { $0.origin == .substance })
    }

    @Test
    func `Checker pairs a selected modulator with a selected substrate`() throws {
        let effects = MetabolicModulation.checkerEffects(among: ["Ritonavir", "Midazolam"])
        let effect = try #require(effects.first)
        #expect(effect.substrate == "Midazolam")
        #expect(effect.modulatorID == .ritonavir)
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
        // Armodafinil is an *alias row* on Modafinil in the substances table, so this
        // also gates that the two stay separate rules: keyed on a substance they
        // would collapse into one, and whichever lost would show the other's name.
        for name in ["Modafinil", "modafinil", "Provigil", "Armodafinil", "Nuvigil"] {
            let caution = try #require(
                MetabolicModulation.contraceptiveEfficacyCaution(
                    forSubstance: name, in: store.enzymeModulators(),
                ),
                "expected a caution for \(name)",
            )
            #expect(caution.enzyme == .cyp3a4)
            #expect(caution.direction == .induces)
        }
        let armodafinil = MetabolicModulation.contraceptiveEfficacyCaution(
            forSubstance: "Nuvigil", in: store.enzymeModulators(),
        )
        #expect(armodafinil?.id == .armodafinil)
    }

    @Test
    func `The contraceptive caution generalizes to every moderate-or-stronger 3A4 inducer`() {
        // It is a class property of being a 3A4 inducer, not a modafinil special case,
        // so it must hold for every rule in the table that qualifies.
        let catalog = store.enzymeModulators()
        let inducers = catalog.filter {
            $0.origin == .substance && $0.enzyme == .cyp3a4 && $0.direction == .induces && $0.strength >= .moderate
        }
        #expect(!inducers.isEmpty)
        for inducer in inducers {
            let reachable = inducer.matchers.contains {
                MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: $0, in: catalog) != nil
            }
            #expect(reachable, "\(inducer.id.rawValue) qualifies but no matcher reaches it")
        }
    }

    @Test
    func `Non-inducers (inhibitors, unrelated drugs) get no contraceptive caution`() {
        let catalog = store.enzymeModulators()
        // A 3A4 *inhibitor* raises levels — it must not fire the induction caution.
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Ritonavir", in: catalog) == nil)
        // A 1A2 inducer is not a 3A4 inducer.
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Caffeine", in: catalog) == nil)
        #expect(MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: "Midazolam", in: catalog) == nil)
    }

    @Test
    func `A co-present modafinil lowers a CYP3A4 substrate's levels in the checker`() throws {
        let effects = MetabolicModulation.checkerEffects(among: ["Modafinil", "Midazolam"])
        let mod = try #require(effects.first { $0.modulatorID == .modafinil })
        #expect(mod.substrate == "Midazolam")
        #expect(!mod.raisesLevels) // induction → lower levels
    }
}
