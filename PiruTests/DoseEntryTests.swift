import CoreLocation
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

    // MARK: - Unknown amount

    @Test
    func `Unknown-dose flag defaults to false and the amount reads as a number`() {
        let entry = DoseEntry(substance: "Caffeine", amount: 100)
        #expect(entry.isUnknownDose == false)
        #expect(entry.amountDisplay == "100")
    }

    @Test
    func `An unknown dose stores amount 0, reads as ?, and is never approximate`() {
        let entry = DoseEntry(substance: "Cocaine", amount: 40, unit: "mg", route: .insufflation, isApproximate: true, isUnknownDose: true)
        #expect(entry.isUnknownDose)
        #expect(entry.amount == 0)
        #expect(entry.amountDisplay == "?")
        #expect(entry.isApproximate == false)
        #expect(entry.unit == "mg")
        #expect(entry.route == .insufflation)
    }

    // MARK: - Location

    @Test
    func `Location fields default to nil`() {
        let entry = DoseEntry(substance: "Test", amount: 10)
        #expect(entry.locationName == nil)
        #expect(entry.latitude == nil)
        #expect(entry.longitude == nil)
        #expect(entry.coordinate == nil)
    }

    @Test
    func `coordinate is non-nil only when both latitude and longitude are set`() {
        let full = DoseEntry(
            substance: "Test",
            amount: 10,
            locationName: "Home",
            latitude: 51.5,
            longitude: -0.12,
        )
        #expect(full.coordinate?.latitude == 51.5)
        #expect(full.coordinate?.longitude == -0.12)

        // A name without coordinates yields no coordinate.
        let nameOnly = DoseEntry(substance: "Test", amount: 10, locationName: "Somewhere")
        #expect(nameOnly.coordinate == nil)

        // A lone latitude (no longitude) is not a usable coordinate.
        let partial = DoseEntry(substance: "Test", amount: 10, latitude: 51.5)
        #expect(partial.coordinate == nil)
    }
}
