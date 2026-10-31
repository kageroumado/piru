import Foundation
import SwiftData

/// The single writer of ``RoutineOccurrence`` state (design:
/// `Specs/routine-occurrences.md`, re-keyed by the Meds redesign —
/// `Specs/meds-reminders-redesign.md`).
///
/// One occurrence per (med × time slot × day): a med with 8:00 and 13:00
/// reminder times has two rows per due day, a med with no set times has one
/// "anytime" row (`slotMinutes == nil`). As-needed meds carry no expectation
/// and get no occurrences. A day is a journal day (Settings ▸ Journal ▸ Day
/// Starts At), keyed by ``Foundation/Calendar/journalDay(for:boundaryHour:)``,
/// and a dose belongs to the journal day it fell in on the clock of the zone it
/// was logged in.
///
/// Rather than an incremental state machine hand-updated on every log, edit,
/// and delete — exactly where dose-scan inference failed silently —
/// ``reconcile(in:)`` idempotently re-derives today's occurrence states from
/// scratch on every call. The hooks that already funnel through
/// `DoseNotificationManager.syncMedReminders(in:)` (dose commits, med edits,
/// app foreground) therefore keep the record current for free.
@MainActor
enum RoutineOccurrenceService {
    /// Re-derive today's occurrence truth: expire past-day pendings to
    /// `missed`, materialize today's occurrences for due meds' slots, and
    /// re-run dose matching. `skipped` is a sticky user choice and survives;
    /// `logged` rows whose dose disappeared revert to `pending`. Saves only
    /// when the plan has something to write: an unchanged day leaves the
    /// context untouched, so no `@Query` re-evaluates for nothing.
    static func reconcile(in context: ModelContext, now: Date = .now) {
        let today = Calendar.current.journalDay(for: now)
        let plan = plan(from: context, today: today, products: CustomSubstanceStore.shared.productMeds)
        guard !plan.isEmpty else { return }
        apply(plan, in: context, today: today)
        try? context.save()
    }

    /// Whether ``reconcile(in:now:)`` would write anything, decided on
    /// ``DatabaseActor`` over a fresh context, so the launch and foreground
    /// syncs skip the main-actor fetches and the save on an unchanged day.
    @DatabaseActor
    static func needsReconcile(container: ModelContainer, now: Date = .now) -> Bool {
        let context = ModelContext(container)
        let today = Calendar.current.journalDay(for: now)
        return !plan(from: context, today: today, products: MedSchedule.productMeds()).isEmpty
    }

    // MARK: - Snapshots

    /// The reconcile's inputs as values, so the same decision runs on the
    /// main context (to apply) and on ``DatabaseActor`` (to ask).
    nonisolated struct ItemSnapshot: Sendable {
        let substance: String
        let substanceUID: String?
        let route: RouteOfAdministration
        /// Sorted reminder times, or a single `nil` "anytime" slot.
        let slots: [Int?]
    }

    nonisolated struct OccurrenceSnapshot: Sendable, LiveOccurrence {
        let id: PersistentIdentifier
        let substance: String
        let substanceUID: String?
        let route: RouteOfAdministration
        let slotMinutes: Int?
        let state: RoutineOccurrence.State
        let satisfyingEntryID: UUID?
    }

    nonisolated struct EntrySnapshot: Sendable {
        let id: UUID
        let substance: String
        let substanceUID: String?
        let route: RouteOfAdministration
        let timestamp: Date
        /// ``DoseEntry/combinationName``: the product this dose was one component of.
        var combinationName: String?
        /// ``DoseEntry/timeZoneIdentifier``: the zone the dose was logged in.
        var timeZoneIdentifier: String?
        /// ``DoseEntry/medSlotMinutes``: the slot the dose was checked off for.
        var medSlotMinutes: Int?
    }

    /// What one reconcile has to write. Empty on an unchanged day.
    nonisolated struct Plan: Sendable {
        struct NewOccurrence: Sendable {
            let substance: String
            let substanceUID: String?
            let route: RouteOfAdministration
            let slotMinutes: Int?
            let state: RoutineOccurrence.State
            let satisfyingEntryID: UUID?
        }

        /// Past-day pendings that become `missed`.
        var expire: [PersistentIdentifier] = []
        var inserts: [NewOccurrence] = []
        /// Today's pendings whose (med × slot) is no longer due.
        var deletes: [PersistentIdentifier] = []
        /// Existing occurrences whose match outcome changed.
        var updates: [PersistentIdentifier: (state: RoutineOccurrence.State, satisfyingEntryID: UUID?)] = [:]

        var isEmpty: Bool {
            expire.isEmpty && inserts.isEmpty && deletes.isEmpty && updates.isEmpty
        }
    }

    /// Read today's inputs from `context` and plan the reconcile.
    private nonisolated static func plan(
        from context: ModelContext, today: Date, products: [String: MedSchedule.ProductMed],
    ) -> Plan {
        let pendingRaw = RoutineOccurrence.State.pending.rawValue
        let expiredPredicate = #Predicate<RoutineOccurrence> { $0.dueDay < today && $0.stateRaw == pendingRaw }
        let expired = ((try? context.fetch(FetchDescriptor(predicate: expiredPredicate))) ?? []).map(\.persistentModelID)

        let items = ((try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? [])
            .filter { !$0.isAsNeeded && AdherenceCalculator.isDue(startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays, intervalDays: $0.frequencyIntervalDays, on: today) }
            .map { item in
                let times = item.reminderTimesMinutes.sorted()
                return ItemSnapshot(substance: item.substance, substanceUID: item.substanceUID, route: item.route, slots: times.isEmpty ? [nil] : times)
            }
        let occurrencePredicate = #Predicate<RoutineOccurrence> { $0.dueDay == today }
        let occurrences = ((try? context.fetch(FetchDescriptor(predicate: occurrencePredicate))) ?? []).map {
            OccurrenceSnapshot(
                id: $0.persistentModelID, substance: $0.substance, substanceUID: $0.substanceUID, route: $0.route,
                slotMinutes: $0.slotMinutes, state: $0.state, satisfyingEntryID: $0.satisfyingEntryID,
            )
        }
        // A window wide enough for a dose logged in any zone, narrowed to the
        // doses whose own journal day is today.
        let calendar = Calendar.current
        let boundaryHour = Calendar.sessionDayBoundaryHour
        let window = calendar.doseFetchWindow(forJournalDay: today, boundaryHour: boundaryHour)
        let windowStart = window.start, windowEnd = window.end
        let entryPredicate = #Predicate<DoseEntry> { $0.timestamp >= windowStart && $0.timestamp < windowEnd }
        let entries = ((try? context.fetch(FetchDescriptor(predicate: entryPredicate))) ?? [])
            .filter { $0.journalDay(in: calendar, boundaryHour: boundaryHour) == today }
            .map {
                EntrySnapshot(
                    id: $0.id, substance: $0.substance, substanceUID: $0.substanceUID, route: $0.route,
                    timestamp: $0.timestamp, combinationName: $0.combinationName,
                    timeZoneIdentifier: $0.timeZoneIdentifier, medSlotMinutes: $0.medSlotMinutes,
                )
            }

        return plan(
            dueItems: items, occurrences: occurrences, expired: expired, entries: entries,
            products: products,
        )
    }

    /// The pure reconcile: which occurrences to create, drop, expire, and
    /// which match outcomes changed. The §D matching rules run as a batch
    /// over today's entries: identity (uid-first, else name) + route, one
    /// claim per entry. A dose checked off for a slot
    /// (``DoseEntry/medSlotMinutes``) claims that slot first, so an 8:00 dose
    /// recorded at 15:00 ticks 8:00 and leaves 20:00 open; every other dose
    /// then takes the nearest open slot, in timestamp order, measured on the
    /// journal-day clock it was logged by. Unclaimed occurrences revert to
    /// `pending`, which is the whole delete/edit reconciliation.
    nonisolated static func plan(
        dueItems: [ItemSnapshot],
        occurrences: [OccurrenceSnapshot],
        expired: [PersistentIdentifier],
        entries: [EntrySnapshot],
        products: [String: MedSchedule.ProductMed] = [:],
        calendar: Calendar = .current,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> Plan {
        var plan = Plan()
        plan.expire = expired

        // Today's live set: the existing rows that still correspond to a due
        // slot (or are settled history), plus a row for every due slot without
        // one. Each live row is keyed by its position in `live`.
        struct Live: LiveOccurrence {
            let substance: String
            let substanceUID: String?
            let route: RouteOfAdministration
            let slotMinutes: Int?
            let state: RoutineOccurrence.State
            let existing: OccurrenceSnapshot?
        }
        var live: [Live] = []
        for occurrence in occurrences {
            let stillDue = dueItems.contains { item in
                item.slots.contains { corresponds(occurrence, to: item, slot: $0) }
            }
            if occurrence.state == .pending, !stillDue {
                plan.deletes.append(occurrence.id)
            } else {
                live.append(Live(
                    substance: occurrence.substance, substanceUID: occurrence.substanceUID, route: occurrence.route,
                    slotMinutes: occurrence.slotMinutes, state: occurrence.state, existing: occurrence,
                ))
            }
        }
        for item in dueItems {
            for slot in item.slots where !live.contains(where: { corresponds($0, to: item, slot: slot) }) {
                live.append(Live(
                    substance: item.substance, substanceUID: item.substanceUID, route: item.route,
                    slotMinutes: slot, state: .pending, existing: nil,
                ))
            }
        }

        var claimed = Set<Int>()
        var assignment: [Int: UUID] = [:]
        func open(_ index: Int, for entry: EntrySnapshot) -> Bool {
            live[index].state != .skipped && !claimed.contains(index)
                && matches(entry: entry, occurrence: live[index], products: products)
        }
        let byTime = entries.sorted { $0.timestamp < $1.timestamp }
        var unplaced: [EntrySnapshot] = []
        for entry in byTime {
            guard let slot = entry.medSlotMinutes,
                  let named = live.indices.first(where: { live[$0].slotMinutes == slot && open($0, for: entry) })
            else {
                unplaced.append(entry)
                continue
            }
            claimed.insert(named)
            assignment[named] = entry.id
        }
        for entry in unplaced {
            let entryMinutes = calendar.journalMinutes(
                for: entry.timestamp, loggedIn: entry.timeZoneIdentifier, boundaryHour: boundaryHour,
            )
            let best = live.indices
                .filter { open($0, for: entry) }
                .min {
                    distance(entryMinutes, toSlotAt: live[$0].slotMinutes, boundaryHour: boundaryHour)
                        < distance(entryMinutes, toSlotAt: live[$1].slotMinutes, boundaryHour: boundaryHour)
                }
            guard let best else { continue }
            claimed.insert(best)
            assignment[best] = entry.id
        }

        for (index, row) in live.enumerated() {
            let outcome: (state: RoutineOccurrence.State, satisfyingEntryID: UUID?) = if row.state == .skipped {
                (.skipped, row.existing?.satisfyingEntryID)
            } else if let entryID = assignment[index] {
                (.logged, entryID)
            } else {
                (.pending, nil)
            }
            if let existing = row.existing {
                if existing.state != outcome.state || existing.satisfyingEntryID != outcome.satisfyingEntryID {
                    plan.updates[existing.id] = outcome
                }
            } else {
                plan.inserts.append(Plan.NewOccurrence(
                    substance: row.substance, substanceUID: row.substanceUID, route: row.route,
                    slotMinutes: row.slotMinutes, state: outcome.state, satisfyingEntryID: outcome.satisfyingEntryID,
                ))
            }
        }
        return plan
    }

    /// Write `plan` into `context` (no save).
    private static func apply(_ plan: Plan, in context: ModelContext, today: Date) {
        for id in plan.expire {
            if let occurrence = context.model(for: id) as? RoutineOccurrence {
                occurrence.state = .missed
            }
        }
        for id in plan.deletes {
            if let occurrence = context.model(for: id) as? RoutineOccurrence {
                context.delete(occurrence)
            }
        }
        for (id, outcome) in plan.updates {
            if let occurrence = context.model(for: id) as? RoutineOccurrence {
                occurrence.state = outcome.state
                occurrence.satisfyingEntryID = outcome.satisfyingEntryID
            }
        }
        for new in plan.inserts {
            let occurrence = RoutineOccurrence(
                substance: new.substance,
                substanceUID: new.substanceUID,
                route: new.route,
                dueDay: today,
                slotMinutes: new.slotMinutes,
            )
            occurrence.state = new.state
            occurrence.satisfyingEntryID = new.satisfyingEntryID
            context.insert(occurrence)
        }
    }

    /// The stable key of one (med × slot): identity (uid when resolved, else
    /// lowercased name) + route + slot minutes. Shared by the reminder
    /// scheduler and the Skip Today action so both sides agree on which
    /// occurrence a notification is about.
    nonisolated static func slotKey(
        substance: String,
        substanceUID: String?,
        route: RouteOfAdministration,
        slotMinutes: Int?,
    ) -> String {
        let identity = (substanceUID?.isEmpty == false) ? substanceUID! : substance.lowercased()
        return "\(identity)|\(route.rawValue)|\(slotMinutes.map(String.init) ?? "any")"
    }

    static func slotKey(for occurrence: RoutineOccurrence) -> String {
        slotKey(
            substance: occurrence.substance,
            substanceUID: occurrence.substanceUID,
            route: occurrence.route,
            slotMinutes: occurrence.slotMinutes,
        )
    }

    /// The slot keys whose reminder today needs no more re-asks: `logged` or
    /// `skipped`. Assumes ``reconcile(in:)`` ran this pass.
    ///
    /// Reminders fire on the wall clock, so "today's" 8:00 re-ask is the one
    /// at 8:00 on today's calendar date. Between midnight and the Day Starts
    /// At hour that firing belongs to the next journal day, not the current
    /// one, so the current day's ticked 8:00 must not silence it: only slots
    /// whose calendar-today firing falls in the current journal day count.
    static func satisfiedSlotKeys(in context: ModelContext, now: Date = .now) -> Set<String> {
        let calendar = Calendar.current
        let boundaryHour = Calendar.sessionDayBoundaryHour
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)
        let calendarToday = calendar.startOfDay(for: now)
        return Set(
            todaysOccurrences(today, in: context)
                .filter { $0.state == .logged || $0.state == .skipped }
                .filter { occurrence in
                    guard let minutes = occurrence.slotMinutes else { return true }
                    let firing = AdherenceCalculator.slotDate(minutes: minutes, on: calendarToday, calendar: calendar, boundaryHour: 0)
                    return calendar.journalDay(for: firing, boundaryHour: boundaryHour) == today
                }
                .map(slotKey(for:)),
        )
    }

    /// The user's "stop asking about these today": every still-pending
    /// occurrence whose slot key matches becomes `skipped` (sticky through
    /// later reconciles). The caller resyncs reminders so the remaining
    /// follow-ups cancel.
    static func skipToday(slotKeys: Set<String>, in context: ModelContext, now: Date = .now) {
        let today = Calendar.current.journalDay(for: now)
        for occurrence in todaysOccurrences(today, in: context)
            where occurrence.state == .pending && slotKeys.contains(slotKey(for: occurrence)) {
            occurrence.state = .skipped
        }
        try? context.save()
    }

    // MARK: - Joins

    /// Occurrence ↔ (med, slot) correspondence: identity + route + slot.
    private nonisolated static func corresponds(_ occurrence: some LiveOccurrence, to item: ItemSnapshot, slot: Int?) -> Bool {
        occurrence.slotMinutes == slot
            && occurrence.route == item.route
            && MedSchedule.identityMatches(
                keyA: occurrence.substanceUID, nameA: occurrence.substance,
                keyB: item.substanceUID, nameB: item.substance,
            )
    }

    /// Entry ↔ occurrence match: identity and route (spec §D). Identity runs
    /// through ``MedSchedule/identityMatches(keyA:nameA:keyB:nameB:)``, the
    /// same join the quick-log chips and the adherence calendar use, so the
    /// checklist and the Log sheet agree on what has been taken today. An
    /// occurrence of a combination product is claimed by the product's lead
    /// component entry (``MedSchedule/productMatches(entryName:entryCombination:product:)``).
    private nonisolated static func matches(
        entry: EntrySnapshot, occurrence: some LiveOccurrence, products: [String: MedSchedule.ProductMed],
    ) -> Bool {
        if let product = products[occurrence.substance.lowercased()] {
            return MedSchedule.productMatches(
                entryName: entry.substance, entryCombination: entry.combinationName, product: product,
            )
        }
        return entry.route == occurrence.route
            && MedSchedule.identityMatches(
                keyA: entry.substanceUID, nameA: entry.substance,
                keyB: occurrence.substanceUID, nameB: occurrence.substance,
            )
    }

    /// How far a dose (on the journal-day scale) is from a slot. An anytime
    /// slot sorts after any timed slot.
    private nonisolated static func distance(_ minutes: Int, toSlotAt slotMinutes: Int?, boundaryHour: Int) -> Int {
        guard let slotMinutes else { return .max }
        return abs(minutes - Calendar.journalMinutes(ofSlot: slotMinutes, boundaryHour: boundaryHour))
    }

    private static func todaysOccurrences(_ today: Date, in context: ModelContext) -> [RoutineOccurrence] {
        let predicate = #Predicate<RoutineOccurrence> { $0.dueDay == today }
        return (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }
}

/// The identity fields the matching joins read, shared by an existing
/// occurrence and one the plan is about to create.
nonisolated protocol LiveOccurrence {
    var substance: String { get }
    var substanceUID: String? { get }
    var route: RouteOfAdministration { get }
    var slotMinutes: Int? { get }
}
