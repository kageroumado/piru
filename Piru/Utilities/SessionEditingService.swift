import SwiftData
import SwiftUI

/// The one home for changing a logged dose: delete, retime and edit, each with
/// the full set of side effects (session bounds, the live session / Live
/// Activity snapshot, pending reminders, the change signal, deferred
/// bookkeeping). Every screen that changes a dose calls these.
///
/// Env-injected so `DayEntryRow` invokes them directly. Never hand the row
/// parent closures instead: closures defeat SwiftUI's view-value comparison, so
/// the row would re-evaluate, and re-run its heavy substance resolve, on every
/// unrelated detail-screen toggle (graph expand, timeline enlarge, any sheet).
/// Behind this stable env reference the row is `Equatable` on its display value
/// alone and SwiftUI skips it when nothing it shows changed.
///
/// The transient `*ToAdjustTime` / `*ToMove` / `*ToRecolor` intents are written
/// by a row's context-menu action and observed by `SessionDetailView` to drive
/// its sheets; the mutations run against the passed `ModelContext`.
@MainActor
@Observable
final class SessionEditingService {
    static let shared = SessionEditingService()

    /// A request to recolor a substance — `Identifiable` so it drives a
    /// `.sheet(item:)` without a closure binding.
    struct RecolorRequest: Identifiable {
        let id = UUID()
        let substanceName: String
    }

    /// Set by a row action; `SessionDetailView` presents the matching sheet.
    var entryToAdjustTime: DoseEntry?
    var entryToMove: DoseEntry?
    var recolorRequest: RecolorRequest?

    /// One-shot intent set by a row's Edit action just before it pushes the
    /// entry detail; `EntryDetailView` consumes it on appear and opens in edit
    /// mode. Transient by design — never persisted, so a restored navigation
    /// stack always opens the detail in read mode.
    var pendingEditEntryID: UUID?

    private init() {}

    func requestAdjustTime(_ entry: DoseEntry) {
        entryToAdjustTime = entry
    }

    func requestEdit(_ entry: DoseEntry) {
        pendingEditEntryID = entry.id
    }
    func requestMove(_ entry: DoseEntry) {
        entryToMove = entry
    }
    func requestRecolor(_ substanceName: String) {
        recolorRequest = RecolorRequest(substanceName: substanceName)
    }

    /// Delete a dose, drop its pending reminders, and keep the live session /
    /// Live Activity snapshot in sync. Colors are fetched from the context so
    /// the row doesn't have to thread a `@Query` array through.
    func delete(_ entry: DoseEntry, in context: ModelContext) {
        // Capture before delete — the entry is invalid afterwards.
        let id = entry.id
        let name = entry.substance
        let timestamp = entry.timestamp
        let session = entry.session

        DoseNotificationManager.doseDeleted(entryID: id, timestamp: timestamp)
        withAnimation {
            context.delete(entry)
        }
        session?.refreshDoseBounds()

        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        ActiveSessionManager.shared.removeDose(
            id: id,
            substanceName: name,
            timestamp: timestamp,
            allColors: colors,
        )
        DoseLogService.shared.changed()
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: [name], in: context)
    }

    /// `entry`'s timestamp moved from `previous`: bring its session's bounds, the
    /// live session / Live Activity snapshot and its pending reminders to the
    /// new time, then signal the change. Returns at once when the time stands.
    func retimed(_ entry: DoseEntry, from previous: Date, in context: ModelContext) {
        guard previous != entry.timestamp else { return }
        resync(entry, previousTimestamp: previous, substance: SubstanceLibrary.lookup(entry.substance), in: context)
    }

    /// Write `draft` onto `entry`, then re-sync everything that reads the dose
    /// outside SwiftData. `substance` is the entry's resolved record: it supplies
    /// the alias units, the by-volume capability and the PSID. Returns `false`,
    /// writing nothing, for a draft that cannot commit.
    func commit(_ draft: EntryDraft, to entry: DoseEntry, substance: Substance?, in context: ModelContext) -> Bool {
        guard draft.canCommit else { return false }
        let previousTimestamp = entry.timestamp
        let previousMeal = entry.meal

        write(draft, to: entry, substance: substance)
        resync(
            entry,
            previousTimestamp: previousTimestamp,
            mealChanged: previousMeal != entry.meal,
            substance: substance,
            in: context,
        )
        return true
    }

    /// The amount and unit a draft stores. A colloquial alias ("drink") is
    /// normalized to its canonical physical unit so cumulative dose, level chips
    /// and PK scaling see the right number. An unknown dose has no number to
    /// normalize: it stores 0 in the draft unit.
    private func storedDose(for draft: EntryDraft, substance: Substance?) -> (amount: Double, unit: String) {
        guard !draft.isUnknownDose, let parsed = draft.parsedAmount else { return (0, draft.unit) }
        if let alias = substance?.unitAliases.first(where: { $0.label == draft.unit }) {
            return (parsed * alias.amountPerUnit, alias.unit)
        }
        return (parsed, draft.unit)
    }

    private func write(_ draft: EntryDraft, to entry: DoseEntry, substance: Substance?) {
        let stored = storedDose(for: draft, substance: substance)
        // A component of a liquid combination, or a solution of a substance
        // with no by-volume editor, keeps its recorded volume while its amount
        // and unit stand; once either changes, the volume no longer describes
        // the dose.
        let keepsRecordedVolume = (entry.combinationName != nil || substance?.byVolumeDosing == nil) && entry.volumeML != nil
            && !draft.isUnknownDose && stored.amount == entry.amount && stored.unit == entry.unit

        entry.amount = stored.amount
        entry.unit = stored.unit
        entry.route = draft.route
        entry.saltForm = draft.saltForm
        entry.isomer = draft.isomer
        entry.substanceUID = substance?.substanceUID
        // An edit keeps the substance and its release form and can change only
        // the isomer, but the snapshot composes across both, so a Focalin XR
        // dose stays "Dexmethylphenidate XR".
        entry.displayNameSnapshot = DoseTitle.snapshot(canonicalName: entry.substance, isomer: draft.isomer, releaseForm: entry.releaseForm)
        entry.timestamp = draft.timestamp
        entry.isUnknownDose = draft.isUnknownDose
        entry.isApproximate = draft.isApproximate && !draft.isUnknownDose
        entry.notes = draft.notes.isEmpty ? nil : draft.notes
        // By-volume metadata is set for a dose logged as a drink and cleared
        // otherwise, including for an unknown dose, whose volume and strength
        // are the unknowns.
        if !keepsRecordedVolume {
            let keepsVolume = draft.byVolumeMode && !draft.isUnknownDose
            entry.volumeML = keepsVolume ? draft.enteredVolumeML : nil
            entry.abv = keepsVolume ? draft.enteredABV : nil
            entry.drinkName = keepsVolume ? draft.trimmedDrinkName : nil
        }
        entry.tags = Array(Set(draft.tags + TagExtractor.extractTags(from: draft.notes)))
        entry.locationName = draft.location?.name
        entry.latitude = draft.location?.latitude
        entry.longitude = draft.location?.longitude
        entry.meal = draft.route == .oral ? draft.meal : nil
        entry.injectionSite = draft.injectionSite.flatMap { site in
            InjectionSite.Area.offered(for: draft.route).contains(site.area) ? site : nil
        }
    }

    /// Carry a changed `entry` to everything that reads it outside SwiftData.
    private func resync(
        _ entry: DoseEntry,
        previousTimestamp: Date,
        mealChanged: Bool = false,
        substance: Substance?,
        in context: ModelContext,
    ) {
        entry.session?.refreshDoseBounds()

        // The session accessory and Live Activity read ActiveSessionManager's
        // snapshot of the dose.
        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        ActiveSessionManager.shared.updateDose(
            previousSubstanceName: entry.substance,
            previousTimestamp: previousTimestamp,
            entry: entry,
            substance: substance,
            tint: SubstancePalette.tint(for: entry.substance, tintMap: colors.tintMap),
            allColors: colors,
        )

        // Pending reminders are keyed to the old timestamp: a moved dose drops
        // them and reschedules from its new time.
        DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: previousTimestamp, mealChanged: mealChanged)

        // The tick every derived surface keys its rebuild on; the timeline
        // strip lays a moved dose out at its new time only after this.
        DoseLogService.shared.changed()
        // Inventory replays doses by time, routines match them to a day's slots
        // and the widgets print the latest dose's time, so a moved dose owes
        // the same off-screen pass as an edited or deleted one.
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: [entry.substance], in: context)
    }

    /// Split the owning session so `entry` and every later dose become a new
    /// session. Derives the session from the dose's relationship.
    func split(at entry: DoseEntry, in context: ModelContext) {
        guard let session = entry.session else { return }
        withAnimation { _ = SessionService.split(session, at: entry, in: context) }
    }
}

extension EnvironmentValues {
    @Entry var sessionEditingService: SessionEditingService = .shared
}
