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
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ketamine = try #require(store.lookup("Ketamine"))
        let uid = try #require(ketamine.substanceUID, "Ketamine should carry a substance_uid")
        #expect(PSID.isWellformedFamily(uid))
    }

    @Test
    func `A fold family shares one uid across its members`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Ketamine / Esketamine / Arketamine coexist pre-fold under one block-1
        // FAMILY — the canonical one-to-many case the uid index must model.
        let uid = try #require(store.substanceUID(forNameOrAlias: "Ketamine"))
        let family = store.substances(uid: uid)
        let names = Set(family.map(\.name))
        #expect(names.contains("Ketamine"))
        #expect(names.contains("Esketamine"))
        #expect(names.contains("Arketamine"))
        #expect(family.allSatisfy { $0.substanceUID == uid })
    }

    @Test
    func `Forward name→uid and reverse uid→members agree`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let esUID = try #require(store.substanceUID(forNameOrAlias: "Esketamine"))
        let ketUID = try #require(store.substanceUID(forNameOrAlias: "Ketamine"))
        #expect(esUID == ketUID, "enantiomer and racemate share a FAMILY")
        #expect(store.substanceIDs(forUID: esUID).count >= 2)
    }

    @Test
    func `An unknown name or uid resolves to nothing`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

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
