import Foundation
import SwiftData

/// A user-defined colloquial unit for one substance — "1 capsule = 30 mg",
/// "1 tab = 100 µg" — so a dose can be entered in whole pills and resolved to
/// its mass automatically. The user-editable counterpart to the curated
/// `UnitAlias` seeds (alcohol's "drink") that ``Substance/unitAliases`` carries:
/// both surface in the dose form's unit picker, and both resolve to canonical
/// mass at log time, so the substance keeps all its pharmacology (a custom unit
/// is pure input convenience, never a separate substance).
///
/// Additive SwiftData `@Model` with property-level defaults (lightweight
/// migration, no version ladder — see `StoreRecovery`). Lives in `Shared/` so
/// the schema stays identical across the app, widget, and Live Activity targets
/// that open the same store.
@Model
final class CustomUnitPreset {
    /// Canonical substance this unit belongs to, lowercased for matching. A
    /// custom unit is scoped to one substance — a "capsule" of Lisdexamfetamine
    /// is not a "capsule" of anything else.
    var substanceName: String = ""
    /// The unit's display label ("capsule", "tab", "scoop") — what appears in the
    /// dose form's unit picker. User content, not localized once saved.
    var label: String = ""
    /// How many ``unit``s one instance of ``label`` represents (30, for a 30 mg
    /// capsule). Clamped positive at init.
    var amountPerUnit: Double = 0
    /// The physical unit ``amountPerUnit`` is denominated in ("mg", "µg", "g").
    var unit: String = "mg"
    /// Display order within the substance's list, ascending.
    var sortOrder: Double = 0
    /// Creation time — a stable tiebreak. Fully-qualified default for migration.
    var createdAt: Date = Date.distantPast

    init(
        substanceName: String,
        label: String,
        amountPerUnit: Double,
        unit: String = "mg",
        sortOrder: Double = 0,
        createdAt: Date = .now,
    ) {
        self.substanceName = substanceName.lowercased()
        self.label = label
        self.amountPerUnit = max(0, amountPerUnit)
        self.unit = unit
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
