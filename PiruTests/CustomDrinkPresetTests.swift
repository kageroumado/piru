import Foundation
import SwiftData
import Testing
@testable import Piru

/// `CustomDrinkPreset` is the user-managed drink library backing the By-Drink
/// editor. These tests pin its seeding (curated defaults on first use, idempotent
/// per substance) and the `QuickLogDose` key that keeps distinct drinks distinct.
///
/// `@MainActor` so the `ModelContainer` builds serialize with the app's other
/// container suites — see ``StoreRecoveryTests``.
@Suite("CustomDrinkPreset")
@MainActor
struct CustomDrinkPresetTests {
    /// Alcohol's by-volume capability as the app resolves it, so the seeded rows are gated against
    /// what `by_volume_dosing` + `drink_presets` actually ship rather than a fixture.
    private let alcoholCapability: ByVolumeDosing

    init() throws {
        _ = SubstanceStore.shared
        alcoholCapability = try #require(
            ByVolumeCatalog.capability(forAnyOf: ["Alcohol"]),
            "no by_volume_dosing row for Alcohol in the bundled DB",
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    @Test
    func `seeds the curated drink presets on first use`() throws {
        let ctx = try makeContext()
        CustomDrinkPreset.seedIfNeeded(for: "alcohol", capability: alcoholCapability, context: ctx)

        let seeded = try ctx.fetch(FetchDescriptor<CustomDrinkPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(seeded.count == alcoholCapability.drinkPresets.count)
        #expect(seeded.map(\.name) == ["Beer", "Wine", "Shot", "Pint"])
        let beer = seeded.first
        #expect(beer?.emoji == "🍺")
        #expect(beer?.strengthABV == 5)
        #expect(beer?.volumeML == 330)
        #expect(beer?.substanceName == "alcohol")
    }

    @Test
    func `seeding is idempotent — a second call adds nothing`() throws {
        let ctx = try makeContext()
        CustomDrinkPreset.seedIfNeeded(for: "alcohol", capability: alcoholCapability, context: ctx)
        CustomDrinkPreset.seedIfNeeded(for: "alcohol", capability: alcoholCapability, context: ctx)
        let count = try ctx.fetchCount(FetchDescriptor<CustomDrinkPreset>())
        #expect(count == alcoholCapability.drinkPresets.count)
    }

    @Test
    func `seeding does not clobber a user-edited list`() throws {
        let ctx = try makeContext()
        // User already has one custom preset — seeding must leave it alone.
        ctx.insert(CustomDrinkPreset(name: "House IPA", strengthABV: 6, substanceName: "alcohol"))
        try ctx.save()
        CustomDrinkPreset.seedIfNeeded(for: "alcohol", capability: alcoholCapability, context: ctx)
        let all = try ctx.fetch(FetchDescriptor<CustomDrinkPreset>())
        #expect(all.count == 1)
        #expect(all.first?.name == "House IPA")
    }

    @Test
    func `strength-only preset stores a nil volume`() {
        let preset = CustomDrinkPreset(name: "IPA", strengthABV: 6, volumeML: nil)
        #expect(preset.volumeML == nil)
        #expect(preset.detailLabel == "6%")
    }

    @Test
    func `fixed-volume preset labels volume and strength`() {
        let preset = CustomDrinkPreset(name: "Beer", strengthABV: 5, volumeML: 330)
        #expect(preset.detailLabel == "330 mL · 5%")
    }
}

/// The curated quick-log chip key folds in by-volume detail so distinct drinks
/// stay distinct chips, while plain mass doses keep their simple key.
@Suite("QuickLogDose drink key")
struct QuickLogDoseKeyTests {
    @Test
    func `plain mass dose key is unchanged by nil detail`() {
        let key = QuickLogDose.makeKey(substance: "Caffeine", route: .oral, amount: 100, unit: "mg")
        #expect(key == "caffeine|oral|100.0|mg")
    }

    @Test
    func `two drinks with the same grams but different detail get distinct keys`() {
        let ipa = QuickLogDose.makeKey(
            substance: "Alcohol", route: .oral, amount: 14, unit: "g",
            volumeML: 355, abv: 5, drinkName: "IPA",
        )
        let cider = QuickLogDose.makeKey(
            substance: "Alcohol", route: .oral, amount: 14, unit: "g",
            volumeML: 355, abv: 5, drinkName: "Cider",
        )
        #expect(ipa != cider)
    }

    @Test
    func `the same drink produces a stable key`() {
        func key() -> String {
            QuickLogDose.makeKey(
                substance: "Alcohol", route: .oral, amount: 13, unit: "g",
                volumeML: 330, abv: 5, drinkName: "Beer",
            )
        }
        #expect(key() == key())
    }
}
