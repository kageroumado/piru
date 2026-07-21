import Foundation
import SwiftData

/// The single writer of ``RoutineOccurrence`` state (design:
/// `Specs/routine-occurrences.md`, re-keyed by the Meds redesign —
/// `Specs/meds-reminders-redesign.md`).
///
/// One occurrence per (med × time slot × day): a med with 8:00 and 13:00
/// reminder times has two rows per due day, a med with no set times has one
/// "anytime" row (`slotMinutes == nil`). As-needed meds carry no expectation
/// and get no occurrences.
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
    /// `logged` rows whose dose disappeared revert to `pending`.
    static func reconcile(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        expirePastPendings(before: today, in: context)

        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let occurrences = todaysOccurrences(today, in: context)

        let dueItems = items.filter { !$0.isAsNeeded && AdherenceCalculator.isDue($0, on: today) }

        let current = materialize(dueItems: dueItems, existing: occurrences, today: today, in: context)
        match(occurrences: current, today: today, now: now, in: context)

        try? context.save()
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

    /// Today's slot keys that need no more re-asks: `logged` or `skipped`.
    /// Assumes ``reconcile(in:)`` ran this pass.
    static func satisfiedSlotKeys(in context: ModelContext, now: Date = .now) -> Set<String> {
        let today = Calendar.current.startOfDay(for: now)
        return Set(
            todaysOccurrences(today, in: context)
                .filter { $0.state == .logged || $0.state == .skipped }
                .map(slotKey(for:)),
        )
    }

    /// The user's "stop asking about these today": every still-pending
    /// occurrence whose slot key matches becomes `skipped` (sticky through
    /// later reconciles). The caller resyncs reminders so the remaining
    /// follow-ups cancel.
    static func skipToday(slotKeys: Set<String>, in context: ModelContext, now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        for occurrence in todaysOccurrences(today, in: context)
            where occurrence.state == .pending && slotKeys.contains(slotKey(for: occurrence)) {
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

    /// A due med's slots for one day: its sorted reminder times, or a single
    /// `nil` "anytime" slot when it has none.
    private static func slots(of item: DailyDoseItem) -> [Int?] {
        let times = item.reminderTimesMinutes.sorted()
        return times.isEmpty ? [nil] : times
    }

    /// Create today's missing occurrences and drop today's *pending* ones
    /// whose (med × slot) no longer exists or isn't due (edit/removal
    /// mid-day) — `logged`/`skipped` rows stay as history. Returns today's
    /// live set.
    private static func materialize(
        dueItems: [DailyDoseItem],
        existing: [RoutineOccurrence],
        today: Date,
        in context: ModelContext,
    ) -> [RoutineOccurrence] {
        var result = existing
        for item in dueItems {
            for slot in slots(of: item)
                where !result.contains(where: { corresponds($0, to: item, slot: slot) }) {
                let occurrence = RoutineOccurrence(
                    substance: item.substance,
                    substanceUID: item.substanceUID,
                    route: item.route,
                    dueDay: today,
                    slotMinutes: slot,
                )
                context.insert(occurrence)
                result.append(occurrence)
            }
        }
        for occurrence in result where occurrence.state == .pending
            && !dueItems.contains(where: { item in
                slots(of: item).contains { corresponds(occurrence, to: item, slot: $0) }
            }) {
            context.delete(occurrence)
            result.removeAll { $0 === occurrence }
        }
        return result
    }

    /// The §D matching rules, applied as a batch over today's entries in
    /// timestamp order: identity (uid-first, else name) + route, one claim per
    /// entry, nearest slot time on a tie. Unclaimed occurrences revert to
    /// `pending` — which is the whole delete/edit reconciliation.
    private static func match(
        occurrences: [RoutineOccurrence],
        today: Date,
        now: Date,
        in context: ModelContext,
    ) {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? now
        let predicate = #Predicate<DoseEntry> { $0.timestamp >= today && $0.timestamp < dayEnd }
        let entries = ((try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [])
            .sorted { $0.timestamp < $1.timestamp }

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
                distance(entryMinutes, toSlotAt: lhs.slotMinutes)
                    < distance(entryMinutes, toSlotAt: rhs.slotMinutes)
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

    /// Occurrence ↔ (med, slot) correspondence: identity + route + slot.
    private static func corresponds(_ occurrence: RoutineOccurrence, to item: DailyDoseItem, slot: Int?) -> Bool {
        occurrence.slotMinutes == slot
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

    /// An anytime slot sorts after any timed slot.
    private static func distance(_ minutes: Int, toSlotAt slotMinutes: Int?) -> Int {
        guard let slotMinutes else { return .max }
        return abs(minutes - slotMinutes)
    }

    private static func todaysOccurrences(_ today: Date, in context: ModelContext) -> [RoutineOccurrence] {
        let predicate = #Predicate<RoutineOccurrence> { $0.dueDay == today }
        return (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }
}
