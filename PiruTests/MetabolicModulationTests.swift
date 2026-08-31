import Foundation
import Testing
@testable import Piru

/// Stage 4c — the metabolic-modulation readout. Exercises ``MetabolicModulation``: the
/// `enzyme_modulators` rules (grapefruit/smoking/co-active drugs/MDMA self-edge) joined against the
/// bundled DB's metabolism table on the substrate side, surfacing direction + qualitative strength
/// (never a fabricated fold-change). (`Specs/pharmacology-axis-meta-plan.md`, Stage 4c.)
///
/// The catalog is a database table, so these gate the rows rather than restating their values: that
/// every rule decodes, that every rule carries display text, that a rule's enzyme is one the metabolism
/// table actually names, and that origin decides which surface a rule reaches.
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

    @Test
    func `A clause the cell calls minor contributes no enzyme`() {
        // Every string here is a real `metabolism.enzyme` cell. The qualifier
        // scopes over its own clause, not the whole cell — the first case would
        // otherwise lose the two enzymes it explicitly calls major.
        #expect(
            MetabolicModulation.Enzyme.major(inDBString: "CYP3A4, CYP1A2 (major); CYP2D6 (minor)")
                == [.cyp3a4, .cyp1a2],
        )
        #expect(
            MetabolicModulation.Enzyme.major(
                inDBString: "CYP2D6 (dominant; CYP2C8/CYP2E1/CYP2A6 minor — CYP1A2 contribution is negligible)",
            ) == [.cyp2d6],
        )
        // The whole cell is one minor pathway, so nothing in it is major.
        #expect(
            MetabolicModulation.Enzyme.major(inDBString: "CYP2B6 / CYP1A2 / CYP3A4 (minor N-demethylation)")
                .isEmpty,
        )
        // An unqualified cell is unchanged by the split.
        #expect(MetabolicModulation.Enzyme.major(inDBString: "CYP2C19, CYP3A4") == [.cyp2c19, .cyp3a4])
        #expect(MetabolicModulation.Enzyme.major(inDBString: "CYP2D6 (major)") == [.cyp2d6])
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

    @Test
    func `An unquantified pathway the cell calls minor is not promoted`() {
        // The generous unquantified default exists because most cells carry no
        // fraction; it must not override the cell saying so in words.
        let enzymes = MetabolicModulation.majorEnzymes(metabolism: [
            Self.metab("CYP2D6", nil),
            Self.metab("CYP2B6 / CYP1A2 / CYP3A4 (minor N-demethylation)", nil),
        ])
        #expect(enzymes == [.cyp2d6])
    }

    // MARK: - The curated table itself

    @Test
    func `Every curated rule decodes and carries display text`() {
        let modulators = store.enzymeModulators()
        #expect(!modulators.isEmpty)
        for m in modulators {
            #expect(!m.displayName.isEmpty, "\(m.id) has no display name")
            #expect(!m.userNote.isEmpty, "\(m.id) has no user note")
        }
    }

    @Test
    func `Origin decides whether a rule carries matchers`() {
        // A context flag is never logged as a dose, so it must not be identifiable
        // by name; a drug rule is useless without names to recognize it by.
        for modulator in store.enzymeModulators() {
            switch modulator.origin {
            case .context:
                #expect(modulator.matchers.isEmpty, "\(modulator.id) is a context flag with matchers")
            case .substance, .selfEdge:
                #expect(!modulator.matchers.isEmpty, "\(modulator.id) has no matchers to recognize it by")
            }
        }
    }

    @Test
    func `Matchers are stored lowercased so name folding can hit them`() {
        // `PharmacologyNameKey.canonical` lowercases before comparing, so an
        // upper-case matcher row would be permanently unreachable.
        for modulator in store.enzymeModulators() {
            for matcher in modulator.matchers {
                #expect(matcher == matcher.lowercased(), "\(modulator.id): \(matcher)")
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
        let grapefruit = try #require(store.enzymeModulators().first { $0.id == "grapefruit" })
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
        #expect(armodafinil?.id == "armodafinil")
    }

    @Test
    func `The contraceptive caution generalizes to every 3A4 inducer, weak ones included`() {
        // It is a class property of being a 3A4 inducer, not a modafinil special case,
        // so it must hold for every rule in the table that qualifies — and strength is
        // deliberately not part of qualifying. A `>= .moderate` filter here silently
        // dropped modafinil and armodafinil the moment their labels re-graded them
        // weak; see the prohibition on `contraceptiveEfficacyCaution`.
        let catalog = store.enzymeModulators()
        let inducers = catalog.filter {
            $0.origin == .substance && $0.enzyme == .cyp3a4 && $0.direction == .induces
        }
        #expect(!inducers.isEmpty)
        #expect(
            inducers.contains { $0.strength == .weak },
            "the weak-inducer case this gate exists to keep is gone; the test no longer proves anything",
        )
        for inducer in inducers {
            let reachable = inducer.matchers.contains {
                MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: $0, in: catalog) != nil
            }
            #expect(reachable, "\(inducer.id) qualifies but no matcher reaches it")
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
        let mod = try #require(effects.first { $0.modulatorID == "modafinil" })
        #expect(mod.substrate == "Midazolam")
        #expect(!mod.raisesLevels) // induction → lower levels
    }

    // MARK: - Tag-derived enzyme interactions

    @Test
    func `Tag-derived interactions populate the materialized table`() {
        let interactions = store.tagEnzymeInteractions()
        #expect(!interactions.isEmpty, "tag_enzyme_interactions table is empty — pipeline materialization failed")
    }

    @Test
    func `Bupropion plus tramadol surfaces via tag-derived engine`() {
        let effects = MetabolicModulation.checkerEffects(among: ["Bupropion", "Tramadol"])
        #expect(!effects.isEmpty, "expected bupropion→tramadol enzyme interaction")
        let tramadolEffect = effects.first { $0.substrate == "Tramadol" }
        #expect(tramadolEffect != nil, "expected an effect on tramadol as substrate")
    }
}
