import Foundation
import Observation
import Synchronization
import Testing
@testable import Piru

/// Regression coverage for two App Store / TestFlight crashes triaged from the
/// build-21/22 Xcode Organizer reports:
///
///   1. **Launch crash** — `SubstanceStore.init` used to `fatalError` whenever a
///      database open threw. A corrupt / half-applied OTA substances DB or a
///      bad-WAL user-prefs DB then crashed the app on *every* launch. The init
///      now recovers (quarantine the applied update / recreate the prefs store)
///      instead of trapping.
///   2. **AttributeGraph crash** — the memoization caches are `@ObservationIgnored`
///      so a SwiftUI body that reads a getter no longer writes an observed
///      property mid-`body`. The getters explicitly read `enabledSourceOrder` so
///      a warm read still establishes the observation dependency that drives a
///      re-render on a source-priority change.
@Suite("SubstanceStore launch recovery & observation")
@MainActor
struct SubstanceStoreRecoveryTests {
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("piru-recovery-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bundledDBURL: URL {
        get throws {
            try #require(
                Bundle(for: SubstanceStore.self).url(forResource: "piru-substances", withExtension: "sqlite"),
                "Bundled piru-substances.sqlite missing from the test host bundle",
            )
        }
    }

    // MARK: - #1 Launch recovery

    @Test
    func `A corrupt (non-bundled) substances DB falls back to the bundled copy instead of crashing`() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A non-SQLite file at a path that is neither the bundle nor the OTA
        // applied URL — the init should log, skip quarantine, and reopen the
        // bundled DB rather than `fatalError`.
        let corruptSubstances = tempDir.appendingPathComponent("corrupt-substances.sqlite")
        try Data(repeating: 0xFF, count: 4_096).write(to: corruptSubstances)

        let store = SubstanceStore(
            substancesDBURL: corruptSubstances,
            userPrefsDBURL: tempDir.appendingPathComponent("piru-user-prefs.sqlite"),
            prewarmsAllCache: false,
        )

        // Loaded from the bundled DB: the name index is populated and lookups work.
        #expect(store.count > 0)
        let firstName = try #require(store.allNames.first)
        #expect(store.lookup(firstName) != nil)
    }

    @Test
    func `A corrupt user-prefs DB is recreated and reseeded instead of crashing`() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let corruptPrefs = tempDir.appendingPathComponent("piru-user-prefs.sqlite")
        try Data("this is not a sqlite database".utf8).write(to: corruptPrefs)
        // A leftover sibling WAL must be cleared too, or the recreate reopens onto
        // a stale write-ahead log.
        try Data(repeating: 0x00, count: 128).write(to: URL(fileURLWithPath: corruptPrefs.path + "-wal"))

        let store = try SubstanceStore(
            substancesDBURL: bundledDBURL,
            userPrefsDBURL: corruptPrefs,
            prewarmsAllCache: false,
        )

        // The fresh prefs store was seeded from bundled defaults: there is at
        // least one enabled source, so resolution works.
        #expect(!store.enabledSourceOrder.isEmpty)
        #expect(!store.sourceStates().isEmpty)
    }

    // MARK: - #2 Observation dependency

    @Test
    func `A warm categorySummary() read re-fires observation when source priority changes`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        // Warm the cache (it is @ObservationIgnored — the read of enabledSourceOrder
        // inside the getter is the only thing that should register a dependency).
        _ = store.categorySummary()

        // `onChange` is `@Sendable` (it can run off the mutating thread), so the
        // flag is guarded rather than a bare captured `var`.
        let fired = Mutex(false)
        withObservationTracking {
            _ = store.categorySummary()
        } onChange: {
            fired.withLock { $0 = true }
        }

        let enabledSlug = try #require(store.sourceStates().first(where: { $0.enabled })?.slug)
        store.setSource(enabledSlug, enabled: false)

        #expect(fired.withLock { $0 }, "warm categorySummary() read did not establish an observation dependency on enabledSourceOrder")
    }

    @Test
    func `A warm lookup() (resolveSubstance path) re-fires observation when source priority changes`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }

        let name = try #require(store.allNames.first)
        _ = store.lookup(name) // warm resolvedCache

        let fired = Mutex(false)
        withObservationTracking {
            _ = store.lookup(name)
        } onChange: {
            fired.withLock { $0 = true }
        }

        let enabledSlug = try #require(store.sourceStates().first(where: { $0.enabled })?.slug)
        store.setSource(enabledSlug, enabled: false)

        #expect(fired.withLock { $0 }, "warm lookup() read did not establish an observation dependency on enabledSourceOrder")
    }
}
