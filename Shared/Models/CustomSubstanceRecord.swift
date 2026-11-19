import Foundation
import SwiftData

/// Store-resident user-defined substance.
///
/// Never keep user-authored substances in `UserDefaults`: outside the store
/// they miss its backup and recovery and survive a store reset that wipes
/// everything else. `CustomSubstanceStore`'s one-time migration verifies every
/// legacy row landed here before it deletes the old blob.
///
/// Fields are deliberately primitive (raw strings, JSON `Data?` blobs) so the
/// model carries no dependency on Piru-only types (`DoseRange`,
/// `DurationProfile`, `SubstanceCategory`) and compiles into every target that
/// opens the store — including the widget, whose container schema must know
/// every entity present on disk or the open fails. The typed
/// `CustomSubstanceEntry` mapping lives in the Piru target (see
/// `CustomSubstance.swift`). Adding this entity is purely additive, so it
/// migrates via automatic lightweight migration with no migration plan (see the
/// schema-migration policy in `StoreRecovery`).
@Model
final class CustomSubstanceRecord {
    /// Stable identity, preserved across edits and import round-trips. Not a
    /// `.unique` constraint — uniqueness is enforced by name in code, and unique
    /// constraints have sharp migration edges (see ``DoseEntry``).
    var id: UUID = UUID()

    /// Canonical name used for logging/lookup (matched case-insensitively).
    var name: String = ""

    /// Optional personal display label (e.g. "THC" shown as "joint").
    var displayName: String?

    /// `SubstanceCategory.rawValue`.
    var categoryRaw: String = "Other"

    /// `RouteOfAdministration.rawValue`.
    var defaultRouteRaw: String = "oral"

    var unit: String = "mg"
    var notes: String = ""

    /// JSON-encoded `DoseRange?` — encoded/decoded in the Piru target, opaque here.
    var dosesData: Data?

    /// JSON-encoded `DurationProfile?` — encoded/decoded in the Piru target, opaque here.
    var durationData: Data?

    var halfLifeMinutes: Double?

    /// JSON-encoded `[CombinationComponent]` for a combination product (co-codamol
    /// = paracetamol + codeine per tablet); `nil` for a single compound. Encoded
    /// and decoded in the Piru target, opaque here.
    var componentsData: Data?

    var createdAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        name: String = "",
        displayName: String? = nil,
        categoryRaw: String = "Other",
        defaultRouteRaw: String = "oral",
        unit: String = "mg",
        notes: String = "",
        dosesData: Data? = nil,
        durationData: Data? = nil,
        halfLifeMinutes: Double? = nil,
        componentsData: Data? = nil,
        createdAt: Date = .now,
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.categoryRaw = categoryRaw
        self.defaultRouteRaw = defaultRouteRaw
        self.unit = unit
        self.notes = notes
        self.dosesData = dosesData
        self.durationData = durationData
        self.halfLifeMinutes = halfLifeMinutes
        self.componentsData = componentsData
        self.createdAt = createdAt
    }
}
