import Testing
import Foundation
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

    @Test("Starts empty")
    func startsEmpty() {
        let (store, _, _) = makeStore()
        #expect(store.all.isEmpty)
    }

    @Test("Add inserts and persists to defaults")
    func addPersists() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let entry = CustomSubstanceEntry(
            name: "Test",
            category: .stimulant,
            defaultRoute: .oral,
            unit: "mg",
            notes: "hi"
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

    @Test("Add sorts alphabetically case-insensitively")
    func addSorts() {
        let (store, _, _) = makeStore()
        store.add(CustomSubstanceEntry(name: "zebra"))
        store.add(CustomSubstanceEntry(name: "Apple"))
        store.add(CustomSubstanceEntry(name: "banana"))
        #expect(store.all.map(\.name) == ["Apple", "banana", "zebra"])
    }

    @Test("Update replaces the entry by id and preserves insertion")
    func updateReplaces() {
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

    @Test("Delete by entry removes the row")
    func deleteByEntry() {
        let (store, _, _) = makeStore()
        let entry = CustomSubstanceEntry(name: "Foo")
        store.add(entry)
        store.add(CustomSubstanceEntry(name: "Bar"))

        store.delete(entry)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Bar")
    }

    @Test("Delete at offsets removes the matching rows")
    func deleteAtOffsets() {
        let (store, _, _) = makeStore()
        store.add(CustomSubstanceEntry(name: "Alpha"))
        store.add(CustomSubstanceEntry(name: "Beta"))
        store.add(CustomSubstanceEntry(name: "Gamma"))

        store.delete(at: IndexSet([1])) // removes "Beta"

        #expect(store.all.map(\.name) == ["Alpha", "Gamma"])
    }

    @Test("contains(name:) is case-insensitive")
    func containsCaseInsensitive() {
        let (store, _, _) = makeStore()
        store.add(CustomSubstanceEntry(name: "Aspirin"))
        #expect(store.contains(name: "aspirin"))
        #expect(store.contains(name: "ASPIRIN"))
        #expect(!store.contains(name: "Tylenol"))
    }

    @Test("asSubstance produces a usable Substance value")
    func asSubstanceMapping() {
        let entry = CustomSubstanceEntry(
            name: "Custom",
            category: .analgesic,
            defaultRoute: .sublingual,
            unit: "µg"
        )
        let substance = entry.asSubstance
        #expect(substance.name == "Custom")
        #expect(substance.category == .analgesic)
        #expect(substance.defaultRoute == .sublingual)
        #expect(substance.unit(for: .sublingual) == "µg")
    }
}
