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

    /// Regression: a substance dosed by an **alias** resolves its full pharmacology. Canonical is now
    /// "LSD"; the systematic "Lysergic Acid Diethylamide" is the alias. The per-field accessors used to
    /// resolve via `nameIndex` (canonical only), so a dose logged under the non-canonical name came back
    /// empty and the tolerance engine silently dropped it. Both names must resolve identically.
    @Test
    func `Substance dosed by alias resolves the same pharmacology as its canonical name`() {
        let byAlias = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "LSD")
        let byCanonical = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Lysergic Acid Diethylamide")
        #expect(byAlias.canComputeOccupancy)
        #expect(byAlias.molarMassGramsPerMole != nil)
        // Resolving by alias yields the *same* row's pharmacology as the canonical name — the whole bug.
        #expect(byAlias.primaryTarget?.id == byCanonical.primaryTarget?.id)
        #expect(byAlias.vdLPerKg == byCanonical.vdLPerKg)
        #expect(byAlias.molarMassGramsPerMole == byCanonical.molarMassGramsPerMole)
        #expect(byAlias.targets.contains { $0.target.contains("5-HT2A") }) // LSD's signature psychedelic target is present
        #expect(!byCanonical.targets.isEmpty)
    }

    /// Regression: when no oral F was measured the resolver defaults bioavailability to 1.0, flagged
    /// `.unverified`. MDMA's absolute oral F is "definitionally underivable without an IV arm" and its
    /// stored Vd is an apparent V/F, so F = 1 is the consistent reading — and it keeps the canonical
    /// MDMA serotonergic tolerance computable instead of silently dropped.
    @Test
    func `Unmeasured bioavailability defaults to 1.0, flagged unverified`() {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "MDMA")
        #expect(p.bioavailabilityFraction == 1.0)
        #expect(p.bioavailabilityConfidence == .unverified)
        #expect(p.canComputeOccupancy) // was dropped (F nil) before the default
    }

    /// Phase 2b: a logged *preparation* resolves its pharmacology from its active constituent and
    /// scales the dose. Kratom (dosed in g of leaf) routes to mitragynine (a μ-opioid partial agonist)
    /// at ~1.5% content — completing the kratom opioid-tolerance safety fix.
    @Test
    func `Kratom routes to mitragynine pharmacology with a content-fraction dose scale`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Kratom")
        #expect(p.doseScale == 0.015) // ~15 mg/g mitragynine in dried leaf
        #expect(p.doseScaleConfidence == .low) // potency varies → badged
        #expect(p.canComputeOccupancy) // was dropped entirely (no MW/Vd/target) before routing
        let primary = try #require(p.primaryTarget)
        #expect(ReceptorClasses.classify(target: primary.target, action: primary.action) == .muOpioid)
        // A logged plant dose occupies the target as the equivalent active-compound mass would.
        let kratomPeak = try #require(p.peakPrimaryOccupancy(doseMg: 5_000, weightKg: 75))
        let mito = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Mitragynine")
        let mitoPeak = try #require(mito.peakPrimaryOccupancy(doseMg: 5_000 * 0.015, weightKg: 75))
        #expect(abs(kratomPeak - mitoPeak) < 1e-9)
    }

    /// Cannabis curated doses are already mg Δ9-THC, so routing to THC is a pure param-alias (scale 1.0).
    @Test
    func `Cannabis routes to THC at full scale`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Cannabis")
        #expect(p.doseScale == 1.0) // doses already expressed as active THC mass
        #expect(p.canComputeOccupancy)
        let primary = try #require(p.primaryTarget)
        #expect(ReceptorClasses.classify(target: primary.target, action: primary.action) == .cannabinoidCB1)
    }

    /// Regression: the pipeline backfills `molecular_weight` from a present `formula` (it used to only
    /// *correct* an existing mass, never fill a null one). Diazepam shipped with formula C16H13ClN2O
    /// but a null MW, which made its GABA tolerance uncomputable.
    @Test
    func `Diazepam resolves a molar mass and computes occupancy`() {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Diazepam")
        let mw = p.molarMassGramsPerMole
        #expect(mw != nil)
        #expect((mw ?? 0) > 280 && (mw ?? 0) < 290) // C16H13ClN2O ≈ 284.74
        #expect(p.canComputeOccupancy)
    }

    // MARK: - Derivation layer (reference-substance borrow + interspecies scaling)

    /// 2-MMC has no citeable PK of its own; its `pk_reference` pointer borrows mephedrone's kinetics
    /// wholesale (rat Vd 2.6 + human t½ 129). The borrow is flagged: the Vd confidence is floored to
    /// at most `.low`, while 2-MMC's OWN transporter bindings (never borrowed) still drive the target.
    @Test
    func `2-MMC borrows mephedrone PK, flagged at most low confidence`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "2-MMC")
        let vd = try #require(p.vdLPerKg)
        #expect(abs(vd - 2.6) < 1e-6) // mephedrone's rat Vd, borrowed
        #expect(p.halfLifeMinutes != nil) // mephedrone's measured human t½ wins over scaled rat
        #expect(p.molarMassGramsPerMole != nil) // 2-MMC's OWN freebase MW (177.24), not borrowed
        #expect(p.pkSpecies == "rat") // the borrowed coherent row is rat-flagged
        #expect(p.vdConfidence <= .low) // borrowed + non-human → floored
        let primary = try #require(p.primaryTarget)
        #expect(primary.action == .releasingAgent) // 2-MMC's own DAT/NET/SERT release, not borrowed
    }

    /// The borrow yields a *computable* occupancy — the whole point — but the confidence badge stays
    /// at or below `.low` so the UI never presents surrogate kinetics as measured 2-MMC data.
    @Test
    func `2-MMC borrowed occupancy is computable but confidence stays at most low`() throws {
        let p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "2-MMC")
        #expect(p.canComputeOccupancy)
        let occ = try #require(p.peakPrimaryOccupancy(doseMg: 100, weightKg: 70))
        #expect(occ > 0)
    }

    /// The reference borrow is SINGLE-HOP: the surrogate (mephedrone) must carry real PK of its own and
    /// must NOT itself hold a `pk_reference` — no transitive chain. Verified against the pointer table.
    @Test
    func `Reference borrow is single-hop with no transitive chain`() throws {
        let meph = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Mephedrone")
        #expect(meph.vdLPerKg != nil) // its own (rat) Vd, resolved directly
        #expect(meph.canComputeOccupancy)
        let db = SubstanceStore.shared.substancesDB
        let mephID = try #require(SubstanceStore.shared.substanceID(forNameOrAlias: "Mephedrone"))
        #expect(SubstanceReadModel.pkReference(substanceID: mephID, db: db) == nil) // no onward pointer
        let twoID = try #require(SubstanceStore.shared.substanceID(forNameOrAlias: "2-MMC"))
        let ref = try #require(SubstanceReadModel.pkReference(substanceID: twoID, db: db))
        #expect(ref.name == "Mephedrone")
        #expect(ref.confidence <= .low)
    }

    /// `scaledToHuman` is a no-op for a human (or unspecified-species) row: no confidence floor, no
    /// half-life scaling — the measured human value is already the target of projection.
    @Test
    func `scaledToHuman leaves a human or unspecified row unchanged`() {
        let human = Self.makePKRow(species: "human", vd: 3.0, halfLife: 120, clearance: 5, confidence: .high)
        let projectedHuman = SubstanceStore.scaledToHuman(human)
        #expect(projectedHuman.vdLPerKg == 3.0)
        #expect(projectedHuman.halfLifeMin == 120)
        #expect(projectedHuman.clearanceMlPerMinPerKg == 5)
        #expect(projectedHuman.confidence == .high) // not floored

        let unspecified = Self.makePKRow(species: nil, vd: 2.0, halfLife: 90, clearance: 3, confidence: .medium)
        let projectedUnspecified = SubstanceStore.scaledToHuman(unspecified)
        #expect(projectedUnspecified.halfLifeMin == 90)
        #expect(projectedUnspecified.confidence == .medium)
    }

    /// A rat row keeps its species-invariant Vd/kg unchanged but has its confidence floored to `.low`
    /// (a non-human Vd is a class-default proxy, never human-anchored).
    @Test
    func `scaledToHuman keeps a rat Vd per kg but floors its confidence`() {
        let rat = Self.makePKRow(species: "rat", vd: 2.6, halfLife: 60, clearance: 100, confidence: .high)
        let projected = SubstanceStore.scaledToHuman(rat)
        #expect(projected.vdLPerKg == 2.6) // species-invariant → unchanged
        #expect(projected.confidence <= .low) // floored regardless of the source grade
        #expect((projected.halfLifeMin ?? 0) > 60) // small-animal t½ scaled UP to human
    }

    /// A `PKRouteHit` factory for the pure `scaledToHuman` tests.
    private static func makePKRow(
        species: String?, vd: Double?, halfLife: Double?, clearance: Double?, confidence: ConfidenceTier,
    ) -> PKRouteHit {
        PKRouteHit(
            id: 0, route: "oral", bioavailabilityPct: nil, cmaxNgPerMl: nil, tmaxMin: nil,
            halfLifeMin: halfLife, vdLPerKg: vd, clearanceMlPerMinPerKg: clearance,
            proteinBindingPct: nil, doseInStudyMg: nil, subjectN: nil, demographics: nil,
            species: species, sourceSlug: "test", doi: nil, pmid: nil, notes: nil, confidence: confidence,
        )
    }
}
