import Foundation
import UserNotifications

// MARK: - Ramp Down & Wellness Notification Scheduler
// Schedules harm-reduction notifications: comedown care, hydration reminders,
// sleep nudges for stimulant sessions, and cumulative dose alerts.

enum RampDownScheduler {

    static let notificationCategory = "rampDown"
    private static let hydrationCategory = "hydration"
    private static let sleepCategory = "sleepReminder"
    private static let cumulativeCategory = "cumulativeDose"

    /// Whether automatic wellness notifications (hydration, sleep) are enabled.
    static var wellnessNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "wellnessNotificationsEnabled") as? Bool ?? true
    }

    // MARK: - Calculate Comedown Time

    /// Calculate when the comedown begins (start of offset phase).
    /// This is when the user most needs recovery reminders.
    static func calculateRedoseTime(
        doseTime: Date,
        duration: DurationProfile
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

    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Schedule the main comedown notification — now with harm-reduction messaging
    static func scheduleNotification(
        substanceName: String,
        initialAmount: Double,
        unit: String,
        doseTime: Date,
        duration: DurationProfile,
        entryID: Int,
        category: SubstanceCategory? = nil
    ) {
        let center = UNUserNotificationCenter.current()

        let notifCategory = UNNotificationCategory(
            identifier: notificationCategory,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        center.setNotificationCategories([notifCategory])

        let comedownTime = calculateRedoseTime(doseTime: doseTime, duration: duration)
        let timeInterval = comedownTime.timeIntervalSince(.now)

        guard timeInterval > 5 else {
            print("[RampDown] Comedown time already passed (\(Int(timeInterval))s ago)")
            return
        }

        let message = comedownMessage(for: category)

        let content = UNMutableNotificationContent()
        content.title = message.title.replacingOccurrences(of: "{name}", with: substanceName)
        content.body = message.body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = notificationCategory

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(entryID: entryID),
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[RampDown] Failed to schedule: \(error.localizedDescription)")
            } else {
                let mins = Int(timeInterval / 60)
                print("[RampDown] Comedown notification scheduled in \(mins) min for \(substanceName)")
            }
        }
    }

    static func cancelNotification(for entryID: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(entryID: entryID)]
        )
    }

    private static func notificationIdentifier(entryID: Int) -> String {
        "\(notificationCategory)_\(String(entryID))"
    }

    // MARK: - Wellness Notifications (Auto-scheduled on dose log)

    /// Schedule hydration + sleep reminders after logging a dose.
    /// Called automatically from QuickLogView / EntryFormView.
    static func scheduleWellnessNotifications(
        substanceName: String,
        category: SubstanceCategory?,
        doseTime: Date,
        duration: DurationProfile?,
        recentStimHours: Double? = nil
    ) {
        guard wellnessNotificationsEnabled else { return }

        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }

            // Deduplicate: skip if a wellness notification of the same type is already pending within 30 min
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let now = Date.now

            func hasPendingWithin30Min(prefix: String) -> Bool {
                pending.contains { req in
                    guard req.identifier.hasPrefix(prefix),
                          let trigger = req.trigger as? UNTimeIntervalNotificationTrigger else { return false }
                    let fireDate = now.addingTimeInterval(trigger.timeInterval)
                    return abs(fireDate.timeIntervalSince(now)) < 1800
                }
            }

            // Hydration reminder at ~1 hour or peak start, whichever is sooner
            let hydrationDelay: TimeInterval
            if let duration {
                let peakStart = duration.phaseBoundaries.comeupEnd * 60
                hydrationDelay = min(peakStart, 3600)
            } else {
                hydrationDelay = 3600 // 1 hour default
            }

            let hydrationInterval = doseTime.addingTimeInterval(hydrationDelay).timeIntervalSince(.now)
            if hydrationInterval > 10 && !hasPendingWithin30Min(prefix: hydrationCategory) {
                scheduleSimpleNotification(
                    id: "\(hydrationCategory)_\(Int(doseTime.timeIntervalSince1970))",
                    title: "Stay hydrated",
                    body: hydrationMessage(for: category),
                    timeInterval: hydrationInterval,
                    category: hydrationCategory
                )
            }

            // Second hydration reminder at offset start
            if let duration {
                let offsetStart = duration.phaseBoundaries.peakEnd * 60
                let secondInterval = doseTime.addingTimeInterval(offsetStart).timeIntervalSince(.now)
                if secondInterval > hydrationInterval + 1800 && !hasPendingWithin30Min(prefix: "\(hydrationCategory)2") { // at least 30 min after first
                    scheduleSimpleNotification(
                        id: "\(hydrationCategory)2_\(Int(doseTime.timeIntervalSince1970))",
                        title: "Hydration check",
                        body: "Have some water and a snack if you haven't recently. Your body will thank you.",
                        timeInterval: secondInterval,
                        category: hydrationCategory
                    )
                }
            }

            // Sleep reminder for stimulants — if session has been going 12+ hours
            if category == .stimulant || category == .empathogen {
                if let stimHours = recentStimHours, stimHours >= 10 {
                    // Already been at it a while — send sleep reminder in 2 hours
                    scheduleSimpleNotification(
                        id: "\(sleepCategory)_\(Int(doseTime.timeIntervalSince1970))",
                        title: "Time to rest",
                        body: "You've been going for over \(Int(stimHours)) hours. Try to wind down — dim the lights, put the phone away, and let yourself sleep.",
                        timeInterval: 7200,
                        category: sleepCategory
                    )
                } else {
                    // Schedule for 12h from first dose today (approximated as current dose time)
                    let sleepInterval = doseTime.addingTimeInterval(12 * 3600).timeIntervalSince(.now)
                    if sleepInterval > 3600 {
                        scheduleSimpleNotification(
                            id: "\(sleepCategory)_\(Int(doseTime.timeIntervalSince1970))",
                            title: "Time to rest",
                            body: "It's been a long session. Your body and brain need sleep to recover. Try to wind down.",
                            timeInterval: sleepInterval,
                            category: sleepCategory
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
        category: SubstanceCategory?
    ) {
        guard wellnessNotificationsEnabled else { return }

        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }

            let tip = cumulativeTip(for: category)

            scheduleSimpleNotification(
                id: "\(cumulativeCategory)_\(substanceName.lowercased())_\(Int(Date.now.timeIntervalSince1970))",
                title: "Heads up — \(totalAmount.doseFormatted)\(unit) \(substanceName) today",
                body: "That's a high cumulative dose. \(tip)",
                timeInterval: 5, // Near-immediate
                category: cumulativeCategory
            )
        }
    }

    /// Cancel all wellness notifications for a session
    static func cancelWellnessNotifications(for doseTimestamp: Date) {
        let ts = Int(doseTimestamp.timeIntervalSince1970)
        let ids = [
            "\(hydrationCategory)_\(ts)",
            "\(hydrationCategory)2_\(ts)",
            "\(sleepCategory)_\(ts)",
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Notification Helpers

    private static func scheduleSimpleNotification(
        id: String,
        title: String,
        body: String,
        timeInterval: TimeInterval,
        category: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = category

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(5, timeInterval),
            repeats: false
        )

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Wellness] Failed to schedule \(category): \(error.localizedDescription)")
            } else {
                print("[Wellness] \(category) notification scheduled in \(Int(timeInterval / 60)) min")
            }
        }
    }

    // MARK: - Category-Aware Messages

    private static func comedownMessage(for category: SubstanceCategory?) -> (title: String, body: String) {
        switch category {
        case .stimulant:
            ("{name} wearing off",
             "Eat a nutritious meal, drink water, and rest. Magnesium and vitamin C may help. Don't fight the tiredness — your body needs recovery.")
        case .empathogen:
            ("{name} wearing off",
             "The low mood is temporary and normal. Eat light foods, stay warm, and rest. Be kind to yourself over the next few days.")
        case .psychedelic:
            ("{name} effects fading",
             "You're coming back to baseline. Rest, eat something light. Give yourself time to process the experience.")
        case .opioid:
            ("{name} wearing off",
             "Stay hydrated and comfortable. Avoid redosing to chase the feeling — reach out if you need support.")
        case .dissociative:
            ("{name} wearing off",
             "Stay somewhere comfortable and safe. Eat and hydrate when you can. Avoid driving.")
        case .benzodiazepine:
            ("{name} wearing off",
             "Rebound anxiety is temporary. Avoid caffeine and alcohol. Breathing exercises: 4 in, 7 hold, 8 out.")
        case .depressant:
            ("{name} wearing off",
             "Drink water and eat something with electrolytes. Rest in a cool, dark room if your head hurts.")
        case .cannabinoid:
            ("{name} wearing off",
             "Drink water, eat something balanced. If foggy, a short walk or fresh air helps clear it.")
        default:
            ("{name} wearing off",
             "Take care of yourself — eat, hydrate, and rest. The effects will fade with time.")
        }
    }

    private static func hydrationMessage(for category: SubstanceCategory?) -> String {
        switch category {
        case .stimulant:
            "Drink some water. Stimulants mask thirst — your body needs more fluids than you realize."
        case .empathogen:
            "Sip some water — a glass every 30-60 minutes. Don't overdo it, just stay steady."
        case .dissociative:
            "Have some water if you can. Your body needs fluids even if you don't feel thirsty."
        default:
            "Drink some water. Your body needs it, especially right now."
        }
    }

    private static func cumulativeTip(for category: SubstanceCategory?) -> String {
        switch category {
        case .stimulant:
            "Remember to hydrate, eat, and try to get some sleep. Your heart has been working hard."
        case .empathogen:
            "Your serotonin system is taking a hit. Please rest and take care of yourself."
        case .opioid:
            "Be very careful. Don't mix with other downers. Have naloxone nearby if possible."
        case .benzodiazepine:
            "High cumulative benzo doses impair memory and coordination. Stay somewhere safe."
        case .dissociative:
            "Stay somewhere safe. Don't drive. Your coordination and judgment are affected."
        default:
            "Take it easy. Hydrate, eat, and rest."
        }
    }

    // MARK: - Cumulative Dose Check

    /// Check if cumulative dose in the last 12 hours is in the heavy range.
    /// Returns (totalAmount, shouldAlert) — call scheduleCumulativeDoseNotification if shouldAlert.
    static func checkCumulativeDose(
        substanceName: String,
        newAmount: Double,
        unit: String,
        route: RouteOfAdministration,
        existingEntries: [DoseEntry]
    ) -> (total: Double, shouldAlert: Bool) {
        let twelveHoursAgo = Date.now.addingTimeInterval(-12 * 3600)
        let recentSame = existingEntries.filter {
            $0.substance.lowercased() == substanceName.lowercased() &&
            $0.timestamp >= twelveHoursAgo
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
        return Date.now.timeIntervalSince(earliest) / 3600
    }

    // MARK: - Persistence

    private static let storageKey = "rampDownEntryIDs"

    static func saveActiveEntry(_ entryID: Int) {
        var ids = loadActiveEntries()
        ids.insert(String(entryID))
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    static func removeActiveEntry(_ entryID: Int) {
        var ids = loadActiveEntries()
        ids.remove(String(entryID))
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    static func isActive(for entryID: Int) -> Bool {
        loadActiveEntries().contains(String(entryID))
    }

    private static func loadActiveEntries() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }
}

// MARK: - Double Rounding Helper

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
