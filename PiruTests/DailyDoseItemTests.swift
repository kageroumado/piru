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
