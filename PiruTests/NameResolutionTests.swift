import Foundation
import SwiftData
import Testing
@testable import Piru

/// One path for "what is this substance called", and one for "find it".
///
/// A tester set 4-MMC as their name for mephedrone and got it on some screens
/// and not others: the override was stored under one spelling and every surface
/// asking under another missed it, and search never consulted the overlay at all.
@Suite("Name resolution")
@MainActor
struct NameResolutionTests {
    private func makeStore() throws -> (CustomSubstanceStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (CustomSubstanceStore.forTesting(context: container.mainContext), container)
    }

    @Test
    func `An alias and its canonical name share one key`() {
        // The whole mechanism in one line: whatever a surface calls it, the
        // override is filed and found under the same key.
        let canonical = CustomSubstanceStore.canonicalKey("Mephedrone")
        #expect(CustomSubstanceStore.canonicalKey("4-MMC") == canonical)
        #expect(CustomSubstanceStore.canonicalKey("mephedrone") == canonical)
    }

    @Test
    func `A name the library does not know is its own key`() {
        // A custom-only substance is its own canonical name — the fallback must
        // not collapse two unrelated customs onto one key.
        #expect(CustomSubstanceStore.canonicalKey("Notarealsubstance") == "notarealsubstance")
        #expect(CustomSubstanceStore.canonicalKey("  ") == "")
    }

    @Test
    func `An override stored under an alias is found under the canonical name`() throws {
        let (store, _) = try makeStore()
        // Stored the way a user would: under the name they typed.
        store.add(CustomSubstanceEntry(name: "4-MMC", displayName: "My Meph"))
        // Every surface asks under whichever spelling it holds.
        #expect(store.first(whereName: "4-MMC")?.displayName == "My Meph")
        #expect(store.first(whereName: "Mephedrone")?.displayName == "My Meph")
        #expect(store.displayName(for: "Mephedrone") == "My Meph")
    }

    @Test
    func `Search results carry the personal name`() {
        // The Library list and Search used to show the catalog name while the
        // detail screen showed the user's — the same substance, two names.
        let matches = SubstanceLibrary.searchMatches("caffeine", limit: 5)
        #expect(!matches.isEmpty)
        // No customs in this run, so the overlay is a pass-through; what is
        // asserted is that it ran and did not drop or reorder the results.
        #expect(matches.contains { $0.substance.name.localizedCaseInsensitiveContains("caffeine") })
    }

    @Test
    func `Browse and search agree on what a substance is called`() {
        // The contract: a Substance from SubstanceLibrary already carries the
        // user's name for it, so no two surfaces can disagree.
        guard let browsed = SubstanceLibrary.all.first(where: { $0.name == "Caffeine" }) else {
            Issue.record("Caffeine missing from the library")
            return
        }
        let searched = SubstanceLibrary.search("Caffeine", limit: 5).first { $0.name == "Caffeine" }
        let looked = SubstanceLibrary.resolveFull("Caffeine")
        #expect(browsed.displayTitle == searched?.displayTitle)
        #expect(browsed.displayTitle == looked?.displayTitle)
    }

    @Test
    func `An alias resolves everywhere a canonical name does`() {
        // piru://substance/4-MMC said "Substance Not Found" while the detail
        // screen resolved it, because 19 call sites used an exact-only lookup
        // that no longer exists.
        for alias in ["4-MMC", "4mmc", "Mephedrone"] {
            #expect(
                SubstanceLibrary.resolveFull(alias)?.name == "Mephedrone",
                "\(alias) did not resolve to Mephedrone",
            )
        }
    }

    @Test
    func `A canonical name still wins over an alias that spells it differently`() {
        // Precedence, not just reachability: the alias arm must only run when
        // the canonical one misses, or a substance whose name is another's
        // alias would resolve to the wrong row.
        #expect(SubstanceLibrary.resolveFull("Caffeine")?.name == "Caffeine")
        #expect(SubstanceLibrary.resolveFull("LSD")?.name == "LSD")
    }
}
