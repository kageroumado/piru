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
    var inventoryEnabled: Bool = true

    init() {}
}
