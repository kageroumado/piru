import Foundation
import os
import UserNotifications

// MARK: - Logger

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "RampDown")

// MARK: - Ramp Down & Wellness Notification Scheduler

/// Schedules harm-reduction local notifications around logged doses.
///
/// The scheduler registers four notification categories — ``rampDownCategoryID``
/// (comedown alerts), ``hydrationCategoryID`` (hydration nudges),
/// ``sleepCategoryID`` (sleep reminders for stimulant sessions), and
/// ``cumulativeCategoryID`` (heads-up when cumulative dose hits the heavy
/// range) — each with their respective actions.
///
/// Doses logged within a rolling 6-hour window share a notification
/// `threadIdentifier` so iOS groups them into a single session in
/// Notification Center. Cumulative-dose alerts and other wellness reminders
/// are deduplicated within a 90-minute window against the pending request
/// queue to avoid spamming the user during a multi-dose session.
///
/// Comedown alerts are keyed off a stable per-entry string (see
/// ``entryKey(for:)``) derived from the dose's substance and timestamp, so
/// the "alert scheduled" state and the pending notification identifier both
/// survive app relaunches.
///
/// Depends on `UNUserNotificationCenter` authorization — call
/// ``requestPermissionIfNeeded()`` before scheduling.
enum RampDownScheduler {
    // MARK: - Timing Constants

    /// Time-interval constants used by the scheduler.
    private nonisolated enum Timing {
        /// 6-hour grouping window for session-aware notification threading.
        static let sessionWindow: TimeInterval = 6 * 3_600
        /// Default window used when checking the pending queue for duplicate
        /// wellness/cumulative notifications of the same prefix.
        static let pendingDedupWindow: TimeInterval = 90 * 60
        /// Default hydration reminder delay when no duration profile is available.
        static let hydrationInitialDelay: TimeInterval = 3_600
        /// Upper bound on the hydration peak-start trigger
        /// (`min(peakStart, peakStartCap)`).
        static let peakStartCap: TimeInterval = 3_600
        /// Minimum spacing between the first and second hydration reminders.
        static let hydrationReminderSpacing: TimeInterval = 1_800
        /// Sleep-reminder delay when the user is already 10+ hours into a
        /// stimulant session at log time.
        static let extendedStimSleepDelay: TimeInterval = 2 * 3_600
        /// Default delay before firing the stimulant-session sleep reminder.
        static let stimulantSleepDelay: TimeInterval = 12 * 3_600
        /// Don't bother scheduling the default stimulant sleep reminder unless
        /// it's at least this far in the future.
        static let minSleepReminderLeadTime: TimeInterval = 3_600
        /// Sliding window for evaluating cumulative dose totals.
        static let cumulativeDoseWindow: TimeInterval = 12 * 3_600
    }

    // MARK: - Notification Category IDs

    static let rampDownCategoryID = "rampDown"
    private static let hydrationCategoryID = "hydration"
    private static let sleepCategoryID = "sleepReminder"
    private static let cumulativeCategoryID = "cumulativeDose"
    private static let phaseCategoryID = "phaseAlert"

    /// Groups doses within 6-hour windows into the same notification thread.
    static func sessionIdentifier(for doseTime: Date) -> String {
        let startOfDay = Calendar.current.startOfDay(for: doseTime)
        let window = Int(doseTime.timeIntervalSince(startOfDay) / Timing.sessionWindow)
        return "session_\(Int(startOfDay.timeIntervalSince1970))_\(window)"
    }

    /// Whether automatic wellness notifications (hydration, sleep) are enabled.
    static var wellnessNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "wellnessNotificationsEnabled") as? Bool ?? false
    }

    /// Whether per-phase notifications (onset / come-up / peak) are enabled.
    static var phaseNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "phaseNotificationsEnabled") as? Bool ?? false
    }

    // MARK: - Comedown Timing

    /// The moment the comedown begins (start of the offset phase).
    ///
    /// This is when the user most needs recovery reminders — peak has ended
    /// and the descent is beginning.
    static func comedownStartTime(
        doseTime: Date,
        duration: DurationProfile,
    ) -> Date {
        let boundaries = duration.phaseBoundaries
        let peakEndMinutes = boundaries.peakEnd
        let comeupMinutes = boundaries.comeupEnd - boundaries.onsetEnd

        let redoseMinutes = peakEndMinutes - comeupMinutes
        return doseTime.addingTimeInterval(max(0, redoseMinutes) * 60)
    }

    /// Suggested redose amount (kept for users who explicitly want it)
    static func suggestedRedoseAmount(_ initialAmount: Double) -> Double {
        (initialAmount * 0.33).rounded(toPlaces: 1)
    }

    // MARK: - Notifications

    /// Stable per-entry key for the comedown alert. Derived from the dose's
    /// content rather than `persistentModelID.hashValue` — `Hashable` is
    /// seeded per process, so a hash-based key changes on every launch and
    /// orphans both the persisted "active" flag and the pending notification.
    static func entryKey(for entry: DoseEntry) -> String {
        "\(entry.substance)-\(entry.timestamp.timeIntervalSince1970)"
    }

    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await (try? center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Schedule the main comedown notification — now with harm-reduction messaging
    static func scheduleNotification(
        substanceName: String,
        initialAmount _: Double,
        unit _: String,
        doseTime: Date,
        duration: DurationProfile,
        entryKey: String,
        category: SubstanceCategory? = nil,
    ) {
        let center = UNUserNotificationCenter.current()

        let notifCategory = UNNotificationCategory(
            identifier: rampDownCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction,
        )
        center.setNotificationCategories([notifCategory])

        let comedownTime = comedownStartTime(doseTime: doseTime, duration: duration)
        let timeInterval = comedownTime.timeIntervalSince(.now)

        guard timeInterval > 5 else {
            logger.warning("Comedown time already passed (\(Int(timeInterval))s ago)")
            return
        }

        let message = comedownMessage(for: category)

        let content = UNMutableNotificationContent()
        content.title = message.title.replacingOccurrences(of: "{name}", with: substanceName)
        content.body = message.body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = rampDownCategoryID
        content.threadIdentifier = sessionIdentifier(for: doseTime)

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false,
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(entryKey: entryKey),
            content: content,
            trigger: trigger,
        )

        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule comedown notification: \(error.localizedDescription)")
            } else {
                let mins = Int(timeInterval / 60)
                logger.info("Comedown notification scheduled in \(mins) min for \(substanceName)")
            }
        }
    }

    static func cancelNotification(for entryKey: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(entryKey: entryKey)],
        )
    }

    private static func notificationIdentifier(entryKey: String) -> String {
        "\(rampDownCategoryID)_\(entryKey)"
    }

    // MARK: - Wellness Notifications (Auto-scheduled on dose log)

    /// Schedule hydration and sleep reminders after logging a dose.
    ///
    /// Called automatically from QuickLogView / EntryFormView. The schedule
    /// rules are:
    ///
    /// - **Hydration #1**: fires at `min(peakStart, peakStartCap)` —
    ///   whichever is sooner. With no duration profile, falls back to a
    ///   1-hour delay.
    /// - **Hydration #2**: fires at the start of the offset phase, but only
    ///   if it's at least 30 minutes after the first reminder.
    /// - **Sleep reminder (stimulants/empathogens only)**: fires 12 hours
    ///   after the dose by default. If the user has already been on a stim
    ///   session for 10+ hours, fires 2 hours after the new dose instead so
    ///   the nudge actually arrives during the session.
    ///
    /// All reminders are deduplicated against the pending queue within a
    /// 90-minute window per prefix to avoid spamming during multi-dose
    /// sessions.
    static func scheduleWellnessNotifications(
        substanceName _: String,
        category: SubstanceCategory?,
        doseTime: Date,
        duration: DurationProfile?,
        recentStimHours: Double? = nil,
    ) {
        guard wellnessNotificationsEnabled else { return }
        let threadId = sessionIdentifier(for: doseTime)

        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }

            // Deduplicate: skip if a wellness notification of the same type is
            // already pending within the dedup window.
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let now = Date.now

            func hasPendingWithin(
                window: TimeInterval = Timing.pendingDedupWindow,
                of targetFireDate: Date,
                prefix: String,
            ) -> Bool {
                pending.contains { req in
                    guard req.identifier.hasPrefix(prefix),
                          let trigger = req.trigger as? UNTimeIntervalNotificationTrigger else { return false }
                    let fireDate = now.addingTimeInterval(trigger.timeInterval)
                    return abs(fireDate.timeIntervalSince(targetFireDate)) < window
                }
            }

            // Hydration reminder at ~1 hour or peak start, whichever is sooner
            let hydrationDelay: TimeInterval
            if let duration {
                let peakStart = duration.phaseBoundaries.comeupEnd * 60
                hydrationDelay = min(peakStart, Timing.peakStartCap)
            } else {
                hydrationDelay = Timing.hydrationInitialDelay
            }

            let hydrationInterval = doseTime.addingTimeInterval(hydrationDelay).timeIntervalSince(.now)
            let hydrationFireDate = doseTime.addingTimeInterval(hydrationDelay)
            if hydrationInterval > 10 && !hasPendingWithin(of: hydrationFireDate, prefix: hydrationCategoryID) {
                scheduleSimpleNotification(
                    id: "\(hydrationCategoryID)_\(Int(doseTime.timeIntervalSince1970))",
                    title: String(localized: "Stay hydrated"),
                    body: hydrationMessage(for: category),
                    timeInterval: hydrationInterval,
                    category: hydrationCategoryID,
                    threadId: threadId,
                )
            }

            // Second hydration reminder at offset start
            if let duration {
                let offsetStart = duration.phaseBoundaries.peakEnd * 60
                let secondInterval = doseTime.addingTimeInterval(offsetStart).timeIntervalSince(.now)
                let secondFireDate = doseTime.addingTimeInterval(offsetStart)
                if secondInterval > hydrationInterval + Timing.hydrationReminderSpacing,
                   !hasPendingWithin(of: secondFireDate, prefix: hydrationCategoryID) {
                    scheduleSimpleNotification(
                        id: "\(hydrationCategoryID)2_\(Int(doseTime.timeIntervalSince1970))",
                        title: String(localized: "Hydration check"),
                        body: String(localized: "Have some water and a snack if you haven't recently. Your body will thank you."),
                        timeInterval: secondInterval,
                        category: hydrationCategoryID,
                        threadId: threadId,
                    )
                }
            }

            // Sleep reminder for stimulants — if session has been going 12+ hours
            if category == .stimulant || category == .empathogen {
                if let stimHours = recentStimHours, stimHours >= 10 {
                    let sleepFireDate = Date.now.addingTimeInterval(Timing.extendedStimSleepDelay)
                    if !hasPendingWithin(of: sleepFireDate, prefix: sleepCategoryID) {
                        scheduleSimpleNotification(
                            id: "\(sleepCategoryID)_\(Int(doseTime.timeIntervalSince1970))",
                            title: String(localized: "Time to rest"),
                            body: String(localized: "You've been going for over \(Int(stimHours)) hours. Try to wind down — dim the lights, put the phone away, and let yourself sleep."),
                            timeInterval: Timing.extendedStimSleepDelay,
                            category: sleepCategoryID,
                            threadId: threadId,
                        )
                    }
                } else {
                    let sleepInterval = doseTime.addingTimeInterval(Timing.stimulantSleepDelay).timeIntervalSince(.now)
                    let sleepFireDate = doseTime.addingTimeInterval(Timing.stimulantSleepDelay)
                    if sleepInterval > Timing.minSleepReminderLeadTime,
                       !hasPendingWithin(of: sleepFireDate, prefix: sleepCategoryID) {
                        scheduleSimpleNotification(
                            id: "\(sleepCategoryID)_\(Int(doseTime.timeIntervalSince1970))",
                            title: String(localized: "Time to rest"),
                            body: String(localized: "It's been a long session. Your body and brain need sleep to recover. Try to wind down."),
                            timeInterval: sleepInterval,
                            category: sleepCategoryID,
                            threadId: threadId,
                        )
                    }
                }
            }
        }
    }

    /// Schedule a notification for high cumulative doses.
    static func scheduleCumulativeDoseNotification(
        substanceName: String,
        totalAmount: Double,
        unit: String,
        category: SubstanceCategory?,
        doseTime: Date = .now,
    ) {
        guard wellnessNotificationsEnabled else { return }
        let threadId = sessionIdentifier(for: doseTime)

        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }

            let tip = cumulativeTip(for: category)

            scheduleSimpleNotification(
                id: "\(cumulativeCategoryID)_\(substanceName.lowercased())_\(Int(Date.now.timeIntervalSince1970))",
                title: String(localized: "Heads up — \(totalAmount.doseFormatted)\(unit) \(substanceName) today"),
                body: String(localized: "That's a high cumulative dose. \(tip)"),
                timeInterval: 5,
                category: cumulativeCategoryID,
                threadId: threadId,
            )
        }
    }

    /// Cancel all wellness notifications for a session
    static func cancelWellnessNotifications(for doseTimestamp: Date) {
        let ts = Int(doseTimestamp.timeIntervalSince1970)
        let ids = [
            "\(hydrationCategoryID)_\(ts)",
            "\(hydrationCategoryID)2_\(ts)",
            "\(sleepCategoryID)_\(ts)",
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Phase Notifications

    /// One of the pharmacokinetic phases that gets its own notification.
    enum Phase: String, CaseIterable {
        case onset
        case comeup
        case peak

        var displayName: LocalizedStringResource {
            switch self {
            case .onset: "Onset"
            case .comeup: "Come-up"
            case .peak: "Peak"
            }
        }
    }

    /// Schedule notifications at the start of each pharmacokinetic phase.
    ///
    /// - **Onset**: fires 1 minute after the dose (a confirmation that tracking
    ///   has begun and a heads-up that effects will start within onset-min /
    ///   onset-max minutes).
    /// - **Come-up**: fires at `onsetEnd` minutes (when the come-up phase
    ///   begins — typically the first perceptible effects).
    /// - **Peak**: fires at `comeupEnd` minutes (when the peak phase begins).
    ///
    /// Requires a `DurationProfile` with usable phase data; phases that are
    /// nil in the profile are skipped silently. All requests share the dose's
    /// session thread so iOS groups them.
    static func schedulePhaseNotifications(
        substanceName: String,
        doseTime: Date,
        duration: DurationProfile?,
    ) {
        guard phaseNotificationsEnabled, let duration else { return }
        let threadId = sessionIdentifier(for: doseTime)

        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }

            let boundaries = duration.phaseBoundaries
            let onsetEndSec = boundaries.onsetEnd * 60
            let comeupEndSec = boundaries.comeupEnd * 60

            func body(for phase: Phase) -> String {
                switch phase {
                case .onset:
                    if let onset = duration.onset {
                        return String(localized: "Effects should start within \(Int(onset.min))-\(Int(onset.max)) minutes.")
                    }
                    return String(localized: "Tracking started. Effects on the way.")
                case .comeup:
                    return String(localized: "First effects starting now. Find your spot.")
                case .peak:
                    return String(localized: "Peak is hitting. Stay safe and aware.")
                }
            }

            schedulePhase(.onset, of: substanceName, delaySec: 60, body: body(for: .onset), doseTime: doseTime, threadId: threadId)
            if onsetEndSec > 0 {
                schedulePhase(.comeup, of: substanceName, delaySec: onsetEndSec, body: body(for: .comeup), doseTime: doseTime, threadId: threadId)
            }
            if comeupEndSec > 0, comeupEndSec > onsetEndSec {
                schedulePhase(.peak, of: substanceName, delaySec: comeupEndSec, body: body(for: .peak), doseTime: doseTime, threadId: threadId)
            }
        }
    }

    /// Cancel any pending phase notifications for a given dose.
    static func cancelPhaseNotifications(for doseTimestamp: Date) {
        let ts = Int(doseTimestamp.timeIntervalSince1970)
        let ids = Phase.allCases.map { "\(phaseCategoryID)_\($0.rawValue)_\(ts)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func schedulePhase(
        _ phase: Phase,
        of substance: String,
        delaySec: TimeInterval,
        body: String,
        doseTime: Date,
        threadId: String,
    ) {
        let absoluteInterval = doseTime.addingTimeInterval(delaySec).timeIntervalSince(.now)
        // Don't schedule phases that have already passed (e.g. backfilling an
        // old entry) or that are too imminent for the user to react to.
        guard absoluteInterval > 5 else { return }

        scheduleSimpleNotification(
            id: "\(phaseCategoryID)_\(phase.rawValue)_\(Int(doseTime.timeIntervalSince1970))",
            title: "\(substance) — \(String(localized: phase.displayName))",
            body: body,
            timeInterval: absoluteInterval,
            category: phaseCategoryID,
            threadId: threadId,
        )
    }

    // MARK: - Notification Helpers

    private static func scheduleSimpleNotification(
        id: String,
        title: String,
        body: String,
        timeInterval: TimeInterval,
        category: String,
        threadId: String? = nil,
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = category
        if let threadId { content.threadIdentifier = threadId }

        // A non-positive interval means the fire time is already in the past
        // (most commonly a retroactively-logged dose). Skip it outright — the
        // old `max(5, …)` floor clamped such intervals to 5 s and fired the
        // notification immediately, which is exactly the "logged an old entry,
        // got buzzed right away" bug. UNTimeIntervalNotificationTrigger also
        // requires a strictly-positive interval.
        guard timeInterval > 0 else {
            logger.debug("\(category) notification skipped — fire time already past (\(Int(timeInterval))s)")
            return
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false,
        )

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to schedule \(category) notification: \(error.localizedDescription)")
            } else {
                logger.debug("\(category) notification scheduled in \(Int(timeInterval / 60)) min")
            }
        }
    }

    // MARK: - Category-Aware Messages

    private static func comedownMessage(for category: SubstanceCategory?) -> (title: String, body: String) {
        switch category {
        case .stimulant:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Eat a nutritious meal, drink water, and rest. Magnesium and vitamin C may help. Don't fight the tiredness — your body needs recovery."),
            )
        case .empathogen:
            (
                String(localized: "{name} wearing off"),
                String(localized: "The low mood is temporary and normal. Eat light foods, stay warm, and rest. Be kind to yourself over the next few days."),
            )
        case .psychedelic:
            (
                String(localized: "{name} effects fading"),
                String(localized: "You're coming back to baseline. Rest, eat something light. Give yourself time to process the experience."),
            )
        case .opioid:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Stay hydrated and comfortable. Avoid redosing to chase the feeling — reach out if you need support."),
            )
        case .dissociative:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Stay somewhere comfortable and safe. Eat and hydrate when you can. Avoid driving."),
            )
        case .benzodiazepine:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Rebound anxiety is temporary. Avoid caffeine and alcohol. Breathing exercises: 4 in, 7 hold, 8 out."),
            )
        case .depressant:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Drink water and eat something with electrolytes. Rest in a cool, dark room if your head hurts."),
            )
        case .cannabinoid:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Drink water, eat something balanced. If foggy, a short walk or fresh air helps clear it."),
            )
        default:
            (
                String(localized: "{name} wearing off"),
                String(localized: "Take care of yourself — eat, hydrate, and rest. The effects will fade with time."),
            )
        }
    }

    private static func hydrationMessage(for category: SubstanceCategory?) -> String {
        switch category {
        case .stimulant:
            String(localized: "Drink some water. Stimulants mask thirst — your body needs more fluids than you realize.")
        case .empathogen:
            String(localized: "Sip some water — a glass every 30-60 minutes. Don't overdo it, just stay steady.")
        case .dissociative:
            String(localized: "Have some water if you can. Your body needs fluids even if you don't feel thirsty.")
        default:
            String(localized: "Drink some water. Your body needs it, especially right now.")
        }
    }

    private static func cumulativeTip(for category: SubstanceCategory?) -> String {
        switch category {
        case .stimulant:
            String(localized: "Remember to hydrate, eat, and try to get some sleep. Your heart has been working hard.")
        case .empathogen:
            String(localized: "Your serotonin system is taking a hit. Please rest and take care of yourself.")
        case .opioid:
            String(localized: "Be very careful. Don't mix with other downers. Have naloxone nearby if possible.")
        case .benzodiazepine:
            String(localized: "High cumulative benzo doses impair memory and coordination. Stay somewhere safe.")
        case .dissociative:
            String(localized: "Stay somewhere safe. Don't drive. Your coordination and judgment are affected.")
        default:
            String(localized: "Take it easy. Hydrate, eat, and rest.")
        }
    }

    // MARK: - Cumulative Dose Check

    /// Check if cumulative dose in the last 12 hours is in the heavy range.
    /// Returns (totalAmount, shouldAlert) — call scheduleCumulativeDoseNotification if shouldAlert.
    static func checkCumulativeDose(
        substanceName: String,
        newAmount: Double,
        unit _: String,
        route: RouteOfAdministration,
        existingEntries: [DoseEntry],
    ) -> (total: Double, shouldAlert: Bool) {
        let windowStart = Date.now.addingTimeInterval(-Timing.cumulativeDoseWindow)
        let recentSame = existingEntries.filter {
            $0.substance.lowercased() == substanceName.lowercased() &&
                $0.timestamp >= windowStart
        }
        let priorTotal = recentSame.reduce(0.0) { $0 + $1.amount }
        let total = priorTotal + newAmount

        guard let substance = SubstanceLibrary.lookupByNameOrAlias(substanceName),
              let doseRange = substance.doseRange(for: route) else {
            // No dose data — can't make a judgment
            return (total, false)
        }

        // Alert if cumulative is at or above the heavy threshold
        if let heavy = doseRange.heavy, total >= heavy {
            return (total, true)
        }

        // Or if cumulative is well above the strong range
        if let strong = doseRange.strong, total >= strong.upperBound * 1.5 {
            return (total, true)
        }

        return (total, false)
    }

    /// Compute how many hours the user has been using stimulants today.
    static func stimulantSessionHours(from entries: [DoseEntry]) -> Double? {
        let today = Calendar.current.startOfDay(for: .now)
        let stimEntries = entries.filter { entry in
            entry.timestamp >= today &&
                SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category == .stimulant
        }
        guard let earliest = stimEntries.map(\.timestamp).min() else { return nil }
        return Date.now.timeIntervalSince(earliest) / 3_600
    }

    // MARK: - Persistence

    private static let storageKey = "rampDownEntryIDs"

    static func saveActiveEntry(_ entryKey: String) {
        var ids = loadActiveEntries()
        ids.insert(entryKey)
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    static func removeActiveEntry(_ entryKey: String) {
        var ids = loadActiveEntries()
        ids.remove(entryKey)
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    static func isActive(for entryKey: String) -> Bool {
        loadActiveEntries().contains(entryKey)
    }

    private static func loadActiveEntries() -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        // Legacy values were per-launch `persistentModelID.hashValue`s —
        // unrecoverable across relaunches, so drop them on read (the next
        // save/remove persists the cleaned set).
        return Set(stored.filter { Int($0) == nil })
    }
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
