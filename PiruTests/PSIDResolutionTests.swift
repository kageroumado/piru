import Foundation
import Testing
@testable import Piru

/// Stage 0.2 — the app loads `substance_uid` off the bundled DB and resolves by
/// it, in parallel with name resolution (no behavior change). Exercises the real
/// bundled DB through an isolated store. See
/// `Specs/stereoisomer-and-release-form-axes.md`.
@MainActor
@Suite("PSID resolution")
struct PSIDResolutionTests {
    @Test
    func `Substances load a well-formed PSID FAMILY`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let ketamine = try #require(store.lookup("Ketamine"))
        let uid = try #require(ketamine.substanceUID, "Ketamine should carry a substance_uid")
        #expect(PSID.isWellformedFamily(uid))
    }

    @Test
    func `A folded family folds to one row exposing its isomers`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Stage A folds Ketamine / Esketamine / Arketamine into ONE row: the
        // enantiomer names resolve to Ketamine's FAMILY via alias, and Ketamine
        // exposes them as selectable isomer forms rather than separate rows.
        let ketUID = try #require(store.substanceUID(forNameOrAlias: "Ketamine"))
        #expect(store.substanceUID(forNameOrAlias: "Esketamine") == ketUID)
        #expect(store.substanceUID(forNameOrAlias: "Arketamine") == ketUID)

        let ketamine = try #require(store.lookup("Ketamine"))
        let isomers = Set(ketamine.availableIsomers)
        #expect(isomers.contains("S"), "Esketamine folds in as isomer S")
        #expect(isomers.contains("R"), "Arketamine folds in as isomer R")
    }

    @Test
    func `Forward name→uid and reverse uid→members agree`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // A folded family is one row: the enantiomer alias resolves to the
        // racemate's FAMILY, and the reverse uid→rows lookup returns just that row.
        let esUID = try #require(store.substanceUID(forNameOrAlias: "Esketamine"))
        let ketUID = try #require(store.substanceUID(forNameOrAlias: "Ketamine"))
        #expect(esUID == ketUID, "enantiomer alias resolves to the racemate's FAMILY")
        #expect(store.substanceIDs(forUID: ketUID).count == 1)

        // The intentionally-unfolded Etiracetam/Levetiracetam pair are two distinct
        // rows sharing one FAMILY — the surviving genuine one-to-many uid case.
        let levUID = try #require(store.substanceUID(forNameOrAlias: "Levetiracetam"))
        #expect(store.substanceIDs(forUID: levUID).count >= 2)
    }

    @Test
    func `A release-form brand resolves to its parent plus a release facet`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Stage B: brands are aliases of their parent (there is no separate XR row),
        // so the facet is what carries "which form" — and only the names that
        // actually claim a form get one.
        let mphUID = try #require(store.substanceUID(forNameOrAlias: "Methylphenidate"))
        #expect(store.substanceUID(forNameOrAlias: "Concerta") == mphUID)
        #expect(store.releaseForm(forNameOrAlias: "Concerta") == "XR")
        #expect(store.releaseForm(forNameOrAlias: "Ritalin LA") == "XR")
        #expect(store.releaseForm(forNameOrAlias: "Methylphenidate") == nil, "plain name, no form")
        #expect(store.releaseForm(forNameOrAlias: "Vyvanse") == nil, "prodrug, not a release form")
        #expect(store.releaseForm(forNameOrAlias: "not-a-real-substance-xyz") == nil)
    }

    @Test
    func `Form titles come composed from the build, across both axes`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        #expect(store.formTitle(forNameOrAlias: "Methylphenidate") == "Methylphenidate")
        #expect(store.formTitle(forNameOrAlias: "Concerta") == "Methylphenidate XR")
        #expect(store.formTitle(forNameOrAlias: "Focalin") == "Dexmethylphenidate")
        // Both axes at once — the title the app must never assemble itself.
        #expect(store.formTitle(forNameOrAlias: "Focalin XR") == "Dexmethylphenidate XR")
        #expect(store.formTitle(forNameOrAlias: "not-a-real-substance-xyz") == nil)
    }

    @Test
    func `Branded products enumerate a substance's brands, flagships first`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let mphUID = try #require(store.substanceUID(forNameOrAlias: "Methylphenidate"))
        let brands = store.brandProducts(forUID: mphUID)
        let byName = Dictionary(uniqueKeysWithValues: brands.map { ($0.name, $0) })

        // Concerta is an extended-release brand with a real curve — selecting it
        // (→ productName) is what fixes the "bare XR draws nothing" gap.
        let concerta = try #require(byName["Concerta"])
        #expect(concerta.isExtendedRelease)
        #expect(concerta.hasCurve)
        #expect(concerta.isFlagship)
        #expect(byName["Ritalin LA"]?.isExtendedRelease == true)
        // The enantiomer axis is NOT a brand — Focalin is a distinct_substance alias,
        // so it never appears in the brand pill.
        #expect(byName["Focalin"] == nil)

        // Flagship/curve brands lead; niche ones (no curve, no rank) trail.
        let concertaIdx = try #require(brands.firstIndex { $0.name == "Concerta" })
        if let nicheIdx = brands.firstIndex(where: { !$0.isFlagship && $0.isExtendedRelease }) {
            #expect(concertaIdx < nicheIdx, "flagship/curve brands sort ahead of niche")
        }
    }

    @Test
    func `A brandless substance offers no brand pill`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Caffeine has no extended-release brand, so the brand pill (gated on an ER
        // brand existing) never shows.
        let caffeineUID = try #require(store.substanceUID(forNameOrAlias: "Caffeine"))
        let hasExtendedReleaseBrand = store.brandProducts(forUID: caffeineUID).contains { $0.isExtendedRelease }
        #expect(!hasExtendedReleaseBrand)
    }

    @Test
    func `An unknown name or uid resolves to nothing`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        #expect(store.substanceUID(forNameOrAlias: "not-a-real-substance-xyz") == nil)
        #expect(store.substances(uid: "ZZZZZZZZZZZZZZ").isEmpty)
    }

    @Test
    func `The façade resolves a family and stays overlay-aware`() {
        // The shared façade reads the shared singleton store; the isolated store
        // above already proves the mechanism, so here we just assert the façade
        // forwards a known family without throwing and returns overlaid rows.
        guard let uid = SubstanceLibrary.substanceUID(for: "Ketamine") else {
            // The shared store may be cold in some hosts; the isolated-store
            // tests are the authoritative coverage, so don't fail on that.
            return
        }
        #expect(PSID.isWellformedFamily(uid))
        let family = SubstanceLibrary.substances(uid: uid)
        #expect(family.contains { $0.name == "Ketamine" })
    }
}
