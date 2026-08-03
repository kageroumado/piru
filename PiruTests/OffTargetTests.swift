import Foundation
import Testing
@testable import Piru

/// The `off_targets` read path. The card itself is thin — the load-bearing logic
/// is the per-target collapse and the concern ordering, and both exist to stop a
/// specific misreading rather than to tidy the list.
@Suite("Off-targets")
@MainActor
struct OffTargetTests {
    @Test
    func `Ketamine's off-targets load, most-consequential first`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let hits = store.offTargets(forSubstanceName: "Ketamine")
        #expect(!hits.isEmpty)
        // The bladder row is the one that matters clinically, so it must lead
        // regardless of where it sits in the table.
        #expect(hits.first?.concern == .high)
        #expect(hits.first?.target.lowercased().contains("bladder") == true)
        // Non-increasing concern down the list.
        for (earlier, later) in zip(hits, hits.dropFirst()) {
            #expect(earlier.concern >= later.concern)
        }
    }

    @Test
    func `Citalopram's two hERG rows collapse to the black-box one`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let hits = store.offTargets(forSubstanceName: "Citalopram")
        let herg = hits.filter { $0.target.lowercased() == "herg" }
        // Two rows ship: an FDA black-box `high` and a mechanistic `moderate`.
        // Printing both invites the reader to average them, which answers "does
        // this prolong my QT?" wrongly.
        #expect(herg.count == 1)
        #expect(herg.first?.concern == .high)
    }

    @Test
    func `A repeated target with equal concern keeps the more potent measurement`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Ketamine carries HCN1 twice, both `moderate`, at 7 µM and 16 µM.
        let hcn1 = store.offTargets(forSubstanceName: "Ketamine")
            .filter { $0.target.lowercased() == "hcn1" }
        #expect(hcn1.count == 1)
        #expect(hcn1.first?.valueNm == 7_000)
    }

    @Test
    func `Low-concern rows survive — 'binds, and it doesn't matter' is the content`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Mephedrone's hERG row exists precisely to say the cardiotoxicity is
        // sympathomimetic rather than channel-mediated.
        let hits = store.offTargets(forSubstanceName: "Mephedrone")
        let herg = try #require(hits.first { $0.target.lowercased() == "herg" })
        #expect(herg.concern == .low)
        #expect(herg.clinicalConsequence?.isEmpty == false)
    }

    @Test
    func `A substance with no off-target rows returns empty rather than failing`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        #expect(store.offTargets(forSubstanceName: "not-a-substance-xyzzy").isEmpty)
    }

    @Test
    func `Concern sorts by clinical weight, not alphabetically`() {
        // `.low` < `.moderate` < `.high` alphabetically reads h < l < m, which
        // would put `high` first by accident and `low` first once a level is
        // renamed. The comparison is explicit for that reason.
        #expect(SubstanceStore.OffTargetConcern.high > .moderate)
        #expect(SubstanceStore.OffTargetConcern.moderate > .low)
    }
}
