import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("CustomSubstanceStore")
@MainActor
struct CustomSubstanceStoreTests {
    /// A fresh in-memory container (full schema) and a store bound to its main
    /// context, so runs don't contaminate each other or the user's real store.
    private func makeStore() throws -> (CustomSubstanceStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (CustomSubstanceStore.forTesting(context: container.mainContext), container)
    }

    @Test
    func `Starts empty`() throws {
        let (store, _) = try makeStore()
        #expect(store.all.isEmpty)
    }

    @Test
    func `Add inserts and persists to the store`() throws {
        let (store, container) = try makeStore()

        let entry = CustomSubstanceEntry(
            name: "Test",
            category: .stimulant,
            defaultRoute: .oral,
            unit: "mg",
            notes: "hi",
        )
        store.add(entry)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Test")

        // A fresh store on a new context of the SAME container reads the
        // persisted rows back — the data round-trips through the store, not memory.
        let reloaded = CustomSubstanceStore.forTesting(context: ModelContext(container))
        #expect(reloaded.all.count == 1)
        #expect(reloaded.all.first?.name == "Test")
        #expect(reloaded.all.first?.category == .stimulant)
        #expect(reloaded.all.first?.defaultRoute == .oral)
        #expect(reloaded.all.first?.notes == "hi")
    }

    @Test
    func `Add sorts alphabetically case-insensitively`() throws {
        let (store, _) = try makeStore()
        store.add(CustomSubstanceEntry(name: "zebra"))
        store.add(CustomSubstanceEntry(name: "Apple"))
        store.add(CustomSubstanceEntry(name: "banana"))
        #expect(store.all.map(\.name) == ["Apple", "banana", "zebra"])
    }

    @Test
    func `Update replaces the entry by id and preserves insertion`() throws {
        let (store, _) = try makeStore()
        let entry = CustomSubstanceEntry(name: "Original")
        store.add(entry)

        var edited = entry
        edited.name = "Renamed"
        edited.notes = "updated"
        store.update(edited)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Renamed")
        #expect(store.all.first?.notes == "updated")
        #expect(store.all.first?.id == entry.id)
    }

    @Test
    func `Delete by entry removes the row`() throws {
        let (store, _) = try makeStore()
        let entry = CustomSubstanceEntry(name: "Foo")
        store.add(entry)
        store.add(CustomSubstanceEntry(name: "Bar"))

        store.delete(entry)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Bar")
    }

    @Test
    func `Delete at offsets removes the matching rows`() throws {
        let (store, _) = try makeStore()
        store.add(CustomSubstanceEntry(name: "Alpha"))
        store.add(CustomSubstanceEntry(name: "Beta"))
        store.add(CustomSubstanceEntry(name: "Gamma"))

        store.delete(at: IndexSet([1])) // removes "Beta"

        #expect(store.all.map(\.name) == ["Alpha", "Gamma"])
    }

    @Test
    func `Add replaces an existing same-name custom rather than duplicating`() throws {
        let (store, _) = try makeStore()
        store.add(CustomSubstanceEntry(name: "Foo", category: .stimulant))
        store.add(CustomSubstanceEntry(name: "foo", category: .depressant)) // same name, different case

        #expect(store.all.count == 1)
        #expect(store.all.first?.category == .depressant)
    }

    @Test
    func `contains(name:) is case-insensitive`() throws {
        let (store, _) = try makeStore()
        store.add(CustomSubstanceEntry(name: "Aspirin"))
        #expect(store.contains(name: "aspirin"))
        #expect(store.contains(name: "ASPIRIN"))
        #expect(!store.contains(name: "Tylenol"))
    }

    @Test
    func `asSubstance produces a usable Substance value`() {
        let entry = CustomSubstanceEntry(
            name: "Custom",
            category: .analgesic,
            defaultRoute: .sublingual,
            unit: "µg",
        )
        let substance = entry.asSubstance
        #expect(substance.name == "Custom")
        #expect(substance.category == .analgesic)
        #expect(substance.defaultRoute == .sublingual)
        #expect(substance.unit(for: .sublingual) == "µg")
    }

    @Test
    func `Custom duration round-trips through persistence`() throws {
        let (store, container) = try makeStore()

        let duration = DurationProfile(
            onset: DurationRange(min: 30, max: 60),
            comeup: DurationRange(min: 15, max: 30),
            peak: DurationRange(min: 60, max: 120),
            offset: DurationRange(min: 30, max: 60),
            afterglow: nil,
            total: nil,
        )
        let entry = CustomSubstanceEntry(name: "TestDuration", duration: duration)
        store.add(entry)

        // Force a fresh read from the persisted store rows (the duration is JSON
        // blob in the record — this proves the encode/decode survives a reload).
        let store2 = CustomSubstanceStore.forTesting(context: ModelContext(container))
        let loaded = store2.all.first { $0.name == "TestDuration" }
        #expect(loaded?.duration?.onset?.min == 30)
        #expect(loaded?.duration?.peak?.max == 120)

        // The exported Substance picks up the duration on its route.
        let substance = entry.asSubstance
        #expect(substance.duration(for: substance.defaultRoute)?.peak?.midpoint == 90)
    }

    @Test
    func `Pre-1.3 stored entries (no duration field) decode with duration = nil`() throws {
        // Simulates a v1.2 record persisted before custom durations existed.
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "category": "Other",
            "defaultRoute": "oral",
            "unit": "mg",
            "notes": "",
            "createdAt": 770000000
        }
        """
        let entry = try JSONDecoder().decode(CustomSubstanceEntry.self, from: Data(legacyJSON.utf8))
        #expect(entry.name == "Legacy")
        #expect(entry.duration == nil)
        // And re-encoding then decoding preserves nil.
        let data = try JSONEncoder().encode(entry)
        let roundTripped = try JSONDecoder().decode(CustomSubstanceEntry.self, from: data)
        #expect(roundTripped.duration == nil)
    }
}
