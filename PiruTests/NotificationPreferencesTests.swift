import Foundation
import SwiftData
import Testing
import UserNotifications
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
        #expect(NotificationType.nextDose.rawValue == "nextDose")
        #expect(NotificationType.inventory.rawValue == "inventory")
        #expect(NotificationType.allCases.count == 9)
    }

    @Test
    func `Identifier grammar is piru-notif dot type dot anchor dot ordinal`() {
        #expect(NotificationType.comedown.identifier(anchor: "ABC") == "piru.notif.comedown.ABC")
        #expect(NotificationType.hydration.identifier(anchor: "ABC", ordinal: "2") == "piru.notif.hydration.ABC.2")
        #expect(NotificationType.phase.identifier(anchor: "ABC", ordinal: "peak") == "piru.notif.phase.ABC.peak")
        #expect(
            NotificationType.routineFollowUp.identifier(anchor: "morning", ordinal: "20260718.1")
                == "piru.notif.routineFollowUp.morning.20260718.1",
        )
        // Every built identifier must match its own type's cancel prefix.
        for type in NotificationType.allCases {
            #expect(type.identifier(anchor: "x").hasPrefix(type.identifierPrefix))
        }
    }

    @Test
    func `Cancel prefixes cover the current grammar plus the legacy set`() {
        // The exact strings the schedulers build identifiers from — if one of
        // these drifts, disabling a type stops cancelling its notifications.
        // Legacy entries are the transition sweep for pre-grammar pending.
        #expect(NotificationType.comedown.identifierPrefixes == ["piru.notif.comedown.", "rampDown_"])
        #expect(NotificationType.hydration.identifierPrefixes == ["piru.notif.hydration.", "hydration"])
        #expect(NotificationType.sleep.identifierPrefixes == ["piru.notif.sleep.", "sleepReminder_"])
        #expect(NotificationType.phase.identifierPrefixes == ["piru.notif.phase.", "phaseAlert_"])
        #expect(NotificationType.cumulative.identifierPrefixes == ["piru.notif.cumulative.", "cumulativeDose_"])
        #expect(NotificationType.routine.identifierPrefixes == ["piru.notif.routine.", "routineReminder_"])
        #expect(NotificationType.routineFollowUp.identifierPrefixes == ["piru.notif.routineFollowUp.", "routineFollowUp_"])
        #expect(NotificationType.nextDose.identifierPrefixes == ["piru.notif.nextDose."])
        #expect(NotificationType.inventory.identifierPrefixes == ["piru.notif.inventory.", "inventoryLowStock_"])
    }

    // MARK: - Time Sensitive

    @Test
    func `Time Sensitive defaults on for eligible types and toggles through the mirror`() throws {
        let defaults = makeDefaults()

        // Pre-configure defaults: eligible types are time-sensitive, others never.
        #expect(NotificationPreferencesStore.interruptionLevel(for: .routine, defaults: defaults) == .timeSensitive)
        #expect(NotificationPreferencesStore.interruptionLevel(for: .cumulative, defaults: defaults) == .timeSensitive)
        #expect(NotificationPreferencesStore.interruptionLevel(for: .hydration, defaults: defaults) == .active)

        let store = NotificationPreferencesStore()
        try store.configure(container: makeContainer(), defaults: defaults)
        store.setTimeSensitive(.routine, false)
        #expect(!store.isTimeSensitiveEnabled(.routine))
        #expect(NotificationPreferencesStore.interruptionLevel(for: .routine, defaults: defaults) == .active)
        #expect(NotificationPreferencesStore.interruptionLevel(for: .routineFollowUp, defaults: defaults) == .timeSensitive)

        // Ineligible types ignore writes.
        store.setTimeSensitive(.hydration, true)
        #expect(!store.isTimeSensitiveEnabled(.hydration))
    }

    // MARK: - Quiet hours

    @Test
    func `Quiet hours window matches inside, outside, wrap, and disabled`() {
        let defaults = makeDefaults()
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        }

        // Disabled → never quiet.
        #expect(!NotificationPreferencesStore.isInQuietHours(at(3), defaults: defaults))

        let store = NotificationPreferencesStore()
        do {
            let container = try ModelContainer(
                for: Schema(StoreRecovery.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
            )
            store.configure(container: container, defaults: defaults)
        } catch {
            Issue.record("container: \(error)")
            return
        }

        // Wrapping window 23:00 → 07:00 (the defaults).
        store.setQuietHours(enabled: true)
        #expect(NotificationPreferencesStore.isInQuietHours(at(23, 30), defaults: defaults))
        #expect(NotificationPreferencesStore.isInQuietHours(at(3), defaults: defaults))
        #expect(!NotificationPreferencesStore.isInQuietHours(at(7), defaults: defaults))
        #expect(!NotificationPreferencesStore.isInQuietHours(at(12), defaults: defaults))

        // Non-wrapping window 13:00 → 15:00.
        store.setQuietHours(enabled: true, startMinutes: 13 * 60, endMinutes: 15 * 60)
        #expect(NotificationPreferencesStore.isInQuietHours(at(14), defaults: defaults))
        #expect(!NotificationPreferencesStore.isInQuietHours(at(12), defaults: defaults))
        #expect(!NotificationPreferencesStore.isInQuietHours(at(15), defaults: defaults))
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

    // Satisfaction moved to the occurrence record — see RoutineOccurrenceTests.
}
