import Foundation
import SwiftData
import UserNotifications

/// Single owner of dose-related local notifications and the *conditions*
/// under which they should exist.
///
/// Views report entry lifecycle events — logged, time edited, deleted — and
/// the manager reconciles the pending-notification queue to match.
/// `RampDownScheduler` keeps the PK timing math and message copy; nothing
/// outside this type should pair a schedule call with its matching cancel by
/// hand — a missed cancel is exactly how stale "Stay hydrated" reminders
/// survived a backdate edit.
@MainActor
enum DoseNotificationManager {
    // MARK: - Dose lifecycle

    /// Schedule the wellness + phase set (and run the cumulative-dose check)
    /// for a freshly logged dose. Doses logged in the past schedule nothing —
    /// every fire time is computed from the dose time and past intervals are
    /// skipped.
    static func doseLogged(entry: DoseEntry, recentEntries: [DoseEntry]) {
        let substance = library(for: entry)
        let duration = substance?.resolveDuration(for: entry.route)

        RampDownScheduler.scheduleWellnessNotifications(
            substanceName: entry.substance,
            category: substance?.category,
            doseTime: entry.timestamp,
            duration: duration,
            recentStimHours: RampDownScheduler.stimulantSessionHours(from: recentEntries),
        )
        RampDownScheduler.schedulePhaseNotifications(
            substanceName: entry.substance,
            doseTime: entry.timestamp,
            duration: duration,
        )

        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: entry.substance,
            newAmount: entry.amount,
            unit: entry.unit,
            route: entry.route,
            existingEntries: recentEntries,
        )
        if shouldAlert {
            RampDownScheduler.scheduleCumulativeDoseNotification(
                substanceName: entry.substance,
                totalAmount: total,
                unit: entry.unit,
                category: substance?.category,
            )
        }
    }

    /// The dose moved in time (edit, retime, move-to-session): wellness and
    /// phase reminders are keyed to the old timestamp, so cancel those and
    /// reschedule from the new time. A dose moved into the past schedules
    /// nothing — which is the fix for a backdated dose still pinging
    /// "Stay hydrated" at its original fire times.
    static func doseRescheduled(entry: DoseEntry, previousTimestamp: Date, recentEntries: [DoseEntry] = []) {
        guard previousTimestamp != entry.timestamp else { return }
        cancelDoseNotifications(timestamp: previousTimestamp)

        let substance = library(for: entry)
        let duration = substance?.resolveDuration(for: entry.route)
        RampDownScheduler.scheduleWellnessNotifications(
            substanceName: entry.substance,
            category: substance?.category,
            doseTime: entry.timestamp,
            duration: duration,
            recentStimHours: RampDownScheduler.stimulantSessionHours(from: recentEntries),
        )
        RampDownScheduler.schedulePhaseNotifications(
            substanceName: entry.substance,
            doseTime: entry.timestamp,
            duration: duration,
        )
    }

    /// The dose is gone — so are its pending reminders.
    static func doseDeleted(timestamp: Date) {
        cancelDoseNotifications(timestamp: timestamp)
    }

    private static func cancelDoseNotifications(timestamp: Date) {
        RampDownScheduler.cancelWellnessNotifications(for: timestamp)
        RampDownScheduler.cancelPhaseNotifications(for: timestamp)
    }

    private static func library(for entry: DoseEntry) -> Substance? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance.lowercased())
    }

    // MARK: - Routine reminders

    /// Reconcile the repeating routine reminders with the source of truth:
    /// one daily calendar notification per routine that has a time and
    /// "Remind Me" on. Also clears the legacy global `dailyDoseReminder_*`
    /// set the pre-routines screen scheduled.
    static func syncRoutineReminders(routines: [DoseRoutine]) {
        let active = routines
            .filter { $0.remind && $0.timeMinutes != nil }
            .map { (name: $0.name, timeMinutes: $0.timeMinutes ?? 0) }

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix(routineReminderPrefix) || $0.hasPrefix("dailyDoseReminder")
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            guard !active.isEmpty else { return }
            guard await RampDownScheduler.requestPermissionIfNeeded() else { return }

            for routine in active {
                let content = UNMutableNotificationContent()
                content.title = routine.name
                content.body = String(localized: "Time for your \(routine.name) routine.")
                content.sound = .default

                var components = DateComponents()
                components.hour = routine.timeMinutes / 60
                components.minute = routine.timeMinutes % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                try? await center.add(UNNotificationRequest(
                    identifier: routineReminderIdentifier(name: routine.name),
                    content: content,
                    trigger: trigger,
                ))
            }
        }
    }

    private static let routineReminderPrefix = "routineReminder_"

    private static func routineReminderIdentifier(name: String) -> String {
        routineReminderPrefix + name.lowercased()
    }
}
