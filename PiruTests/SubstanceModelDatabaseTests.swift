import Foundation
import Testing
@testable import Piru

/// Tests the curated table + the analogue-fallback resolver — the "works for any substance, else its
/// closest analogue, else Tier 0" contract.
@Suite("SubstanceModelDatabase — resolver + analogue fallback")
struct SubstanceModelDatabaseTests {
    @Test
    func `A curated substance resolves as .curated with its real params`() {
        let r = SubstanceModelDatabase.resolve(name: "Amphetamine", category: .stimulant)
        #expect(r?.source == .curated)
        #expect(r?.params.releaser == true)
        #expect(r?.params.wSERT == 0.0)
    }

    @Test
    func `An alias resolves to the canonical curated params`() {
        #expect(SubstanceModelDatabase.resolve(name: "Adderall", category: .stimulant)?.source == .curated)
        #expect(SubstanceModelDatabase.resolve(name: "molly", category: .empathogen)?.source == .curated)
    }

    @Test
    func `An uncurated substance falls back to its class analogue`() {
        // cocaine isn't curated yet → the generic stimulant template, flagged as an estimate
        let r = SubstanceModelDatabase.resolve(name: "cocaine", category: .stimulant)
        #expect(r?.source == .analogue(.stimulant))
        #expect(r?.params.wDAT == SubstanceModelDatabase.resolve(name: "amphetamine", category: .stimulant)?.params.wDAT)
        // an uncurated opioid → the morphine template
        #expect(SubstanceModelDatabase.resolve(name: "fentanyl", category: .opioid)?.source == .analogue(.opioid))
    }

    @Test
    func `An unmodelable class returns nil → the classic duration curve (honest, not faked)`() {
        #expect(SubstanceModelDatabase.resolve(name: "LSD", category: .psychedelic) == nil)
        #expect(SubstanceModelDatabase.resolve(name: "ketamine", category: .dissociative) == nil)
        #expect(SubstanceModelDatabase.resolve(name: "vitamin d", category: .supplement) == nil)
    }

    @Test
    func `Mechanistic lenses surface only for sessions with a stimulant or opioid`() {
        #expect(SubstanceModelDatabase.supportsMechanisticView([("amphetamine", .stimulant)]))
        #expect(SubstanceModelDatabase.supportsMechanisticView([("kratom", .opioid)])) // opioid µ → yes
        #expect(SubstanceModelDatabase.supportsMechanisticView([("cocaine", .stimulant), ("vitamin c", .supplement)])) // analogue stimulant → yes
        #expect(!SubstanceModelDatabase.supportsMechanisticView([("bromazepam", .benzodiazepine)])) // sedative alone → Tier 0
        #expect(!SubstanceModelDatabase.supportsMechanisticView([("LSD", .psychedelic), ("magnesium", .supplement)]))
    }
}
