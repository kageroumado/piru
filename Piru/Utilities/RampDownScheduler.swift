import Foundation
import UserNotifications

// MARK: - Ramp Down Scheduler
// Notifies you to take a small redose timed so its comeup
// overlaps with your original dose's comedown — no crash gap.

enum RampDownScheduler {

    static let notificationCategory = "rampDown"

    // MARK: - Calculate Redose Time

    /// Calculate when to redose so the comeup of the new dose
    /// aligns with the comedown of the original dose.
    ///
    /// redoseTime = doseTime + peakEnd - comeupDuration
    ///
    /// This way the redose "catches" you as you come down.
    static func calculateRedoseTime(
        doseTime: Date,
        duration: DurationProfile
    ) -> Date {
        let boundaries = duration.phaseBoundaries
        let peakEndMinutes = boundaries.peakEnd
        let comeupMinutes = boundaries.comeupEnd - boundaries.onsetEnd

        // Redose time = when peak ends minus how long the comeup takes
        let redoseMinutes = peakEndMinutes - comeupMinutes
        return doseTime.addingTimeInterval(max(0, redoseMinutes) * 60)
    }

    /// Suggested redose amount — typically 25-50% of original
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

    static func scheduleNotification(
        substanceName: String,
        initialAmount: Double,
        unit: String,
        doseTime: Date,
        duration: DurationProfile,
        entryID: Int
    ) {
        let center = UNUserNotificationCenter.current()

        // Register category
        let category = UNNotificationCategory(
            identifier: notificationCategory,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        center.setNotificationCategories([category])

        let redoseTime = calculateRedoseTime(doseTime: doseTime, duration: duration)
        let timeInterval = redoseTime.timeIntervalSince(.now)

        guard timeInterval > 5 else {
            print("[RampDown] Redose time already passed (\(Int(timeInterval))s ago)")
            return
        }

        let suggestedAmount = suggestedRedoseAmount(initialAmount)

        let content = UNMutableNotificationContent()
        content.title = "💊 Comedown approaching — \(substanceName)"
        content.body = "You're about to come down. A small redose (~\(suggestedAmount.doseFormatted) \(unit)) now could soften the landing."
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
                print("[RampDown] Notification scheduled in \(mins) min for \(substanceName)")
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
