import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("Custom units")
@MainActor
struct CustomUnitTests {
    private func makeStore() throws -> (CustomUnitStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (CustomUnitStore.forTesting(context: container.mainContext), container)
    }

    // MARK: - Store

    @Test
    func `Starts empty`() throws {
        let (store, _) = try makeStore()
        #expect(store.all.isEmpty)
        #expect(store.aliases(forSubstanceNamed: "Lisdexamfetamine").isEmpty)
    }

    @Test
    func `Add persists and exposes an alias, matched case-insensitively`() throws {
        let (store, container) = try makeStore()
        store.add(substanceName: "Lisdexamfetamine", label: "capsule", amountPerUnit: 30, unit: "mg")

        let alias = store.aliases(forSubstanceNamed: "lisdexamfetamine").first
        #expect(alias?.label == "capsule")
        #expect(alias?.amountPerUnit == 30)
        #expect(alias?.unit == "mg")

        // Round-trips through the store, not memory.
        let reloaded = CustomUnitStore.forTesting(context: ModelContext(container))
        #expect(reloaded.presets(forSubstanceNamed: "Lisdexamfetamine").count == 1)
    }

    @Test
    func `Duplicate label is detectable`() throws {
        let (store, _) = try makeStore()
        store.add(substanceName: "Amphetamine", label: "pill", amountPerUnit: 20, unit: "mg")
        #expect(store.hasLabel("Pill", forSubstanceNamed: "amphetamine"))
        #expect(!store.hasLabel("scoop", forSubstanceNamed: "amphetamine"))
    }

    @Test
    func `Delete removes the alias`() throws {
        let (store, _) = try makeStore()
        store.add(substanceName: "Caffeine", label: "scoop", amountPerUnit: 200, unit: "mg")
        let preset = try #require(store.presets(forSubstanceNamed: "Caffeine").first)
        store.delete(preset)
        #expect(store.aliases(forSubstanceNamed: "Caffeine").isEmpty)
    }

    // MARK: - Conversion through the Substance merge

    @Test
    func `A custom unit converts to mass, before the curated aliases`() throws {
        var sub = try #require(SubstanceLibrary.lookup("Caffeine"))
        sub.customUnitAliases = [UnitAlias(label: "capsule", amountPerUnit: 100, unit: "mg")]

        #expect(sub.unitAliases.contains { $0.label == "capsule" })
        // Half a 100 mg capsule → 50 mg on caffeine's native oral unit.
        #expect(sub.convert(amount: 0.5, from: "capsule", toRoute: .oral) == 50)
    }

    @Test
    func `Custom aliases lead the curated ones`() throws {
        // Alcohol has a curated "drink" alias; a user alias must sit ahead of it so
        // a colliding label resolves to the user's definition.
        var sub = try #require(SubstanceLibrary.lookup("Alcohol"))
        let curatedCount = sub.unitAliases.count
        sub.customUnitAliases = [UnitAlias(label: "can", amountPerUnit: 20, unit: "g")]
        #expect(sub.unitAliases.first?.label == "can")
        #expect(sub.unitAliases.count == curatedCount + 1)
    }
}
