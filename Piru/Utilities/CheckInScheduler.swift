import Foundation
import os
import UserNotifications

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "CheckIn")

/// Opt-in per-session "How is it going?" prompts. Each fires a local
/// notification whose tap (or its **Add Note** action) opens the note sheet on
/// the session, pre-tagged `.checkIn`. Off unless the session asks
/// (``Session/checkInIntervalMinutes``).
///
/// Requests use the `piru.notif.checkIn.<sessionID>.<n>` grammar and the same
/// 6-hour session thread as the ramp-down notifications, so they collapse into
/// the session's group in Notification Center.
enum CheckInScheduler {
    nonisolated static let categoryID = "checkIn"

    /// The cadence a session can choose. Stored as minutes on the session;
    /// `ladder` is the `0` sentinel.
    nonisolated enum Cadence: Hashable, CaseIterable, Identifiable {
        /// T+30 m, 1 h, 2 h, 4 h, 6 h — dense while things change, sparse later.
        case ladder
        case every30Minutes
        case everyHour
        case every2Hours

        var id: Self {
            self
        }

        var storedMinutes: Double {
            switch self {
            case .ladder: 0
            case .every30Minutes: 30
            case .everyHour: 60
            case .every2Hours: 120
            }
        }

        init?(storedMinutes: Double?) {
            guard let storedMinutes else { return nil }
            switch storedMinutes {
            case 0: self = .ladder
            case 30: self = .every30Minutes
            case 60: self = .everyHour
            case 120: self = .every2Hours
            default: return nil
            }
        }

        /// Offsets from the anchor dose, in seconds. Interval cadences run for
        /// eight hours — long enough for a whole psychedelic session, short
        /// enough that a forgotten toggle stops on its own.
        var offsets: [TimeInterval] {
            switch self {
            case .ladder: [30, 60, 120, 240, 360].map { $0 * 60 }
            case .every30Minutes: stride(from: 30.0, through: 480, by: 30).map { $0 * 60 }
            case .everyHour: stride(from: 60.0, through: 480, by: 60).map { $0 * 60 }
            case .every2Hours: stride(from: 120.0, through: 480, by: 120).map { $0 * 60 }
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .ladder: "T+30 m, 1 h, 2 h, 4 h, 6 h"
            case .every30Minutes: "Every 30 minutes"
            case .everyHour: "Every hour"
            case .every2Hours: "Every 2 hours"
            }
        }
    }

    /// Anchor time for a session's check-ins: its latest dose.
    nonisolated static func anchor(for session: Session) -> Date {
        session.lastDoseDate ?? session.startDate
    }

    /// The fire dates a cadence yields from `anchor`, dropping any already past
    /// `now`. Pure, for tests.
    nonisolated static func fireDates(cadence: Cadence, anchor: Date, now: Date = .now) -> [Date] {
        cadence.offsets.map { anchor.addingTimeInterval($0) }.filter { $0 > now.addingTimeInterval(5) }
    }

    /// Apply the session's stored cadence: cancel what is pending and schedule
    /// afresh from the latest dose. Call after the cadence changes and after a
    /// dose is added to the session (the anchor moved).
    static func sync(session: Session) {
        cancel(sessionID: session.id)
        guard let cadence = Cadence(storedMinutes: session.checkInIntervalMinutes) else { return }
        guard NotificationPreferencesStore.allows(.checkIn) else { return }
        let dates = fireDates(cadence: cadence, anchor: anchor(for: session))
        let center = UNUserNotificationCenter.current()
        let thread = RampDownScheduler.sessionIdentifier(for: session.startDate)
        for (index, date) in dates.enumerated() {
            if NotificationPreferencesStore.isInQuietHours(date) { continue }
            let content = UNMutableNotificationContent(
                title: String(localized: "How is it going?"),
                body: String(localized: "Add a note to your session — what you notice, at this moment."),
                category: categoryID,
                threadIdentifier: thread,
            )
            content.userInfo = [
                DoseNotificationManager.deepLinkUserInfoKey: "\(DeepLink.scheme)://session/\(session.id.uuidString)?note=checkIn",
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
            let request = UNNotificationRequest(
                identifier: NotificationType.checkIn.identifier(anchor: session.id.uuidString, ordinal: String(index)),
                content: content,
                trigger: trigger,
            )
            center.add(request) { error in
                if let error {
                    logger.error("Check-in schedule failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        logger.debug("Scheduled \(dates.count) check-ins for session \(session.id.uuidString, privacy: .public)")
    }

    static func cancel(sessionID: UUID) {
        let prefix = NotificationType.checkIn.identifierPrefix + sessionID.uuidString
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    /// Whether a session should be *offered* check-ins: the offer appears once,
    /// only for a session carrying a psychedelic or dissociative dose that is
    /// still in its effect window.
    static func shouldOffer(session: Session, hasOngoingDose: Bool) -> Bool {
        guard hasOngoingDose, !session.checkInOffered, session.checkInIntervalMinutes == nil else { return false }
        return (session.doses ?? []).contains { dose in
            guard let category = SubstanceLibrary.lookup(dose.substance)?.category else { return false }
            return category == .psychedelic || category == .dissociative
        }
    }
}
