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
    // MARK: - Authorization + category registry

    /// The single OS-permission entry point (spec §B): invoked from the
    /// management screen's header, onboarding's reminders step, and the
    /// explicit per-dose comedown arm — never lazily from a scheduling path.
    static func requestAuthorization() async -> Bool {
        await RampDownScheduler.requestPermissionIfNeeded()
    }

    /// Register every notification category once at launch — previously the
    /// only registration happened as a side effect of scheduling a comedown
    /// alert, which wiped the category set down to `rampDown` and left every
    /// other `categoryIdentifier` pointing at nothing. Actions land in a
    /// later stage; registering the categories now just makes each type a
    /// real, non-phantom citizen of the notification system.
    static func registerCategories() {
        let identifiers = [
            RampDownScheduler.rampDownCategoryID,
            RampDownScheduler.hydrationCategoryID,
            RampDownScheduler.sleepCategoryID,
            RampDownScheduler.cumulativeCategoryID,
            RampDownScheduler.phaseCategoryID,
            routineCategoryID,
            routineFollowUpCategoryID,
            inventoryCategoryID,
        ]
        let categories = identifiers.map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    nonisolated static let routineCategoryID = "routine"
    nonisolated static let routineFollowUpCategoryID = "routineFollowUp"
    nonisolated static let inventoryCategoryID = "inventory"

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
            entryID: entry.id,
            category: substance?.category,
            doseTime: entry.timestamp,
            duration: duration,
            recentStimHours: RampDownScheduler.stimulantSessionHours(from: recentEntries),
        )
        RampDownScheduler.schedulePhaseNotifications(
            entryID: entry.id,
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
                entryID: entry.id,
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
        cancelDoseNotifications(entryID: entry.id, timestamp: previousTimestamp)

        let substance = library(for: entry)
        let duration = substance?.resolveDuration(for: entry.route)
        RampDownScheduler.scheduleWellnessNotifications(
            entryID: entry.id,
            category: substance?.category,
            doseTime: entry.timestamp,
            duration: duration,
            recentStimHours: RampDownScheduler.stimulantSessionHours(from: recentEntries),
        )
        RampDownScheduler.schedulePhaseNotifications(
            entryID: entry.id,
            substanceName: entry.substance,
            doseTime: entry.timestamp,
            duration: duration,
            displayName: DoseTitle.resolve(for: entry),
        )
    }

    /// The dose is gone — so are its pending reminders. The timestamp rides
    /// along for the pre-grammar epoch-keyed pending items.
    static func doseDeleted(entryID: UUID, timestamp: Date) {
        cancelDoseNotifications(entryID: entryID, timestamp: timestamp)
    }

    private static func cancelDoseNotifications(entryID: UUID, timestamp: Date) {
        RampDownScheduler.cancelWellnessNotifications(entryID: entryID, doseTimestamp: timestamp)
        RampDownScheduler.cancelPhaseNotifications(entryID: entryID, doseTimestamp: timestamp)
    }

    // MARK: - Comedown (armed per dose from the ramp-down screen)

    /// Arm the comedown alert for a dose — the façade path RampDownView uses
    /// instead of driving the scheduler and its persistence by hand.
    static func armComedownAlert(entry: DoseEntry, duration: DurationProfile) {
        let entryKey = RampDownScheduler.entryKey(for: entry)
        RampDownScheduler.scheduleNotification(
            substanceName: entry.substance,
            initialAmount: entry.amount,
            unit: entry.unit,
            doseTime: entry.timestamp,
            duration: duration,
            entryKey: entryKey,
            category: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category,
            displayName: DoseTitle.resolve(for: entry),
        )
        RampDownScheduler.saveActiveEntry(entryKey)
    }

    /// Cancel a dose's armed comedown alert and forget its armed state.
    static func cancelComedownAlert(entry: DoseEntry) {
        let entryKey = RampDownScheduler.entryKey(for: entry)
        RampDownScheduler.cancelNotification(for: entryKey)
        RampDownScheduler.removeActiveEntry(entryKey)
    }

    private static func library(for entry: DoseEntry) -> Substance? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance.lowercased())
    }

    // MARK: - Routine reminders

    /// Reconcile the routine reminders from the store: fetches routines,
    /// items, and today's doses, then delegates to the value-based overload.
    /// The one entry point every "something routine-relevant changed" site
    /// calls — routine edits, dose commits, app foreground.
    static func syncRoutineReminders(in context: ModelContext) {
        let routines = (try? context.fetch(FetchDescriptor<DoseRoutine>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let dayStart = Calendar.current.startOfDay(for: .now)
        let predicate = #Predicate<DoseEntry> { $0.timestamp >= dayStart }
        let todaysEntries = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        syncRoutineReminders(routines: routines, items: items, todaysEntries: todaysEntries)
    }

    /// Reconcile the repeating routine reminders — one daily calendar
    /// notification per routine that has a time and "Remind Me" on — plus
    /// their snooze-style follow-ups. Also clears the legacy global
    /// `dailyDoseReminder_*` set the pre-routines screen scheduled.
    ///
    /// **Follow-ups** ("still need to log?") can't be repeating triggers:
    /// cancelling today's re-ask would cancel every future day's too. So they
    /// are materialized as one-shot requests over a short rolling horizon
    /// (``followUpHorizonDays``), re-derived on every sync — and today's are
    /// skipped when the routine is already satisfied
    /// (``routineSatisfiedToday(named:items:entries:on:)``).
    static func syncRoutineReminders(
        routines: [DoseRoutine],
        items: [DailyDoseItem],
        todaysEntries: [DoseEntry],
    ) {
        // With the type disabled, the sync degrades to a sweep: clear
        // anything pending, schedule nothing. Per-routine `remind` flags stay
        // untouched so re-enabling the type re-arms them.
        let remindersAllowed = NotificationPreferencesStore.allows(.routine)
        let followUpsAllowed = remindersAllowed && NotificationPreferencesStore.allows(.routineFollowUp)
        let active = remindersAllowed
            ? routines
            .filter { $0.remind && $0.timeMinutes != nil }
            .map { (name: $0.name, timeMinutes: $0.timeMinutes ?? 0) }
            : []

        // Snapshot the follow-up plan as plain values before the Task.
        var followUps: [FollowUpRequest] = []
        if followUpsAllowed {
            for routine in routines where routine.remind && routine.timeMinutes != nil && !routine.followUpMinutes.isEmpty {
                let satisfied = routineSatisfiedToday(named: routine.name, items: items, entries: todaysEntries)
                let slots = followUpFireDates(
                    timeMinutes: routine.timeMinutes ?? 0,
                    offsets: routine.followUpMinutes,
                    days: followUpHorizonDays,
                    skipToday: satisfied,
                    now: .now,
                )
                for slot in slots {
                    followUps.append(FollowUpRequest(
                        identifier: NotificationType.routineFollowUp.identifier(
                            anchor: routine.name.lowercased(),
                            ordinal: "\(slot.dayKey).\(slot.ordinal)",
                        ),
                        title: routine.name,
                        // A question, deliberately — a follow-up re-asks, it
                        // never implies the dose was taken or scolds.
                        body: String(localized: "Still need to log your \(routine.name) routine?"),
                        deepLink: routineDeepLink(name: routine.name)?.absoluteString,
                        fireDate: slot.fireDate,
                    ))
                }
            }
        }

        Task {
            let center = UNUserNotificationCenter.current()
            // Sweep both grammars: the current prefixes plus the legacy sets
            // (routine repeats fully self-migrate here on the first sync).
            let sweepPrefixes = NotificationType.routine.identifierPrefixes
                + NotificationType.routineFollowUp.identifierPrefixes
                + ["dailyDoseReminder"]
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { id in
                sweepPrefixes.contains { id.hasPrefix($0) }
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            // No permission gate here (an ambient-request site the spec
            // removes): requests added before the grant simply deliver once
            // the user allows notifications — the management screen's header
            // is the honest surface for that state.
            guard !active.isEmpty else { return }

            for routine in active {
                let content = UNMutableNotificationContent()
                content.title = routine.name
                content.body = String(localized: "Time for your \(routine.name) routine.")
                content.sound = .default
                content.categoryIdentifier = routineCategoryID
                // A routine and its follow-ups share a thread so the re-asks
                // stack under the reminder they follow.
                content.threadIdentifier = routineThreadIdentifier(name: routine.name)
                content.interruptionLevel = .timeSensitive
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

            for followUp in followUps {
                let interval = followUp.fireDate.timeIntervalSince(.now)
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = followUp.title
                content.body = followUp.body
                content.sound = .default
                content.categoryIdentifier = routineFollowUpCategoryID
                content.threadIdentifier = routineThreadIdentifier(name: followUp.title)
                content.interruptionLevel = .timeSensitive
                if let link = followUp.deepLink {
                    content.userInfo = [Self.deepLinkUserInfoKey: link]
                }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: followUp.identifier,
                    content: content,
                    trigger: trigger,
                ))
            }
        }
    }

    // Pre-grammar identifier prefixes, still swept/cancelled during the
    // transition (see `NotificationType.identifierPrefixes`). Delete a
    // release or two after the `piru.notif.` grammar ships.
    nonisolated static let legacyRoutineReminderPrefix = "routineReminder_"
    nonisolated static let legacyRoutineFollowUpPrefix = "routineFollowUp_"

    /// How many days of one-shot follow-ups to keep materialized. Deliberately
    /// short: every app open / dose commit / routine edit rolls the horizon
    /// forward, and a small window keeps well clear of iOS's 64-pending-
    /// request cap. If the app isn't opened for this many days the primary
    /// (repeating) reminder still fires — only the re-asks pause.
    private static let followUpHorizonDays = 3

    private static func routineReminderIdentifier(name: String) -> String {
        NotificationType.routine.identifier(anchor: name.lowercased())
    }

    private nonisolated static func routineThreadIdentifier(name: String) -> String {
        "piru.notif.thread.routine.\(name.lowercased())"
    }

    /// One planned follow-up notification, snapshotted as plain values.
    private struct FollowUpRequest {
        let identifier: String
        let title: String
        let body: String
        let deepLink: String?
        let fireDate: Date
    }

    /// Whether every item of the named routine that is *due today* already
    /// has a matching dose logged today — the "don't re-ask after it's
    /// logged" gate for follow-ups. A routine with nothing due counts as
    /// satisfied (there is nothing left to log). Partial logging keeps the
    /// re-ask alive for the remaining items.
    ///
    /// This is inference over today's entries — interim until the
    /// `RoutineOccurrence` subsystem (notifications spec §D) lands. Its worst
    /// failure mode is a redundant *question* ("still need to log?"), never a
    /// wrong assertion.
    static func routineSatisfiedToday(
        named name: String,
        items: [DailyDoseItem],
        entries: [DoseEntry],
        on date: Date = .now,
    ) -> Bool {
        let due = items.filter { $0.category == name && AdherenceCalculator.isDue($0, on: date) }
        guard !due.isEmpty else { return true }
        return due.allSatisfy { item in
            entries.contains { AdherenceCalculator.entryMatches(entry: $0, item: item) }
        }
    }

    /// The one-shot fire slots for a routine's follow-ups over the rolling
    /// horizon: `timeMinutes + offset` on each of the next `days` days,
    /// dropping already-past times and (when `skipToday`) all of today's.
    nonisolated static func followUpFireDates(
        timeMinutes: Int,
        offsets: [Int],
        days: Int,
        skipToday: Bool,
        now: Date,
        calendar: Calendar = .current,
    ) -> [(dayKey: String, ordinal: Int, fireDate: Date)] {
        let todayStart = calendar.startOfDay(for: now)
        var slots: [(dayKey: String, ordinal: Int, fireDate: Date)] = []
        for day in 0 ..< max(0, days) {
            if day == 0, skipToday { continue }
            guard let dayStart = calendar.date(byAdding: .day, value: day, to: todayStart) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let dayKey = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            for (ordinal, offset) in offsets.enumerated() {
                guard let fireDate = calendar.date(byAdding: .minute, value: timeMinutes + offset, to: dayStart),
                      fireDate > now else { continue }
                slots.append((dayKey: dayKey, ordinal: ordinal, fireDate: fireDate))
            }
        }
        return slots
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
        guard NotificationPreferencesStore.allows(.inventory) else { return }
        let content = UNMutableNotificationContent()
        if isOut {
            content.title = String(localized: "Out of \(substance)")
            content.body = String(localized: "You're out of \(substance). Restock when you can.")
        } else {
            content.title = String(localized: "Running low on \(substance)")
            content.body = String(localized: "\(remaining.doseFormatted) \(unit) of \(substance) left.")
        }
        content.sound = .default
        content.categoryIdentifier = inventoryCategoryID
        content.threadIdentifier = inventoryThreadIdentifier
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: inventoryNotificationIdentifier(itemID),
            content: content,
            trigger: nil,
        ))
    }

    /// Clear any pending or already-delivered low-stock alert for an item —
    /// called when the user stops tracking it, so a stale "running low" banner
    /// doesn't linger on the Lock Screen for something they no longer track.
    /// Removes both grammars' identifiers during the transition.
    static func cancelInventoryLowStock(itemID: UUID) {
        let identifiers = [
            inventoryNotificationIdentifier(itemID),
            legacyInventoryLowStockPrefix + itemID.uuidString,
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    nonisolated static let legacyInventoryLowStockPrefix = "inventoryLowStock_"

    private nonisolated static let inventoryThreadIdentifier = "piru.notif.thread.inventory"

    private static func inventoryNotificationIdentifier(_ id: UUID) -> String {
        NotificationType.inventory.identifier(anchor: id.uuidString)
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
