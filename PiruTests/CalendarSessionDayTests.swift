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
        let comps = DateComponents(timeZone: cal.timeZone, year: 2026, month: 5, day: 22)
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

    @Test("Dose at 02:00 with 4 AM cutoff maps to previous calendar day")
    func lateNightDosesRollBack() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let twoAM = midnight.addingTimeInterval(2 * 3600)
            let sessionStart = cal.sessionDayStart(for: twoAM)
            // Should be 04:00 on the previous day.
            let expected = midnight.addingTimeInterval(-24 * 3600).addingTimeInterval(4 * 3600)
            #expect(sessionStart == expected)
        }
    }

    @Test("Dose at 04:00 (exactly the cutoff) starts the new session day")
    func cutoffHourStartsNewDay() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let fourAM = midnight.addingTimeInterval(4 * 3600)
            let sessionStart = cal.sessionDayStart(for: fourAM)
            #expect(sessionStart == fourAM)
        }
    }

    @Test("Dose at 14:00 belongs to that day's session")
    func eveningDosesStayOnSameDay() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let twoPM = midnight.addingTimeInterval(14 * 3600)
            let sessionStart = cal.sessionDayStart(for: twoPM)
            let expected = midnight.addingTimeInterval(4 * 3600)
            #expect(sessionStart == expected)
        }
    }

    @Test("Cutoff of 0 reproduces classic midnight grouping")
    func zeroCutoffMatchesMidnight() {
        let (cal, midnight) = setup()
        withBoundaryHour(0) {
            let twoAM = midnight.addingTimeInterval(2 * 3600)
            // With 0 cutoff, 02:00 belongs to the calendar day starting 00:00.
            #expect(cal.sessionDayStart(for: twoAM) == midnight)
        }
    }

    @Test("Session day spans 24 hours")
    func sessionDayEndIs24HoursAfterStart() {
        let (cal, midnight) = setup()
        withBoundaryHour(4) {
            let noon = midnight.addingTimeInterval(12 * 3600)
            let start = cal.sessionDayStart(for: noon)
            let end = cal.sessionDayEnd(for: noon)
            #expect(end.timeIntervalSince(start) == 86400)
        }
    }
}
