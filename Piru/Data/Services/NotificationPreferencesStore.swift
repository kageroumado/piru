import Foundation
import Observation
import os
import SwiftData
import UserNotifications

// MARK: - Notification Type

/// Every kind of local notification the app can send — one case per
/// user-togglable row on the Notifications management screen.
///
/// The screen listing exactly these cases *is* the contract
/// (`Specs/notifications-system.md` §Honesty — no hidden senders): anything a
/// scheduler can fire must have a case here, and its schedule path must gate
/// on ``NotificationPreferencesStore/allows(_:defaults:)``.
nonisolated enum NotificationType: String, CaseIterable, Identifiable {
    /// Comedown / wear-off alert, armed per dose from its ramp-down screen.
    case comedown
    /// Timed hydration nudges during a session.
    case hydration
    /// Wind-down reminder after long stimulant/empathogen sessions.
    case sleep
    /// Onset / come-up / peak timing alerts.
    case phase
    /// Heads-up when a substance's rolling 12-hour total reaches a heavy range.
    case cumulative
    /// Daily repeating reminder per routine with "Remind Me" on.
    case routine
    /// Snooze-style re-ask a little after a routine reminder that hasn't
    /// been logged yet ("still need to log?").
    case routineFollowUp
    /// Low-stock / out-of-stock alert for tracked inventory items.
    case inventory

    var id: String {
        rawValue
    }

    /// Whether the type is on for a user who has never touched the screen.
    /// Mirrors shipped behavior: comedown, routine, and inventory fired with
    /// no switch (so they default on); the session types were gated behind
    /// flags that defaulted off until onboarding enabled them.
    var defaultEnabled: Bool {
        switch self {
        // Follow-ups also default on: they fire only for routines the user
        // explicitly gave an "ask again" cadence, so the toggle is a kill
        // switch, not an opt-in.
        case .comedown, .routine, .routineFollowUp, .inventory: true
        case .hydration, .sleep, .phase, .cumulative: false
        }
    }

    /// Prefixes of the pending-request identifiers this type schedules —
    /// disabling a type cancels everything matching them.
    var identifierPrefixes: [String] {
        switch self {
        // No underscore on hydration: covers both `hydration_` and `hydration2_`.
        case .comedown: ["\(RampDownScheduler.rampDownCategoryID)_"]
        case .hydration: [RampDownScheduler.hydrationCategoryID]
        case .sleep: ["\(RampDownScheduler.sleepCategoryID)_"]
        case .phase: ["\(RampDownScheduler.phaseCategoryID)_"]
        case .cumulative: ["\(RampDownScheduler.cumulativeCategoryID)_"]
        case .routine: [DoseNotificationManager.routineReminderPrefix]
        case .routineFollowUp: [DoseNotificationManager.routineFollowUpPrefix]
        case .inventory: [DoseNotificationManager.inventoryLowStockPrefix]
        }
    }
}

// MARK: - Store

/// Single home for notification enablement: which of the app's notification
/// types the user has turned on, plus the master pause switch.
///
/// Follows the `UserProfileStore` pattern — an `@Observable` singleton
/// wrapping the app's shared container, configured once at launch. The
/// durable source of truth is the ``NotificationPreferences`` SwiftData
/// record (so the setup rides the backup path); a write-through
/// `UserDefaults` mirror lets the nonisolated schedulers gate synchronously
/// from any context via ``allows(_:defaults:)``.
///
/// On first launch the record is seeded from the legacy two-flag shape
/// (`wellnessNotificationsEnabled` gated hydration + sleep + cumulative;
/// `phaseNotificationsEnabled` gated phase), then the flags are abandoned —
/// a user who turned phase alerts off stays off.
@Observable @MainActor
final class NotificationPreferencesStore {
    static let shared = NotificationPreferencesStore()

    private let logger = Logger(subsystem: "dev.yumeji.piru", category: "NotificationPrefs")

    // Persistence backing is `@ObservationIgnored` for the same reason as
    // UserProfileStore: observation-tracked SwiftData handles trap when the
    // graph mutates outside a view update. Views observe the published
    // values below; the record is the durable mirror.
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var record: NotificationPreferences?
    @ObservationIgnored private var defaults: UserDefaults = .standard

    /// `internal` so tests can build isolated instances against an in-memory
    /// container and a scratch `UserDefaults` suite; production uses ``shared``.
    init() {}

    // MARK: - Published state

    /// Master posture — `false` pauses everything without losing per-type choices.
    private(set) var masterEnabled = true

    /// The user's per-type choice (independent of ``masterEnabled``).
    private(set) var typeEnabled: [NotificationType: Bool] = [:]

    /// The user's choice for one type — what the management screen's row shows.
    func isTypeEnabled(_ type: NotificationType) -> Bool {
        typeEnabled[type] ?? type.defaultEnabled
    }

    /// Whether the type may actually fire (per-type choice AND master posture).
    func isEffectivelyEnabled(_ type: NotificationType) -> Bool {
        masterEnabled && isTypeEnabled(type)
    }

    // MARK: - Scheduler gate

    private nonisolated static let masterMirrorKey = "notificationMasterEnabled"

    private nonisolated static func mirrorKey(_ type: NotificationType) -> String {
        "notificationTypeEnabled_\(type.rawValue)"
    }

    /// Synchronous gate for the schedulers, readable from any isolation —
    /// backed by the `UserDefaults` write-through mirror, so it agrees with
    /// the SwiftData record after `configure` has run once.
    nonisolated static func allows(_ type: NotificationType, defaults: UserDefaults = .standard) -> Bool {
        let master = defaults.object(forKey: masterMirrorKey) as? Bool ?? true
        let enabled = defaults.object(forKey: mirrorKey(type)) as? Bool ?? type.defaultEnabled
        return master && enabled
    }

    // MARK: - Configuration

    /// Bind to the app's shared container. Call once at launch, before any
    /// view reads notification state. Idempotent. Creates + seeds the record
    /// on first run, then refreshes the mirror.
    func configure(container: ModelContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        let ctx = container.mainContext
        context = ctx
        record = (try? ctx.fetch(FetchDescriptor<NotificationPreferences>()))?.first
        if record == nil {
            record = seedRecord(into: ctx, from: defaults)
        }
        publishFromRecord()
        mirrorAll()
    }

    /// One-time adoption of the legacy flag shape into a fresh record.
    private func seedRecord(into ctx: ModelContext, from defaults: UserDefaults) -> NotificationPreferences {
        let seeded = NotificationPreferences()
        let wellness = defaults.object(forKey: "wellnessNotificationsEnabled") as? Bool ?? false
        let phase = defaults.object(forKey: "phaseNotificationsEnabled") as? Bool ?? false
        seeded.hydrationEnabled = wellness
        seeded.sleepEnabled = wellness
        seeded.cumulativeEnabled = wellness
        seeded.phaseEnabled = phase
        ctx.insert(seeded)
        save()
        logger.info("Seeded notification preferences (wellness=\(wellness), phase=\(phase))")
        return seeded
    }

    private func publishFromRecord() {
        guard let record else {
            masterEnabled = true
            typeEnabled = [:]
            return
        }
        masterEnabled = record.masterEnabled
        typeEnabled = Dictionary(uniqueKeysWithValues: NotificationType.allCases.map {
            ($0, record[keyPath: $0.recordKeyPath])
        })
    }

    private func mirrorAll() {
        defaults.set(masterEnabled, forKey: Self.masterMirrorKey)
        for type in NotificationType.allCases {
            defaults.set(isTypeEnabled(type), forKey: Self.mirrorKey(type))
        }
    }

    // MARK: - Mutations

    /// Persist a per-type choice. Disabling cancels the type's pending
    /// notifications; re-enabling re-arms only what repeats (routine
    /// reminders) — dose-anchored types re-arm on future doses, never
    /// retroactively.
    func setEnabled(_ type: NotificationType, _ value: Bool) {
        guard value != isTypeEnabled(type) else { return }
        typeEnabled[type] = value
        ensureRecord()[keyPath: type.recordKeyPath] = value
        save()
        defaults.set(value, forKey: Self.mirrorKey(type))
        reconcilePending(for: type, enabled: value)
    }

    /// Persist the master posture. Pausing cancels everything pending;
    /// resuming re-arms the repeating types.
    func setMasterEnabled(_ value: Bool) {
        guard value != masterEnabled else { return }
        masterEnabled = value
        ensureRecord().masterEnabled = value
        save()
        defaults.set(value, forKey: Self.masterMirrorKey)
        for type in NotificationType.allCases {
            reconcilePending(for: type, enabled: value && isTypeEnabled(type))
        }
    }

    // MARK: - Pending-queue reconciliation

    private func reconcilePending(for type: NotificationType, enabled: Bool) {
        if enabled {
            // Only the repeating type has anything to re-arm; everything else
            // schedules off future dose/stock events.
            if type == .routine || type == .routineFollowUp { resyncRoutineReminders() }
        } else {
            Self.removePending(withPrefixes: type.identifierPrefixes)
            // Keep the per-entry "alert active" chips honest — their pending
            // requests are gone.
            if type == .comedown { RampDownScheduler.clearActiveEntries() }
        }
    }

    private func resyncRoutineReminders() {
        guard let context else { return }
        DoseNotificationManager.syncRoutineReminders(in: context)
    }

    private nonisolated static func removePending(withPrefixes prefixes: [String]) {
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { id in
                prefixes.contains { id.hasPrefix($0) }
            }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Record lifecycle

    private func ensureRecord() -> NotificationPreferences {
        if let record { return record }
        let fresh = NotificationPreferences()
        if let context {
            context.insert(fresh)
        } else {
            logger.fault("NotificationPreferencesStore mutated before configure(container:); write will not persist")
            assertionFailure("NotificationPreferencesStore.configure(container:) must run before any mutation")
        }
        record = fresh
        return fresh
    }

    private func save() {
        do {
            try context?.save()
        } catch {
            logger.error("Failed to save notification preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Type ↔ record field mapping

private extension NotificationType {
    var recordKeyPath: ReferenceWritableKeyPath<NotificationPreferences, Bool> {
        switch self {
        case .comedown: \.comedownEnabled
        case .hydration: \.hydrationEnabled
        case .sleep: \.sleepEnabled
        case .phase: \.phaseEnabled
        case .cumulative: \.cumulativeEnabled
        case .routine: \.routineEnabled
        case .routineFollowUp: \.routineFollowUpEnabled
        case .inventory: \.inventoryEnabled
        }
    }
}
