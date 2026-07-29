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
        let suite = UserDefaults(suiteName: "group.dev.yumeji.piru")
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
