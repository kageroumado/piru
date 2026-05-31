import Foundation
import Testing
@testable import Piru

@Suite("DoseEntry")
struct DoseEntryTests {
    @Test
    func `Initializes with correct default values`() {
        let entry = DoseEntry(substance: "Caffeine", amount: 100)
        #expect(entry.substance == "Caffeine")
        #expect(entry.amount == 100)
        #expect(entry.unit == "mg")
        #expect(entry.route == .oral)
        #expect(entry.notes == nil)
    }

    @Test
    func `Custom values are set correctly`() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let entry = DoseEntry(
            substance: "Morphine",
            amount: 10,
            unit: "µg",
            route: .intravenous,
            timestamp: date,
            notes: "Test note",
        )
        #expect(entry.substance == "Morphine")
        #expect(entry.amount == 10)
        #expect(entry.unit == "µg")
        #expect(entry.route == .intravenous)
        #expect(entry.timestamp == date)
        #expect(entry.notes == "Test note")
    }

    @Test
    func `Negative amount is clamped to zero`() {
        let entry = DoseEntry(substance: "Test", amount: -5)
        #expect(entry.amount == 0)
    }

    @Test
    func `Zero amount is allowed`() {
        let entry = DoseEntry(substance: "Test", amount: 0)
        #expect(entry.amount == 0)
    }

    @Test
    func `Large amount is stored correctly`() {
        let entry = DoseEntry(substance: "Test", amount: 99_999)
        #expect(entry.amount == 99_999)
    }
}
