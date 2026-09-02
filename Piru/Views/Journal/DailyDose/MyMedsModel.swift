import SwiftData
import SwiftUI

/// The My Meds card's derived and fetched state: today's checkable slots, the
/// adherence streak, and the interaction warnings a tap has to clear before it
/// logs. Held apart from the card so a streak landing or a warning check doesn't
/// re-evaluate every row, and so the card's own `@State` stays limited to UI
/// toggles.
@MainActor
@Observable
final class MyMedsModel {
    /// The past-year adherence streak — nil until fetched.
    private(set) var streak: Int?
    /// The warnings blocking `pendingSlots`, shown in the confirmation sheet.
    private(set) var interactionWarnings: [InteractionResult] = []
    /// The slots a blocked tap wants to log once the sheet is cleared.
    private(set) var pendingSlots: [MyMedsCard.MedSlot] = []

    /// Today's checkable dose slots: every due, non-PRN med × one of its reminder
    /// times (or a single "anytime" slot), carrying the state its occurrence row
    /// records. Earliest slots first.
    static func slots(items: [DailyDoseItem], occurrences: [RoutineOccurrence]) -> [MyMedsCard.MedSlot] {
        var slots: [MyMedsCard.MedSlot] = []
        let occurrencesByKey = Dictionary(
            occurrences.map { (RoutineOccurrenceService.slotKey(for: $0), $0) },
            uniquingKeysWith: { _, last in last },
        )
        for item in items where !item.isAsNeeded && AdherenceCalculator.isDue(item, on: .now) {
            let times = item.reminderTimesMinutes.sorted()
            let expected = max(1, times.count)
            for index in 0 ..< expected {
                let slotMinutes = times.indices.contains(index) ? times[index] : nil
                let key = RoutineOccurrenceService.slotKey(
                    substance: item.substance,
                    substanceUID: item.substanceUID,
                    route: item.route,
                    slotMinutes: slotMinutes,
                )
                let state: MyMedsCard.SlotState = switch occurrencesByKey[key]?.state {
                case .logged: .taken
                case .skipped: .skipped
                default: .pending
                }
                slots.append(MyMedsCard.MedSlot(
                    item: item,
                    time: slotMinutes,
                    index: index,
                    state: state,
                ))
            }
        }
        return slots.sorted { ($0.time ?? .max) < ($1.time ?? .max) }
    }

    /// The past-year streak — fetch, snapshot, and calendar walk all on
    /// ``DatabaseActor``, so the main actor never materializes a year of rows.
    func refreshStreak(items: [DailyDoseItem], container: ModelContainer) async {
        guard !items.isEmpty else { return }
        streak = await AdherenceStreakFetcher.currentStreak(container: container)
    }

    /// Whether the tapped slots may log straight away. When they may not, the
    /// blocking warnings and the slots are held for the confirmation sheet.
    ///
    /// See `LogMedicationsView.attemptLog`: only `.notable` and above may block.
    func mayLog(slots: [MyMedsCard.MedSlot], against recentEntries: [DoseEntry]) -> Bool {
        let names = slots.map(\.item.substance)
        let active = InteractionChecker.activeEntries(from: recentEntries)
        let warnings = InteractionChecker.checkBatch(names, against: active).admitted(.notable)
        guard !warnings.isEmpty else { return true }
        pendingSlots = slots
        interactionWarnings = warnings
        return false
    }

    func clearPending() {
        pendingSlots = []
        interactionWarnings = []
    }
}

/// The info lines' facts that need a store: each tracked med's supply
/// projection (a dose fetch per item, so refreshed on the dose-log revision
/// rather than per body pass) and the missed-notice dismissals.
@MainActor
@Observable
final class MyMedsInfoModel {
    private(set) var restock: MyMedsInfoLine?
    private var dismissedDayKeys: Set<String> = []

    private let defaults = UserDefaults(suiteName: "group.dev.yumeji.piru")

    func refresh(items: [DailyDoseItem], in context: ModelContext) {
        var projections: [MyMedsInfo.SupplyProjection] = []
        var seen = Set<UUID>()
        for item in items where !item.isAsNeeded {
            // A med scheduled without a salt still matches the salt-less
            // tracked supply; a salted schedule wants its own.
            guard let stock = InventoryService.find(substance: item.substance, saltForm: item.saltForm, in: context)
                ?? InventoryService.find(substance: item.substance, saltForm: nil, in: context),
                seen.insert(stock.id).inserted,
                let runOut = InventoryMath.runOut(for: stock, in: context)
            else { continue }
            let name = item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
            projections.append(MyMedsInfo.SupplyProjection(name: name, daysLeft: runOut.daysLeft, itemID: stock.id))
        }
        restock = MyMedsInfo.restock(from: projections)
        if let defaults {
            dismissedDayKeys = Set(defaults.stringArray(forKey: MissedNoticeDismissals.defaultsKey) ?? [])
        }
    }

    func isDismissed(_ dayKey: String) -> Bool {
        dismissedDayKeys.contains(dayKey)
    }

    func dismiss(_ dayKey: String) {
        dismissedDayKeys.insert(dayKey)
        if let defaults {
            MissedNoticeDismissals.dismiss(dayKey, in: defaults)
        }
    }
}
