import Foundation
import SwiftData
import Testing
@testable import Piru

/// The one-time migration that moves custom substances out of the legacy
/// App-Group `UserDefaults` blob (`piru.customSubstances.v1`) and into the
/// SwiftData store. It must copy every entry with full fidelity, verify the rows
/// landed before deleting the blob, dedup against rows already in the store, and
/// be a clean no-op once there's nothing left to migrate.
@Suite("CustomSubstanceMigration")
@MainActor
struct CustomSubstanceMigrationTests {
    /// The legacy blob key — a wire constant, mirrored from `CustomSubstanceStore`.
    private static let legacyKey = "piru.customSubstances.v1"

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "piru.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func seedBlob(_ entries: [CustomSubstanceEntry], into defaults: UserDefaults) throws {
        try defaults.set(JSONEncoder().encode(entries), forKey: Self.legacyKey)
    }

    @Test
    func `Migrates the legacy blob into the store and clears it`() throws {
        let container = try makeContainer()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try seedBlob([
            CustomSubstanceEntry(name: "Foo", category: .stimulant),
            CustomSubstanceEntry(name: "Bar", category: .depressant),
        ], into: defaults)

        let store = CustomSubstanceStore.forTesting(context: container.mainContext, mirrorDefaults: defaults)

        #expect(Set(store.all.map(\.name)) == ["Foo", "Bar"])
        // Verified → the blob is deleted so it never re-runs.
        #expect(defaults.data(forKey: Self.legacyKey) == nil)
        // The rows really are in the store — a fresh context sees them.
        let fresh = CustomSubstanceStore.forTesting(context: ModelContext(container), mirrorDefaults: defaults)
        #expect(fresh.all.count == 2)
    }

    @Test
    func `Migration preserves displayName, doses, and half-life`() throws {
        let container = try makeContainer()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let entry = CustomSubstanceEntry(
            name: "THC",
            displayName: "joint",
            category: .stimulant,
            doses: DoseRange(common: 5 ... 10, heavy: 30),
            halfLifeMinutes: 180,
        )
        try seedBlob([entry], into: defaults)

        let store = CustomSubstanceStore.forTesting(context: container.mainContext, mirrorDefaults: defaults)
        let loaded = try #require(store.all.first)
        #expect(loaded.id == entry.id)
        #expect(loaded.displayName == "joint")
        #expect(loaded.halfLifeMinutes == 180)
        #expect(loaded.doses?.common == 5 ... 10)
        #expect(loaded.doses?.heavy == 30)
    }

    @Test
    func `No blob is a clean no-op`() throws {
        let container = try makeContainer()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CustomSubstanceStore.forTesting(context: container.mainContext, mirrorDefaults: defaults)
        #expect(store.all.isEmpty)
    }

    @Test
    func `Migration dedups against an existing store row by name without clobbering it`() throws {
        let container = try makeContainer()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // A row already in the store (e.g. created post-migration on another device).
        container.mainContext.insert(CustomSubstanceRecord(CustomSubstanceEntry(name: "Caffeine", category: .stimulant)))
        try container.mainContext.save()
        // Same name (different case) in the legacy blob.
        try seedBlob([CustomSubstanceEntry(name: "caffeine", category: .depressant)], into: defaults)

        let store = CustomSubstanceStore.forTesting(context: container.mainContext, mirrorDefaults: defaults)

        #expect(store.all.count == 1) // not duplicated
        #expect(store.all.first?.category == .stimulant) // existing row left untouched
        #expect(defaults.data(forKey: Self.legacyKey) == nil) // legacy name present → verified → cleared
    }

    @Test
    func `An empty blob is cleared without inserting anything`() throws {
        let container = try makeContainer()
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try seedBlob([], into: defaults)

        let store = CustomSubstanceStore.forTesting(context: container.mainContext, mirrorDefaults: defaults)
        #expect(store.all.isEmpty)
        #expect(defaults.data(forKey: Self.legacyKey) == nil)
    }
}
