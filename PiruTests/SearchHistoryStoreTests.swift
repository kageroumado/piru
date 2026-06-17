import Foundation
import Testing
@testable import Piru

@Suite("SearchHistoryStore")
@MainActor
struct SearchHistoryStoreTests {
    /// Fresh, isolated UserDefaults per test so runs don't contaminate each other
    /// or the user's real App Group.
    private func makeStore() -> (SearchHistoryStore, UserDefaults, String) {
        let suite = "piru.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SearchHistoryStore.forTesting(defaults: defaults), defaults, suite)
    }

    @Test
    func `Starts empty`() {
        let (store, _, _) = makeStore()
        #expect(store.recent.isEmpty)
    }

    @Test
    func `Record inserts most-recent-first and persists`() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record("Caffeine")
        store.record("LSD")

        #expect(store.recent == ["LSD", "Caffeine"])

        // Reload a new store against the same UserDefaults — the data round-trips.
        let reloaded = SearchHistoryStore.forTesting(defaults: defaults)
        #expect(reloaded.recent == ["LSD", "Caffeine"])
    }

    @Test
    func `Re-recording moves the entry to the front, deduping case-insensitively`() {
        let (store, _, _) = makeStore()
        store.record("Caffeine")
        store.record("LSD")
        store.record("caffeine")
        // Deduped case-insensitively (no second Caffeine row), most-recent first,
        // and the latest record's casing wins.
        #expect(store.recent == ["caffeine", "LSD"])
    }

    @Test
    func `Caps at ten, evicting the oldest`() {
        let (store, _, _) = makeStore()
        for i in 1 ... 11 {
            store.record("Substance \(i)")
        }
        #expect(store.recent.count == 10)
        #expect(store.recent.first == "Substance 11")
        #expect(!store.recent.contains("Substance 1"))
    }

    @Test
    func `Blank names are ignored`() {
        let (store, _, _) = makeStore()
        store.record("   ")
        store.record("")
        #expect(store.recent.isEmpty)
    }

    @Test
    func `Clear empties and persists`() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record("Caffeine")
        store.clear()
        #expect(store.recent.isEmpty)

        let reloaded = SearchHistoryStore.forTesting(defaults: defaults)
        #expect(reloaded.recent.isEmpty)
    }
}
