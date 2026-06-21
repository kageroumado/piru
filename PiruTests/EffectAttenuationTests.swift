import Foundation
import Testing
@testable import Piru

/// Stage 3c — the sign-flipped effect-attenuation readout. Exercises ``EffectAttenuation/analyze``
/// against the real substance data: a reuptake blocker onboard blunts a co-present releaser's
/// transporter-mediated effect (SSRI weakens MDMA), distinct from danger stacking, and — critically —
/// the lethal MAOI + serotonergic edge is *never* mistaken for blunting.
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 3c.)
@Suite("EffectAttenuation")
@MainActor
struct EffectAttenuationTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func dose(_ substance: String, mg: Double = 10, hoursAgo: Double = 0) -> DoseEntry {
        DoseEntry(
            substance: substance, amount: mg, unit: "mg", route: .oral,
            timestamp: now.addingTimeInterval(-hoursAgo * 3_600),
        )
    }

    // MARK: - The evidenced archetype

    @Test
    func `SSRI onboard blunts a co-present MDMA dose`() throws {
        let results = EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100), Self.dose("Fluoxetine", mg: 20, hoursAgo: 6),
        ])
        let result = try #require(results.first)
        #expect(result.attenuated == "MDMA")
        #expect(result.blockers.contains("Fluoxetine"))
        #expect(result.transporter == .sert)
        #expect(result.confidence == .high) // empathogen × antidepressant SERT blocker
        #expect(abs(result.reductionLow - 0.30) < 1e-9)
        #expect(abs(result.reductionHigh - 0.80) < 1e-9)
    }

    @Test
    func `Reduction range renders as a percentage band`() throws {
        let result = try #require(EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100), Self.dose("Sertraline", mg: 50),
        ]).first)
        #expect(result.reductionRangeText == "30\u{2013}80%")
    }

    @Test
    func `An SNRI also blunts MDMA`() throws {
        let result = try #require(EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100), Self.dose("Venlafaxine", mg: 75),
        ]).first)
        #expect(result.attenuated == "MDMA")
        #expect(result.blockers.contains("Venlafaxine"))
    }

    @Test
    func `Multiple blockers fold into one result, de-duplicated`() throws {
        let results = EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100),
            Self.dose("Fluoxetine", mg: 20),
            Self.dose("Sertraline", mg: 50),
        ])
        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.blockers.count == 2)
        #expect(Set(result.blockers) == ["Fluoxetine", "Sertraline"])
    }

    // MARK: - No false positives

    @Test
    func `MDMA alone produces no attenuation`() {
        #expect(EffectAttenuation.analyze(entries: [Self.dose("MDMA", mg: 100)]).isEmpty)
    }

    @Test
    func `An SSRI alone produces no attenuation`() {
        #expect(EffectAttenuation.analyze(entries: [Self.dose("Fluoxetine", mg: 20)]).isEmpty)
    }

    @Test
    func `A non-competing depressant pair produces no attenuation`() {
        // Morphine + diazepam stack on depression, but neither releases nor blocks SERT.
        #expect(EffectAttenuation.analyze(entries: [
            Self.dose("Morphine", mg: 30), Self.dose("Diazepam", mg: 10),
        ]).isEmpty)
    }

    // MARK: - The lethal edge must never read as blunting

    @Test
    func `An MAOI plus MDMA is NOT treated as blunting`() {
        // MAOI + serotonergic is the genuine lethal additive-toxicity edge — it must stay a danger
        // rule and never surface here as a benign "reduced effect".
        #expect(EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100), Self.dose("Phenelzine", mg: 45),
        ]).isEmpty)
        #expect(EffectAttenuation.analyze(entries: [
            Self.dose("MDMA", mg: 100), Self.dose("Tranylcypromine", mg: 20),
        ]).isEmpty)
    }
}
