import Foundation
import Testing
@testable import Piru

/// The body-load row leaves its clear-by date out when My Meds schedules the
/// next dose before it: the projection covers only the doses logged so far.
@Suite("SessionBodyLoadSchedule")
@MainActor
struct SessionBodyLoadScheduleTests {
    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSinceReferenceDate: 800_000_000))!
    }

    private func med(
        frequency: DoseFrequency = .daily, intervalDays: Int = DoseFrequency.defaultIntervalDays,
        reminderMinutes: [Int] = [9 * 60], asNeeded: Bool = false,
    ) -> DailyDoseItem {
        DailyDoseItem(
            substance: "Sertraline", amount: 100, frequency: frequency, frequencyIntervalDays: intervalDays,
            startDate: calendar.startOfDay(for: now), reminderTimesMinutes: reminderMinutes, isAsNeeded: asNeeded,
        )
    }

    private func days(_ n: Double) -> Date {
        now.addingTimeInterval(n * 86_400)
    }

    @Test
    func `A daily med due tomorrow comes before a clear-by date days away`() {
        #expect(SessionBodyLoadModel.scheduledDose(of: [med()], before: days(5), now: now))
    }

    @Test
    func `A clear-by date before tomorrow's dose keeps its date`() throws {
        // Tomorrow's dose is at 9 AM; the substance clears at 6 AM.
        let clear = try #require(calendar.date(bySettingHour: 6, minute: 0, second: 0, of: days(1)))
        #expect(!SessionBodyLoadModel.scheduledDose(of: [med()], before: clear, now: now))
    }

    @Test
    func `A dose due later today comes before a clear-by date tonight`() throws {
        // 10 AM now, a 10 PM dose, clearing at 11 PM.
        let clear = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        #expect(SessionBodyLoadModel.scheduledDose(of: [med(reminderMinutes: [22 * 60])], before: clear, now: now))
    }

    @Test
    func `Today's dose taken early fills its slot`() throws {
        let clear = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        #expect(!SessionBodyLoadModel.scheduledDose(
            of: [med(reminderMinutes: [22 * 60])], before: clear, now: now, loggedToday: 1,
        ))
    }

    @Test
    func `The second slot of a twice-daily med is due after the first is taken`() throws {
        // 9 AM and 9 PM slots; the 9 AM dose is logged.
        let twice = med(reminderMinutes: [9 * 60, 21 * 60])
        let clear = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        #expect(SessionBodyLoadModel.scheduledDose(of: [twice], before: clear, now: now, loggedToday: 1))
        #expect(!SessionBodyLoadModel.scheduledDose(of: [twice], before: clear, now: now, loggedToday: 2))
    }

    @Test
    func `A slot already past today is not due`() throws {
        // The 9 AM dose was missed; nothing else is due before 11 PM.
        let clear = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        #expect(!SessionBodyLoadModel.scheduledDose(of: [med()], before: clear, now: now))
    }

    @Test
    func `A med every seven days counts only once its day comes`() {
        let weekly = med(frequency: .everyNDays, intervalDays: 7)
        #expect(!SessionBodyLoadModel.scheduledDose(of: [weekly], before: days(5), now: now))
        #expect(SessionBodyLoadModel.scheduledDose(of: [weekly], before: days(9), now: now))
    }

    @Test
    func `Without a scheduled med the date stands`() {
        #expect(!SessionBodyLoadModel.scheduledDose(of: [], before: days(30), now: now))
    }
}
