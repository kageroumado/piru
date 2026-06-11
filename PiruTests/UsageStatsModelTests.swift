import Foundation
import SwiftUI
import Testing
@testable import Piru

@MainActor
@Suite("UsageStatsModel")
struct UsageStatsModelTests {
    typealias CachedEntry = UsageStatsModel.CachedEntry
    typealias DaySubstance = UsageStatsModel.DaySubstance

    /// Fixed UTC gregorian calendar so hour/day math is deterministic.
    private let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }()

    /// Amsterdam calendar for DST-transition tests (EU spring-forward).
    private let amsterdam: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        cal.firstWeekday = 1
        return cal
    }()

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        calendar: Calendar? = nil,
    ) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(
        _ substance: String,
        amount: Double = 10,
        unit: String = "mg",
        at timestamp: Date,
    ) -> CachedEntry {
        CachedEntry(substance: substance, amount: amount, unit: unit, timestamp: timestamp)
    }

    /// The session-day grouping the aggregation should reproduce, computed via
    /// the canonical `sessionDayStart` (so tests hold for any configured
    /// day-boundary hour).
    private func expectedDayBuckets(_ entries: [CachedEntry], calendar: Calendar) -> [DaySubstance: Int] {
        var buckets: [DaySubstance: Int] = [:]
        for e in entries {
            let day = calendar.sessionDayStart(for: e.timestamp)
            buckets[DaySubstance(date: day, substance: e.substance), default: 0] += 1
        }
        return buckets
    }

    // MARK: - Day bucketing

    @Test
    func `Buckets entries by session day per substance and dedups substance days`() {
        let entries = [
            entry("Caffeine", at: date(2_026, 6, 1, 9)),
            entry("Caffeine", at: date(2_026, 6, 1, 15)),
            entry("Caffeine", at: date(2_026, 6, 2, 9)),
            entry("Aspirin", at: date(2_026, 6, 1, 9)),
        ]
        let agg = UsageStatsModel.aggregate(entries, calendar: utc)

        #expect(agg.dayBuckets == expectedDayBuckets(entries, calendar: utc))
        #expect(agg.substanceDays["Caffeine"]?.count == 2)
        #expect(agg.substanceDays["Aspirin"]?.count == 1)
        #expect(agg.substanceCounts == ["Caffeine": 3, "Aspirin": 1])
        #expect(agg.uniqueSubstanceCount == 2)
    }

    @Test
    func `Noon entries on consecutive days across a month boundary land in distinct buckets`() {
        // Noon is always at-or-after the session boundary (0...12), so these
        // assertions hold regardless of the configured day-boundary hour.
        let entries = [
            entry("Caffeine", at: date(2_026, 5, 31, 12)),
            entry("Caffeine", at: date(2_026, 6, 1, 12)),
        ]
        let agg = UsageStatsModel.aggregate(entries, calendar: utc)

        #expect(agg.dayBuckets.count == 2)
        #expect(agg.dayBuckets.values.allSatisfy { $0 == 1 })
        #expect(agg.substanceDays["Caffeine"]?.count == 2)
    }

    @Test
    func `Bucketing survives a DST spring-forward transition`() {
        // Europe/Amsterdam jumps 02:00 → 03:00 on 2026-03-29.
        let entries = [
            entry("Melatonin", at: date(2_026, 3, 28, 12, calendar: amsterdam)),
            entry("Melatonin", at: date(2_026, 3, 29, 12, calendar: amsterdam)),
            entry("Melatonin", at: date(2_026, 3, 30, 12, calendar: amsterdam)),
        ]
        let agg = UsageStatsModel.aggregate(entries, calendar: amsterdam)

        #expect(agg.dayBuckets == expectedDayBuckets(entries, calendar: amsterdam))
        #expect(agg.dayBuckets.count == 3)
        #expect(agg.substanceDays["Melatonin"]?.count == 3)
    }

    @Test
    func `Midnight and late-night entries group by the canonical session day`() {
        let entries = [
            entry("Caffeine", at: date(2_026, 6, 2, 0, 0)),
            entry("Caffeine", at: date(2_026, 6, 1, 23, 59)),
            entry("Caffeine", at: date(2_026, 6, 2, 12)),
        ]
        let agg = UsageStatsModel.aggregate(entries, calendar: utc)

        #expect(agg.dayBuckets == expectedDayBuckets(entries, calendar: utc))
        #expect(agg.substanceCounts["Caffeine"] == 3)
    }

    // MARK: - Time of day binning

    @Test
    func `Time-of-day bin edges map to the documented buckets`() {
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 0) == 3) // midnight → night
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 5) == 3)
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 6) == 0) // morning starts
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 11) == 0)
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 12) == 1) // afternoon starts
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 17) == 1)
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 18) == 2) // evening starts
        #expect(UsageStatsModel.timeOfDayBucketIndex(hour: 23) == 2) // 23:59 is evening
    }

    @Test
    func `Aggregation bins midnight as night and 23-59 as evening`() {
        let entries = [
            entry("A", at: date(2_026, 6, 1, 0, 0)),
            entry("A", at: date(2_026, 6, 1, 23, 59)),
            entry("A", at: date(2_026, 6, 1, 6, 0)),
            entry("A", at: date(2_026, 6, 1, 12, 0)),
        ]
        let agg = UsageStatsModel.aggregate(entries, calendar: utc)
        #expect(agg.timeOfDayBuckets == [1, 1, 1, 1])
    }

    // MARK: - Frequency ranking

    @Test
    func `Frequency ranking sorts descending and keeps all tied substances`() {
        let ranking = UsageStatsModel.frequencyRanking(["A": 5, "B": 3, "C": 3, "D": 1])

        #expect(ranking.count == 4)
        #expect(ranking[0].substance == "A")
        #expect(ranking[0].count == 5)
        #expect(Set(ranking[1 ... 2].map(\.substance)) == ["B", "C"])
        #expect(ranking[1].count == 3)
        #expect(ranking[2].count == 3)
        #expect(ranking[3].substance == "D")
        #expect(ranking[3].count == 1)
    }

    @Test
    func `Frequency ranking caps at the top ten`() {
        let counts = Dictionary(uniqueKeysWithValues: (1 ... 12).map { ("S\($0)", $0) })
        let ranking = UsageStatsModel.frequencyRanking(counts)

        #expect(ranking.count == 10)
        #expect(ranking.map(\.count) == Array((3 ... 12).reversed()))
    }

    // MARK: - Timeline + daily totals

    @Test
    func `Timeline data is sorted by date and daily totals sum across substances`() {
        let day1 = date(2_026, 6, 1)
        let day2 = date(2_026, 6, 2)
        let buckets: [DaySubstance: Int] = [
            DaySubstance(date: day2, substance: "B"): 1,
            DaySubstance(date: day1, substance: "A"): 2,
            DaySubstance(date: day1, substance: "B"): 3,
        ]

        let timeline = UsageStatsModel.timelineData(from: buckets)
        #expect(timeline.map(\.key.date) == [day1, day1, day2])

        let totals = UsageStatsModel.dailyTotals(from: buckets)
        #expect(totals.map(\.date) == [day1, day2])
        #expect(totals.map(\.count) == [5, 1])
    }

    @Test
    func `Legend dedups case-insensitively, keeps first-seen casing, and sorts by name`() {
        let day1 = date(2_026, 6, 1)
        let day2 = date(2_026, 6, 2)
        let timeline = UsageStatsModel.timelineData(from: [
            DaySubstance(date: day1, substance: "Caffeine"): 1,
            DaySubstance(date: day2, substance: "caffeine"): 1,
            DaySubstance(date: day1, substance: "Aspirin"): 1,
        ])
        let legend = UsageStatsModel.legend(for: timeline, colorMap: ["aspirin": .red])

        #expect(legend.map(\.name) == ["Aspirin", "Caffeine"])
        #expect(legend[0].color == .red)
        #expect(legend[1].color == Theme.accent)
    }

    // MARK: - Trend candidates

    @Test
    func `Trend candidates need two entries on two distinct days, ranked by count`() {
        let day1 = date(2_026, 6, 1)
        let day2 = date(2_026, 6, 2)
        let candidates = UsageStatsModel.trendCandidates(
            substanceDays: [
                "MultiDay": [day1, day2],
                "Busy": [day1, day2],
                "OneDayManyDoses": [day1],
                "TwoDaysOneEntryEach": [day1, day2],
            ],
            substanceCounts: [
                "MultiDay": 2,
                "Busy": 5,
                "OneDayManyDoses": 4,
                "TwoDaysOneEntryEach": 1,
            ],
        )

        #expect(candidates.map(\.name) == ["Busy", "MultiDay"])
        #expect(candidates.map(\.count) == [5, 2])
    }

    // MARK: - Category aggregation

    @Test
    func `Category aggregation counts entries and ranks the per-category breakdown`() {
        let categories: [String: SubstanceCategory] = [
            "Coffee": .stimulant,
            "Tea": .stimulant,
            "Beer": .depressant,
        ]
        let entries = [
            entry("Coffee", at: date(2_026, 6, 1, 9)),
            entry("Coffee", at: date(2_026, 6, 1, 14)),
            entry("Coffee", at: date(2_026, 6, 2, 9)),
            entry("Tea", at: date(2_026, 6, 1, 16)),
            entry("Tea", at: date(2_026, 6, 2, 16)),
            entry("Beer", at: date(2_026, 6, 1, 20)),
            entry("Beer", at: date(2_026, 6, 2, 20)),
            entry("Mystery", at: date(2_026, 6, 1, 21)),
        ]
        let result = UsageStatsModel.categoryAggregation(entries: entries) { categories[$0] ?? .other }

        #expect(result.counts.map(\.category) == [.stimulant, .depressant, .other])
        #expect(result.counts.map(\.count) == [5, 2, 1])
        #expect(result.substanceCounts[.stimulant]?.map(\.substance) == ["Coffee", "Tea"])
        #expect(result.substanceCounts[.stimulant]?.map(\.count) == [3, 2])
        #expect(result.substanceCounts[.depressant]?.map(\.substance) == ["Beer"])
        #expect(result.substanceCounts[.other]?.map(\.substance) == ["Mystery"])
    }

    @Test
    func `Category aggregation of no entries is empty`() {
        let result = UsageStatsModel.categoryAggregation(entries: []) { _ in .other }
        #expect(result.counts.isEmpty)
        #expect(result.substanceCounts.isEmpty)
    }

    // MARK: - Trend data

    @Test
    func `Daily trend uses a trailing seven-point moving average`() {
        // Ten consecutive noon doses with amounts 1...10 (span 9 days → daily).
        let entries = (0 ..< 10).map { i in
            entry("X", amount: Double(i + 1), at: date(2_026, 1, 5 + i))
        }
        let result = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 1, calendar: utc, now: date(2_026, 1, 15),
        )

        #expect(result.weekly == false)
        #expect(result.mixedUnits == false)
        #expect(result.unit == "mg")
        #expect(result.points.count == 10)
        #expect(result.points.map(\.total) == (1 ... 10).map(Double.init))

        // Trailing window: shorter than 7 at the start, exactly 7 once filled.
        #expect(result.maLookup[result.points[0].date] == 1)
        #expect(result.maLookup[result.points[2].date] == 2) // (1+2+3)/3
        #expect(result.maLookup[result.points[6].date] == 4) // (1+...+7)/7
        #expect(result.maLookup[result.points[9].date] == 7) // (4+...+10)/7
    }

    @Test
    func `Weekly trend averages complete weeks over seven days with a four-point window`() {
        // Six Sunday doses, amounts 7,14,...,42; zoom 0.25 lowers the weekly
        // threshold to 22.5 days so the 35-day span aggregates weekly.
        let sundays = [4, 11, 18, 25].map { date(2_026, 1, $0) } + [date(2_026, 2, 1), date(2_026, 2, 8)]
        let entries = sundays.enumerated().map { i, day in
            entry("X", amount: Double((i + 1) * 7), at: day)
        }
        let result = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 0.25, calendar: utc, now: date(2_026, 3, 1),
        )

        #expect(result.weekly == true)
        #expect(result.points.count == 6)
        #expect(result.points.map(\.total) == [1, 2, 3, 4, 5, 6])

        #expect(result.maLookup[result.points[0].date] == 1)
        #expect(result.maLookup[result.points[3].date] == 2.5) // (1+2+3+4)/4
        #expect(result.maLookup[result.points[5].date] == 4.5) // (3+4+5+6)/4
    }

    @Test
    func `Incomplete week divides by elapsed days, not seven`() {
        // 95-day span → weekly at zoom 1 needs > 90: Oct 1 → Jan 4 qualifies.
        // "Now" is Tuesday of the last entry's week, so that week is incomplete
        // and its total divides by the 3 elapsed days (Sun, Mon, Tue).
        let entries = [
            entry("X", amount: 7, at: date(2_025, 10, 1)),
            entry("X", amount: 30, at: date(2_026, 1, 4)),
        ]
        let result = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 1, calendar: utc, now: date(2_026, 1, 6),
        )

        #expect(result.weekly == true)
        #expect(result.points.map(\.total) == [1, 10])
        // Two points only — moving average needs three.
        #expect(result.maLookup.isEmpty)
    }

    @Test
    func `Zooming in raises the weekly threshold back to daily buckets`() {
        let entries = [
            entry("X", amount: 10, at: date(2_026, 1, 1)),
            entry("X", amount: 20, at: date(2_026, 2, 20)),
            entry("X", amount: 30, at: date(2_026, 4, 11)), // span 100 days
        ]
        let weekly = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 1, calendar: utc, now: date(2_026, 5, 1),
        )
        let daily = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 2, calendar: utc, now: date(2_026, 5, 1),
        )

        #expect(weekly.weekly == true)
        #expect(daily.weekly == false)
        #expect(daily.points.map(\.total) == [10, 20, 30])
        #expect(daily.maLookup[daily.points[2].date] == 20) // (10+20+30)/3
    }

    @Test
    func `Mixed units keep only the predominant unit and flag the exclusion`() {
        let entries = [
            entry("X", amount: 10, unit: "mg", at: date(2_026, 6, 1)),
            entry("X", amount: 20, unit: "mg", at: date(2_026, 6, 2)),
            entry("X", amount: 5, unit: "µg", at: date(2_026, 6, 3)),
        ]
        let result = UsageStatsModel.trendData(
            entries: entries, substance: "X", zoom: 1, calendar: utc, now: date(2_026, 6, 4),
        )

        #expect(result.mixedUnits == true)
        #expect(result.unit == "mg")
        #expect(result.points.map(\.total) == [10, 20])
    }

    @Test
    func `Trend data for an unknown substance is empty`() {
        let entries = [entry("X", at: date(2_026, 6, 1))]
        let result = UsageStatsModel.trendData(
            entries: entries, substance: "Y", zoom: 1, calendar: utc, now: date(2_026, 6, 2),
        )

        #expect(result.points.isEmpty)
        #expect(result.unit == "mg")
        #expect(result.weekly == false)
        #expect(result.maLookup.isEmpty)
        #expect(result.mixedUnits == false)
    }

    // MARK: - Rebuild

    @Test
    func `Rebuild filters entries to the selected time range`() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let recent = DoseEntry(substance: "Caffeine", amount: 100, timestamp: now.addingTimeInterval(-2 * 86_400))
        let old = DoseEntry(substance: "Theanine", amount: 200, timestamp: now.addingTimeInterval(-10 * 86_400))

        let model = UsageStatsModel()
        model.rebuild(entries: [recent, old], colors: [], rangeDays: 7, now: now, categoryOf: { _ in .other })

        #expect(model.filteredEntries.count == 1)
        #expect(model.filteredEntries.first?.substance == "Caffeine")
        #expect(model.frequencyTotal == 1)
        #expect(model.uniqueSubstances == 1)
        #expect(model.mostLogged == "Caffeine")

        model.rebuild(entries: [recent, old], colors: [], rangeDays: nil, now: now, categoryOf: { _ in .other })
        #expect(model.filteredEntries.count == 2)
        #expect(model.uniqueSubstances == 2)
    }

    @Test
    func `Rebuild with no entries publishes empty defaults`() {
        let model = UsageStatsModel()
        model.rebuild(entries: [], colors: [], rangeDays: 30, categoryOf: { _ in .other })

        #expect(model.filteredEntries.isEmpty)
        #expect(model.frequencyData.isEmpty)
        #expect(model.frequencyTotal == 0)
        #expect(model.timeOfDayBuckets == [0, 0, 0, 0])
        #expect(model.uniqueSubstances == 0)
        #expect(model.mostLogged == "—")
        #expect(model.timelineData.isEmpty)
        #expect(model.dailyTotals.isEmpty)
        #expect(model.timelineLegend.isEmpty)
        #expect(model.trendSubstances.isEmpty)
        #expect(model.categoryCounts.isEmpty)
        #expect(model.categorySubstanceCounts.isEmpty)
    }
}
