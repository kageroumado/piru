import Foundation
import SwiftData

/// Per-type notification enablement — the durable backing of the Notifications
/// management screen (`Specs/notifications-system.md` §C).
///
/// A singleton record (created lazily by `NotificationPreferencesStore`, which
/// also seeds it once from the legacy `wellnessNotificationsEnabled` /
/// `phaseNotificationsEnabled` flags). Lives in SwiftData rather than
/// `UserDefaults` so a user's notification setup rides the existing
/// backup/restore path. Property-level defaults keep the addition a pure
/// lightweight migration.
///
/// Defaults mirror today's shipped behavior: the three types that fire with no
/// switch (comedown, routine, inventory) default on; the flag-gated session
/// types default off until onboarding or the management screen enables them.
@Model
final class NotificationPreferences {
    /// Master posture — `false` pauses every notification type without
    /// touching the per-type choices.
    var masterEnabled: Bool = true

    var comedownEnabled: Bool = true
    var hydrationEnabled: Bool = false
    var sleepEnabled: Bool = false
    var phaseEnabled: Bool = false
    var cumulativeEnabled: Bool = false
    var routineEnabled: Bool = true
    var routineFollowUpEnabled: Bool = true
    var nextDoseEnabled: Bool = true
    var inventoryEnabled: Bool = true

    /// Quiet hours: dose reminders and session nudges whose fire time falls
    /// inside the window are silenced. Safety warnings (cumulative dose) and
    /// routines the user timed explicitly are exempt. Minutes from midnight;
    /// the window may wrap (23:00 → 07:00).
    var quietHoursEnabled: Bool = false
    var quietHoursStartMinutes: Int = 23 * 60
    var quietHoursEndMinutes: Int = 7 * 60

    /// Per-type Time Sensitive delivery (break through Focus / the summary) —
    /// the user decides which of the eligible types get it (Kiri, 2026-07-18).
    /// Defaults on, matching the behavior before the setting existed.
    var routineTimeSensitive: Bool = true
    var routineFollowUpTimeSensitive: Bool = true
    var nextDoseTimeSensitive: Bool = true
    var cumulativeTimeSensitive: Bool = true

    /// JSON-encoded backing storage for ``askAgainDefaultMinutes``. Empty
    /// (never written) reads as the `[10]` default; an explicit empty cadence
    /// encodes as `"[]"` and round-trips as "no re-asks".
    var askAgainDefaultData: Data = Data()

    /// The global Ask Again cadence (Specs/meds-reminders-redesign.md):
    /// minutes after a med's reminder time for each "still need to log?"
    /// re-ask. User-editable intervals; a med can override or opt out via
    /// `DailyDoseItem.askAgainOverrideMinutes`.
    var askAgainDefaultMinutes: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: askAgainDefaultData)) ?? [10] }
        set { askAgainDefaultData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init() {}
}
