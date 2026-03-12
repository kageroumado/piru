import Testing
import Foundation
@testable import Piru

@Suite("DailyDoseItem")
struct DailyDoseItemTests {

    @Test("Initializes with correct default values")
    func defaults() {
        let item = DailyDoseItem(substance: "Caffeine", amount: 200)
        #expect(item.substance == "Caffeine")
        #expect(item.amount == 200)
        #expect(item.unit == "mg")
        #expect(item.route == .oral)
        #expect(item.sortOrder == 0)
    }

    @Test("Custom values are set correctly")
    func customValues() {
        let item = DailyDoseItem(
            substance: "Vitamin D",
            amount: 5000,
            unit: "IU",
            route: .oral,
            sortOrder: 3
        )
        #expect(item.substance == "Vitamin D")
        #expect(item.amount == 5000)
        #expect(item.unit == "IU")
        #expect(item.sortOrder == 3)
    }

    @Test("Defaults to daily frequency")
    func defaultFrequency() {
        let item = DailyDoseItem(substance: "Caffeine", amount: 200)
        #expect(item.frequency == .daily)
        #expect(item.frequencyDays.isEmpty)
    }

    @Test("Weekly frequency with start date")
    func weeklyFrequency() {
        let start = Date.now
        let item = DailyDoseItem(
            substance: "Testosterone",
            amount: 100,
            unit: "mg",
            route: .intramuscular,
            frequency: .weekly,
            startDate: start
        )
        #expect(item.frequency == .weekly)
        #expect(item.startDate == start)
    }

    @Test("Specific days stores weekday indices")
    func specificDaysFrequency() {
        let item = DailyDoseItem(
            substance: "Methotrexate",
            amount: 15,
            frequency: .specificDays,
            frequencyDays: [2, 4, 6]
        )
        #expect(item.frequency == .specificDays)
        #expect(item.frequencyDays == [2, 4, 6])
    }
}
