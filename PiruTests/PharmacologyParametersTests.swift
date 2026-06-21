import Foundation
import Testing
@testable import Piru

/// End-to-end tests for the Foundation-A resolver: do the flagship Vd / Kᵢ / EC₅₀ / IC₅₀ seeded into
/// the bundled DB resolve into usable occupancy inputs, and does occupancy come out dose-dependent on
/// *real* data (not just the pure-model gate in `PKModelTests`)?
@Suite("Pharmacology parameters resolver")
@MainActor
struct PharmacologyParametersTests {
    @Test
    func `Unknown substance resolves to empty parameters`() {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "zzzNotARealCompound")
        #expect(p.vdLPerKg == nil)
        #expect(p.targets.isEmpty)
        #expect(!p.canComputeOccupancy)
        #expect(p.occupancyConfidence == .unverified)
    }

    @Test
    func `Amphetamine resolves graded Vd and a releaser primary target`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Amphetamine")
        #expect(p.vdLPerKg != nil)
        #expect(p.vdConfidence == .high) // flagship seed grades the Vd HIGH
        #expect(p.bioavailabilityFraction != nil)
        #expect(p.halfLifeMinutes != nil)
        #expect(p.molarMassGramsPerMole != nil)
        #expect(p.canComputeOccupancy)
        let primary = try #require(p.primaryTarget)
        #expect(primary.action == .releasingAgent) // amphetamine is a releaser, not a blocker
        #expect(primary.kind == .ec50) // functional release EC₅₀, not a binding Kᵢ
    }

    @Test
    func `Methylphenidate resolves as a reuptake inhibitor, not a releaser`() throws {
        // The flagship finding: methylphenidate must NOT be lumped with amphetamine — it is a
        // blocker (transporter inhibition), a distinct mechanism. The half-max may resolve from a
        // transporter Kᵢ or an uptake IC₅₀ (both express inhibition potency for a blocker); what
        // matters is the mechanism and that the primary target is a potent transporter.
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Methylphenidate")
        let primary = try #require(p.primaryTarget)
        #expect(primary.action == .reuptakeInhibitor)
        #expect(primary.action != .releasingAgent)
        #expect(primary.kind == .ki || primary.kind == .ic50)
        #expect(primary.halfMaxNanomolar < 500) // potent DAT/NET inhibition
    }

    @Test
    func `Targets are ordered most-potent first`() {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Amphetamine")
        let halfMaxes = p.targets.map(\.halfMaxNanomolar)
        #expect(halfMaxes == halfMaxes.sorted())
    }

    /// DB-backed dose-dependence gate: real flagship caffeine parameters produce *different*
    /// occupancy at a low vs high dose, with the low dose sitting in the sub-saturation regime. This
    /// proves the normalized-PK flaw is closed end-to-end — through the curated DB, the resolver, the
    /// absolute molar pathway, and the Hill occupancy step — not just in the pure-model unit test.
    @Test
    func `Occupancy is dose-dependent on real flagship caffeine data`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Caffeine")
        let low = try #require(p.peakPrimaryOccupancy(doseMg: 50, weightKg: 70))
        let high = try #require(p.peakPrimaryOccupancy(doseMg: 200, weightKg: 70))
        #expect(low > 0)
        #expect(high > low) // the flaw: a normalized model would make these identical
        #expect(low < 0.45) // a small cup sits below half-saturation
        #expect(high > 0.5) // four cups climbs past it
    }

    @Test
    func `Same dose yields higher occupancy in a lighter person`() throws {
        // Body weight is the denominator turning a dose into an exposure — the keystone input.
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Caffeine")
        let light = try #require(p.peakPrimaryOccupancy(doseMg: 100, weightKg: 50))
        let heavy = try #require(p.peakPrimaryOccupancy(doseMg: 100, weightKg: 100))
        #expect(light > heavy)
    }

    @Test
    func `Occupancy confidence is the weakest link`() {
        // Caffeine: Vd graded HIGH but its adenosine Kᵢ graded MEDIUM → overall MEDIUM.
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Caffeine")
        #expect(p.occupancyConfidence == .medium)
    }
}
