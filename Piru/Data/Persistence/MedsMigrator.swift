import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "MedsMigrator")

/// One-time fold of the routine layer into per-med fields for the Meds
/// redesign (Specs/meds-reminders-redesign.md): each item inherits its
/// routine's reminder time and `remind` flag as `reminderTimesMinutes` /
/// `remind`, `isBackgroundMed` maps onto the Quiet tier, and the most common
/// routine follow-up cadence becomes the global Ask Again default.
///
/// Wired at app launch (`PiruApp`, before the reminder sync so folded state
/// is what gets scheduled), guarded by a one-shot flag — a user's post-fold
/// edits are never clobbered by a relaunch. `DoseRoutine` rows are left in
/// place (never delete a shipped `@Model`); they just stop being read.
@MainActor
enum MedsMigrator {
    private static let doneKey = "medsRoutineFoldDone"

    static func foldRoutinesIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }

        let routines = (try? context.fetch(FetchDescriptor<DoseRoutine>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let routinesByName = Dictionary(routines.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        for item in items {
            if let routine = routinesByName[item.category] {
                item.reminderTimesMinutes = routine.timeMinutes.map { [$0] } ?? []
                item.remind = routine.remind
            } else {
                item.reminderTimesMinutes = []
            }
            // Quiet tier: background meds opted in explicitly; supplements
            // fold in by library category (the same smart default the med
            // form applies) — otherwise a shipped user's 6-supplement
            // "Morning" routine would migrate from ONE routine notification
            // to six individual ones.
            if item.isBackgroundMed || isSupplement(item) {
                item.isQuiet = true
            }
        }

        // The global Ask Again default inherits the most common non-empty
        // routine cadence; users with no cadenced routines keep the [10]
        // default. Only set when the preferences record already exists — if
        // it doesn't, the store's lazy creation gives the same default.
        let cadences = routines.map(\.followUpMinutes).filter { !$0.isEmpty }
        if let record = (try? context.fetch(FetchDescriptor<NotificationPreferences>()))?.first,
           let common = Dictionary(grouping: cadences, by: { $0 })
           .max(by: { $0.value.count < $1.value.count })?.key {
            record.askAgainDefaultMinutes = common
        }

        // Mark done only after the folded state is on disk — the fold is
        // idempotent, so an unsaved run must retry on the next launch rather
        // than burn its one shot.
        do {
            try context.save()
            defaults.set(true, forKey: doneKey)
        } catch {
            logger.error("Routine fold save failed, will retry next launch: \(error)")
        }
    }

    private static func isSupplement(_ item: DailyDoseItem) -> Bool {
        SubstanceLibrary.lookup(item.substance)?.category == .supplement
    }
}
