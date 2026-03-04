import Testing
import Foundation
@testable import Piru

@Suite("DoseEntry")
struct DoseEntryTests {

    @Test("Initializes with correct default values")
    func defaults() {
        let entry = DoseEntry(substance: "Caffeine", amount: 100)
        #expect(entry.substance == "Caffeine")
        #expect(entry.amount == 100)
        #expect(entry.unit == "mg")
        #expect(entry.route == .oral)
        #expect(entry.notes == nil)
    }

    @Test("Custom values are set correctly")
    func customValues() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let entry = DoseEntry(
            substance: "Morphine",
            amount: 10,
            unit: "µg",
            route: .intravenous,
            timestamp: date,
            notes: "Test note"
        )
        #expect(entry.substance == "Morphine")
        #expect(entry.amount == 10)
        #expect(entry.unit == "µg")
        #expect(entry.route == .intravenous)
        #expect(entry.timestamp == date)
        #expect(entry.notes == "Test note")
    }

    @Test("Negative amount is clamped to zero")
    func negativeAmountClamped() {
        let entry = DoseEntry(substance: "Test", amount: -5)
        #expect(entry.amount == 0)
    }

    @Test("Zero amount is allowed")
    func zeroAmount() {
        let entry = DoseEntry(substance: "Test", amount: 0)
        #expect(entry.amount == 0)
    }

    @Test("Large amount is stored correctly")
    func largeAmount() {
        let entry = DoseEntry(substance: "Test", amount: 99999)
        #expect(entry.amount == 99999)
    }
}
