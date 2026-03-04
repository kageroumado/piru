import Testing
import Foundation
@testable import Piru

@Suite("AdherenceCalculator")
struct AdherenceCalculatorTests {

    // MARK: - Helpers

    private func makeEntry(substance: String, timestamp: Date = .now) -> DoseEntry {
        DoseEntry(substance: substance, amount: 10, route: .oral, timestamp: timestamp)
    }

    private func makeItem(substance: String) -> DailyDoseItem {
        DailyDoseItem(substance: substance, amount: 10, unit: "mg", route: .oral)
    }

    private var calendar: Calendar { Calendar.current }

    private var today: Date { calendar.startOfDay(for: .now) }

    private func dayOffset(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: today)!
    }

    // MARK: - entryMatches

    @Test("Entry matches item case-insensitive")
    func entryMatchesCaseInsensitive() {
        let entry = makeEntry(substance: "Caffeine")
        let item = makeItem(substance: "caffeine")
        #expect(AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    @Test("Entry does not match different substance")
    func entryNoMatch() {
        let entry = makeEntry(substance: "Caffeine")
        let item = makeItem(substance: "Melatonin")
        #expect(!AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    // MARK: - adherence()

    @Test("No daily items returns noData")
    func noDataWhenNoDailyItems() {
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [])
        #expect(result.status == .noData)
        #expect(result.takenCount == 0)
        #expect(result.totalCount == 0)
    }

    @Test("All items taken returns complete")
    func completeWhenAllTaken() {
        let items = [makeItem(substance: "Caffeine"), makeItem(substance: "Melatonin")]
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let entries = [
            makeEntry(substance: "Caffeine", timestamp: noon),
            makeEntry(substance: "Melatonin", timestamp: noon),
        ]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .complete)
        #expect(result.takenCount == 2)
        #expect(result.totalCount == 2)
    }

    @Test("Some items taken returns partial")
    func partialWhenSomeTaken() {
        let items = [makeItem(substance: "Caffeine"), makeItem(substance: "Melatonin")]
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let entries = [makeEntry(substance: "Caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .partial)
        #expect(result.takenCount == 1)
        #expect(result.totalCount == 2)
    }

    @Test("No items taken returns missed")
    func missedWhenNoneTaken() {
        let items = [makeItem(substance: "Caffeine")]
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: items)
        #expect(result.status == .missed)
        #expect(result.takenCount == 0)
        #expect(result.totalCount == 1)
    }

    @Test("Entries from different day not counted")
    func entriesFromDifferentDayIgnored() {
        let items = [makeItem(substance: "Caffeine")]
        let yesterday = dayOffset(-1).addingTimeInterval(3600 * 12)
        let entries = [makeEntry(substance: "Caffeine", timestamp: yesterday)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .missed)
    }

    @Test("Case-insensitive matching in adherence")
    func caseInsensitiveAdherence() {
        let items = [makeItem(substance: "CAFFEINE")]
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let entries = [makeEntry(substance: "caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .complete)
    }

    @Test("Adherence date is set correctly")
    func adherenceDateIsCorrect() {
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [])
        #expect(calendar.isDate(result.date, inSameDayAs: today))
    }

    // MARK: - currentStreak()

    @Test("No data returns zero streak")
    func zeroStreak() {
        #expect(AdherenceCalculator.currentStreak(adherenceData: []) == 0)
    }

    @Test("Consecutive complete days count as streak")
    func consecutiveStreak() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2),
            DayAdherence(date: dayOffset(-3), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 3)
    }

    @Test("Partial days count toward streak")
    func partialCountsInStreak() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .partial, takenCount: 1, totalCount: 2),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 2)
    }

    @Test("Missed day breaks streak")
    func missedBreaksStreak() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .missed, takenCount: 0, totalCount: 2),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 0)
    }

    @Test("Gap in dates breaks streak")
    func gapBreaksStreak() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2),
            // Day -2 missing
            DayAdherence(date: dayOffset(-3), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 1)
    }

    @Test("Today's complete data adds to streak")
    func todayAddsToStreak() {
        let data = [
            DayAdherence(date: today, status: .complete, takenCount: 2, totalCount: 2),
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 2)
    }

    @Test("Today's missed data does not add to streak")
    func todayMissedNotAdded() {
        let data = [
            DayAdherence(date: today, status: .missed, takenCount: 0, totalCount: 2),
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 1)
    }
}
