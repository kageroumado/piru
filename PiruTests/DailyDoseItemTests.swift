import Foundation
import Testing
@testable import Piru

@Suite("DailyDoseItem")
struct DailyDoseItemTests {
    @Test
    func `Initializes with correct default values`() {
        let item = DailyDoseItem(substance: "Caffeine", amount: 200)
        #expect(item.substance == "Caffeine")
        #expect(item.amount == 200)
        #expect(item.unit == "mg")
        #expect(item.route == .oral)
        #expect(item.sortOrder == 0)
    }

    @Test
    func `Meds redesign fields default correctly`() {
        let item = DailyDoseItem(substance: "Caffeine", amount: 200)
        #expect(item.reminderTimesMinutes.isEmpty)
        #expect(item.remind == true)
        #expect(item.askAgainOverrideMinutes == nil)
        #expect(item.isQuiet == false)
        #expect(item.isAsNeeded == false)
        #expect(item.maxPerDay == nil)
    }

    @Test
    func `Reminder times round-trip through JSON backing`() {
        let item = DailyDoseItem(substance: "Methylphenidate", amount: 10, reminderTimesMinutes: [480, 780])
        #expect(item.reminderTimesMinutes == [480, 780])
        item.reminderTimesMinutes = [540]
        #expect(item.reminderTimesMinutes == [540])
        item.reminderTimesMinutes = []
        #expect(item.reminderTimesMinutes.isEmpty)
    }

    @Test
    func `Ask Again override distinguishes nil from empty`() {
        let item = DailyDoseItem(substance: "Magnesium", amount: 400)
        #expect(item.askAgainOverrideMinutes == nil) // follow global default

        item.askAgainOverrideMinutes = [] // explicit opt-out
        #expect(item.askAgainOverrideMinutes == [])

        item.askAgainOverrideMinutes = [15, 45]
        #expect(item.askAgainOverrideMinutes == [15, 45])

        item.askAgainOverrideMinutes = nil // back to global
        #expect(item.askAgainOverrideMinutes == nil)
    }

    @Test
    func `As-needed item carries its daily cap`() {
        let item = DailyDoseItem(substance: "Ibuprofen", amount: 400, isAsNeeded: true, maxPerDay: 3)
        #expect(item.isAsNeeded)
        #expect(item.maxPerDay == 3)
    }

    @Test
    func `Custom values are set correctly`() {
        let item = DailyDoseItem(
            substance: "Vitamin D",
            amount: 5_000,
            unit: "IU",
            route: .oral,
            sortOrder: 3,
        )
        #expect(item.substance == "Vitamin D")
        #expect(item.amount == 5_000)
        #expect(item.unit == "IU")
        #expect(item.sortOrder == 3)
    }

    @Test
    func `Defaults to daily frequency`() {
        let item = DailyDoseItem(substance: "Caffeine", amount: 200)
        #expect(item.frequency == .daily)
        #expect(item.frequencyDays.isEmpty)
    }

    @Test
    func `Weekly frequency with start date`() {
        let start = Date.now
        let item = DailyDoseItem(
            substance: "Testosterone",
            amount: 100,
            unit: "mg",
            route: .intramuscular,
            frequency: .weekly,
            startDate: start,
        )
        #expect(item.frequency == .weekly)
        #expect(item.startDate == start)
    }

    @Test
    func `Specific days stores weekday indices`() {
        let item = DailyDoseItem(
            substance: "Methotrexate",
            amount: 15,
            frequency: .specificDays,
            frequencyDays: [2, 4, 6],
        )
        #expect(item.frequency == .specificDays)
        #expect(item.frequencyDays == [2, 4, 6])
    }
}
