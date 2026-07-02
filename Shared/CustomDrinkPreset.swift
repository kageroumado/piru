import Foundation
import SwiftData

/// A user-managed drink preset for a by-volume substance (alcohol in v1): a
/// named strength (and optional fixed volume) that pre-fills the By-Drink
/// editor with one tap. A preset is defined by **name + strength**; ``volumeML``
/// is optional — a preset with a fixed volume (a 330 mL can) fills both dials,
/// one without (an IPA you pour freely) fills only the strength and leaves the
/// volume for you to dial.
///
/// This is the user-editable counterpart to the curated ``DrinkPreset`` seeds in
/// ``ByVolumeDosing``: the seeds populate the list on first use, after which every
/// row is a `CustomDrinkPreset` the user can add / rename / delete. Grams stays
/// canonical on ``DoseEntry`` — a preset is pure input convenience.
///
/// Additive SwiftData model with property-level defaults (lightweight migration,
/// no version ladder — see `StoreRecovery`). Lives in `Shared/` so the schema
/// stays identical across the app, widget, and Live Activity targets.
@Model
final class CustomDrinkPreset {
    /// User-facing drink name ("Beer", "IPA", "House red"). Not localized once
    /// saved — it's user content.
    var name: String = ""
    /// A single emoji shown on the preset row and card chip. Defaults to 🍺.
    var emoji: String = "🍺"
    /// Strength as percent alcohol-by-volume — the defining figure alongside ``name``.
    var strengthABV: Double = 5
    /// Optional fixed serving volume in millilitres. `nil` → strength-only preset.
    var volumeML: Double?
    /// Canonical substance this preset belongs to (lowercased). Alcohol in v1; the
    /// column lets any future by-volume substance reuse the same table for free.
    var substanceName: String = "alcohol"
    /// Display order within the substance's list, ascending.
    var sortOrder: Double = 0
    /// Creation time — a stable tiebreak. Fully-qualified default for migration.
    var createdAt: Date = Date.distantPast

    init(
        name: String,
        emoji: String = "🍺",
        strengthABV: Double,
        volumeML: Double? = nil,
        substanceName: String = "alcohol",
        sortOrder: Double = 0,
        createdAt: Date = .now,
    ) {
        self.name = name
        self.emoji = emoji
        self.strengthABV = strengthABV
        self.volumeML = volumeML
        self.substanceName = substanceName.lowercased()
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension CustomDrinkPreset {
    /// Seed the curated defaults (Beer/Wine/Shot/Pint) for a substance the first
    /// time its preset list is shown, so the list is never empty on first use.
    /// Idempotent: seeds **only when no preset exists for the substance** — same
    /// store-lifecycle-tied approach as ``QuickLogManager/seedIfNeeded(history:context:)``,
    /// with no persistent "already seeded" flag to go stale across a restore.
    @MainActor
    static func seedIfNeeded(for substanceName: String, capability: ByVolumeDosing, context: ModelContext) {
        let lower = substanceName.lowercased()
        var descriptor = FetchDescriptor<CustomDrinkPreset>(
            predicate: #Predicate { $0.substanceName == lower },
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        for (index, preset) in capability.drinkPresets.enumerated() {
            context.insert(CustomDrinkPreset(
                name: String(localized: preset.name),
                emoji: preset.kind.emoji,
                strengthABV: preset.defaultABV,
                volumeML: preset.volume.converted(to: .milliliters).value,
                substanceName: lower,
                sortOrder: Double(index),
            ))
        }
        try? context.save()
    }
}
