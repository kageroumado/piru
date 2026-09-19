import Foundation

/// The rules a custom check-in schedule obeys, apart from any store or view:
/// what a valid time is, how a set of them is normalized, and how one reads.
///
/// In `Shared/` because the session model that persists the list and the app
/// that edits it both need the same answer, and a list that round-trips through
/// the store must already satisfy the rules it is read back under.
nonisolated enum CheckInOffsets {
    /// The soonest a check-in may sit after the dose. Below this it lands
    /// before most things have started, on a phone still in the hand that
    /// logged the dose.
    static let minimumMinutes = 5
    /// The furthest out one may sit. A day is past where a session's own
    /// anchor means anything, and a prompt beyond it reads as a stray alarm.
    static let maximumMinutes = 24 * 60
    /// How many a session may carry. iOS keeps 64 pending notifications per
    /// app across every kind Piru schedules, so a session's share is small on
    /// purpose.
    static let maximumCount = 12

    /// Ascending, unique, in range, and no more than ``maximumCount`` — the
    /// form the store holds and every reader can assume.
    static func normalized(_ minutes: [Int]) -> [Int] {
        Array(
            Set(minutes.filter { $0 >= minimumMinutes && $0 <= maximumMinutes })
                .sorted()
                .prefix(maximumCount),
        )
    }

    /// Whether `minutes` can still be added to `existing`.
    static func canAdd(_ minutes: Int, to existing: [Int]) -> Bool {
        minutes >= minimumMinutes
            && minutes <= maximumMinutes
            && existing.count < maximumCount
            && !existing.contains(minutes)
    }

    /// One offset as a relative label — "+45m", "+1h", "+2h 30m".
    static func label(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "+\(remainder)m" }
        if remainder == 0 { return "+\(hours)h" }
        return "+\(hours)h \(remainder)m"
    }
}
