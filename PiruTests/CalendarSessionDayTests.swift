import Foundation
import Testing
@testable import Piru

@Suite("CalendarSessionDay")
struct CalendarSessionDayTests {
    /// Build a Calendar configured for the test, plus a fixed reference date.
    /// All session-day arithmetic is timezone-relative, so we pin to GMT for
    /// reproducibility.
    private func setup() -> (Calendar, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        // 2026-05-22 00:00 UTC
        let comps = DateComponents(timeZone: cal.timeZone, year: 2_026, month: 5, day: 22)
        return (cal, cal.date(from: comps)!)
    }

    /// Override the App Group UserDefaults key for the test, defer cleanup.
    private func withBoundaryHour(_ hour: Int, _ work: () -> Void) {
        let suite = UserDefaults(suiteName: AppIdentity.appGroup)
        let previous = suite?.object(forKey: Calendar.dayBoundaryHourKey)
        suite?.set(hour, forKey: Calendar.dayBoundaryHourKey)
        defer {
            if let previous {
                suite?.set(previous, forKey: Calendar.dayBoundaryHourKey)
            } else {
                suite?.removeObject(forKey: Calendar.dayBoundaryHourKey)
            }
        }
        work()
    }

    @Test
    func `Dose at 02:00 with 4 AM cutoff maps to previous calendar day`() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let twoAM = midnight.addingTimeInterval(2 * 3_600)
            let sessionStart = cal.sessionDayStart(for: twoAM)
            // Should be 04:00 on the previous day.
            let expected = midnight.addingTimeInterval(-24 * 3_600).addingTimeInterval(4 * 3_600)
            #expect(sessionStart == expected)
        }
    }

    @Test
    func `Dose at 04:00 (exactly the cutoff) starts the new session day`() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let fourAM = midnight.addingTimeInterval(4 * 3_600)
            let sessionStart = cal.sessionDayStart(for: fourAM)
            #expect(sessionStart == fourAM)
        }
    }

    @Test
    func `Dose at 14:00 belongs to that day's session`() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let twoPM = midnight.addingTimeInterval(14 * 3_600)
            let sessionStart = cal.sessionDayStart(for: twoPM)
            let expected = midnight.addingTimeInterval(4 * 3_600)
            #expect(sessionStart == expected)
        }
    }

    @Test
    func `Cutoff of 0 reproduces classic midnight grouping`() {
        let (cal, midnight) = setup()
        withBoundaryHour(0) {
            let twoAM = midnight.addingTimeInterval(2 * 3_600)
            // With 0 cutoff, 02:00 belongs to the calendar day starting 00:00.
            #expect(cal.sessionDayStart(for: twoAM) == midnight)
        }
    }

    @Test
    func `Session day spans 24 hours`() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let noon = midnight.addingTimeInterval(12 * 3_600)
            let start = cal.sessionDayStart(for: noon)
            let end = cal.sessionDayEnd(for: noon)
            #expect(end.timeIntervalSince(start) == 86_400)
        }
    }

    // MARK: Journal day (kageroumado/piru#23)

    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func at(_ cal: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func midnight(_ cal: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test
    func `03:59 belongs to the previous journal day with a 4 AM start`() {
        let cal = calendar("Europe/Paris")
        let late = at(cal, 2_026, 10, 30, 3, 59)
        #expect(cal.journalDay(for: late, boundaryHour: 4) == midnight(cal, 2_026, 10, 29))
        #expect(cal.sessionDayStart(for: late, boundaryHour: 4) == at(cal, 2_026, 10, 29, 4))
        #expect(cal.sessionDayEnd(for: late, boundaryHour: 4) == at(cal, 2_026, 10, 30, 4))
    }

    @Test
    func `04:00 starts the new journal day`() {
        let cal = calendar("Europe/Paris")
        let four = at(cal, 2_026, 10, 30, 4)
        #expect(cal.journalDay(for: four, boundaryHour: 4) == midnight(cal, 2_026, 10, 30))
        #expect(cal.sessionDayStart(for: four, boundaryHour: 4) == four)
    }

    /// Hour 0 is the calendar day: every hour of a date keys to its own midnight.
    @Test(arguments: [0, 1, 3, 4, 12, 23])
    func `A midnight day start is the calendar day`(hour: Int) {
        let cal = calendar("America/New_York")
        let date = at(cal, 2_026, 6, 10, hour, 30)
        #expect(cal.journalDay(for: date, boundaryHour: 0) == cal.startOfDay(for: date))
        #expect(cal.sessionDayStart(for: date, boundaryHour: 0) == cal.startOfDay(for: date))
    }

    /// US spring-forward, 2026-03-08: 02:00 does not exist, so the day is 23 hours.
    /// The 4 AM boundary is still 04:00 on the wall clock, three hours after midnight.
    @Test
    func `The spring-forward journal day is 23 hours and starts at 04:00 local`() {
        let cal = calendar("America/New_York")
        let start = cal.journalDayStart(of: midnight(cal, 2_026, 3, 8), boundaryHour: 4)
        #expect(cal.component(.hour, from: start) == 4)
        #expect(start.timeIntervalSince(midnight(cal, 2_026, 3, 8)) == 3 * 3_600)
        #expect(cal.journalDay(for: at(cal, 2_026, 3, 8, 3, 30), boundaryHour: 4) == midnight(cal, 2_026, 3, 7))
        #expect(cal.journalDay(for: at(cal, 2_026, 3, 8, 4), boundaryHour: 4) == midnight(cal, 2_026, 3, 8))
        let noon = at(cal, 2_026, 3, 7, 12)
        #expect(cal.sessionDayEnd(for: noon, boundaryHour: 4).timeIntervalSince(cal.sessionDayStart(for: noon, boundaryHour: 4)) == 23 * 3_600)
    }

    /// A boundary hour DST skips moves to the next time that exists.
    @Test
    func `A skipped boundary hour starts the day at the next existing time`() {
        let cal = calendar("America/New_York")
        let start = cal.journalDayStart(of: midnight(cal, 2_026, 3, 8), boundaryHour: 2)
        #expect(start == at(cal, 2_026, 3, 8, 3))
        #expect(cal.journalDay(for: at(cal, 2_026, 3, 8, 1, 59), boundaryHour: 2) == midnight(cal, 2_026, 3, 7))
        #expect(cal.journalDay(for: start, boundaryHour: 2) == midnight(cal, 2_026, 3, 8))
    }

    /// US fall-back, 2026-11-01: 01:00–02:00 happens twice, so the day is 25 hours,
    /// and both 01:30s are still before 04:00.
    @Test
    func `The fall-back journal day is 25 hours and both 01:30s stay on the day before`() {
        let cal = calendar("America/New_York")
        let firstOneThirty = at(cal, 2_026, 11, 1, 1, 30)
        let secondOneThirty = firstOneThirty.addingTimeInterval(3_600)
        #expect(cal.component(.hour, from: secondOneThirty) == 1)
        #expect(cal.journalDay(for: firstOneThirty, boundaryHour: 4) == midnight(cal, 2_026, 10, 31))
        #expect(cal.journalDay(for: secondOneThirty, boundaryHour: 4) == midnight(cal, 2_026, 10, 31))
        let noon = at(cal, 2_026, 10, 31, 12)
        #expect(cal.sessionDayEnd(for: noon, boundaryHour: 4).timeIntervalSince(cal.sessionDayStart(for: noon, boundaryHour: 4)) == 25 * 3_600)
        #expect(cal.sessionDayEnd(for: noon, boundaryHour: 4) == at(cal, 2_026, 11, 1, 4))
    }

    @Test
    func `Today and Yesterday name journal days`() {
        let cal = calendar("Asia/Shanghai")
        let twoAM = at(cal, 2_026, 10, 31, 2)
        #expect(cal.isJournalDayToday(midnight(cal, 2_026, 10, 30), now: twoAM, boundaryHour: 4))
        #expect(!cal.isJournalDayToday(midnight(cal, 2_026, 10, 31), now: twoAM, boundaryHour: 4))
        #expect(cal.isJournalDayYesterday(midnight(cal, 2_026, 10, 29), now: twoAM, boundaryHour: 4))
        #expect(cal.isJournalDayToday(midnight(cal, 2_026, 10, 31), now: twoAM, boundaryHour: 0))
    }

    /// A Sunday-first calendar is the identity case — this is why the header bug
    /// never showed up in the US.
    @Test
    func `Sunday-first locale leaves the weekday header unrotated`() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.firstWeekday = 1
        #expect(cal.orderedShortWeekdaySymbols == cal.shortWeekdaySymbols)
    }

    /// The reported bug: a Monday-first grid under a Sunday-first header put
    /// every date one column early.
    @Test
    func `Monday-first locale rotates the weekday header to match the grid`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_GB")
        cal.firstWeekday = 2

        let ordered = cal.orderedShortWeekdaySymbols
        #expect(ordered.count == 7)
        #expect(ordered.first == cal.shortWeekdaySymbols[1])
        #expect(ordered.last == cal.shortWeekdaySymbols[0])

        // The header column a given date lands in must be the column the grid's
        // leading-blank math puts it in. 2026-07-01 is a Wednesday; under a
        // Monday-first calendar that is column 2, which must read "Wed".
        let july1 = try #require(cal.date(from: DateComponents(year: 2_026, month: 7, day: 1)))
        let column = (cal.component(.weekday, from: july1) - cal.firstWeekday + 7) % 7
        #expect(ordered[column] == cal.shortWeekdaySymbols[cal.component(.weekday, from: july1) - 1])
    }

    /// Every `firstWeekday` the API admits must produce a 7-symbol rotation whose
    /// column mapping round-trips.
    @Test(arguments: 1 ... 7)
    func `Weekday header rotation round-trips for every first weekday`(first: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = first
        let ordered = cal.orderedShortWeekdaySymbols
        #expect(ordered.count == 7)
        #expect(Set(ordered) == Set(cal.shortWeekdaySymbols))
        for weekday in 1 ... 7 {
            let column = (weekday - first + 7) % 7
            #expect(ordered[column] == cal.shortWeekdaySymbols[weekday - 1])
        }
    }
}
