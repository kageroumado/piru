import Foundation
import Testing
@testable import Piru

/// What a My Meds reminder stages in quick log: the group's meds not yet taken
/// today, by the rule My Meds ticks slots off with.
@MainActor
@Suite("Routine staging")
struct RoutineStagingTests {
    private let calendar = Calendar.current
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func med(_ name: String, times: [Int], asNeeded: Bool = false) -> DailyDoseItem {
        DailyDoseItem(substance: name, amount: 10, reminderTimesMinutes: times, isAsNeeded: asNeeded)
    }

    private func names(_ items: [DailyDoseItem]) -> [String] {
        items.map(\.substance)
    }

    @Test
    func `A med taken this morning is left out; one not taken stays`() {
        let taken = med("ZZTestMedA", times: [8 * 60])
        let pending = med("ZZTestMedB", times: [9 * 60])
        let dose = DoseEntry(medication: taken, timestamp: at(8, 5))
        let staged = MedTimeGroup.membersToStage(
            of: .morning, items: [taken, pending], todayEntries: [dose], calendar: calendar,
        )
        #expect(names(staged) == ["ZZTestMedB"])
    }

    @Test
    func `Every med in the group taken stages nothing`() {
        let first = med("ZZTestMedA", times: [8 * 60])
        let second = med("ZZTestMedB", times: [9 * 60])
        let doses = [
            DoseEntry(medication: first, timestamp: at(8)),
            DoseEntry(medication: second, timestamp: at(9, 30)),
        ]
        let staged = MedTimeGroup.membersToStage(
            of: .morning, items: [first, second], todayEntries: doses, calendar: calendar,
        )
        #expect(staged.isEmpty)
    }

    @Test
    func `A twice-daily med taken in the morning is still staged in the evening`() {
        let twice = med("ZZTestMedA", times: [8 * 60, 20 * 60])
        let dose = DoseEntry(medication: twice, timestamp: at(8, 10))
        #expect(MedTimeGroup.membersToStage(of: .morning, items: [twice], todayEntries: [dose], calendar: calendar).isEmpty)
        #expect(names(MedTimeGroup.membersToStage(of: .evening, items: [twice], todayEntries: [dose], calendar: calendar)) == ["ZZTestMedA"])
    }

    @Test
    func `A dose checked off for the evening slot leaves the morning slot open`() {
        let twice = med("ZZTestMedA", times: [8 * 60, 20 * 60])
        let dose = DoseEntry(medication: twice, timestamp: at(9), slotMinutes: 20 * 60)
        #expect(names(MedTimeGroup.membersToStage(of: .morning, items: [twice], todayEntries: [dose], calendar: calendar)) == ["ZZTestMedA"])
        #expect(MedTimeGroup.membersToStage(of: .evening, items: [twice], todayEntries: [dose], calendar: calendar).isEmpty)
    }

    @Test
    func `An anytime med taken today is left out`() {
        let anytime = med("ZZTestMedA", times: [])
        let dose = DoseEntry(medication: anytime, timestamp: at(14))
        #expect(MedTimeGroup.membersToStage(of: .anytime, items: [anytime], todayEntries: [dose], calendar: calendar).isEmpty)
        #expect(names(MedTimeGroup.membersToStage(of: .anytime, items: [anytime], todayEntries: [], calendar: calendar)) == ["ZZTestMedA"])
    }

    @Test
    func `An as-needed med is always staged`() {
        let prn = med("ZZTestMedA", times: [], asNeeded: true)
        let dose = DoseEntry(medication: prn, timestamp: at(10))
        #expect(names(MedTimeGroup.membersToStage(of: .asNeeded, items: [prn], todayEntries: [dose], calendar: calendar)) == ["ZZTestMedA"])
    }
}
