import Foundation
import Testing
@testable import Piru

@Suite("CustomSubstanceStore")
@MainActor
struct CustomSubstanceStoreTests {
    /// Fresh, isolated UserDefaults per test so runs don't contaminate each other
    /// or the user's real App Group.
    private func makeStore() -> (CustomSubstanceStore, UserDefaults, String) {
        let suite = "piru.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CustomSubstanceStore.forTesting(defaults: defaults), defaults, suite)
    }

    @Test
    func `Starts empty`() {
        let (store, _, _) = makeStore()
        #expect(store.all.isEmpty)
    }

    @Test
    func `Add inserts and persists to defaults`() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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

        // Reload a new store against the same UserDefaults — the data round-trips.
        let reloaded = CustomSubstanceStore.forTesting(defaults: defaults)
        #expect(reloaded.all.count == 1)
        #expect(reloaded.all.first?.name == "Test")
        #expect(reloaded.all.first?.category == .stimulant)
        #expect(reloaded.all.first?.defaultRoute == .oral)
        #expect(reloaded.all.first?.notes == "hi")
    }

    @Test
    func `Add sorts alphabetically case-insensitively`() {
        let (store, _, _) = makeStore()
        store.add(CustomSubstanceEntry(name: "zebra"))
        store.add(CustomSubstanceEntry(name: "Apple"))
        store.add(CustomSubstanceEntry(name: "banana"))
        #expect(store.all.map(\.name) == ["Apple", "banana", "zebra"])
    }

    @Test
    func `Update replaces the entry by id and preserves insertion`() {
        let (store, _, _) = makeStore()
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
    func `Delete by entry removes the row`() {
        let (store, _, _) = makeStore()
        let entry = CustomSubstanceEntry(name: "Foo")
        store.add(entry)
        store.add(CustomSubstanceEntry(name: "Bar"))

        store.delete(entry)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Bar")
    }

    @Test
    func `Delete at offsets removes the matching rows`() {
        let (store, _, _) = makeStore()
        store.add(CustomSubstanceEntry(name: "Alpha"))
        store.add(CustomSubstanceEntry(name: "Beta"))
        store.add(CustomSubstanceEntry(name: "Gamma"))

        store.delete(at: IndexSet([1])) // removes "Beta"

        #expect(store.all.map(\.name) == ["Alpha", "Gamma"])
    }

    @Test
    func `contains(name:) is case-insensitive`() {
        let (store, _, _) = makeStore()
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
    func `Custom duration round-trips through persistence`() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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

        // Force a fresh read from persisted data.
        let store2 = CustomSubstanceStore.forTesting(defaults: defaults)
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
