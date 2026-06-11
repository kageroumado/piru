import Foundation
import Testing
@testable import Piru

@Suite("RampDownScheduler")
struct RampDownSchedulerTests {
    // MARK: - Helpers

    private func makeDuration(
        onset: Double = 15,
        comeup: Double = 30,
        peak: Double = 120,
        offset: Double = 60,
        afterglow: Double? = nil,
    ) -> DurationProfile {
        DurationProfile(
            onset: DurationRange(min: onset, max: onset),
            comeup: DurationRange(min: comeup, max: comeup),
            peak: DurationRange(min: peak, max: peak),
            offset: DurationRange(min: offset, max: offset),
            afterglow: afterglow.map { DurationRange(min: $0, max: $0) },
            total: nil,
        )
    }

    // MARK: - comedownStartTime

    @Test
    func `Comedown time is after dose time`() {
        let doseTime = Date.now
        let duration = makeDuration()
        let comedown = RampDownScheduler.comedownStartTime(doseTime: doseTime, duration: duration)
        #expect(comedown > doseTime)
    }

    @Test
    func `Comedown time accounts for phase boundaries`() {
        let doseTime = Date(timeIntervalSince1970: 0)
        // onset=15, comeup=30, peak=120 → peakEnd = 15+30+120 = 165
        // comeupMinutes = comeupEnd - onsetEnd = 45 - 15 = 30
        // redoseMinutes = peakEnd - comeupMinutes = 165 - 30 = 135
        let duration = makeDuration(onset: 15, comeup: 30, peak: 120)
        let comedown = RampDownScheduler.comedownStartTime(doseTime: doseTime, duration: duration)
        let expectedInterval = 135.0 * 60 // 135 minutes in seconds
        #expect(abs(comedown.timeIntervalSince(doseTime) - expectedInterval) < 1)
    }

    @Test
    func `Very short duration still produces non-negative offset`() {
        let doseTime = Date.now
        let duration = makeDuration(onset: 0, comeup: 0, peak: 5)
        let comedown = RampDownScheduler.comedownStartTime(doseTime: doseTime, duration: duration)
        #expect(comedown >= doseTime)
    }

    // MARK: - suggestedRedoseAmount

    @Test
    func `Suggested redose is 33% of initial`() {
        #expect(RampDownScheduler.suggestedRedoseAmount(100) == 33)
    }

    @Test
    func `Suggested redose rounds to one decimal`() {
        // 75 * 0.33 = 24.75 → 24.8
        #expect(RampDownScheduler.suggestedRedoseAmount(75) == 24.8)
    }

    @Test
    func `Suggested redose of zero is zero`() {
        #expect(RampDownScheduler.suggestedRedoseAmount(0) == 0)
    }

    @Test
    func `Suggested redose of small amount`() {
        // 10 * 0.33 = 3.3
        #expect(RampDownScheduler.suggestedRedoseAmount(10) == 3.3)
    }

    // MARK: - Entry key

    @Test
    func `Entry key is the entry's stable id — repeatable per entry, distinct across entries`() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let a = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", timestamp: timestamp)
        let b = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", timestamp: timestamp)
        // Repeatable for the same entry…
        #expect(RampDownScheduler.entryKey(for: a) == RampDownScheduler.entryKey(for: a))
        // …but two content-identical doses are still distinguishable (the
        // failure mode of the old substance-timestamp key).
        #expect(RampDownScheduler.entryKey(for: a) != RampDownScheduler.entryKey(for: b))
        #expect(RampDownScheduler.entryKey(for: a) == a.id.uuidString)
    }

    @Test
    func `Entry key survives a timestamp edit`() {
        let entry = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        let keyBefore = RampDownScheduler.entryKey(for: entry)
        entry.timestamp = entry.timestamp.addingTimeInterval(3_600)
        #expect(RampDownScheduler.entryKey(for: entry) == keyBefore)
    }

    // MARK: - Persistence (UserDefaults)

    @Test
    func `Save and check active entry`() {
        let key = UUID().uuidString
        RampDownScheduler.saveActiveEntry(key)
        #expect(RampDownScheduler.isActive(for: key))
        // Cleanup
        RampDownScheduler.removeActiveEntry(key)
    }

    @Test
    func `Remove clears active entry`() {
        let key = UUID().uuidString
        RampDownScheduler.saveActiveEntry(key)
        RampDownScheduler.removeActiveEntry(key)
        #expect(!RampDownScheduler.isActive(for: key))
    }

    @Test
    func `Non-existent entry is not active`() {
        #expect(!RampDownScheduler.isActive(for: UUID().uuidString))
    }

    @Test
    func `Multiple entries can be active simultaneously`() {
        let key1 = UUID().uuidString
        let key2 = UUID().uuidString
        RampDownScheduler.saveActiveEntry(key1)
        RampDownScheduler.saveActiveEntry(key2)
        #expect(RampDownScheduler.isActive(for: key1))
        #expect(RampDownScheduler.isActive(for: key2))
        // Cleanup
        RampDownScheduler.removeActiveEntry(key1)
        RampDownScheduler.removeActiveEntry(key2)
    }

    @Test
    func `Legacy key formats are dropped on read`() {
        // Pre-V4 formats: per-launch hashValue ints and substance-timestamp
        // strings. Both orphan (no current key ever matches) and are pruned by
        // loadActiveEntries' UUID filter.
        RampDownScheduler.saveActiveEntry("Caffeine-1700000000.0")
        RampDownScheduler.saveActiveEntry("-3458764513820540928")
        #expect(!RampDownScheduler.isActive(for: "Caffeine-1700000000.0"))
        #expect(!RampDownScheduler.isActive(for: "-3458764513820540928"))
        // A real UUID key saved alongside still round-trips.
        let key = UUID().uuidString
        RampDownScheduler.saveActiveEntry(key)
        #expect(RampDownScheduler.isActive(for: key))
        RampDownScheduler.removeActiveEntry(key)
    }

    // MARK: - Cumulative dose check

    @Test
    func `No entries returns total equal to new amount, no alert`() {
        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: "zzzNotReal",
            newAmount: 50,
            unit: "mg",
            route: .oral,
            existingEntries: [],
        )
        #expect(total == 50)
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
        let (total, _) = RampDownScheduler.checkCumulativeDose(
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
        let (total, _) = RampDownScheduler.checkCumulativeDose(
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
        let (total, _) = RampDownScheduler.checkCumulativeDose(
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
        let (total, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 100,
            unit: "mg",
            route: .oral,
            existingEntries: [entry],
        )
        #expect(total == 300)
    }
}
