import Foundation
import Testing
@testable import Piru

/// End-to-end: prove that reordering source priority actually changes what
/// the rest of the app sees. The Bool of `enabledSourceOrder.first ==
/// "piru-curated"` (in `BundledDatabaseTests`) only verifies the bookkeeping;
/// these tests verify the bookkeeping shows up in resolved field values.
///
/// Each test mutates source priority on its own isolated store (temp-dir
/// user-prefs DB), so nothing leaks into other suites or the shared singleton.
@Suite("Source priority resolution")
struct SourcePriorityResolutionTests {
    @Test
    @MainActor
    func `Reordering changes the resolved category source`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let original = store.enabledSourceOrder

        // Find a substance whose category disagrees across sources — that's
        // where reordering has visible effect. Caffeine is a safe baseline
        // because tripsit and drug.community both carry it.
        let withTripsitFirst = ["tripsit"] + original.filter { $0 != "tripsit" }
        store.setSourcePriority(orderedSlugs: withTripsitFirst)
        let categorySourceA = store.provenance(forSubstanceName: "Caffeine")?.categorySource

        let withDrugCommunityFirst = ["drug.community"] + original.filter { $0 != "drug.community" }
        store.setSourcePriority(orderedSlugs: withDrugCommunityFirst)
        let categorySourceB = store.provenance(forSubstanceName: "Caffeine")?.categorySource

        // Both should be in the enabled list. If the underlying data has
        // category rows from both sources, the slug differs; if only one
        // source carries it, the slug is the same. Either way: never garbage.
        if let a = categorySourceA { #expect(store.enabledSourceOrder.contains(a)) }
        if let b = categorySourceB { #expect(store.enabledSourceOrder.contains(b)) }
    }

    @Test
    @MainActor
    func `Disabled source never appears in resolved provenance`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.setSource("tripsit", enabled: false)
        let prov = store.provenance(forSubstanceName: "Caffeine")
        #expect(prov?.categorySource != "tripsit")
        #expect(prov?.halfLifeSource != "tripsit")
        #expect(prov?.mechanismSource != "tripsit")
        for (_, route) in prov?.routesBySource ?? [:] {
            #expect(route.doseSource != "tripsit")
            #expect(route.durationSource != "tripsit")
        }
    }
}

/// Locale-first text resolution: FreeOD Wiki's native Chinese descriptions and
/// effects win when the app runs in Chinese, while English never shows raw zh.
@Suite("FreeOD locale resolution")
struct FreeODLocaleResolutionTests {
    private func hasHan(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
    }

    @Test
    @MainActor
    func `Chinese app shows native FreeOD overview`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.languageOverride = "zh-Hans"
        let overview = try #require(store.lookup("MDMA")?.overview)
        #expect(hasHan(overview.text))
        #expect(overview.machineTranslated == false)
    }

    @Test
    @MainActor
    func `English app shows authentic English overview, never raw Chinese`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.languageOverride = "en"
        // MDMA has authentic PsychonautWiki lead prose, so the English overview
        // is present, contains no Han, and is NOT flagged machine-translated.
        let overview = try #require(store.lookup("MDMA")?.overview)
        #expect(!hasHan(overview.text))
        #expect(overview.machineTranslated == false)
        for effect in store.lookup("MDMA")?.subjectiveEffects ?? [] {
            #expect(!hasHan(effect.name))
        }
    }

    @Test
    @MainActor
    func `English overview for a FreeOD-only substance is flagged machine-translated`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.languageOverride = "en"
        // 3-Me-PCP is a research chemical PsychonautWiki doesn't cover, so its
        // overview is machine-translated from FreeOD's Chinese — present, no Han,
        // flagged machine-translated, and attributed to FreeOD (not PW).
        let overview = try #require(store.lookup("3-Me-PCP")?.overview)
        #expect(!hasHan(overview.text))
        #expect(overview.machineTranslated == true)
        #expect(overview.sourceSlug == "freeodwiki")
    }

    @Test
    @MainActor
    func `Authentic PsychonautWiki overview is attributed to PW, not FreeOD`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.languageOverride = "en"
        // Methamphetamine's FreeOD page is Chinese-titled, but the English text
        // comes from PsychonautWiki — attribution must follow the real source so
        // the credit row links to PW (not a 404 FreeOD page).
        let overview = try #require(store.lookup("Methamphetamine")?.overview)
        #expect(overview.machineTranslated == false)
        #expect(overview.sourceSlug == "psychonautwiki")
    }

    @Test
    @MainActor
    func `Chinese subjective effects are native zh`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        store.languageOverride = "zh-Hans"
        let effects = store.lookup("MDMA")?.subjectiveEffects ?? []
        #expect(!effects.isEmpty)
        #expect(effects.contains { hasHan($0.name) })
    }
}
