import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("NotificationPreferencesStore", .serialized)
@MainActor
struct NotificationPreferencesStoreTests {
    /// A throwaway in-memory container using the full app schema (the pattern
    /// the other SwiftData suites use — single-entity in-memory containers
    /// proved flaky under the parallel runner).
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    /// A scratch `UserDefaults` suite so the mirror + legacy-flag reads never
    /// touch the real standard defaults (or another parallel test's).
    private func makeDefaults() -> UserDefaults {
        let name = "NotificationPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Seeding

    @Test
    func `Fresh install seeds shipped-behavior defaults`() throws {
        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: makeDefaults())

        // The three types that fired with no switch default on.
        #expect(store.isTypeEnabled(.comedown))
        #expect(store.isTypeEnabled(.routine))
        #expect(store.isTypeEnabled(.inventory))
        // The flag-gated session types default off (flags defaulted false).
        #expect(!store.isTypeEnabled(.hydration))
        #expect(!store.isTypeEnabled(.sleep))
        #expect(!store.isTypeEnabled(.phase))
        #expect(!store.isTypeEnabled(.cumulative))
        #expect(store.masterEnabled)
    }

    @Test
    func `Legacy wellness flag seeds hydration, sleep, and cumulative`() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "wellnessNotificationsEnabled")
        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: defaults)

        #expect(store.isTypeEnabled(.hydration))
        #expect(store.isTypeEnabled(.sleep))
        #expect(store.isTypeEnabled(.cumulative))
        #expect(!store.isTypeEnabled(.phase))
    }

    @Test
    func `Legacy phase flag seeds phase alone`() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "phaseNotificationsEnabled")
        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: defaults)

        #expect(store.isTypeEnabled(.phase))
        #expect(!store.isTypeEnabled(.hydration))
        #expect(!store.isTypeEnabled(.sleep))
        #expect(!store.isTypeEnabled(.cumulative))
    }

    @Test
    func `Seeding runs once — later flag changes don't override the record`() throws {
        let container = try makeContainer()
        let defaults = makeDefaults()
        let store = NotificationPreferencesStore()
        store.configure(container: container, defaults: defaults)
        #expect(!store.isTypeEnabled(.phase))

        // A user who turned phase alerts off must stay off, even if the
        // abandoned legacy flag later flips.
        defaults.set(true, forKey: "phaseNotificationsEnabled")
        let reloaded = NotificationPreferencesStore()
        reloaded.configure(container: container, defaults: defaults)
        #expect(!reloaded.isTypeEnabled(.phase))
    }

    // MARK: - Persistence

    @Test
    func `setEnabled persists across a reload`() throws {
        let container = try makeContainer()
        let defaults = makeDefaults()
        let store = NotificationPreferencesStore()
        store.configure(container: container, defaults: defaults)

        store.setEnabled(.hydration, true)
        store.setEnabled(.inventory, false)

        let reloaded = NotificationPreferencesStore()
        reloaded.configure(container: container, defaults: defaults)
        #expect(reloaded.isTypeEnabled(.hydration))
        #expect(!reloaded.isTypeEnabled(.inventory))
    }

    @Test
    func `Master posture persists and doesn't clobber per-type choices`() throws {
        let container = try makeContainer()
        let defaults = makeDefaults()
        let store = NotificationPreferencesStore()
        store.configure(container: container, defaults: defaults)

        store.setEnabled(.phase, true)
        store.setMasterEnabled(false)

        let reloaded = NotificationPreferencesStore()
        reloaded.configure(container: container, defaults: defaults)
        #expect(!reloaded.masterEnabled)
        #expect(reloaded.isTypeEnabled(.phase))
        #expect(!reloaded.isEffectivelyEnabled(.phase))
    }

    // MARK: - Scheduler gate (the UserDefaults mirror)

    @Test
    func `allows agrees with the store through the mirror`() throws {
        let defaults = makeDefaults()
        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: defaults)

        #expect(NotificationPreferencesStore.allows(.comedown, defaults: defaults))
        #expect(!NotificationPreferencesStore.allows(.hydration, defaults: defaults))

        store.setEnabled(.hydration, true)
        #expect(NotificationPreferencesStore.allows(.hydration, defaults: defaults))

        store.setEnabled(.comedown, false)
        #expect(!NotificationPreferencesStore.allows(.comedown, defaults: defaults))
    }

    @Test
    func `Master pause gates every type in the mirror`() throws {
        let defaults = makeDefaults()
        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: defaults)

        store.setMasterEnabled(false)
        for type in NotificationType.allCases {
            #expect(!NotificationPreferencesStore.allows(type, defaults: defaults))
        }

        store.setMasterEnabled(true)
        #expect(NotificationPreferencesStore.allows(.routine, defaults: defaults))
    }

    @Test
    func `allows falls back to shipped defaults before configure ever ran`() {
        let defaults = makeDefaults()
        #expect(NotificationPreferencesStore.allows(.comedown, defaults: defaults))
        #expect(NotificationPreferencesStore.allows(.routine, defaults: defaults))
        #expect(NotificationPreferencesStore.allows(.inventory, defaults: defaults))
        #expect(!NotificationPreferencesStore.allows(.hydration, defaults: defaults))
        #expect(!NotificationPreferencesStore.allows(.cumulative, defaults: defaults))
    }

    // MARK: - Type catalog

    @Test
    func `Raw values are stable wire format`() {
        #expect(NotificationType.comedown.rawValue == "comedown")
        #expect(NotificationType.hydration.rawValue == "hydration")
        #expect(NotificationType.sleep.rawValue == "sleep")
        #expect(NotificationType.phase.rawValue == "phase")
        #expect(NotificationType.cumulative.rawValue == "cumulative")
        #expect(NotificationType.routine.rawValue == "routine")
        #expect(NotificationType.routineFollowUp.rawValue == "routineFollowUp")
        #expect(NotificationType.inventory.rawValue == "inventory")
        #expect(NotificationType.allCases.count == 8)
    }

    @Test
    func `Cancel prefixes match the schedulers' identifier grammar`() {
        // The exact strings the schedulers build identifiers from — if one of
        // these drifts, disabling a type stops cancelling its notifications.
        #expect(NotificationType.comedown.identifierPrefixes == ["rampDown_"])
        #expect(NotificationType.hydration.identifierPrefixes == ["hydration"])
        #expect(NotificationType.sleep.identifierPrefixes == ["sleepReminder_"])
        #expect(NotificationType.phase.identifierPrefixes == ["phaseAlert_"])
        #expect(NotificationType.cumulative.identifierPrefixes == ["cumulativeDose_"])
        #expect(NotificationType.routine.identifierPrefixes == ["routineReminder_"])
        #expect(NotificationType.routineFollowUp.identifierPrefixes == ["routineFollowUp_"])
        #expect(NotificationType.inventory.identifierPrefixes == ["inventoryLowStock_"])
    }
}

@Suite("RoutineFollowUps")
@MainActor
struct RoutineFollowUpTests {
    /// Noon on a fixed day, so "today / past" math is deterministic.
    private let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: .now,
    )!

    // MARK: - Fire-date materialization

    @Test
    func `Slots cover the horizon and skip already-past times`() {
        // Routine at 9:00 with re-asks +10/+30, evaluated at noon: today's
        // slots are already past, so only the next two days remain.
        let slots = DoseNotificationManager.followUpFireDates(
            timeMinutes: 9 * 60, offsets: [10, 30], days: 3, skipToday: false, now: noon,
        )
        #expect(slots.count == 4)
        #expect(slots.allSatisfy { $0.fireDate > noon })
    }

    @Test
    func `Today's future slots are included when not satisfied`() {
        // Routine at 14:00, evaluated at noon: today contributes both slots.
        let slots = DoseNotificationManager.followUpFireDates(
            timeMinutes: 14 * 60, offsets: [10, 30], days: 3, skipToday: false, now: noon,
        )
        #expect(slots.count == 6)
        let todayKey = slots.first?.dayKey
        #expect(slots.count(where: { $0.dayKey == todayKey }) == 2)
    }

    @Test
    func `skipToday drops only today's slots`() {
        let all = DoseNotificationManager.followUpFireDates(
            timeMinutes: 14 * 60, offsets: [10], days: 3, skipToday: false, now: noon,
        )
        let skipped = DoseNotificationManager.followUpFireDates(
            timeMinutes: 14 * 60, offsets: [10], days: 3, skipToday: true, now: noon,
        )
        #expect(all.count == 3)
        #expect(skipped.count == 2)
        #expect(Set(skipped.map(\.dayKey)) == Set(all.dropFirst().map(\.dayKey)))
    }

    @Test
    func `Ordinals follow the offset order`() {
        let slots = DoseNotificationManager.followUpFireDates(
            timeMinutes: 14 * 60, offsets: [10, 30], days: 1, skipToday: false, now: noon,
        )
        #expect(slots.map(\.ordinal) == [0, 1])
        #expect(slots[0].fireDate < slots[1].fireDate)
    }

    // MARK: - Satisfaction inference

    private func makeItem(_ substance: String, routine: String) -> DailyDoseItem {
        let item = DailyDoseItem(substance: substance, amount: 10, unit: "mg")
        item.category = routine
        return item
    }

    @Test
    func `Routine with all due items logged today is satisfied`() {
        let items = [makeItem("Vitamin D3", routine: "Morning"), makeItem("Magnesium", routine: "Morning")]
        let entries = [
            DoseEntry(substance: "vitamin d3", amount: 4_000, unit: "IU"),
            DoseEntry(substance: "Magnesium", amount: 350, unit: "mg"),
        ]
        #expect(DoseNotificationManager.routineSatisfiedToday(named: "Morning", items: items, entries: entries))
    }

    @Test
    func `Partially logged routine keeps re-asking`() {
        let items = [makeItem("Vitamin D3", routine: "Morning"), makeItem("Magnesium", routine: "Morning")]
        let entries = [DoseEntry(substance: "Vitamin D3", amount: 4_000, unit: "IU")]
        #expect(!DoseNotificationManager.routineSatisfiedToday(named: "Morning", items: items, entries: entries))
    }

    @Test
    func `Routine with nothing due counts as satisfied`() {
        #expect(DoseNotificationManager.routineSatisfiedToday(named: "Morning", items: [], entries: []))
    }

    @Test
    func `Other routines' items don't satisfy this one`() {
        let items = [makeItem("Vitamin D3", routine: "Morning"), makeItem("Melatonin", routine: "Night")]
        let entries = [DoseEntry(substance: "Melatonin", amount: 1, unit: "mg")]
        #expect(!DoseNotificationManager.routineSatisfiedToday(named: "Morning", items: items, entries: entries))
    }
}
