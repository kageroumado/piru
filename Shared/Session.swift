import Foundation
import SwiftData

/// A *session*: a set of `DoseEntry`s grouped by temporal proximity — the
/// Journal's primary organizing unit, replacing calendar-day bucketing.
///
/// A session is decided at log time by ``SessionClustering`` and persisted; it
/// is never silently re-clustered afterwards. The user owns it from then on via
/// merge / split / reassign. A lone dose (including a single daily medication)
/// is a session of one — the model is uniform, with no special-casing.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`), like the other models in `Shared/`.
///
/// ## Maintenance sessions
/// A session whose doses are *all* background medications
/// (``DoseEntry/isBackgroundMed``) is a *maintenance* session — it renders as a
/// compact "Medications" row rather than a full timeline card. This is derived
/// (``isMaintenance``), not stored, so it stays correct as doses move.
///
/// ## CloudKit
/// Like the rest of the schema, this is opened with `cloudKitDatabase: .none`
/// (see `PiruApp.makeContainer`), so the `.unique` `id` and the non-optional
/// `startDate` are fine. The ``doses`` relationship is optional with an explicit
/// inverse (``DoseEntry/session``) and a `.nullify` delete rule, so deleting a
/// session never deletes its doses — they simply become unassigned.
@Model
final class Session {
    // `startDate` drives every chronological session list and the journal's day-grouping/windowed
    // load, so it's indexed. `id` is already `@Attribute(.unique)` (an implicit index), so it needs no
    // explicit one.
    #Index<Session>([\.startDate])

    /// Stable identifier for routing and deep links (`PersistentIdentifier`
    /// isn't URL-stable). Unique; safe because CloudKit mirroring is disabled.
    @Attribute(.unique) var id: UUID

    /// Denormalized first-dose timestamp, cached for cheap sorting and
    /// day-header grouping. Keep in sync via ``refreshStartDate()`` whenever the
    /// earliest dose changes (insert / delete / time-edit / reassign).
    var startDate: Date

    /// Optional user-authored session title (e.g. "Festival Saturday").
    var title: String?

    /// Optional free-form session note.
    var note: String?

    /// The doses in this session. Optional relationship with an explicit inverse
    /// and `.nullify` rule — deleting the session never deletes the doses.
    @Relationship(deleteRule: .nullify, inverse: \DoseEntry.session)
    var doses: [DoseEntry]?

    init(id: UUID = UUID(), startDate: Date, title: String? = nil, note: String? = nil) {
        self.id = id
        self.startDate = startDate
        self.title = title
        self.note = note
    }

    /// The session's doses in ascending time order (the relationship array is
    /// unordered).
    var orderedDoses: [DoseEntry] {
        (doses ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// `true` when every dose is a background medication, so the session should
    /// render as a compact maintenance row. An empty session is not maintenance.
    var isMaintenance: Bool {
        let doses = doses ?? []
        return !doses.isEmpty && doses.allSatisfy(\.isBackgroundMed)
    }

    /// Recompute ``startDate`` from the current earliest dose. Call after any
    /// membership or timestamp change. Leaves ``startDate`` untouched if the
    /// session is (transiently) empty so a soon-to-be-deleted session doesn't
    /// jump to `distantPast`.
    func refreshStartDate() {
        if let earliest = (doses ?? []).map(\.timestamp).min() {
            startDate = earliest
        }
    }
}
