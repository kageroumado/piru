import Foundation
import SwiftData

/// A single logged dose of a substance.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`). Because the same store is opened from
/// extensions, schema changes here must remain compatible across all three
/// targets.
///
/// ## Storage Conventions
/// - ``route`` is a `RouteOfAdministration` enum that SwiftData persists via
///   its `String` `rawValue` (`"oral"`, `"insufflation"`, etc.), making the
///   column human-readable and stable across renames of the Swift type.
/// - ``tags`` is a computed view over ``tagsRaw``, a comma-separated string.
///   Tags are CSV-encoded rather than stored as a relationship because
///   SwiftData arrays of value types are awkward to query across targets
///   and the tag set is small and read-mostly. Whitespace is trimmed on read.
///
/// ## Invariants
/// - ``amount`` is clamped to be non-negative at construction time.
@Model
final class DoseEntry {
    /// The substance's canonical (non-normalized) display name as logged by the user.
    var substance: String
    /// Quantity of the dose in ``unit``. Clamped to be `>= 0` at init.
    var amount: Double
    /// Unit of measure for ``amount`` (e.g. `"mg"`, `"µg"`, `"g"`, `"mL"`).
    var unit: String
    /// Route of administration; persisted as `rawValue` (a `String`).
    var route: RouteOfAdministration
    /// When the dose was taken.
    var timestamp: Date
    /// Optional free-form note attached to the dose.
    var notes: String?
    /// CSV-encoded backing storage for ``tags``. Prefer reading/writing ``tags``.
    var tagsRaw: String?

    /// The session this dose belongs to, assigned at log time by
    /// ``SessionClustering`` and persisted. Optional so the V1→V2 migration stays
    /// lightweight and `nil` for any not-yet-populated entry; ``Session`` owns
    /// the inverse with a `.nullify` delete rule.
    var session: Session?

    /// Whether this dose was logged as a *background* medication (a daily med
    /// flagged "background"). Background doses never open or extend a recreational
    /// session — they fold into the current one if active, else form a quiet
    /// maintenance session. Stamped at log time from the ``DailyDoseItem`` so it
    /// survives later edits to the template. Defaults `false`.
    var isBackgroundMed: Bool = false

    /// Free-form labels attached to the dose, decoded from ``tagsRaw``.
    ///
    /// Backed by a comma-separated string for portable SwiftData storage across
    /// the app, widget, and Live Activity extensions. Whitespace around each
    /// tag is trimmed on read; setting an empty array writes `nil`.
    var tags: [String] {
        get {
            guard let raw = tagsRaw, !raw.isEmpty else { return [] }
            return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    init(
        substance: String,
        amount: Double,
        unit: String = "mg",
        route: RouteOfAdministration = .oral,
        timestamp: Date = .now,
        notes: String? = nil,
        tags: [String] = [],
        isBackgroundMed: Bool = false,
    ) {
        self.substance = substance
        self.amount = max(0, amount)
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        self.notes = notes
        self.tagsRaw = tags.isEmpty ? nil : tags.joined(separator: ",")
        self.isBackgroundMed = isBackgroundMed
    }
}
