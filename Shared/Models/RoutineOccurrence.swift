import Foundation
import SwiftData

/// The durable record of "was routine item X due on day Y, and what happened
/// to it" — one row per (routine, item, day) where the item was due.
///
/// Written only by `RoutineOccurrenceService` (see
/// `Specs/routine-occurrences.md`): `reconcile(in:)` re-derives the day's
/// states, `skipToday(slotKeys:)` records the Skip Today action. Follow-up
/// cancellation and the future "did I take it" surfaces read this record
/// instead of re-inferring from raw `DoseEntry` scans.
///
/// The item is referenced by an identity snapshot (`substance` /
/// `substanceUID` / `routeRaw`), not a UUID — `DailyDoseItem` has no stable
/// id field, and adding one repeats the `DoseEntry.id` lightweight-migration
/// trap. Property-level defaults keep the addition a pure lightweight
/// migration.
@Model
final class RoutineOccurrence {
    /// The owning routine, string-joined like `DailyDoseItem.category`.
    var routineName: String = ""
    /// The item's substance name at materialization time.
    var substance: String = ""
    /// The item's PSID identity, when resolved — the preferred join key, so a
    /// relabeled dose still matches (spec §D).
    var substanceUID: String?
    /// The item's route; a dose must match it to satisfy the occurrence.
    /// Literal defaults throughout — a `@Model` stored-property default that
    /// references the type's own nested enum traps SwiftData's schema
    /// generation at runtime.
    var routeRaw: String = "oral"
    /// `startOfDay` of the due date.
    var dueDay: Date = Date.distantPast
    /// Backing storage for ``state``.
    var stateRaw: String = "pending"
    /// The `DoseEntry.id` that satisfied this occurrence (when `logged`).
    var satisfyingEntryID: UUID?
    /// The med's reminder time this occurrence tracks, as minutes from
    /// midnight — the Meds redesign keys occurrences per (med × time slot),
    /// so an 8:00 + 13:00 med has two rows per day. `nil` = the single
    /// "anytime" slot of a med with no set times (and every pre-redesign
    /// legacy row). Additive with a default — a pure lightweight migration.
    var slotMinutes: Int?

    init(
        routineName: String = "",
        substance: String,
        substanceUID: String? = nil,
        route: RouteOfAdministration,
        dueDay: Date,
        slotMinutes: Int? = nil,
    ) {
        self.routineName = routineName
        self.substance = substance
        self.substanceUID = substanceUID
        routeRaw = route.rawValue
        self.dueDay = dueDay
        self.slotMinutes = slotMinutes
    }

    /// What happened to the due item. `missed` is neutral end-of-day history,
    /// never a delivered reprimand; `skipped` is a user choice and sticky.
    enum State: String {
        case pending
        case logged
        case skipped
        case missed
    }

    var state: State {
        get { State(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var route: RouteOfAdministration {
        get { RouteOfAdministration(rawValue: routeRaw) ?? .oral }
        set { routeRaw = newValue.rawValue }
    }
}
