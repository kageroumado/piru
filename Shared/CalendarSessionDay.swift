import Foundation

/// The user's journal day: the unit every surface that groups logged doses by
/// day reads (Journal sections, the vertical timeline, the calendar's counts,
/// Insights and reports).
///
/// A journal day runs from the Day Starts At hour on one calendar date to that
/// hour on the next, and is named after the date it starts on: with a 4 AM
/// start, a dose at 02:00 on Tuesday belongs to Monday. An hour of 0 is the
/// plain calendar day. Default is 4 AM.
///
/// The hour is stored in the shared App Group UserDefaults under
/// `dayBoundaryHour` so the main app, widgets, and Live Activity all agree
/// on where the day breaks.
///
/// Boundaries are wall-clock times found by calendar arithmetic, never
/// midnight plus a fixed number of seconds: on a DST date 04:00 is 3 or 5
/// hours after midnight, and the day is 23 or 25 hours long.
///
/// `nonisolated`: pure date math over thread-safe `UserDefaults` reads, so it
/// stays callable off the main actor under the app target's default MainActor
/// isolation (the widget targets compile without that default, where this is
/// a no-op).
nonisolated extension Calendar {
    /// UserDefaults key used to persist the day-boundary hour across launches.
    static let dayBoundaryHourKey = "dayBoundaryHour"

    /// Hour (0-12) at which one journal day ends and the next begins.
    /// Reads from the App Group suite so widgets see the same value the app
    /// is configured with.
    static var sessionDayBoundaryHour: Int {
        let suite = UserDefaults(suiteName: AppIdentity.appGroup)
        let stored = suite?.object(forKey: dayBoundaryHourKey) as? Int
        return stored.flatMap { (0 ... 12).contains($0) ? $0 : nil } ?? 4
    }

    /// The journal day containing `date`, as the start of the calendar date it
    /// is named after. These keys equal `startOfDay(for:)` of that date, so a
    /// calendar cell or a picked date finds its journal day directly.
    func journalDay(for date: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        let midnight = startOfDay(for: date)
        guard boundaryHour > 0, date < journalDayStart(of: midnight, boundaryHour: boundaryHour) else { return midnight }
        return startOfDay(for: self.date(byAdding: .day, value: -1, to: midnight) ?? midnight.addingTimeInterval(-86_400))
    }

    /// The journal day after `day`, as the start of its calendar date.
    func journalDay(after day: Date) -> Date {
        let midnight = startOfDay(for: day)
        return startOfDay(for: date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400))
    }

    /// The instant the journal day named `day` begins: the boundary hour on
    /// that calendar date, or the next existing time when DST skips it.
    func journalDayStart(of day: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        let midnight = startOfDay(for: day)
        guard boundaryHour > 0 else { return midnight }
        return date(bySettingHour: boundaryHour, minute: 0, second: 0, of: midnight)
            ?? midnight.addingTimeInterval(TimeInterval(boundaryHour) * 3_600)
    }

    /// Whether the journal day named `day` is the one `now` falls in.
    func isJournalDayToday(_ day: Date, now: Date = .now, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Bool {
        startOfDay(for: day) == journalDay(for: now, boundaryHour: boundaryHour)
    }

    /// Whether the journal day named `day` is the one before `now`'s.
    func isJournalDayYesterday(_ day: Date, now: Date = .now, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Bool {
        journalDay(after: day) == journalDay(for: now, boundaryHour: boundaryHour)
    }

    /// The instant the journal day containing `date` begins.
    func sessionDayStart(for date: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        journalDayStart(of: journalDay(for: date, boundaryHour: boundaryHour), boundaryHour: boundaryHour)
    }

    /// The instant the journal day containing `date` ends: the next one's start.
    func sessionDayEnd(for date: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        journalDayStart(of: journalDay(after: journalDay(for: date, boundaryHour: boundaryHour)), boundaryHour: boundaryHour)
    }

    // MARK: A dose's own clock

    /// This calendar in the time zone a dose was logged in: `self` with that
    /// zone, or `self` unchanged when `identifier` is `nil`, unknown, or
    /// already this calendar's zone.
    func loggedIn(_ identifier: String?) -> Calendar {
        guard let identifier, identifier != timeZone.identifier,
              let zone = TimeZone(identifier: identifier) else { return self }
        var calendar = self
        calendar.timeZone = zone
        return calendar
    }

    /// The journal day `date` belongs to on the clock of the zone it was logged
    /// in, keyed like every other journal day in this calendar: the start of
    /// the calendar date it is named after. A dose logged at 23:00 in Paris
    /// stays on that Paris evening's day when the journal is read in Tokyo,
    /// where the same instant is 07:00 the next morning. `nil` reads it on this
    /// calendar's own clock, which is plain ``journalDay(for:boundaryHour:)``.
    func journalDay(for date: Date, loggedIn identifier: String?, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        let zoned = loggedIn(identifier)
        guard zoned.timeZone != timeZone else { return journalDay(for: date, boundaryHour: boundaryHour) }
        let parts = zoned.dateComponents([.year, .month, .day], from: zoned.journalDay(for: date, boundaryHour: boundaryHour))
        return self.date(from: parts).map(startOfDay(for:)) ?? journalDay(for: date, boundaryHour: boundaryHour)
    }

    /// How far into its journal day `date` falls on the clock of the zone it
    /// was logged in, as minutes from the midnight that opens the day's
    /// calendar date: `0 ..< 1440` on that date, and `1440` on for the hours
    /// after midnight that still belong to it (with a 4 AM start, 01:30 is
    /// 1530). Slot times and the adherence noon split are read on this scale,
    /// so a dose at 01:30 is the end of the evening before rather than the
    /// small hours of a morning.
    func journalMinutes(for date: Date, loggedIn identifier: String?, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Int {
        let zoned = loggedIn(identifier)
        let parts = zoned.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let afterMidnight = zoned.startOfDay(for: date) != zoned.journalDay(for: date, boundaryHour: boundaryHour)
        return afterMidnight ? minutes + 1_440 : minutes
    }

    /// A reminder slot (minutes from midnight) on the
    /// ``journalMinutes(for:loggedIn:boundaryHour:)`` scale: a slot before the
    /// boundary hour comes after midnight, at the end of its journal day.
    static func journalMinutes(ofSlot minutes: Int, boundaryHour: Int = sessionDayBoundaryHour) -> Int {
        minutes < boundaryHour * 60 ? minutes + 1_440 : minutes
    }

    /// The instant a reminder slot (minutes from midnight) falls at within the
    /// journal day named `day`: that wall-clock time on the day's date, or on
    /// the next date for a slot before the boundary hour.
    func date(ofSlot minutes: Int, inJournalDay day: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> Date {
        let afterMidnight = Self.journalMinutes(ofSlot: minutes, boundaryHour: boundaryHour) >= 1_440
        let base = afterMidnight ? journalDay(after: day) : startOfDay(for: day)
        return date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: base)
            ?? base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// An interval of instants wide enough to hold every dose of the journal
    /// day named `day` whatever zone each was logged in: the day's own span
    /// widened by 26 hours each way, the distance from UTC−12 to UTC+14.
    /// Fetch with it, then keep the doses whose own journal day is `day`.
    func doseFetchWindow(forJournalDay day: Date, boundaryHour: Int = Self.sessionDayBoundaryHour) -> (start: Date, end: Date) {
        let slack: TimeInterval = 26 * 3_600
        let start = journalDayStart(of: day, boundaryHour: boundaryHour)
        let end = journalDayStart(of: journalDay(after: day), boundaryHour: boundaryHour)
        return (start.addingTimeInterval(-slack), end.addingTimeInterval(slack))
    }

    /// `shortWeekdaySymbols` rotated to start at `firstWeekday`.
    ///
    /// Foundation's `shortWeekdaySymbols` is **always** Sunday-first — index 0 is
    /// Sunday no matter what `firstWeekday` says. A month grid whose leading
    /// blanks are `(weekday - firstWeekday + 7) % 7` is therefore laid out
    /// Monday-first in most of Europe while its header still reads "Sun" over
    /// column 0, and every date appears one day early. That is the "calendar is
    /// a day behind" report; it is invisible in the US because `firstWeekday`
    /// is already 1 there.
    var orderedShortWeekdaySymbols: [String] {
        let symbols = shortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let offset = (firstWeekday - 1 + 7) % 7
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
