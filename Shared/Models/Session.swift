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
    // load, and `lastDoseDate` bounds `SessionService.assignSession`'s candidate fetch, so both are
    // indexed. `id` is already `@Attribute(.unique)` (an implicit index), so it needs no explicit one.
    #Index<Session>([\.startDate], [\.lastDoseDate])

    /// Stable identifier for routing and deep links (`PersistentIdentifier`
    /// isn't URL-stable). Unique; safe because CloudKit mirroring is disabled.
    @Attribute(.unique) var id: UUID

    /// Denormalized first-dose timestamp, cached for cheap sorting and
    /// day-header grouping. Keep in sync via ``refreshDoseBounds()`` whenever the
    /// earliest dose changes (insert / delete / time-edit / reassign).
    var startDate: Date

    /// Denormalized last-dose timestamp. Together with ``startDate`` it bounds
    /// `SessionService.assignSession`'s candidate fetch, so week-spanning merged
    /// sessions stay visible to in-span placement without fetching every session.
    /// It only ever *bounds the fetch* — placement re-derives the true span from
    /// the doses — so a stale value can over-fetch but never misplace, and `nil`
    /// (a row predating the field) is always fetched and self-heals via
    /// `SessionService.ensureSessionsPopulated`. Keep in sync via
    /// ``refreshDoseBounds()`` on every mutation class that can change the latest
    /// dose: dose insert, dose delete, timestamp edit, and merge / split /
    /// move / reassign.
    var lastDoseDate: Date?

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
        lastDoseDate = startDate
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

    /// Recompute ``startDate`` and ``lastDoseDate`` from the current doses in
    /// one pass. Call after any membership or timestamp change. Leaves both
    /// untouched if the session is (transiently) empty so a soon-to-be-deleted
    /// session doesn't jump to `distantPast`. Skips doses already marked
    /// deleted — the relationship still contains them until the context
    /// processes the deletion, and the delete sites refresh before that.
    func refreshDoseBounds() {
        let live = (doses ?? []).filter { !$0.isDeleted }
        guard var earliest = live.first?.timestamp else { return }
        var latest = earliest
        for dose in live.dropFirst() {
            if dose.timestamp < earliest { earliest = dose.timestamp }
            if dose.timestamp > latest { latest = dose.timestamp }
        }
        startDate = earliest
        lastDoseDate = latest
    }
}
