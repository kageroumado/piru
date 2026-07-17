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
        // The name to *show* in copy — the brand the dose was logged as
        // ("Concerta"), so a notification never reverts to "Methylphenidate".
        let displayName = DoseTitle.resolve(for: entry)

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
            displayName: displayName,
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
                displayName: displayName,
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
            displayName: DoseTitle.resolve(for: entry),
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
                // Tapping the reminder lands in quick-log with this routine's
                // items already staged (handled by DoseNotificationDelegate).
                if let link = routineDeepLink(name: routine.name) {
                    content.userInfo = [Self.deepLinkUserInfoKey: link.absoluteString]
                }

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

    // MARK: - Inventory low-stock

    /// Deliver a one-shot low-stock (or out-of-stock) alert for an inventory
    /// item. De-duping is owned by `InventoryService` via the item's
    /// `lowStockNotified` flag, so this just builds and posts the request.
    ///
    /// Delivered immediately (`trigger: nil`); iOS suppresses banners while the
    /// app is foregrounded — the alert then surfaces on the Lock/Home screen the
    /// next time the user leaves the app, which is the intended "you've run low"
    /// nudge for a threshold crossed by an in-app log.
    static func inventoryLowStock(
        substance: String,
        remaining: Double,
        unit: String,
        isOut: Bool,
        itemID: UUID,
    ) {
        Task {
            guard await RampDownScheduler.requestPermissionIfNeeded() else { return }
            let content = UNMutableNotificationContent()
            if isOut {
                content.title = String(localized: "Out of \(substance)")
                content.body = String(localized: "You're out of \(substance). Restock when you can.")
            } else {
                content.title = String(localized: "Running low on \(substance)")
                content.body = String(localized: "\(remaining.doseFormatted) \(unit) of \(substance) left.")
            }
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: inventoryNotificationIdentifier(itemID),
                content: content,
                trigger: nil,
            ))
        }
    }

    /// Clear any pending or already-delivered low-stock alert for an item —
    /// called when the user stops tracking it, so a stale "running low" banner
    /// doesn't linger on the Lock Screen for something they no longer track.
    static func cancelInventoryLowStock(itemID: UUID) {
        let identifier = inventoryNotificationIdentifier(itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static let inventoryLowStockPrefix = "inventoryLowStock_"

    private static func inventoryNotificationIdentifier(_ id: UUID) -> String {
        inventoryLowStockPrefix + id.uuidString
    }

    // MARK: - Deep links

    nonisolated static let deepLinkUserInfoKey = "deepLink"

    /// `piru://quicklog?routine=<name>` — URLComponents handles the
    /// percent-encoding for arbitrary routine names.
    private nonisolated static func routineDeepLink(name: String) -> URL? {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = "quicklog"
        components.queryItems = [URLQueryItem(name: "routine", value: name)]
        return components.url
    }
}

// MARK: - Notification Delegate

/// Routes notification taps. A notification carrying a `piru://` URL in
/// `userInfo[deepLink]` lands at that destination through the same codec the
/// URL scheme uses. Registered once at app init (the center holds the
/// delegate weakly, hence the shared instance).
final class DoseNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DoseNotificationDelegate()

    /// The completion-handler variant, NOT the async one: UIKit runs its
    /// snapshot/state-restoration work synchronously when the handler is
    /// invoked and asserts it's on the main thread — the async variant resumes
    /// on the caller's (background) executor and crashes with SIGABRT in
    /// `_updateStateRestorationArchiveForBackgroundEvent`.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void,
    ) {
        // Extract before hopping — UNNotificationResponse is not Sendable.
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let link = response.notification.request.content
            .userInfo[DoseNotificationManager.deepLinkUserInfoKey] as? String

        DispatchQueue.main.async {
            defer { completionHandler() }
            // Only the default tap action navigates; dismissals do nothing.
            guard isDefaultAction,
                  let link,
                  let url = URL(string: link),
                  let outcome = DeepLink.decode(url)
            else { return }
            AppNavigator.shared.apply(outcome)
        }
    }
}
