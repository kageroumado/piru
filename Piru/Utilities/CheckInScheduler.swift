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

    /// The schedule a session runs, stored as minutes on the session.
    ///
    /// Two of these are ever *offered*: ``everyHour`` and ``custom`` (see
    /// ``offerable``). The three fixed cadences below it are what sessions from
    /// `v2.2-b52` and earlier stored, and they keep decoding and firing — a
    /// session already running its prompts must not go quiet because the picker
    /// stopped listing its cadence.
    nonisolated enum Cadence: Hashable, CaseIterable, Identifiable {
        case everyHour
        /// The times on the session (``Session/checkInOffsetMinutes``).
        case custom
        /// T+30 m, 1 h, 2 h, 4 h, 6 h — dense while things change, sparse later.
        case ladder
        case every30Minutes
        case every2Hours

        /// What the banner and the menu put in front of someone choosing now.
        /// A fixed ladder is someone else's guess at when a session matters;
        /// `custom` lets the person who is in it say.
        static let offerable: [Cadence] = [.everyHour, .custom]

        var id: Self {
            self
        }

        var storedMinutes: Double {
            switch self {
            case .everyHour: 60
            case .custom: -1
            case .ladder: 0
            case .every30Minutes: 30
            case .every2Hours: 120
            }
        }

        init?(storedMinutes: Double?) {
            guard let storedMinutes else { return nil }
            switch storedMinutes {
            case -1: self = .custom
            case 0: self = .ladder
            case 30: self = .every30Minutes
            case 60: self = .everyHour
            case 120: self = .every2Hours
            default: return nil
            }
        }

        /// Fixed offsets from the anchor dose, in minutes. Interval cadences run
        /// for eight hours — long enough for a whole psychedelic session, short
        /// enough that a forgotten toggle stops on its own. `custom` has none of
        /// its own: its times live on the session.
        var fixedOffsetMinutes: [Double] {
            switch self {
            case .custom: []
            case .ladder: [30, 60, 120, 240, 360]
            case .every30Minutes: Array(stride(from: 30.0, through: 480, by: 30))
            case .everyHour: Array(stride(from: 60.0, through: 480, by: 60))
            case .every2Hours: Array(stride(from: 120.0, through: 480, by: 120))
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .everyHour: "Every hour"
            case .custom: "Custom…"
            case .ladder: "T+30 m, 1 h, 2 h, 4 h, 6 h"
            case .every30Minutes: "Every 30 minutes"
            case .every2Hours: "Every 2 hours"
            }
        }
    }

    /// The offsets a session actually runs, in minutes: the cadence's own, or
    /// the session's list when it chose them itself.
    nonisolated static func offsetMinutes(cadence: Cadence, custom: [Int]) -> [Double] {
        cadence == .custom ? CheckInOffsets.normalized(custom).map(Double.init) : cadence.fixedOffsetMinutes
    }

    /// Anchor time for a session's check-ins: its latest dose.
    nonisolated static func anchor(for session: Session) -> Date {
        session.lastDoseDate ?? session.startDate
    }

    /// The fire dates a schedule yields from `anchor`, dropping any already past
    /// `now`. Pure, for tests.
    nonisolated static func fireDates(
        cadence: Cadence,
        custom: [Int] = [],
        anchor: Date,
        now: Date = .now,
    ) -> [Date] {
        offsetMinutes(cadence: cadence, custom: custom)
            .map { anchor.addingTimeInterval($0 * 60) }
            .filter { $0 > now.addingTimeInterval(5) }
    }

    /// One prompt in a session's schedule, as the session screen shows it.
    nonisolated struct Planned: Identifiable, Hashable {
        /// Why a row reads the way it does. A schedule that listed every time
        /// as "coming" would be wrong twice over: a prompt whose hour has gone
        /// is not coming, and one inside quiet hours is never scheduled at all
        /// (``sync(session:)`` skips it).
        enum State: Hashable {
            case scheduled
            case quietHours
            case passed
        }

        let offsetMinutes: Int
        let date: Date
        let state: State

        var id: Int {
            offsetMinutes
        }
    }

    /// The whole schedule a session runs, past prompts included — what
    /// ``fireDates(cadence:custom:anchor:now:)`` computes, without dropping
    /// what has already gone. Pure, for tests.
    nonisolated static func plan(
        cadence: Cadence,
        custom: [Int] = [],
        anchor: Date,
        now: Date = .now,
    ) -> [Planned] {
        offsetMinutes(cadence: cadence, custom: custom).map { minutes in
            let date = anchor.addingTimeInterval(minutes * 60)
            let state: Planned.State = if date <= now {
                .passed
            } else if NotificationPreferencesStore.isInQuietHours(date) {
                .quietHours
            } else {
                .scheduled
            }
            return Planned(offsetMinutes: Int(minutes), date: date, state: state)
        }
    }

    /// The session's schedule, or nil when it runs none.
    static func plan(for session: Session, now: Date = .now) -> [Planned]? {
        guard let cadence = Cadence(storedMinutes: session.checkInIntervalMinutes) else { return nil }
        return plan(cadence: cadence, custom: session.checkInOffsetMinutes, anchor: anchor(for: session), now: now)
    }

    /// `true` when check-in notifications are off app-wide, so a session's
    /// schedule exists but nothing it lists will arrive.
    nonisolated static var isMutedByPreferences: Bool {
        !NotificationPreferencesStore.allows(.checkIn)
    }

    /// Apply the session's stored cadence: cancel what is pending and schedule
    /// afresh from the latest dose. Call after the cadence changes and after a
    /// dose is added to the session (the anchor moved).
    static func sync(session: Session) {
        cancel(sessionID: session.id)
        guard let cadence = Cadence(storedMinutes: session.checkInIntervalMinutes) else { return }
        guard NotificationPreferencesStore.allows(.checkIn) else { return }
        let dates = fireDates(
            cadence: cadence,
            custom: session.checkInOffsetMinutes,
            anchor: anchor(for: session),
        )
        let center = UNUserNotificationCenter.current()
        let thread = RampDownScheduler.sessionIdentifier(for: session.startDate)
        // A session that only carries medication is asked the medication
        // question, in the words its own control uses.
        let form = CheckInForm.build(for: session)
        let isMedication = form.asksWorked && !form.asksIntensity
        let title = isMedication
            ? String(localized: "Is it working?")
            : String(localized: "How is it going?")
        let body = isMedication
            ? String(localized: "One tap records how this dose is going — less than usual, about right, or more.")
            : String(localized: "Add a note to your session — what you notice, at this moment.")
        for (index, date) in dates.enumerated() {
            if NotificationPreferencesStore.isInQuietHours(date) { continue }
            let content = UNMutableNotificationContent(
                title: title,
                body: body,
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

    /// Classes where a timed prompt has something to learn: a psychoactive dose
    /// with a course someone can report on. A supplement or an antibiotic is
    /// logged, not experienced, so asking about it hourly would be noise.
    nonisolated static let offerableCategories: Set<SubstanceCategory> = [
        .psychedelic, .dissociative, .dysdelic, .deliriant, .empathogen,
        .stimulant, .eugeroic, .cannabinoid, .opioid, .benzodiazepine,
        .depressant, .gabapentinoid,
    ]

    /// How many times the offer may be turned down before it stops appearing.
    ///
    /// The offer is per-session, and someone who takes a medication daily starts
    /// a session a day — without this, declining once would mean declining every
    /// morning forever. Two says it clearly enough.
    nonisolated static let maximumDeclines = 2
    private nonisolated static let declineKey = "checkInOfferDeclines"

    private nonisolated static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.dev.yumeji.piru") ?? .standard
    }

    /// Record that the banner was dismissed rather than accepted.
    nonisolated static func recordOfferDeclined() {
        defaults.set(defaults.integer(forKey: declineKey) + 1, forKey: declineKey)
    }

    nonisolated static var isOfferMuted: Bool {
        defaults.integer(forKey: declineKey) >= maximumDeclines
    }

    /// Whether a session should be *offered* check-ins: once per session, while
    /// a dose of an ``offerableCategories`` class is still in its effect window,
    /// and only until the offer has been turned down ``maximumDeclines`` times.
    static func shouldOffer(session: Session, hasOngoingDose: Bool) -> Bool {
        guard hasOngoingDose, !session.checkInOffered, session.checkInIntervalMinutes == nil else { return false }
        guard !isOfferMuted else { return false }
        return (session.doses ?? []).contains { dose in
            guard let category = SubstanceLibrary.lookup(dose.substance)?.category else { return false }
            return offerableCategories.contains(category)
        }
    }
}
