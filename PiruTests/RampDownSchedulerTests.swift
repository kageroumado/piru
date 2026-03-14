import Testing
import Foundation
@testable import Piru

@Suite("RampDownScheduler")
struct RampDownSchedulerTests {

    // MARK: - Helpers

    private func makeDuration(
        onset: Double = 15,
        comeup: Double = 30,
        peak: Double = 120,
        offset: Double = 60,
        afterglow: Double? = nil
    ) -> DurationProfile {
        DurationProfile(
            onset: TimeRange(min: onset, max: onset),
            comeup: TimeRange(min: comeup, max: comeup),
            peak: TimeRange(min: peak, max: peak),
            offset: TimeRange(min: offset, max: offset),
            afterglow: afterglow.map { TimeRange(min: $0, max: $0) },
            total: nil
        )
    }

    // MARK: - calculateRedoseTime

    @Test("Comedown time is after dose time")
    func comedownTimeAfterDose() {
        let doseTime = Date.now
        let duration = makeDuration()
        let comedown = RampDownScheduler.calculateRedoseTime(doseTime: doseTime, duration: duration)
        #expect(comedown > doseTime)
    }

    @Test("Comedown time accounts for phase boundaries")
    func comedownTimePhaseBoundaries() {
        let doseTime = Date(timeIntervalSince1970: 0)
        // onset=15, comeup=30, peak=120 → peakEnd = 15+30+120 = 165
        // comeupMinutes = comeupEnd - onsetEnd = 45 - 15 = 30
        // redoseMinutes = peakEnd - comeupMinutes = 165 - 30 = 135
        let duration = makeDuration(onset: 15, comeup: 30, peak: 120)
        let comedown = RampDownScheduler.calculateRedoseTime(doseTime: doseTime, duration: duration)
        let expectedInterval = 135.0 * 60 // 135 minutes in seconds
        #expect(abs(comedown.timeIntervalSince(doseTime) - expectedInterval) < 1)
    }

    @Test("Very short duration still produces non-negative offset")
    func shortDurationNonNegative() {
        let doseTime = Date.now
        let duration = makeDuration(onset: 0, comeup: 0, peak: 5)
        let comedown = RampDownScheduler.calculateRedoseTime(doseTime: doseTime, duration: duration)
        #expect(comedown >= doseTime)
    }

    // MARK: - suggestedRedoseAmount

    @Test("Suggested redose is 33% of initial")
    func redoseIsOneThird() {
        #expect(RampDownScheduler.suggestedRedoseAmount(100) == 33)
    }

    @Test("Suggested redose rounds to one decimal")
    func redoseRoundsToOneDecimal() {
        // 75 * 0.33 = 24.75 → 24.8
        #expect(RampDownScheduler.suggestedRedoseAmount(75) == 24.8)
    }

    @Test("Suggested redose of zero is zero")
    func redoseOfZero() {
        #expect(RampDownScheduler.suggestedRedoseAmount(0) == 0)
    }

    @Test("Suggested redose of small amount")
    func redoseSmallAmount() {
        // 10 * 0.33 = 3.3
        #expect(RampDownScheduler.suggestedRedoseAmount(10) == 3.3)
    }

    // MARK: - Notification identifier

    @Test("Notification identifiers are deterministic")
    func notificationIdDeterministic() {
        // Test via the public isActive/saveActiveEntry/removeActiveEntry API
        // These use UserDefaults, so we test the key format indirectly
        let entryID = 42
        RampDownScheduler.saveActiveEntry(entryID)
        #expect(RampDownScheduler.isActive(for: entryID))
        RampDownScheduler.removeActiveEntry(entryID)
        #expect(!RampDownScheduler.isActive(for: entryID))
    }

    // MARK: - Persistence (UserDefaults)

    @Test("Save and check active entry")
    func saveAndCheckActive() {
        let id = Int.random(in: 100000...999999)
        RampDownScheduler.saveActiveEntry(id)
        #expect(RampDownScheduler.isActive(for: id))
        // Cleanup
        RampDownScheduler.removeActiveEntry(id)
    }

    @Test("Remove clears active entry")
    func removeActive() {
        let id = Int.random(in: 100000...999999)
        RampDownScheduler.saveActiveEntry(id)
        RampDownScheduler.removeActiveEntry(id)
        #expect(!RampDownScheduler.isActive(for: id))
    }

    @Test("Non-existent entry is not active")
    func nonExistentNotActive() {
        #expect(!RampDownScheduler.isActive(for: -999))
    }

    @Test("Multiple entries can be active simultaneously")
    func multipleActive() {
        let id1 = Int.random(in: 100000...999999)
        let id2 = Int.random(in: 100000...999999)
        RampDownScheduler.saveActiveEntry(id1)
        RampDownScheduler.saveActiveEntry(id2)
        #expect(RampDownScheduler.isActive(for: id1))
        #expect(RampDownScheduler.isActive(for: id2))
        // Cleanup
        RampDownScheduler.removeActiveEntry(id1)
        RampDownScheduler.removeActiveEntry(id2)
    }

    // MARK: - Cumulative dose check

    @Test("No entries returns total equal to new amount, no alert")
    func cumulativeNoEntries() {
        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: "zzzNotReal",
            newAmount: 50,
            unit: "mg",
            route: .oral,
            existingEntries: []
        )
        #expect(total == 50)
        #expect(!shouldAlert)
    }

    @Test("Old entries outside 12h window are excluded")
    func cumulativeOldEntriesExcluded() {
        let oldEntry = DoseEntry(
            substance: "TestDrug",
            amount: 1000,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-13 * 3600) // 13 hours ago
        )
        let (total, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 10,
            unit: "mg",
            route: .oral,
            existingEntries: [oldEntry]
        )
        #expect(total == 10) // Old entry excluded
    }

    @Test("Recent entries of same substance are summed")
    func cumulativeRecentSummed() {
        let recent = DoseEntry(
            substance: "TestDrug",
            amount: 30,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-3600) // 1 hour ago
        )
        let (total, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 20,
            unit: "mg",
            route: .oral,
            existingEntries: [recent]
        )
        #expect(total == 50)
    }

    @Test("Entries of different substance are not summed")
    func cumulativeDifferentSubstance() {
        let different = DoseEntry(
            substance: "OtherDrug",
            amount: 500,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-3600)
        )
        let (total, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "TestDrug",
            newAmount: 10,
            unit: "mg",
            route: .oral,
            existingEntries: [different]
        )
        #expect(total == 10)
    }

    @Test("Case-insensitive substance matching in cumulative check")
    func cumulativeCaseInsensitive() {
        let entry = DoseEntry(
            substance: "CAFFEINE",
            amount: 200,
            route: .oral,
            timestamp: Date.now.addingTimeInterval(-1800)
        )
        let (total, _) = RampDownScheduler.checkCumulativeDose(
            substanceName: "caffeine",
            newAmount: 100,
            unit: "mg",
            route: .oral,
            existingEntries: [entry]
        )
        #expect(total == 300)
    }
}
