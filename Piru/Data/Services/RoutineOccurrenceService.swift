import Foundation
import SwiftData

/// The single writer of ``RoutineOccurrence`` state (design:
/// `Specs/routine-occurrences.md`).
///
/// Rather than an incremental state machine hand-updated on every log, edit,
/// and delete — exactly where dose-scan inference failed silently —
/// ``reconcile(in:)`` idempotently re-derives today's occurrence states from
/// scratch on every call. The hooks that already funnel through
/// `DoseNotificationManager.syncRoutineReminders(in:)` (dose commits, routine
/// edits, app foreground) therefore keep the record current for free.
@MainActor
enum RoutineOccurrenceService {
    /// Re-derive today's occurrence truth: expire past-day pendings to
    /// `missed`, materialize today's occurrences for due routine items, and
    /// re-run dose matching. `skipped` is a sticky user choice and survives;
    /// `logged` rows whose dose disappeared revert to `pending`.
    static func reconcile(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        expirePastPendings(before: today, in: context)

        let routines = (try? context.fetch(FetchDescriptor<DoseRoutine>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let occurrences = todaysOccurrences(today, in: context)

        let dueItems = items.filter { item in
            !item.category.isEmpty
                && routines.contains { $0.name == item.category }
                && AdherenceCalculator.isDue(item, on: today)
        }

        let current = materialize(dueItems: dueItems, existing: occurrences, today: today, in: context)
        match(occurrences: current, routines: routines, today: today, now: now, in: context)

        try? context.save()
    }

    /// Whether the routine needs no more re-asks today: every occurrence is
    /// `logged` or `skipped`. Nothing due counts as satisfied (there is
    /// nothing left to log). Assumes ``reconcile(in:)`` ran this pass.
    static func isSatisfiedToday(routineName: String, in context: ModelContext, now: Date = .now) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        let todays = todaysOccurrences(today, in: context).filter { $0.routineName == routineName }
        return todays.allSatisfy { $0.state == .logged || $0.state == .skipped }
    }

    /// The user's "stop asking about this routine today": every still-pending
    /// occurrence becomes `skipped` (sticky through later reconciles). The
    /// caller resyncs reminders so the remaining follow-ups cancel.
    static func skipToday(routineName: String, in context: ModelContext, now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        for occurrence in todaysOccurrences(today, in: context)
            where occurrence.routineName == routineName && occurrence.state == .pending {
            occurrence.state = .skipped
        }
        try? context.save()
    }

    // MARK: - Reconcile steps

    /// A day ended with the occurrence still pending → `missed`. Neutral
    /// history (spec §D: never surfaced as a scoreboard or a reprimand).
    private static func expirePastPendings(before today: Date, in context: ModelContext) {
        let pendingRaw = RoutineOccurrence.State.pending.rawValue
        let predicate = #Predicate<RoutineOccurrence> { $0.dueDay < today && $0.stateRaw == pendingRaw }
        let expired = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        for occurrence in expired {
            occurrence.state = .missed
        }
    }

    /// Create today's missing occurrences and drop today's *pending* ones
    /// whose item no longer exists or isn't due (rename/removal mid-day) —
    /// `logged`/`skipped` rows stay as history. Returns today's live set.
    private static func materialize(
        dueItems: [DailyDoseItem],
        existing: [RoutineOccurrence],
        today: Date,
        in context: ModelContext,
    ) -> [RoutineOccurrence] {
        var result = existing
        for item in dueItems where !result.contains(where: { corresponds($0, to: item) }) {
            let occurrence = RoutineOccurrence(
                routineName: item.category,
                substance: item.substance,
                substanceUID: item.substanceUID,
                route: item.route,
                dueDay: today,
            )
            context.insert(occurrence)
            result.append(occurrence)
        }
        for occurrence in result where occurrence.state == .pending
            && !dueItems.contains(where: { corresponds(occurrence, to: $0) }) {
            context.delete(occurrence)
            result.removeAll { $0 === occurrence }
        }
        return result
    }

    /// The §D matching rules, applied as a batch over today's entries in
    /// timestamp order: identity (uid-first, else name) + route, one claim per
    /// entry, nearest routine time on a tie. Unclaimed occurrences revert to
    /// `pending` — which is the whole delete/edit reconciliation.
    private static func match(
        occurrences: [RoutineOccurrence],
        routines: [DoseRoutine],
        today: Date,
        now: Date,
        in context: ModelContext,
    ) {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? now
        let predicate = #Predicate<DoseEntry> { $0.timestamp >= today && $0.timestamp < dayEnd }
        let entries = ((try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [])
            .sorted { $0.timestamp < $1.timestamp }
        let routineTime: [String: Int] = Dictionary(
            uniqueKeysWithValues: routines.compactMap { routine in
                routine.timeMinutes.map { (routine.name, $0) }
            },
        )

        var claimed: Set<PersistentIdentifier> = []
        var assignment: [PersistentIdentifier: UUID] = [:]

        for entry in entries {
            let candidates = occurrences.filter {
                $0.state != .skipped
                    && !claimed.contains($0.persistentModelID)
                    && matches(entry: entry, occurrence: $0)
            }
            guard !candidates.isEmpty else { continue }
            let entryMinutes = minutesOfDay(entry.timestamp)
            let best = candidates.min { lhs, rhs in
                distance(entryMinutes, toRoutineAt: routineTime[lhs.routineName])
                    < distance(entryMinutes, toRoutineAt: routineTime[rhs.routineName])
            }
            guard let best else { continue }
            claimed.insert(best.persistentModelID)
            assignment[best.persistentModelID] = entry.id
        }

        for occurrence in occurrences where occurrence.state != .skipped {
            if let entryID = assignment[occurrence.persistentModelID] {
                occurrence.state = .logged
                occurrence.satisfyingEntryID = entryID
            } else {
                occurrence.state = .pending
                occurrence.satisfyingEntryID = nil
            }
        }
    }

    // MARK: - Joins

    /// Occurrence ↔ item correspondence: same routine + identity + route.
    private static func corresponds(_ occurrence: RoutineOccurrence, to item: DailyDoseItem) -> Bool {
        occurrence.routineName == item.category
            && occurrence.route == item.route
            && identityMatches(
                nameA: occurrence.substance, uidA: occurrence.substanceUID,
                nameB: item.substance, uidB: item.substanceUID,
            )
    }

    /// Entry ↔ occurrence match: identity (uid when both sides have one, else
    /// case-insensitive name) and route (spec §D).
    private static func matches(entry: DoseEntry, occurrence: RoutineOccurrence) -> Bool {
        entry.route == occurrence.route
            && identityMatches(
                nameA: entry.substance, uidA: entry.substanceUID,
                nameB: occurrence.substance, uidB: occurrence.substanceUID,
            )
    }

    private static func identityMatches(nameA: String, uidA: String?, nameB: String, uidB: String?) -> Bool {
        if let uidA, let uidB { return uidA == uidB }
        return nameA.lowercased() == nameB.lowercased()
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// A routine with no set time sorts after any timed routine.
    private static func distance(_ minutes: Int, toRoutineAt routineMinutes: Int?) -> Int {
        guard let routineMinutes else { return .max }
        return abs(minutes - routineMinutes)
    }

    private static func todaysOccurrences(_ today: Date, in context: ModelContext) -> [RoutineOccurrence] {
        let predicate = #Predicate<RoutineOccurrence> { $0.dueDay == today }
        return (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }
}
