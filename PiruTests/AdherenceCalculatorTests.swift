import Foundation
import Testing
@testable import Piru

@Suite("AdherenceCalculator")
struct AdherenceCalculatorTests {
    // MARK: - Helpers

    private func makeEntry(
        substance: String,
        route: RouteOfAdministration = .oral,
        substanceUID: String? = nil,
        timestamp: Date = .now,
    ) -> DoseEntry {
        DoseEntry(substance: substance, amount: 10, route: route, substanceUID: substanceUID, timestamp: timestamp)
    }

    private func makeItem(
        substance: String,
        route: RouteOfAdministration = .oral,
        frequency: DoseFrequency = .daily,
        frequencyDays: [Int] = [],
        startDate: Date = .distantPast,
        substanceUID: String? = nil,
        reminderTimesMinutes: [Int] = [],
        isAsNeeded: Bool = false,
    ) -> DailyDoseItem {
        DailyDoseItem(
            substance: substance, amount: 10, unit: "mg", route: route,
            frequency: frequency, frequencyDays: frequencyDays, startDate: startDate,
            substanceUID: substanceUID,
            reminderTimesMinutes: reminderTimesMinutes, isAsNeeded: isAsNeeded,
        )
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var today: Date {
        calendar.startOfDay(for: .now)
    }

    private func dayOffset(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: today)!
    }

    // MARK: - entryMatches

    @Test
    func `Entry matches item case-insensitive`() {
        let entry = makeEntry(substance: "Caffeine")
        let item = makeItem(substance: "caffeine")
        #expect(AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    @Test
    func `Entry does not match different substance`() {
        let entry = makeEntry(substance: "Caffeine")
        let item = makeItem(substance: "Melatonin")
        #expect(!AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    @Test
    func `Identity join credits a brand-name item from a generic-name dose`() {
        // Same resolved PSID identity under different display names.
        let entry = makeEntry(substance: "Methylphenidate", substanceUID: "psid:mph")
        let item = makeItem(substance: "Concerta", substanceUID: "psid:mph")
        #expect(AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    @Test
    func `Route mismatch never credits, even with matching identity`() {
        // Boundary semantics: MPH injected is a journal entry, not adherence
        // credit against the oral prescription.
        let entry = makeEntry(substance: "Methylphenidate", route: .intravenous, substanceUID: "psid:mph")
        let item = makeItem(substance: "Methylphenidate", route: .oral, substanceUID: "psid:mph")
        #expect(!AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    @Test
    func `Name fallback still matches when only one side is PSID-resolved`() {
        let entry = makeEntry(substance: "Caffeine")
        let item = makeItem(substance: "caffeine", substanceUID: "psid:caffeine")
        #expect(AdherenceCalculator.entryMatches(entry: entry, item: item))
    }

    // MARK: - isDue()

    @Test
    func `Daily item is always due`() {
        let item = makeItem(substance: "Caffeine", frequency: .daily)
        #expect(AdherenceCalculator.isDue(item, on: today))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(-5)))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(10)))
    }

    @Test
    func `Weekly item due on start day only`() {
        let item = makeItem(substance: "Testosterone", frequency: .weekly, startDate: today)
        #expect(AdherenceCalculator.isDue(item, on: today))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(1)))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(3)))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(7)))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(14)))
    }

    @Test
    func `Every other day alternates correctly`() {
        let item = makeItem(substance: "Vitamin D", frequency: .everyOtherDay, startDate: today)
        #expect(AdherenceCalculator.isDue(item, on: today))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(1)))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(2)))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(3)))
    }

    @Test
    func `Biweekly item due every 14 days`() {
        let item = makeItem(substance: "B12", frequency: .biweekly, startDate: today)
        #expect(AdherenceCalculator.isDue(item, on: today))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(7)))
        #expect(AdherenceCalculator.isDue(item, on: dayOffset(14)))
    }

    @Test
    func `Specific days checks weekday`() throws {
        // Monday=2, Wednesday=4, Friday=6 in Calendar
        let item = makeItem(substance: "Methotrexate", frequency: .specificDays, frequencyDays: [2, 4, 6])

        // Find next Monday from today
        var monday = today
        while calendar.component(.weekday, from: monday) != 2 {
            monday = try #require(calendar.date(byAdding: .day, value: 1, to: monday))
        }
        let tuesday = try #require(calendar.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try #require(calendar.date(byAdding: .day, value: 2, to: monday))

        #expect(AdherenceCalculator.isDue(item, on: monday))
        #expect(!AdherenceCalculator.isDue(item, on: tuesday))
        #expect(AdherenceCalculator.isDue(item, on: wednesday))
    }

    @Test
    func `Item not due before start date`() {
        let item = makeItem(substance: "New Med", frequency: .daily, startDate: today)
        #expect(AdherenceCalculator.isDue(item, on: today))
        #expect(!AdherenceCalculator.isDue(item, on: dayOffset(-1)))
    }

    // MARK: - adherence()

    @Test
    func `No daily items returns noData`() {
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [])
        #expect(result.status == .noData)
        #expect(result.takenCount == 0)
        #expect(result.totalCount == 0)
        #expect(result.items.isEmpty)
    }

    @Test
    func `All items taken returns complete`() throws {
        let items = [makeItem(substance: "Caffeine"), makeItem(substance: "Melatonin")]
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = [
            makeEntry(substance: "Caffeine", timestamp: noon),
            makeEntry(substance: "Melatonin", timestamp: noon),
        ]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .complete)
        #expect(result.takenCount == 2)
        #expect(result.totalCount == 2)
    }

    @Test
    func `Some items taken returns partial`() throws {
        let items = [makeItem(substance: "Caffeine"), makeItem(substance: "Melatonin")]
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = [makeEntry(substance: "Caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .partial)
        #expect(result.takenCount == 1)
        #expect(result.totalCount == 2)
    }

    @Test
    func `No items taken returns missed`() {
        let items = [makeItem(substance: "Caffeine")]
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: items)
        #expect(result.status == .missed)
        #expect(result.takenCount == 0)
        #expect(result.totalCount == 1)
    }

    @Test
    func `Entries from different day not counted`() {
        let items = [makeItem(substance: "Caffeine")]
        let yesterday = dayOffset(-1).addingTimeInterval(3_600 * 12)
        let entries = [makeEntry(substance: "Caffeine", timestamp: yesterday)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .missed)
    }

    @Test
    func `Case-insensitive matching in adherence`() throws {
        let items = [makeItem(substance: "CAFFEINE")]
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = [makeEntry(substance: "caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)
        #expect(result.status == .complete)
    }

    @Test
    func `Adherence date is set correctly`() {
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [])
        #expect(calendar.isDate(result.date, inSameDayAs: today))
    }

    // MARK: - Frequency-aware adherence

    @Test
    func `Weekly item not due returns noData for off-days`() {
        let item = makeItem(substance: "Injection", frequency: .weekly, startDate: today)
        // Tomorrow is not a due day
        let result = AdherenceCalculator.adherence(for: dayOffset(1), entries: [], dailyItems: [item])
        #expect(result.status == .noData)
        #expect(result.totalCount == 0)
    }

    @Test
    func `Weekly item due day shows missed when no entry`() {
        let item = makeItem(substance: "Injection", frequency: .weekly, startDate: today)
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [item])
        #expect(result.status == .missed)
        #expect(result.totalCount == 1)
    }

    @Test
    func `Mixed frequencies: daily + weekly on off-day only checks daily`() throws {
        let daily = makeItem(substance: "Caffeine", frequency: .daily)
        let weekly = makeItem(substance: "Injection", frequency: .weekly, startDate: today)
        // Tomorrow: daily is due, weekly is not
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayOffset(1)))
        let entries = [makeEntry(substance: "Caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: dayOffset(1), entries: entries, dailyItems: [daily, weekly])
        #expect(result.status == .complete)
        #expect(result.totalCount == 1) // Only the daily item
    }

    @Test
    func `Per-item detail tracks taken/missed`() throws {
        let items = [makeItem(substance: "Caffeine"), makeItem(substance: "Melatonin")]
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = [makeEntry(substance: "Caffeine", timestamp: noon)]
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: items)

        #expect(result.items.count == 2)
        let caffeine = result.items.first { $0.item.substance == "Caffeine" }
        let melatonin = result.items.first { $0.item.substance == "Melatonin" }
        #expect(caffeine?.taken == true)
        #expect(melatonin?.taken == false)
    }

    // MARK: - Multi-time expectations & PRN

    @Test
    func `Multi-time med expects one slot per reminder time`() throws {
        let item = makeItem(substance: "Methylphenidate", reminderTimesMinutes: [480, 780])
        let morning = try #require(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: today))

        let oneDose = AdherenceCalculator.adherence(
            for: today, entries: [makeEntry(substance: "Methylphenidate", timestamp: morning)], dailyItems: [item],
        )
        #expect(oneDose.status == .partial)
        #expect(oneDose.takenCount == 1)
        #expect(oneDose.totalCount == 2)

        let afternoon = try #require(calendar.date(bySettingHour: 13, minute: 5, second: 0, of: today))
        let bothDoses = AdherenceCalculator.adherence(
            for: today,
            entries: [
                makeEntry(substance: "Methylphenidate", timestamp: morning),
                makeEntry(substance: "Methylphenidate", timestamp: afternoon),
            ],
            dailyItems: [item],
        )
        #expect(bothDoses.status == .complete)
        #expect(bothDoses.takenCount == 2)
    }

    @Test
    func `Extra doses beyond expectations do not overcount`() throws {
        let item = makeItem(substance: "Caffeine")
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = (0 ..< 3).map { makeEntry(substance: "Caffeine", timestamp: noon.addingTimeInterval(Double($0) * 3_600)) }
        let result = AdherenceCalculator.adherence(for: today, entries: entries, dailyItems: [item])
        #expect(result.status == .complete)
        #expect(result.takenCount == 1)
        #expect(result.totalCount == 1)
    }

    @Test
    func `As-needed items carry no expectation`() {
        let prn = makeItem(substance: "Ibuprofen", isAsNeeded: true)
        let result = AdherenceCalculator.adherence(for: today, entries: [], dailyItems: [prn])
        #expect(result.status == .noData)
        #expect(result.totalCount == 0)
    }

    @Test
    func `As-needed items are excluded alongside scheduled ones`() throws {
        let daily = makeItem(substance: "Sertraline")
        let prn = makeItem(substance: "Ibuprofen", isAsNeeded: true)
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let result = AdherenceCalculator.adherence(
            for: today, entries: [makeEntry(substance: "Sertraline", timestamp: noon)], dailyItems: [daily, prn],
        )
        #expect(result.status == .complete)
        #expect(result.totalCount == 1)
        #expect(result.items.count == 1)
    }

    @Test
    func `Snapshot dayStatus mirrors model adherence for identity, route, and multi-time`() throws {
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today))
        let entries = [
            AdherenceCalculator.EntrySnapshot(
                substance: "Methylphenidate", identityKey: "psid:mph", route: .oral, timestamp: noon,
            ),
            AdherenceCalculator.EntrySnapshot(
                substance: "Methylphenidate", identityKey: "psid:mph", route: .intravenous, timestamp: noon,
            ),
        ]
        let item = AdherenceCalculator.DailyItemSnapshot(
            substance: "Concerta", identityKey: "psid:mph", route: .oral,
            expectedPerDay: 2, isAsNeeded: false,
            startDate: .distantPast, frequency: .daily, frequencyDays: [],
        )
        // Only the oral dose counts (route gate) → 1 of 2 slots → partial.
        #expect(AdherenceCalculator.dayStatus(for: today, entries: entries, items: [item]) == .partial)

        let prn = AdherenceCalculator.DailyItemSnapshot(
            substance: "Ibuprofen", identityKey: "ibuprofen", route: .oral,
            expectedPerDay: 1, isAsNeeded: true,
            startDate: .distantPast, frequency: .daily, frequencyDays: [],
        )
        #expect(AdherenceCalculator.dayStatus(for: today, entries: [], items: [prn]) == .noData)
    }

    // MARK: - currentStreak()

    @Test
    func `No data returns zero streak`() {
        #expect(AdherenceCalculator.currentStreak(adherenceData: []) == 0)
    }

    @Test
    func `Consecutive complete days count as streak`() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-3), status: .complete, takenCount: 2, totalCount: 2, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 3)
    }

    @Test
    func `Partial days count toward streak`() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .partial, takenCount: 1, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 2)
    }

    @Test
    func `Missed day breaks streak`() {
        let data = [
            DayAdherence(date: dayOffset(-1), status: .missed, takenCount: 0, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-2), status: .complete, takenCount: 2, totalCount: 2, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 0)
    }

    @Test
    func `noData gap does not break streak`() {
        // Weekly prescription: complete on day -7, noData on days -6 through -1
        let data = [
            DayAdherence(date: dayOffset(-7), status: .complete, takenCount: 1, totalCount: 1, items: []),
            DayAdherence(date: dayOffset(-6), status: .noData, takenCount: 0, totalCount: 0, items: []),
            DayAdherence(date: dayOffset(-5), status: .noData, takenCount: 0, totalCount: 0, items: []),
            DayAdherence(date: dayOffset(-4), status: .noData, takenCount: 0, totalCount: 0, items: []),
            DayAdherence(date: dayOffset(-3), status: .noData, takenCount: 0, totalCount: 0, items: []),
            DayAdherence(date: dayOffset(-2), status: .noData, takenCount: 0, totalCount: 0, items: []),
            DayAdherence(date: dayOffset(-1), status: .noData, takenCount: 0, totalCount: 0, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 1)
    }

    @Test
    func `Today's complete data adds to streak`() {
        let data = [
            DayAdherence(date: today, status: .complete, takenCount: 2, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 2)
    }

    @Test
    func `Today's missed data does not add to streak`() {
        let data = [
            DayAdherence(date: today, status: .missed, takenCount: 0, totalCount: 2, items: []),
            DayAdherence(date: dayOffset(-1), status: .complete, takenCount: 2, totalCount: 2, items: []),
        ]
        #expect(AdherenceCalculator.currentStreak(adherenceData: data) == 1)
    }
}
