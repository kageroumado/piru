import Foundation
import Testing
@testable import Piru

/// Tests the curated resolver — the "curated (by name or alias), else the classic duration curve"
/// contract. The per-class analogue fallback is intentionally disabled (see `SubstanceModelDatabase`),
/// so an uncurated substance now resolves to `nil` rather than a fabricated class template.
@Suite("SubstanceModelDatabase — curated resolver")
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
    func `An uncurated substance resolves to nil (analogue fallback disabled — no faked curve)`() {
        // Not in the curated table and no analogue fallback → the classic duration timeline.
        #expect(SubstanceModelDatabase.resolve(name: "cocaine", category: .stimulant) == nil)
        #expect(SubstanceModelDatabase.resolve(name: "fentanyl", category: .opioid) == nil)
    }

    @Test
    func `An unmodelable class returns nil → the classic duration curve (honest, not faked)`() {
        #expect(SubstanceModelDatabase.resolve(name: "LSD", category: .psychedelic) == nil)
        #expect(SubstanceModelDatabase.resolve(name: "ketamine", category: .dissociative) == nil)
        #expect(SubstanceModelDatabase.resolve(name: "vitamin d", category: .supplement) == nil)
    }

    @Test
    func `Mechanistic lenses surface only for sessions with a curated stimulant or opioid`() {
        #expect(SubstanceModelDatabase.supportsMechanisticView([("amphetamine", .stimulant)]))
        #expect(SubstanceModelDatabase.supportsMechanisticView([("kratom", .opioid)])) // opioid µ → yes
        #expect(SubstanceModelDatabase.supportsMechanisticView([("2-MMC", .stimulant), ("vitamin c", .supplement)])) // curated stimulant → yes
        #expect(!SubstanceModelDatabase.supportsMechanisticView([("cocaine", .stimulant)])) // uncurated → no faked curve → Tier 0
        #expect(!SubstanceModelDatabase.supportsMechanisticView([("bromazepam", .benzodiazepine)])) // sedative alone → Tier 0
        #expect(!SubstanceModelDatabase.supportsMechanisticView([("LSD", .psychedelic), ("magnesium", .supplement)]))
    }
}
