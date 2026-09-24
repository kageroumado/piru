import Foundation
import Testing
@testable import Piru

@Suite("RampDownScheduler")
struct RampDownSchedulerTests {
    // MARK: - Cumulative dose check

    @Test
    func `No entries returns total equal to new amount, no alert`() {
        let (total, unit, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: "zzzNotReal",
            newAmount: 50,
            unit: "mg",
            route: .oral,
            existingEntries: [],
        )
        #expect(total == 50)
        #expect(unit == "mg")
        #expect(!shouldAlert)
    }

    @Test
    func `Old entries outside 12h window are excluded`() {
        let oldEntry = DoseEntry(
            substance: "TestDrug",
            amount: 1_000,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-13 * 3_600), // 13 hours ago
        )
        let (total, _, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 10,
            unit: "mg",
            route: .oral,
            existingEntries: [oldEntry],
        )
        #expect(total == 10) // Old entry excluded
    }

    @Test
    func `Recent entries of same substance are summed`() {
        let recent = DoseEntry(
            substance: "TestDrug",
            amount: 30,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-3_600), // 1 hour ago
        )
        let (total, _, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 20,
            unit: "mg",
            route: .oral,
            existingEntries: [recent],
        )
        #expect(total == 50)
    }

    @Test
    func `Entries of different substance are not summed`() {
        let different = DoseEntry(
            substance: "OtherDrug",
            amount: 500,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-3_600),
        )
        let (total, _, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 10,
            unit: "mg",
            route: .oral,
            existingEntries: [different],
        )
        #expect(total == 10)
    }

    @Test
    func `Case-insensitive substance matching in cumulative check`() {
        let entry = DoseEntry(
            substance: "CAFFEINE",
            amount: 200,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-1_800),
        )
        let (total, _, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 100,
            unit: "mg",
            route: .oral,
            existingEntries: [entry],
        )
        #expect(total == 300)
    }

    @Test
    func `A dose backdated past the window never alerts`() {
        // 5 g of caffeine is far past any ladder's heavy threshold; the only
        // thing standing between it and an alert is the dose's own date.
        let (current, _, alertsNow) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 5_000,
            unit: "mg",
            route: .oral,
            existingEntries: [],
        )
        #expect(current == 5_000)
        #expect(alertsNow)

        let (_, _, alertsBackdated) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 5_000,
            unit: "mg",
            route: .oral,
            doseTime: Date.now.addingTimeInterval(-400 * 86_400),
            existingEntries: [],
        )
        #expect(!alertsBackdated)

        let (_, _, alertsFuture) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 5_000,
            unit: "mg",
            route: .oral,
            doseTime: Date.now.addingTimeInterval(3_600),
            existingEntries: [],
        )
        #expect(!alertsFuture)
    }

    @Test
    func `Mixed-unit entries are converted before summing`() {
        // 0.2 g logged earlier + 100 mg now = 300 mg, not 100.2 of anything.
        let entry = DoseEntry(
            substance: "Caffeine",
            amount: 0.2,
            unit: "g",
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-1_800),
        )
        let (total, unit, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 100,
            unit: "mg",
            route: .oral,
            existingEntries: [entry],
        )
        #expect(total == 300)
        #expect(unit == "mg")
    }
}
