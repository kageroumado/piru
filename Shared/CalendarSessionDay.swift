import Foundation

/// Returns the start of the user's "session day" for a given date.
///
/// Unlike `Calendar.startOfDay(for:)` (which always returns midnight), this
/// rolls late-night doses into the previous day's session so a journal entry
/// at 02:00 on Tuesday belongs to the session that started Monday afternoon.
///
/// The cutoff hour is stored in the shared App Group UserDefaults under
/// `dayBoundaryHour` so the main app, widgets, and Live Activity all agree
/// on where the day breaks. A value of 0 reproduces the classic midnight
/// behaviour. Default is 4 AM.
///
/// `nonisolated`: pure date math over thread-safe `UserDefaults` reads, so it
/// stays callable off the main actor under the app target's default MainActor
/// isolation (the widget targets compile without that default, where this is
/// a no-op).
nonisolated extension Calendar {
    /// UserDefaults key used to persist the day-boundary hour across launches.
    static let dayBoundaryHourKey = "dayBoundaryHour"

    /// Hour (0-23) at which one session day ends and the next begins.
    /// Reads from the App Group suite so widgets see the same value the app
    /// is configured with.
    static var sessionDayBoundaryHour: Int {
        let suite = UserDefaults(suiteName: "group.dev.yumeji.piru")
        let stored = suite?.object(forKey: dayBoundaryHourKey) as? Int
        return stored.flatMap { (0 ... 12).contains($0) ? $0 : nil } ?? 4
    }

    /// Start of the session day containing `date`. If `date.hour` is before
    /// the configured boundary hour, returns the boundary hour on the previous
    /// calendar day; otherwise returns the boundary hour on the same day.
    func sessionDayStart(for date: Date) -> Date {
        let cutoff = Self.sessionDayBoundaryHour
        let hour = component(.hour, from: date)
        let midnight = startOfDay(for: date)
        let cutoffToday = midnight.addingTimeInterval(TimeInterval(cutoff) * 3_600)
        return hour < cutoff ? cutoffToday.addingTimeInterval(-86_400) : cutoffToday
    }

    /// End of the session day containing `date` (start of the next session day).
    func sessionDayEnd(for date: Date) -> Date {
        sessionDayStart(for: date).addingTimeInterval(86_400)
    }
}
