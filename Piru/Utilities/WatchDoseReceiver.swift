import Foundation
import SwiftData

/// Maps a `WatchDosePayload` (arriving over WatchConnectivity) onto a `DoseEntry` and
/// inserts it through the **canonical** `DoseLogService.log` path — so a watch dose gets
/// the same session assignment, harm-reduction notifications, and change signal as one
/// logged on the phone. The phone stays the single writer.
///
/// ## Idempotency
/// `transferUserInfo` guarantees delivery but can re-deliver; the payload's `id` is the
/// dedup key. `ingest` skips a payload whose id already exists as a `DoseEntry`, so a
/// re-delivered transfer never double-logs. `DoseEntry.id` is app-level unique,
/// which is exactly what this relies on.
///
/// ## Meds
/// A dose taken from the watch's My Meds names its slot (``WatchDosePayload/medSlot``)
/// and is logged as the phone card logs one: ``DoseEntry/medication(_:at:slotMinutes:)``
/// through `logBatch`, so it carries the med's product and background flag, ticks that
/// slot, and skips the ramp-down notifications and the recents chip. A med deleted or
/// changed on the phone meanwhile logs as a plain watch dose, as the wrist showed it.
///
/// The `WCSessionDelegate` calls ``ingest(_:in:)``; it is otherwise a pure seam,
/// unit-testable with a simulated payload and no watch.
@MainActor
enum WatchDoseReceiver {
    enum Outcome: Equatable {
        /// A new `DoseEntry` was logged; carries its id.
        case inserted(UUID)
        /// A payload with this id was already logged — skipped.
        case duplicate
        /// The med slot it checks off was already taken — skipped, so a wrist that
        /// hadn't heard of a dose logged on the phone can't log the med twice.
        case slotTaken
        /// The med slot was skipped on the phone, which the phone card won't tick
        /// either: a skip is sticky, so the dose would tick another of the med's
        /// slots, or none.
        case slotSkipped
        case staleJournal
    }

    /// Log a watch payload once. Deduped on `payload.id`.
    @discardableResult
    static func ingest(_ payload: WatchDosePayload, in context: ModelContext, journalGeneration: Int = 0) -> Outcome {
        guard JournalResetGeneration.accepts(payload, generation: journalGeneration) else { return .staleJournal }
        let id = payload.id
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return .duplicate
        }

        if let slot = payload.medSlot, let med = medication(forSlot: slot, among: meds(in: context)) {
            return ingestMed(payload, item: med.item, slotMinutes: med.slotMinutes, in: context)
        }

        // Prior entries feed the redose / cumulative-dose warnings, exactly as the
        // phone quick-log passes them. Fetched before insert so the new dose isn't in it.
        let recents = recentEntries(in: context)
        let entry = makeEntry(from: payload)
        DoseLogService.shared.log(entry, in: context, recentEntries: recents)

        // Fold the dose into the curated recents so a watch-logged drink becomes a
        // phone chip too — parity with the phone quick-log commit. The chip's amount is
        // the same canonical value the entry stored, not the watch's advisory number.
        recordRecent(payload, amount: entry.amount, in: context)
        return .inserted(id)
    }

    /// Reconstruct the `DoseEntry`. The `id` is assigned from the payload (the `DoseEntry`
    /// initializer doesn't take one — it defaults a fresh UUID), which is what makes the
    /// dedup fetch above meaningful. By-volume drink detail is set as first-class fields,
    /// matching the phone quick-log commit (no notes breadcrumb on this path).
    static func makeEntry(from payload: WatchDosePayload) -> DoseEntry {
        let entry = DoseEntry(
            substance: payload.substance,
            amount: canonicalAmount(for: payload),
            unit: payload.unit,
            route: RouteOfAdministration(rawValue: payload.route) ?? .oral,
            saltForm: payload.saltForm,
            isomer: payload.isomer,
            releaseForm: payload.releaseForm,
            productName: payload.productName,
            substanceUID: payload.substanceUID,
            displayNameSnapshot: payload.displayName,
            timestamp: payload.timestamp,
            timeZoneIdentifier: payload.timeZoneIdentifier ?? TimeZone.current.identifier,
            notes: payload.notes,
            volumeML: payload.volumeML,
            abv: payload.abv,
            drinkName: payload.drinkName,
        )
        entry.id = payload.id
        return entry
    }

    /// The canonical stored amount for a payload. A by-volume drink (volume + ABV present)
    /// is converted to grams with the real `ByVolumeDosing` conversion here, so the logged
    /// value never depends on the watch's display-only estimate; a mass dose is verbatim.
    private static func canonicalAmount(for payload: WatchDosePayload) -> Double {
        if let volumeML = payload.volumeML, let abv = payload.abv, volumeML > 0, abv > 0 {
            return ByVolumeDosing.grams(volumeML: volumeML, abv: abv)
        }
        return payload.amount
    }

    // MARK: - Meds

    private static func ingestMed(
        _ payload: WatchDosePayload, item: DailyDoseItem, slotMinutes: Int?, in context: ModelContext,
    ) -> Outcome {
        let zone = payload.timeZoneIdentifier
        switch occurrence(of: item, slotMinutes: slotMinutes, at: payload.timestamp, loggedIn: zone, in: context)?.state {
        case .logged: return .slotTaken
        case .skipped: return .slotSkipped
        default: break
        }

        // A transfer can wake the app before the launch prewarm, and a cold library read
        // stalls the main actor: then the dose goes without the library's title, as a
        // Take from the Today's Meds widget does, and the live session without its match.
        let warm = SubstanceStore.shared.isBatchCacheWarm
        let entry = warm
            ? DoseEntry.medication(item, at: payload.timestamp, slotMinutes: slotMinutes)
            : DoseEntry(medication: item, timestamp: payload.timestamp, slotMinutes: slotMinutes)
        entry.id = payload.id
        entry.timeZoneIdentifier = zone ?? entry.timeZoneIdentifier
        let matched = warm ? SubstanceLibrary.lookup(item.substance).flatMap {
            $0.name.lowercased() == item.substance.lowercased() ? $0 : nil
        } : nil
        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        // No deferredBookkeeping, as on the phone card: routine medications skip the
        // ramp-down notifications on purpose.
        DoseLogService.shared.logBatch([(entry, matched)], colors: colors, in: context)
        return .inserted(payload.id)
    }

    private static func meds(in context: ModelContext) -> [DailyDoseItem] {
        (try? context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    /// The med and reminder time a watch slot id names (``ManifestMedSlot/id``), or nil
    /// once no med has that slot.
    private static func medication(forSlot id: String, among items: [DailyDoseItem]) -> (item: DailyDoseItem, slotMinutes: Int?)? {
        for item in items where !item.isAsNeeded {
            let slots: [Int?] = item.reminderTimesMinutes.isEmpty ? [nil] : item.reminderTimesMinutes
            for slotMinutes in slots where ManifestMedSlot.id(of: item, slotMinutes: slotMinutes) == id {
                return (item, slotMinutes)
            }
        }
        return nil
    }

    /// The occurrence of `item`'s slot at `slotMinutes` on the journal day `date` falls
    /// in on the clock of `zone`, as a dose's own day is read. Reconciled first, so a
    /// dose the phone logged moments ago counts.
    private static func occurrence(
        of item: DailyDoseItem, slotMinutes: Int?, at date: Date, loggedIn zone: String?, in context: ModelContext,
    ) -> RoutineOccurrence? {
        RoutineOccurrenceService.reconcile(in: context)
        let day = Calendar.current.journalDay(for: date, loggedIn: zone, boundaryHour: Calendar.sessionDayBoundaryHour)
        let key = RoutineOccurrenceService.slotKey(
            substance: item.substance, substanceUID: item.substanceUID, route: item.route, slotMinutes: slotMinutes,
        )
        let occurrences = (try? context.fetch(FetchDescriptor<RoutineOccurrence>(
            predicate: #Predicate { $0.dueDay == day },
        ))) ?? []
        return occurrences.first { RoutineOccurrenceService.slotKey(for: $0) == key }
    }

    // MARK: - Untaking a med

    enum UntakeOutcome: Equatable {
        /// The dose with this id was removed.
        case removed(UUID)
        /// No dose ticks that slot any more — nothing to remove.
        case nothingToRemove
        case staleJournal
    }

    /// Remove the dose a watch untick names. An untick of the watch's own tick
    /// (``WatchMedUntake/entryID``) removes that dose or nothing: a tick the phone never
    /// logged — withdrawn, or refused because the slot was taken already — must not cost
    /// the dose that did tick the slot. An untick of a slot the phone ticked removes the
    /// dose that ticked it that day, never another dose of the med.
    @discardableResult
    static func untake(_ untake: WatchMedUntake, in context: ModelContext, journalGeneration: Int = 0) -> UntakeOutcome {
        guard JournalResetGeneration.accepts(untake, generation: journalGeneration) else { return .staleJournal }
        guard let entry = entry(untakenBy: untake, in: context) else { return .nothingToRemove }
        let id = entry.id
        SessionEditingService.shared.delete(entry, in: context)
        return .removed(id)
    }

    private static func entry(untakenBy untake: WatchMedUntake, in context: ModelContext) -> DoseEntry? {
        if let id = untake.entryID { return entry(id, in: context) }
        let items = meds(in: context)
        guard let med = medication(forSlot: untake.medSlot, among: items),
              let occurrence = occurrence(
                  of: med.item, slotMinutes: med.slotMinutes, at: untake.timestamp, loggedIn: untake.timeZoneIdentifier, in: context,
              ), occurrence.state == .logged,
              let dose = occurrence.satisfyingEntryID.flatMap({ entry($0, in: context) }) else { return nil }
        // Meds sharing a slot key share its occurrence, so a dose of one ticks them all:
        // unticked on another's row, that dose stays.
        let own = ManifestMedSlot.id(of: dose, slotMinutes: med.slotMinutes)
        if own != untake.medSlot, medication(forSlot: own, among: items) != nil { return nil }
        return dose
    }

    private static func entry(_ id: UUID, in context: ModelContext) -> DoseEntry? {
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func recentEntries(in context: ModelContext) -> [DoseEntry] {
        var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 25
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func recordRecent(_ payload: WatchDosePayload, amount: Double, in context: ModelContext) {
        let fixedOrder = UserDefaults.standard.bool(forKey: QuickLogManager.fixedOrderDefaultsKey)
        QuickLogManager.record(
            [QuickLogManager.LoggedDose(
                substance: payload.substance,
                route: RouteOfAdministration(rawValue: payload.route) ?? .oral,
                amount: amount,
                unit: payload.unit,
                volumeML: payload.volumeML,
                abv: payload.abv,
                drinkName: payload.drinkName,
                emoji: payload.emoji,
                substanceUID: payload.substanceUID,
                isomer: payload.isomer,
                releaseForm: payload.releaseForm,
                saltForm: payload.saltForm,
                productName: payload.productName,
            )],
            fixedOrder: fixedOrder,
            context: context,
        )
    }
}
