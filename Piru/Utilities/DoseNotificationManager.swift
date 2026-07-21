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
    /// other `categoryIdentifier` pointing at nothing.
    ///
    /// Actions: routine + follow-up get **Log** (opens the pre-filled Quick
    /// Log, same landing as the body tap) and **Skip Today** (a background
    /// action — marks the occurrences skipped and cancels the remaining
    /// re-asks *without launching the UI*, so dismissing a nag is
    /// friction-free). Comedown and next-dose get **View Timeline**.
    /// Inventory's Restock action waits on an inventory deep-link route.
    static func registerCategories() {
        let log = UNNotificationAction(
            identifier: logActionID,
            title: String(localized: "Log"),
            options: [.foreground],
        )
        let skip = UNNotificationAction(
            identifier: skipTodayActionID,
            title: String(localized: "Skip Today"),
            options: [],
        )
        let viewTimeline = UNNotificationAction(
            identifier: viewTimelineActionID,
            title: String(localized: "View Timeline"),
            options: [.foreground],
        )

        var categories: Set<UNNotificationCategory> = []
        for identifier in [routineCategoryID, routineFollowUpCategoryID] {
            categories.insert(UNNotificationCategory(
                identifier: identifier, actions: [log, skip], intentIdentifiers: [], options: [],
            ))
        }
        for identifier in [RampDownScheduler.rampDownCategoryID, nextDoseCategoryID] {
            categories.insert(UNNotificationCategory(
                identifier: identifier, actions: [viewTimeline], intentIdentifiers: [], options: [],
            ))
        }
        for identifier in [
            RampDownScheduler.hydrationCategoryID,
            RampDownScheduler.sleepCategoryID,
            RampDownScheduler.cumulativeCategoryID,
            RampDownScheduler.phaseCategoryID,
            inventoryCategoryID,
        ] {
            categories.insert(UNNotificationCategory(
                identifier: identifier, actions: [], intentIdentifiers: [], options: [],
            ))
        }
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    nonisolated static let routineCategoryID = "routine"
    nonisolated static let routineFollowUpCategoryID = "routineFollowUp"
    nonisolated static let nextDoseCategoryID = "nextDose"
    nonisolated static let inventoryCategoryID = "inventory"

    nonisolated static let logActionID = "piru.action.log"
    nonisolated static let skipTodayActionID = "piru.action.skipToday"
    nonisolated static let viewTimelineActionID = "piru.action.viewTimeline"

    // MARK: - Dose lifecycle

    /// Schedule the wellness + phase set (and run the cumulative-dose check,
    /// and the per-item next-dose reminder when a context is supplied) for a
    /// freshly logged dose. Doses logged in the past schedule nothing —
    /// every fire time is computed from the dose time and past intervals are
    /// skipped.
    static func doseLogged(entry: DoseEntry, recentEntries: [DoseEntry], in context: ModelContext? = nil) {
        let resolved = scheduleTimingReminders(for: entry, recentEntries: recentEntries, in: context)

        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: entry.substance,
            newAmount: entry.amount,
            unit: entry.unit,
            route: entry.route,
            existingEntries: recentEntries,
        )
        guard shouldAlert else { return }
        RampDownScheduler.scheduleCumulativeDoseNotification(
            entryID: entry.id,
            substanceName: entry.substance,
            totalAmount: total,
            unit: entry.unit,
            category: resolved.substance?.category,
            displayName: resolved.displayName,
        )
    }

    /// Resolve the dose's substance, duration, and display brand, then arm the
    /// timing reminders both a fresh log and a re-time share: wellness, phase,
    /// and — when a context is supplied — the opt-in next-dose window. Returns
    /// the resolved trio so a caller can layer its own alert (the
    /// cumulative-dose check) without repeating the heavy substance lookup.
    @discardableResult
    private static func scheduleTimingReminders(
        for entry: DoseEntry,
        recentEntries: [DoseEntry],
        in context: ModelContext?,
    ) -> (substance: Substance?, duration: DurationProfile?, displayName: String?) {
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
        if let context {
            scheduleNextDoseReminder(for: entry, duration: duration, displayName: displayName, in: context)
        }
        return (substance, duration, displayName)
    }

    // MARK: - Next-dose window reminder (spec §E)

    /// If the dose matches a daily-med item the user opted into next-dose
    /// reminders, schedule "your next dose window is open" at the model's
    /// redose time. Opt-in lives on the item — the app never guesses
    /// therapeutic vs. recreational intent.
    private static func scheduleNextDoseReminder(
        for entry: DoseEntry,
        duration: DurationProfile?,
        displayName: String?,
        in context: ModelContext,
    ) {
        guard NotificationPreferencesStore.allows(.nextDose), let duration else { return }
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let optedIn = items.contains { item in
            item.nextDoseReminder
                && item.route == entry.route
                && itemIdentityMatches(item: item, entry: entry)
        }
        guard optedIn else { return }

        let windowOpens = RampDownScheduler.comedownStartTime(doseTime: entry.timestamp, duration: duration)
        let interval = windowOpens.timeIntervalSince(.now)
        guard interval > 60 else { return }
        // A dose reminder — silenced inside the quiet window (spec §B).
        guard !NotificationPreferencesStore.isInQuietHours(windowOpens) else { return }

        let shownName = displayName ?? entry.substance
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Next-dose window — \(shownName)")
        // Honesty: a prompt and an estimate, never a directive (spec §Honesty).
        content.body = String(localized: "Enough time has passed since your last dose. This is a model estimate — follow your prescriber's schedule.")
        content.sound = .default
        content.categoryIdentifier = nextDoseCategoryID
        content.threadIdentifier = RampDownScheduler.sessionIdentifier(for: entry.timestamp)
        content.interruptionLevel = NotificationPreferencesStore.interruptionLevel(for: .nextDose)
        let linkTimestamp = Int(entry.timestamp.timeIntervalSince1970)
        content.userInfo = [
            deepLinkUserInfoKey: "\(DeepLink.scheme)://entry/\(linkTimestamp)?id=\(entry.id.uuidString)",
        ]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: NotificationType.nextDose.identifier(anchor: entry.id.uuidString),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false),
        ))
    }

    private static func itemIdentityMatches(item: DailyDoseItem, entry: DoseEntry) -> Bool {
        if let itemUID = item.substanceUID, let entryUID = entry.substanceUID {
            return itemUID == entryUID
        }
        return item.substance.lowercased() == entry.substance.lowercased()
    }

    /// The dose moved in time (edit, retime, move-to-session): wellness and
    /// phase reminders are keyed to the old timestamp, so cancel those and
    /// reschedule from the new time. A dose moved into the past schedules
    /// nothing — which is the fix for a backdated dose still pinging
    /// "Stay hydrated" at its original fire times. An armed comedown alert is
    /// re-armed at the dose's new comedown time (it's keyed by the stable
    /// entry id, so without this it would keep its stale fire time).
    static func doseRescheduled(
        entry: DoseEntry,
        previousTimestamp: Date,
        recentEntries: [DoseEntry] = [],
        in context: ModelContext? = nil,
    ) {
        guard previousTimestamp != entry.timestamp else { return }
        let wasArmed = RampDownScheduler.isActive(for: RampDownScheduler.entryKey(for: entry))
        cancelDoseNotifications(entryID: entry.id, timestamp: previousTimestamp)
        let resolved = scheduleTimingReminders(for: entry, recentEntries: recentEntries, in: context)
        if wasArmed, let duration = resolved.duration {
            armComedownAlert(entry: entry, duration: duration)
        }
    }

    /// The dose is gone — so are its pending reminders, including an armed
    /// comedown alert. The timestamp rides along for the pre-grammar
    /// epoch-keyed pending items.
    static func doseDeleted(entryID: UUID, timestamp: Date) {
        cancelDoseNotifications(entryID: entryID, timestamp: timestamp)
    }

    private static func cancelDoseNotifications(entryID: UUID, timestamp: Date) {
        RampDownScheduler.cancelWellnessNotifications(entryID: entryID, doseTimestamp: timestamp)
        RampDownScheduler.cancelPhaseNotifications(entryID: entryID, doseTimestamp: timestamp)
        // An armed comedown alert dies with its dose too — a missed cancel
        // here is exactly the stale-notification class this manager exists
        // to prevent (it would fire for a dose that no longer exists).
        RampDownScheduler.cancelNotification(for: entryID.uuidString)
        RampDownScheduler.removeActiveEntry(entryID.uuidString)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [NotificationType.nextDose.identifier(anchor: entryID.uuidString)],
        )
    }

    // MARK: - Comedown (armed per dose from the ramp-down screen)

    /// Arm the comedown alert for a dose — the façade path RampDownView uses
    /// instead of driving the scheduler and its persistence by hand.
    static func armComedownAlert(entry: DoseEntry, duration: DurationProfile) {
        let entryKey = RampDownScheduler.entryKey(for: entry)
        RampDownScheduler.scheduleNotification(
            substanceName: entry.substance,
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

    // MARK: - Med reminders

    /// Reconcile the med reminders from the store. The one entry point every
    /// "something med-relevant changed" site calls — med edits, dose commits,
    /// app foreground. Runs the occurrence reconciler first, so follow-up
    /// cancellation reads the durable record (spec §D), not a re-inference
    /// over raw dose scans.
    static func syncMedReminders(in context: ModelContext) {
        RoutineOccurrenceService.reconcile(in: context)
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        let satisfied = RoutineOccurrenceService.satisfiedSlotKeys(in: context)
        let askAgainDefault = (try? context.fetch(FetchDescriptor<NotificationPreferences>()))?
            .first?.askAgainDefaultMinutes ?? [10]
        syncMedReminders(items: items, satisfiedSlots: satisfied, askAgainDefault: askAgainDefault)
    }

    /// Mark a notification's remaining due slots skipped for today and cancel
    /// their follow-ups — the "Skip Today" action. `target` is the request's
    /// ``skipTargetUserInfoKey`` payload: `slot|<slotKey>` for one med's
    /// reminder, `group|<groupSlug>` for a grouped quiet-med reminder (the
    /// group expands to its members' slot keys at action time, so a med edited
    /// after scheduling still resolves correctly). Runs headless (no UI
    /// launch); needs ``modelContainer`` to have been set at app init.
    static func skipMedsToday(target: String) {
        guard let context = modelContainer?.mainContext else { return }
        if target.hasPrefix("slot|") {
            RoutineOccurrenceService.skipToday(slotKeys: [String(target.dropFirst(5))], in: context)
        } else if target.hasPrefix("group|"), let group = MedTimeGroup(slug: String(target.dropFirst(6))) {
            let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
            var keys: Set<String> = []
            for item in items where item.isQuiet && !item.isAsNeeded {
                for time in item.reminderTimesMinutes where MedTimeGroup.group(forMinutes: time) == group {
                    keys.insert(RoutineOccurrenceService.slotKey(
                        substance: item.substance, substanceUID: item.substanceUID,
                        route: item.route, slotMinutes: time,
                    ))
                }
            }
            RoutineOccurrenceService.skipToday(slotKeys: keys, in: context)
        }
        syncMedReminders(in: context)
    }

    /// The app's shared container, set once at launch — the notification
    /// delegate's background actions (Skip Today) have no view hierarchy to
    /// pull a context from.
    static var modelContainer: ModelContainer?

    /// One planned primary reminder, snapshotted as plain values.
    private struct PrimaryRequest {
        let identifier: String
        let title: String
        let body: String
        let threadID: String
        let skipTarget: String
        let deepLink: String?
        let timeMinutes: Int
        /// `nil` = a repeating daily calendar trigger at ``timeMinutes``
        /// (daily-frequency meds); a date = a one-shot materialized on a
        /// specific due day (non-daily frequencies, which a repeating
        /// calendar trigger cannot express).
        let fireDate: Date?
    }

    /// Reconcile the repeating med reminders (Specs/meds-reminders-redesign.md):
    /// one daily calendar notification per (med × reminder time) for regular
    /// meds, and ONE grouped notification per time-of-day for quiet meds
    /// ("Morning supplements (4)", firing at the group's earliest time) — the
    /// Quiet tier's whole point, and what keeps many supplements from eating
    /// the 64-pending-request cap. Plus their snooze-style follow-ups.
    ///
    /// **Follow-ups** ("still need to log?") can't be repeating triggers:
    /// cancelling today's re-ask would cancel every future day's too. So they
    /// are materialized as one-shot requests over a short rolling horizon
    /// (``followUpHorizonDays``), re-derived on every sync — and today's are
    /// skipped when the slot's occurrence record says it's satisfied. The
    /// cadence is the med's Ask Again override when set, else the global
    /// default.
    private static func syncMedReminders(
        items: [DailyDoseItem],
        satisfiedSlots: Set<String>,
        askAgainDefault: [Int],
    ) {
        // With the type disabled, the sync degrades to a sweep: clear
        // anything pending, schedule nothing. Per-med `remind` flags stay
        // untouched so re-enabling the type re-arms them.
        let remindersAllowed = NotificationPreferencesStore.allows(.routine)
        let followUpsAllowed = remindersAllowed && NotificationPreferencesStore.allows(.routineFollowUp)

        var primaries: [PrimaryRequest] = []
        var followUps: [FollowUpRequest] = []

        func appendFollowUps(
            anchor: String,
            timeMinutes: Int,
            cadence: [Int],
            satisfied: Bool,
            title: String,
            body: String,
            threadID: String,
            skipTarget: String,
            deepLink: String?,
        ) {
            guard followUpsAllowed, !cadence.isEmpty else { return }
            let slots = followUpFireDates(
                timeMinutes: timeMinutes,
                offsets: cadence,
                days: followUpHorizonDays,
                skipToday: satisfied,
                now: .now,
            )
            // Re-asks are silenced inside the quiet window (safety warnings
            // and user-timed primaries are exempt; spec §B).
            for slot in slots where !NotificationPreferencesStore.isInQuietHours(slot.fireDate) {
                followUps.append(FollowUpRequest(
                    identifier: NotificationType.routineFollowUp.identifier(
                        anchor: anchor,
                        ordinal: "\(slot.dayKey).\(slot.ordinal)",
                    ),
                    title: title,
                    body: body,
                    threadID: threadID,
                    skipTarget: skipTarget,
                    deepLink: deepLink,
                    fireDate: slot.fireDate,
                ))
            }
        }

        if remindersAllowed {
            let scheduled = items.filter { !$0.isAsNeeded && $0.remind && !$0.reminderTimesMinutes.isEmpty }
            let calendar = Calendar.current
            let now = Date.now

            /// Per-(med × time) scheduling, frequency-aware: daily meds get a
            /// repeating calendar trigger; every other frequency materializes
            /// one-shots on its next due days (a repeating trigger cannot
            /// express weekly/every-other-day/monthly, and an ungated repeat
            /// would nag on off-days a med isn't even due). Used for regular
            /// meds and for non-daily quiet meds (which can't ride the daily
            /// repeating group).
            func schedulePerMed(_ item: DailyDoseItem) {
                let name = item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
                let doseText = "\(item.amount.doseFormatted) \(item.unit)"
                let cadence = item.askAgainOverrideMinutes ?? askAgainDefault
                for time in item.reminderTimesMinutes.sorted() {
                    // `sortOrder` disambiguates two meds sharing an identity
                    // + route + time — without it their requests collide to
                    // one identifier and the second silently wins.
                    let anchor = "\(anchorSlug(for: item)).\(item.sortOrder).\(time)"
                    let slotKey = RoutineOccurrenceService.slotKey(
                        substance: item.substance, substanceUID: item.substanceUID,
                        route: item.route, slotMinutes: time,
                    )
                    let satisfied = satisfiedSlots.contains(slotKey)
                    let threadID = medThreadIdentifier(anchor: anchorSlug(for: item))
                    let skipTarget = "slot|\(slotKey)"
                    let deepLink = groupDeepLink(slug: MedTimeGroup.group(forMinutes: time).slug)?.absoluteString
                    let title = name
                    let body = String(localized: "Time to log \(name) — \(doseText).")
                    // A question, deliberately — a follow-up re-asks, it
                    // never implies the dose was taken or scolds.
                    let followUpBody = String(localized: "Still need to log \(name)?")

                    if item.frequency == .daily {
                        primaries.append(PrimaryRequest(
                            identifier: NotificationType.routine.identifier(anchor: anchor),
                            title: title,
                            body: body,
                            threadID: threadID,
                            skipTarget: skipTarget,
                            deepLink: deepLink,
                            timeMinutes: time,
                            fireDate: nil,
                        ))
                        appendFollowUps(
                            anchor: anchor,
                            timeMinutes: time,
                            cadence: cadence,
                            satisfied: satisfied,
                            title: title,
                            body: followUpBody,
                            threadID: threadID,
                            skipTarget: skipTarget,
                            deepLink: deepLink,
                        )
                        continue
                    }

                    // Non-daily: one-shots on the next few due days — always
                    // scanned far enough ahead that a monthly med's next
                    // reminder exists even if the app isn't opened between
                    // due days. Today's are skipped once the slot is
                    // satisfied (a luxury the repeating trigger can't offer).
                    for day in nextDueDays(for: item, limit: duePrimariesPerSlot, now: now) {
                        let isToday = calendar.isDate(day, inSameDayAs: now)
                        if isToday, satisfied { continue }
                        let parts = calendar.dateComponents([.year, .month, .day], from: day)
                        let dayKey = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                        if let fireDate = calendar.date(byAdding: .minute, value: time, to: day), fireDate > now {
                            primaries.append(PrimaryRequest(
                                identifier: NotificationType.routine.identifier(anchor: anchor, ordinal: dayKey),
                                title: title,
                                body: body,
                                threadID: threadID,
                                skipTarget: skipTarget,
                                deepLink: deepLink,
                                timeMinutes: time,
                                fireDate: fireDate,
                            ))
                        }
                        guard followUpsAllowed, !cadence.isEmpty else { continue }
                        for (ordinal, offset) in cadence.enumerated() {
                            guard let fireDate = calendar.date(byAdding: .minute, value: time + offset, to: day),
                                  fireDate > now,
                                  !NotificationPreferencesStore.isInQuietHours(fireDate) else { continue }
                            followUps.append(FollowUpRequest(
                                identifier: NotificationType.routineFollowUp.identifier(
                                    anchor: anchor,
                                    ordinal: "\(dayKey).\(ordinal)",
                                ),
                                title: title,
                                body: followUpBody,
                                threadID: threadID,
                                skipTarget: skipTarget,
                                deepLink: deepLink,
                                fireDate: fireDate,
                            ))
                        }
                    }
                }
            }

            // Regular meds: one primary per (med × time), frequency-aware.
            for item in scheduled where !item.isQuiet {
                schedulePerMed(item)
            }

            // Quiet meds: one grouped repeating primary per time-of-day
            // group, firing at the group's earliest reminder time. Only
            // daily-frequency meds can ride a repeating group; non-daily
            // quiet meds (a weekly B12, say) fall back to their own
            // due-day one-shots — at their cadence that's one quiet
            // notification a week, not spam.
            let quiet = scheduled.filter(\.isQuiet)
            for item in quiet where item.frequency != .daily {
                schedulePerMed(item)
            }
            let dailyQuiet = quiet.filter { $0.frequency == .daily }
            for group in MedTimeGroup.allCases {
                let members: [(item: DailyDoseItem, time: Int)] = dailyQuiet.flatMap { item in
                    item.reminderTimesMinutes
                        .filter { MedTimeGroup.group(forMinutes: $0) == group }
                        .map { (item, $0) }
                }
                guard let fireTime = members.map(\.time).min() else { continue }
                let names = members.map { $0.item.productName ?? CustomSubstanceStore.shared.displayName(for: $0.item.substance) }
                let uniqueNames = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                let groupLabel = String(localized: group.label)
                let title = String(localized: "\(groupLabel) supplements (\(uniqueNames.count))")
                let anchor = "group.\(group.slug)"
                let threadID = medThreadIdentifier(anchor: anchor)
                let skipTarget = "group|\(group.slug)"
                let deepLink = groupDeepLink(slug: group.slug)?.absoluteString
                let allSatisfied = members.allSatisfy { member in
                    satisfiedSlots.contains(RoutineOccurrenceService.slotKey(
                        substance: member.item.substance, substanceUID: member.item.substanceUID,
                        route: member.item.route, slotMinutes: member.time,
                    ))
                }
                primaries.append(PrimaryRequest(
                    identifier: NotificationType.routine.identifier(anchor: anchor),
                    title: title,
                    body: uniqueNames.joined(separator: ", "),
                    threadID: threadID,
                    skipTarget: skipTarget,
                    deepLink: deepLink,
                    timeMinutes: fireTime,
                    fireDate: nil,
                ))
                appendFollowUps(
                    anchor: anchor,
                    timeMinutes: fireTime,
                    cadence: askAgainDefault,
                    satisfied: allSatisfied,
                    title: title,
                    body: String(localized: "Still need your \(groupLabel.localizedLowercase) supplements?"),
                    threadID: threadID,
                    skipTarget: skipTarget,
                    deepLink: deepLink,
                )
            }
        }

        // Follow-ups are the compressible tail of the SHARED 64-pending-
        // request budget (next-dose, cumulative, inventory, and comedown
        // requests draw from the same pool). Keep only the nearest ones so
        // primaries and the other schedulers always fit; the horizon rolls
        // forward on every sync, so trimmed re-asks reappear as their day
        // approaches.
        followUps.sort { $0.fireDate < $1.fireDate }
        if followUps.count > maxFollowUpRequests {
            followUps = Array(followUps.prefix(maxFollowUpRequests))
        }

        let primariesToAdd = primaries
        let followUpsToAdd = followUps
        Task {
            let center = UNUserNotificationCenter.current()
            // Sweep both grammars: the current prefixes plus the legacy sets
            // (routine-era requests fully self-migrate here on the first sync).
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
            for primary in primariesToAdd {
                let content = medReminderContent(
                    title: primary.title,
                    body: primary.body,
                    type: .routine,
                    category: routineCategoryID,
                    threadID: primary.threadID,
                    skipTarget: primary.skipTarget,
                    deepLink: primary.deepLink,
                )
                let trigger: UNNotificationTrigger
                if let fireDate = primary.fireDate {
                    let interval = fireDate.timeIntervalSince(.now)
                    guard interval > 0 else { continue }
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                } else {
                    var components = DateComponents()
                    components.hour = primary.timeMinutes / 60
                    components.minute = primary.timeMinutes % 60
                    trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                }
                try? await center.add(UNNotificationRequest(
                    identifier: primary.identifier,
                    content: content,
                    trigger: trigger,
                ))
            }

            for followUp in followUpsToAdd {
                let interval = followUp.fireDate.timeIntervalSince(.now)
                guard interval > 0 else { continue }
                let content = medReminderContent(
                    title: followUp.title,
                    body: followUp.body,
                    type: .routineFollowUp,
                    category: routineFollowUpCategoryID,
                    threadID: followUp.threadID,
                    skipTarget: followUp.skipTarget,
                    deepLink: followUp.deepLink,
                )
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
    /// forward, and a small window limits pressure on iOS's 64-pending-request
    /// cap — though many routines × follow-ups can still approach it, and iOS
    /// drops the overflow silently (primaries enqueue first, so re-asks are
    /// what would drop). If the app isn't opened for this many days the
    /// primary (repeating) reminder still fires — only the re-asks pause.
    private static let followUpHorizonDays = 3

    /// How many upcoming due days a non-daily med materializes one-shot
    /// primaries for. Two keeps the next reminder scheduled across even a
    /// monthly gap without opening the app, at trivial budget cost.
    private static let duePrimariesPerSlot = 2

    /// The nearest cap on materialized follow-ups (nearest-first) — see the
    /// budget note in `syncMedReminders`.
    private static let maxFollowUpRequests = 30

    /// The next due days (as `startOfDay`) for a med's schedule, scanned far
    /// enough ahead to cover a monthly cadence.
    private static func nextDueDays(for item: DailyDoseItem, limit: Int, now: Date) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var result: [Date] = []
        for offset in 0 ..< 62 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if AdherenceCalculator.isDue(item, on: day) {
                result.append(day)
                if result.count == limit { break }
            }
        }
        return result
    }

    /// A med's stable identifier fragment: its identity key plus route,
    /// sanitized to the notification-identifier grammar's alphabet.
    private static func anchorSlug(for item: DailyDoseItem) -> String {
        let raw = "\(item.identityKey)-\(item.route.rawValue)".lowercased()
        let sanitized = raw.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(sanitized)
    }

    private nonisolated static func medThreadIdentifier(anchor: String) -> String {
        "piru.notif.thread.med.\(anchor)"
    }

    /// Shared content for a med reminder and its snooze-style follow-up: both
    /// carry the skip target for the Skip Today action, share the med's (or
    /// quiet group's) notification thread so re-asks stack under the reminder
    /// they follow, and fire time-sensitive when the user allows it.
    private nonisolated static func medReminderContent(
        title: String,
        body: String,
        type: NotificationType,
        category: String,
        threadID: String,
        skipTarget: String,
        deepLink: String?,
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = threadID
        content.interruptionLevel = NotificationPreferencesStore.interruptionLevel(for: type)
        var userInfo: [String: Any] = [skipTargetUserInfoKey: skipTarget]
        if let deepLink { userInfo[deepLinkUserInfoKey] = deepLink }
        content.userInfo = userInfo
        return content
    }

    /// One planned follow-up notification, snapshotted as plain values.
    private struct FollowUpRequest {
        let identifier: String
        let title: String
        let body: String
        let threadID: String
        let skipTarget: String
        let deepLink: String?
        let fireDate: Date
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
    /// Skip target carried on med-reminder + follow-up requests so the Skip
    /// Today action knows whose occurrences to mark without launching UI:
    /// `slot|<slotKey>` or `group|<groupSlug>`.
    nonisolated static let skipTargetUserInfoKey = "skipTarget"

    /// `piru://quicklog?routine=<groupSlug>` — lands in quick-log with that
    /// time-of-day group's meds staged (the query key stays `routine` for
    /// deep-link compatibility).
    private nonisolated static func groupDeepLink(slug: String) -> URL? {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = "quicklog"
        components.queryItems = [URLQueryItem(name: "routine", value: slug)]
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
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let link = userInfo[DoseNotificationManager.deepLinkUserInfoKey] as? String
        let skipTarget = userInfo[DoseNotificationManager.skipTargetUserInfoKey] as? String

        DispatchQueue.main.async {
            defer { completionHandler() }
            switch actionIdentifier {
            // Skip Today runs headless: mark the occurrences, cancel the
            // remaining re-asks, never launch the UI.
            case DoseNotificationManager.skipTodayActionID:
                if let skipTarget {
                    DoseNotificationManager.skipMedsToday(target: skipTarget)
                }
            // The body tap and every foreground action (Log, View Timeline)
            // land at the notification's deep link; dismissals do nothing.
            case UNNotificationDefaultActionIdentifier,
                 DoseNotificationManager.logActionID,
                 DoseNotificationManager.viewTimelineActionID:
                guard let link,
                      let url = URL(string: link),
                      let outcome = DeepLink.decode(url)
                else { return }
                AppNavigator.shared.apply(outcome)
            default:
                break
            }
        }
    }
}
