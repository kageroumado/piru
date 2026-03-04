import Testing
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
}
