import Foundation
import Testing
@testable import Piru

/// The aggregation behind Insights → Usage (`Specs/usage-graphs-v2.md`).
///
/// Every function under test is a pure `static` over explicit inputs, so none of
/// this needs a `ModelContainer`, a simulator, or the bundled substance DB — the
/// point of splitting `UsageAnalytics` out from the views.
@MainActor
@Suite("UsageAnalytics")
struct UsageAnalyticsTests {
    /// Fixed UTC gregorian calendar, Sunday-first, so weekday and week-of-year
    /// math is deterministic wherever the tests run.
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func snapshot(
        substance: Int = 0,
        category: Int = 0,
        route: Int = 0,
        level: Int? = nil,
        amount: Double = 10,
        at timestamp: Date,
    ) -> UsageEntrySnapshot {
        UsageEntrySnapshot(
            substanceIndex: substance, categoryIndex: category, routeIndex: route,
            doseLevelIndex: level, amount: amount, timestamp: timestamp,
        )
    }

    private func bounds(_ start: Date, _ end: Date, previous: Bool = true) -> UsageAnalytics.Bounds {
        UsageAnalytics.Bounds(
            start: start, end: end,
            lengthDays: end.timeIntervalSince(start) / 86_400,
            hasPreviousPeriod: previous,
        )
    }

    // MARK: - Windowing

    @Test
    func `A fixed range ends now and is exactly its own length`() {
        let now = date(2_026, 6, 15)
        let result = UsageAnalytics.bounds(for: .thirtyDays, entries: [], now: now)
        #expect(result.end == now)
        #expect(result.lengthDays == 30)
        #expect(result.start == now.addingTimeInterval(-30 * 86_400))
        #expect(result.hasPreviousPeriod)
    }

    @Test
    func `All spans the first entry to now and has no previous period`() {
        let now = date(2_026, 6, 15)
        let first = date(2_026, 5, 16)
        let result = UsageAnalytics.bounds(
            for: .all,
            entries: [snapshot(at: first), snapshot(at: date(2_026, 6, 1))],
            now: now,
        )
        #expect(result.start == first)
        #expect(result.end == now)
        #expect(abs(result.lengthDays - 30) < 0.001)
        #expect(!result.hasPreviousPeriod)
    }

    // MARK: - Period over period (§1)

    @Test
    func `Period-over-period delta compares the window to the one before it`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        // 3 entries this week, 2 the week before.
        let all = [
            snapshot(at: now.addingTimeInterval(-1 * 86_400)),
            snapshot(at: now.addingTimeInterval(-2 * 86_400)),
            snapshot(at: now.addingTimeInterval(-3 * 86_400)),
            snapshot(at: now.addingTimeInterval(-9 * 86_400)),
            snapshot(at: now.addingTimeInterval(-11 * 86_400)),
            // Two weeks back — outside both windows.
            snapshot(at: now.addingTimeInterval(-20 * 86_400)),
        ]
        let inRange = all.filter { $0.timestamp >= window.start }
        let overview = UsageAnalytics.overview(all: all, inRange: inRange, bounds: window, calendar: utc)

        #expect(overview.entryCount == 3)
        #expect(overview.previousEntryCount == 2)
        #expect(overview.percentChange == 0.5)
    }

    @Test
    func `An empty previous period yields no percentage rather than an infinite one`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        let all = [snapshot(at: now.addingTimeInterval(-1 * 86_400))]
        let overview = UsageAnalytics.overview(all: all, inRange: all, bounds: window, calendar: utc)

        #expect(overview.previousEntryCount == 0)
        #expect(overview.percentChange == nil)
    }

    @Test
    func `All has no previous period so no comparison is offered`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-30 * 86_400), now, previous: false)
        let all = [snapshot(at: now.addingTimeInterval(-1 * 86_400))]
        let overview = UsageAnalytics.overview(all: all, inRange: all, bounds: window, calendar: utc)

        #expect(overview.previousEntryCount == nil)
        #expect(overview.percentChange == nil)
    }

    @Test
    func `New substances are the ones whose first-ever dose falls in the window`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        let all = [
            // Substance 0 debuted long ago and is still in use — not new.
            snapshot(substance: 0, at: now.addingTimeInterval(-40 * 86_400)),
            snapshot(substance: 0, at: now.addingTimeInterval(-2 * 86_400)),
            // Substance 1 appears for the first time inside the window — new.
            snapshot(substance: 1, at: now.addingTimeInterval(-3 * 86_400)),
        ]
        let inRange = all.filter { $0.timestamp >= window.start }
        let overview = UsageAnalytics.overview(all: all, inRange: inRange, bounds: window, calendar: utc)

        #expect(overview.uniqueSubstances == 2)
        #expect(overview.newSubstances == 1)
    }

    @Test
    func `Dose intensity counts only entries that landed on a ladder`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        let all = [
            snapshot(level: 2, at: now.addingTimeInterval(-1 * 86_400)), // light
            snapshot(level: 3, at: now.addingTimeInterval(-2 * 86_400)), // common
            snapshot(level: 5, at: now.addingTimeInterval(-3 * 86_400)), // heavy
            snapshot(level: nil, at: now.addingTimeInterval(-4 * 86_400)), // unplaceable
            snapshot(level: nil, at: now.addingTimeInterval(-5 * 86_400)),
        ]
        let overview = UsageAnalytics.overview(all: all, inRange: all, bounds: window, calendar: utc)

        #expect(overview.entryCount == 5)
        #expect(overview.doseResolvedCount == 3)
        #expect(overview.commonOrAboveCount == 2)
        #expect(overview.heavyCount == 1)
        // 2 of 3 *resolved* entries, not 2 of 5 logged ones.
        #expect(overview.doseIntensity == 2.0 / 3.0)
    }

    @Test
    func `Dose intensity is absent, not zero, when nothing could be placed`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        let all = [snapshot(level: nil, at: now.addingTimeInterval(-1 * 86_400))]
        let overview = UsageAnalytics.overview(all: all, inRange: all, bounds: window, calendar: utc)

        #expect(overview.doseIntensity == nil)
    }

    @Test
    func `The sparkline splits the window into seven equal buckets`() {
        let start = date(2_026, 6, 1, 0)
        let end = date(2_026, 6, 8, 0)
        let window = bounds(start, end)
        // One entry per day for seven days → one per bucket.
        let entries = (0 ..< 7).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }

        #expect(UsageAnalytics.sparkline(entries, bounds: window) == [1, 1, 1, 1, 1, 1, 1])
    }

    @Test
    func `An entry at the very end of the window lands in the last sparkline bucket`() {
        let start = date(2_026, 6, 1, 0)
        let end = date(2_026, 6, 8, 0)
        let window = bounds(start, end)

        #expect(UsageAnalytics.sparkline([snapshot(at: end)], bounds: window) == [0, 0, 0, 0, 0, 0, 1])
        #expect(UsageAnalytics.sparkline([snapshot(at: start)], bounds: window) == [1, 0, 0, 0, 0, 0, 0])
    }

    // MARK: - Bucketing (§3, §4)

    @Test
    func `Daily bucketing emits one bucket per day, inclusive of both ends`() {
        let window = bounds(date(2_026, 6, 1, 9), date(2_026, 6, 5, 9))
        let starts = UsageAnalytics.bucketStarts(bounds: window, weekly: false, calendar: utc)

        #expect(starts.count == 5)
        #expect(starts.first == utc.sessionDayStart(for: date(2_026, 6, 1, 9)))
        #expect(starts.last == utc.sessionDayStart(for: date(2_026, 6, 5, 9)))
    }

    @Test
    func `Weekly bucketing snaps to week starts`() {
        // 2026-06-01 is a Monday and 2026-06-20 a Saturday; with firstWeekday =
        // Sunday that is the weeks beginning 05-31, 06-07 and 06-14.
        let window = bounds(date(2_026, 6, 1, 9), date(2_026, 6, 20, 9))
        let starts = UsageAnalytics.bucketStarts(bounds: window, weekly: true, calendar: utc)

        #expect(starts == [date(2_026, 5, 31, 0), date(2_026, 6, 7, 0), date(2_026, 6, 14, 0)])
        for start in starts {
            #expect(utc.component(.weekday, from: start) == utc.firstWeekday)
        }
    }

    @Test
    func `A timestamp resolves to the last bucket that started before it`() {
        let starts = [date(2_026, 6, 1, 0), date(2_026, 6, 8, 0), date(2_026, 6, 15, 0)]

        #expect(UsageAnalytics.bucket(for: date(2_026, 6, 10), in: starts) == starts[1])
        #expect(UsageAnalytics.bucket(for: date(2_026, 6, 8, 0), in: starts) == starts[1])
        #expect(UsageAnalytics.bucket(for: date(2_026, 6, 20), in: starts) == starts[2])
        // Before the first bucket, clamp forward rather than dropping the entry.
        #expect(UsageAnalytics.bucket(for: date(2_026, 5, 1), in: starts) == starts[0])
        #expect(UsageAnalytics.bucket(for: date(2_026, 6, 1), in: []) == nil)
    }

    // MARK: - Rolling windows (§3)

    @Test
    func `A daily trend point counts the trailing seven days, normalized per week`() {
        let start = date(2_026, 6, 1, 0)
        // One dose a day for ten days.
        let entries = (0 ..< 10).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let starts = (0 ..< 10).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 10)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(10 * 86_400),
        )

        #expect(series.count == 1)
        let points = series[0].points
        #expect(points.count == 10)
        // Day 0's window closes at the end of day 0 and covers one dose.
        #expect(points[0].value == 1)
        // From day 6 on, a full week of daily dosing sits inside the window.
        #expect(points[6].value == 7)
        #expect(points[9].value == 7)
    }

    @Test
    func `A four-week window is still reported as entries per week`() {
        let start = date(2_026, 6, 1, 0)
        // 28 doses over 28 days = one per day = seven per week.
        let entries = (0 ..< 28).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let starts = (0 ..< 4).map { start.addingTimeInterval(Double($0) * 7 * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 28)], bucketStarts: starts,
            bucketDays: 7, windowDays: 28, rangeEnd: start.addingTimeInterval(28 * 86_400),
        )

        #expect(series[0].points.last?.value == 7)
    }

    @Test
    func `A dry spell draws zero instead of breaking the line`() {
        let start = date(2_026, 6, 1, 0)
        let entries = [snapshot(at: start.addingTimeInterval(3_600))]
        let starts = (0 ..< 20).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 1)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(20 * 86_400),
        )

        #expect(series[0].points.count == 20)
        #expect(series[0].points.allSatisfy { $0.value >= 0 })
        #expect(series[0].points.last?.value == 0)
    }

    @Test
    func `The newest point closes its window at the range end, not the bucket start`() {
        // A week-bucketed range whose last bucket has only just begun: the point
        // must still reflect the doses logged inside it.
        let weekStart = date(2_026, 6, 7, 0)
        let rangeEnd = date(2_026, 6, 9, 12)
        let entries = [snapshot(at: date(2_026, 6, 8, 10)), snapshot(at: date(2_026, 6, 9, 10))]

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 2)], bucketStarts: [weekStart],
            bucketDays: 7, windowDays: 28, rangeEnd: rangeEnd,
        )

        // Two doses inside a four-week window → 2 × 7/28 = 0.5 per week.
        #expect(series[0].points.first?.value == 0.5)
    }

    @Test
    func `Only the top substances get a line`() {
        let start = date(2_026, 6, 1, 0)
        var entries: [UsageEntrySnapshot] = []
        var ranking: [(substanceIndex: Int, count: Int)] = []
        for index in 0 ..< 14 {
            entries.append(snapshot(substance: index, at: start.addingTimeInterval(Double(index) * 3_600)))
            ranking.append((substanceIndex: index, count: 14 - index))
        }

        let series = UsageAnalytics.trends(
            entries, ranking: ranking, bucketStarts: [start],
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(86_400),
        )

        #expect(series.count == UsageAnalytics.maximumTrendSubstances)
        #expect(series.first?.substanceIndex == 0)
    }

    // MARK: - Dose-level resolution (§4)

    @Test
    func `The dose-level index matches DoseLevel's declaration order`() {
        #expect(UsageAnalyticsModel.index(of: .sub) == 0)
        #expect(UsageAnalyticsModel.index(of: .threshold) == 1)
        #expect(UsageAnalyticsModel.index(of: .light) == 2)
        #expect(UsageAnalyticsModel.index(of: .common) == UsageAnalytics.commonLevelIndex)
        #expect(UsageAnalyticsModel.index(of: .strong) == 4)
        #expect(UsageAnalyticsModel.index(of: .heavy) == UsageAnalytics.heavyLevelIndex)
        // The UI maps back through the same table.
        for level in DoseLevel.allCases {
            #expect(UsageAxes.doseLevel(UsageAnalyticsModel.index(of: level)) == level)
        }
    }

    private let mdmaLadder = DoseRange(
        threshold: 20, light: 40 ... 75, common: 75 ... 110, strong: 110 ... 150, heavy: 150,
    )

    @Test
    func `A dose in the ladder's own unit resolves to its tier`() {
        func level(_ amount: Double) -> Int? {
            UsageAnalyticsModel.doseLevelIndex(range: mdmaLadder, ladderUnit: "mg", amount: amount, loggedUnit: "mg")
        }
        #expect(level(10) == UsageAnalyticsModel.index(of: .sub))
        #expect(level(25) == UsageAnalyticsModel.index(of: .threshold))
        #expect(level(50) == UsageAnalyticsModel.index(of: .light))
        #expect(level(90) == UsageAnalyticsModel.index(of: .common))
        #expect(level(120) == UsageAnalyticsModel.index(of: .strong))
        #expect(level(200) == UsageAnalyticsModel.index(of: .heavy))
    }

    @Test
    func `A convertible mass unit is converted before it is placed`() {
        // 0.09 g is 90 mg — common, not sub-threshold.
        #expect(
            UsageAnalyticsModel.doseLevelIndex(range: mdmaLadder, ladderUnit: "mg", amount: 0.09, loggedUnit: "g")
                == UsageAnalyticsModel.index(of: .common),
        )
        // Both spellings of micro must work; only one of them is MICRO SIGN.
        let microgram = DoseRange(threshold: 20, light: 50 ... 100, common: 100 ... 150, strong: 150 ... 200, heavy: 200)
        #expect(
            UsageAnalyticsModel.doseLevelIndex(range: microgram, ladderUnit: "µg", amount: 0.12, loggedUnit: "mg")
                == UsageAnalyticsModel.index(of: .common),
        )
    }

    @Test
    func `An incomparable unit drops out instead of being read across`() {
        // A volume against a mass ladder: 5 mL is not 5 mg.
        #expect(UsageAnalyticsModel.doseLevelIndex(range: mdmaLadder, ladderUnit: "mg", amount: 5, loggedUnit: "mL") == nil)
        #expect(UsageAnalyticsModel.doseLevelIndex(range: mdmaLadder, ladderUnit: "mg", amount: 5, loggedUnit: "IU") == nil)
        // A qualified unit states a basis; folding it onto plain mg would
        // compare a freebase amount against a salt ladder.
        #expect(UsageAnalyticsModel.doseLevelIndex(range: mdmaLadder, ladderUnit: "mg", amount: 90, loggedUnit: "mg (freebase)") == nil)
    }

    @Test
    func `An empty ladder places nothing`() {
        #expect(UsageAnalyticsModel.doseLevelIndex(range: DoseRange(), ladderUnit: "mg", amount: 90, loggedUnit: "mg") == nil)
    }

    @Test
    func `Dose-level buckets carry only placeable entries and report coverage`() {
        let start = date(2_026, 6, 1, 0)
        let starts = (0 ..< 3).map { start.addingTimeInterval(Double($0) * 86_400) }
        let entries = [
            snapshot(level: 3, at: date(2_026, 6, 1, 10)),
            snapshot(level: 3, at: date(2_026, 6, 1, 20)),
            snapshot(level: 5, at: date(2_026, 6, 2, 10)),
            snapshot(level: nil, at: date(2_026, 6, 2, 11)),
            snapshot(level: nil, at: date(2_026, 6, 3, 11)),
        ]

        let breakdown = UsageAnalytics.doseLevels(
            entries, ranking: [(substanceIndex: 0, count: 5)], bucketStarts: starts, calendar: utc,
        )

        #expect(breakdown.resolvedEntries == 3)
        #expect(breakdown.totalEntries == 5)
        #expect(abs(breakdown.coverage - 0.6) < 0.0001)
        #expect(!breakdown.isLowCoverage)
        #expect(breakdown.overall.count == 2)
        #expect(breakdown.overall.first?.counts[3] == 2)
        #expect(breakdown.selectableSubstances == [0])
    }

    @Test
    func `Coverage under thirty percent demotes the section`() {
        let start = date(2_026, 6, 1, 0)
        var entries = [snapshot(level: 3, at: date(2_026, 6, 1, 10))]
        for hour in 0 ..< 9 {
            entries.append(snapshot(level: nil, at: date(2_026, 6, 1, 11 + hour % 12)))
        }

        let breakdown = UsageAnalytics.doseLevels(
            entries, ranking: [(substanceIndex: 0, count: 10)], bucketStarts: [start], calendar: utc,
        )

        #expect(breakdown.coverage == 0.1)
        #expect(breakdown.isLowCoverage)
    }

    // MARK: - Co-occurrence (§6)

    @Test
    func `Co-use pairs count the days two substances share`() {
        let entries = [
            // Day 1: A, B, C — three pairs.
            snapshot(substance: 0, at: date(2_026, 6, 1, 10)),
            snapshot(substance: 1, at: date(2_026, 6, 1, 11)),
            snapshot(substance: 2, at: date(2_026, 6, 1, 12)),
            // Day 2: A, B.
            snapshot(substance: 0, at: date(2_026, 6, 2, 10)),
            snapshot(substance: 1, at: date(2_026, 6, 2, 11)),
            // Day 3: A only.
            snapshot(substance: 0, at: date(2_026, 6, 3, 10)),
        ]
        let pairs = UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc))

        // A+B twice; A+C and B+C once each, which is below the threshold.
        #expect(pairs.count == 1)
        #expect(pairs[0].firstIndex == 0)
        #expect(pairs[0].secondIndex == 1)
        #expect(pairs[0].days == 2)
        // A on three days, B on two, together on two → union of three.
        #expect(pairs[0].unionDays == 3)
        #expect(abs(pairs[0].overlap - 2.0 / 3.0) < 0.0001)
    }

    @Test
    func `Two doses of the same substance on one day are not a pair`() {
        let entries = [
            snapshot(substance: 0, at: date(2_026, 6, 1, 10)),
            snapshot(substance: 0, at: date(2_026, 6, 1, 18)),
            snapshot(substance: 0, at: date(2_026, 6, 2, 10)),
            snapshot(substance: 0, at: date(2_026, 6, 2, 18)),
        ]
        #expect(UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc)).isEmpty)
    }

    @Test
    func `A single shared day is a coincidence and is not shown`() {
        let entries = [
            snapshot(substance: 0, at: date(2_026, 6, 1, 10)),
            snapshot(substance: 1, at: date(2_026, 6, 1, 11)),
        ]
        #expect(UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc)).isEmpty)
    }

    @Test
    func `Pairs are capped and ranked by shared days`() {
        var entries: [UsageEntrySnapshot] = []
        // Eight substances every day for four days = 28 pairs, all above the
        // threshold; only the cap's worth should come back.
        for day in 1 ... 4 {
            for substance in 0 ..< 8 {
                entries.append(snapshot(substance: substance, at: date(2_026, 6, day, 10 + substance)))
            }
        }
        let pairs = UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc))

        #expect(pairs.count == UsageAnalytics.maximumCoUsePairs)
        #expect(pairs.allSatisfy { $0.days == 4 })
    }

    @Test
    func `A late-night dose pairs with the evening it belongs to`() {
        // 02:00 rolls into the previous session day, so this is one night out,
        // not two separate days with no overlap.
        let entries = [
            snapshot(substance: 0, at: date(2_026, 6, 1, 22)),
            snapshot(substance: 1, at: date(2_026, 6, 2, 2)),
            snapshot(substance: 0, at: date(2_026, 6, 8, 22)),
            snapshot(substance: 1, at: date(2_026, 6, 9, 2)),
        ]
        let pairs = UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc))

        #expect(pairs.count == 1)
        #expect(pairs[0].days == 2)
    }

    // MARK: - Regularity (§7)

    @Test
    func `Interval statistics report mean, deviation, and CV`() {
        let stats = UsageAnalytics.intervalStatistics([1, 1, 1, 1])
        #expect(stats?.mean == 1)
        #expect(stats?.standardDeviation == 0)
        #expect(stats?.coefficientOfVariation == 0)

        let uneven = UsageAnalytics.intervalStatistics([1, 3])
        #expect(uneven?.mean == 2)
        #expect(uneven?.standardDeviation == 1)
        #expect(uneven?.coefficientOfVariation == 0.5)

        #expect(UsageAnalytics.intervalStatistics([]) == nil)
        #expect(UsageAnalytics.intervalStatistics([0, 0]) == nil)
    }

    @Test
    func `A daily habit reads as very regular at one day apart`() {
        let entries = (1 ... 8).map { snapshot(at: date(2_026, 6, $0, 9)) }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: 8)],
        )

        #expect(rows.count == 1)
        #expect(abs(rows[0].meanIntervalDays - 1) < 0.0001)
        #expect(rows[0].coefficientOfVariation == 0)
        #expect(rows[0].tier == .veryRegular)
        #expect(rows[0].fill == 1)
    }

    @Test
    func `Several doses in one day do not make a routine look sporadic`() {
        // Three doses a day, every day: dose-level gaps would be 8 h / 8 h / 8 h
        // then a jump, but the question §7 asks is about days.
        var entries: [UsageEntrySnapshot] = []
        for day in 1 ... 6 {
            for hour in [8, 13, 20] {
                entries.append(snapshot(at: date(2_026, 6, day, hour)))
            }
        }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: 18)],
        )

        #expect(rows[0].tier == .veryRegular)
        #expect(abs(rows[0].meanIntervalDays - 1) < 0.0001)
    }

    @Test
    func `A bursty history reads as sporadic`() {
        // Two clusters far apart: tiny gaps, then a huge one.
        let days = [1, 2, 3, 4, 28]
        let entries = days.map { snapshot(at: date(2_026, 6, $0, 9)) }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: 5)],
        )

        #expect(rows[0].coefficientOfVariation > 1)
        #expect(rows[0].tier == .sporadic)
        #expect(rows[0].fill < 0.35)
    }

    @Test
    func `Too few entries or too few days produce no regularity row`() {
        let sparse = (1 ... 4).map { snapshot(at: date(2_026, 6, $0, 9)) }
        #expect(
            UsageAnalytics.regularity(
                dayIndex: UsageAnalytics.groupByDay(sparse, calendar: utc),
                counts: [(substanceIndex: 0, count: 4)],
            ).isEmpty,
        )

        // Five entries but only two distinct days — one interval is not a
        // spread.
        let clustered = [
            snapshot(at: date(2_026, 6, 1, 8)), snapshot(at: date(2_026, 6, 1, 12)),
            snapshot(at: date(2_026, 6, 1, 18)), snapshot(at: date(2_026, 6, 2, 8)),
            snapshot(at: date(2_026, 6, 2, 18)),
        ]
        #expect(
            UsageAnalytics.regularity(
                dayIndex: UsageAnalytics.groupByDay(clustered, calendar: utc),
                counts: [(substanceIndex: 0, count: 5)],
            ).isEmpty,
        )
    }

    @Test
    func `Regularity tiers follow the spec's CV cut points`() {
        #expect(UsageRegularityTier(coefficientOfVariation: 0.2) == .veryRegular)
        #expect(UsageRegularityTier(coefficientOfVariation: 0.3) == .somewhatRegular)
        #expect(UsageRegularityTier(coefficientOfVariation: 0.59) == .somewhatRegular)
        #expect(UsageRegularityTier(coefficientOfVariation: 0.6) == .irregular)
        #expect(UsageRegularityTier(coefficientOfVariation: 0.99) == .irregular)
        #expect(UsageRegularityTier(coefficientOfVariation: 1.0) == .sporadic)
    }

    // MARK: - Routes (§5)

    @Test
    func `One route is not a breakdown`() {
        let entries = (1 ... 3).map { snapshot(route: 0, at: date(2_026, 6, $0, 9)) }
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])

        #expect(breakdown.distinctRoutes == [0])
        #expect(!breakdown.isMeaningful)
    }

    @Test
    func `Two routes split a substance's bar, most-used first`() {
        let entries = [
            snapshot(route: 0, at: date(2_026, 6, 1, 9)),
            snapshot(route: 0, at: date(2_026, 6, 2, 9)),
            snapshot(route: 3, at: date(2_026, 6, 3, 9)),
        ]
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])

        #expect(breakdown.isMeaningful)
        #expect(breakdown.rows.count == 1)
        #expect(breakdown.rows[0].total == 3)
        #expect(breakdown.rows[0].byRoute.map(\.routeIndex) == [0, 3])
        #expect(breakdown.rows[0].byRoute.map(\.count) == [2, 1])
    }

    // MARK: - Heatmap (§2)

    @Test
    func `The heatmap lays out whole weeks and marks out-of-range padding`() {
        // 2026-06-03 is a Wednesday; the range starts mid-week, so the first
        // column has leading cells outside it.
        let window = bounds(date(2_026, 6, 3, 9), date(2_026, 6, 16, 9))
        let entries = [
            snapshot(at: date(2_026, 6, 3, 10)),
            snapshot(at: date(2_026, 6, 3, 20)),
            snapshot(category: 1, at: date(2_026, 6, 10, 10)),
        ]
        let heatmap = UsageAnalytics.heatmap(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc), bounds: window, calendar: utc,
        )

        #expect(heatmap.rowWeekdays == [1, 2, 3, 4, 5, 6, 7])
        #expect(heatmap.cells.count == heatmap.weekStarts.count * 7)
        #expect(heatmap.maxCount == 2)
        // The Sunday and Monday before the range are padding.
        #expect(heatmap.cell(column: 0, row: 0)?.inRange == false)
        let busiest = heatmap.cells.first { $0.total == 2 }
        #expect(busiest?.inRange == true)
        #expect(busiest?.date == utc.sessionDayStart(for: date(2_026, 6, 3, 10)))
    }

    @Test
    func `Heatmap cells keep a per-category split for the filter pills`() {
        let entries = [
            snapshot(category: 0, at: date(2_026, 6, 3, 10)),
            snapshot(category: 4, at: date(2_026, 6, 3, 12)),
            snapshot(category: 4, at: date(2_026, 6, 3, 14)),
        ]
        let window = bounds(date(2_026, 6, 1, 0), date(2_026, 6, 7, 23))
        let heatmap = UsageAnalytics.heatmap(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc), bounds: window, calendar: utc,
        )
        let day = heatmap.cells.first { $0.total == 3 }

        #expect(day?.byCategory[0] == 1)
        #expect(day?.byCategory[4] == 2)
    }

    @Test
    func `The hour histogram has 24 bins, overall and per day`() {
        let entries = [
            snapshot(at: date(2_026, 6, 3, 9)),
            snapshot(at: date(2_026, 6, 3, 9)),
            snapshot(category: 2, at: date(2_026, 6, 3, 22)),
            snapshot(at: date(2_026, 6, 4, 9)),
        ]
        let profile = UsageAnalytics.hourProfile(entries, calendar: utc)

        #expect(profile.all.total.count == 24)
        #expect(profile.all.total[9] == 3)
        #expect(profile.all.total[22] == 1)
        #expect(profile.all.bins(category: 2)[22] == 1)
        #expect(profile.all.bins(category: 2)[9] == 0)

        let day = utc.sessionDayStart(for: date(2_026, 6, 3, 9))
        #expect(profile.byDay[day]?.total[9] == 2)
        #expect(profile.byDay[day]?.total[22] == 1)
    }

    // MARK: - Weekdays (§8)

    @Test
    func `Weekday buckets are ordered by the calendar's first weekday`() {
        let window = bounds(date(2_026, 6, 1, 0), date(2_026, 6, 14, 23))
        let entries = [
            snapshot(at: date(2_026, 6, 1, 9)), // Monday
            snapshot(at: date(2_026, 6, 8, 9)), // Monday
            snapshot(category: 3, at: date(2_026, 6, 6, 9)), // Saturday
        ]
        let buckets = UsageAnalytics.weekdayBreakdown(entries, bounds: window, calendar: utc)

        #expect(buckets.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
        let monday = buckets.first { $0.weekday == 2 }
        #expect(monday?.total == 2)
        #expect(monday?.occurrences == 2)
        #expect(monday?.average == 1)
        let saturday = buckets.first { $0.weekday == 7 }
        #expect(saturday?.byCategory[3] == 1)
    }

    @Test
    func `A partial range divides by the weekdays it actually contains`() {
        // Ten days: some weekdays come around twice, some once.
        let window = bounds(date(2_026, 6, 1, 0), date(2_026, 6, 10, 23))
        let occurrences = UsageAnalytics.weekdayOccurrences(bounds: window, calendar: utc)

        #expect(occurrences.values.reduce(0, +) == 10)
        #expect(occurrences[2] == 2) // Mondays: the 1st and the 8th
        #expect(occurrences[5] == 1) // Thursday: only the 4th
    }

    // MARK: - End to end

    @Test
    func `A full pass wires every section together`() {
        let now = date(2_026, 6, 15, 12)
        var entries: [UsageEntrySnapshot] = []
        for day in 1 ... 14 {
            entries.append(snapshot(substance: 0, category: 0, route: 0, level: 3, at: date(2_026, 6, day, 8)))
            if day.isMultiple(of: 2) {
                entries.append(snapshot(substance: 1, category: 4, route: 3, level: nil, at: date(2_026, 6, day, 21)))
            }
        }
        let refs = [
            UsageSubstanceRef(name: "Caffeine", displayName: "Caffeine", categoryIndex: 0),
            UsageSubstanceRef(name: "Melatonin", displayName: "Melatonin", categoryIndex: 4),
        ]

        let result = UsageAnalytics.compute(
            entries: entries, substances: refs, range: .thirtyDays, calendar: utc, now: now,
        )

        #expect(result.entryCount == 21)
        #expect(result.overview.uniqueSubstances == 2)
        #expect(result.overview.sparkline.reduce(0, +) == 21)
        #expect(result.trends.count == 2)
        #expect(result.doseLevels.resolvedEntries == 14)
        #expect(result.routes.isMeaningful)
        #expect(result.coUse.count == 1)
        #expect(result.coUse[0].days == 7)
        #expect(result.regularity.count == 2)
        #expect(result.weekdays.count == 7)
        #expect(result.categories.map(\.categoryIndex) == [0, 4])
        #expect(result.heatmap.maxCount == 2)
    }

    @Test
    func `An empty history produces an empty, non-crashing result`() {
        let result = UsageAnalytics.compute(
            entries: [], substances: [], range: .ninetyDays, calendar: utc, now: date(2_026, 6, 15),
        )

        #expect(result.isEmpty)
        #expect(result.overview.entryCount == 0)
        #expect(result.overview.doseIntensity == nil)
        #expect(result.trends.isEmpty)
        #expect(result.coUse.isEmpty)
        #expect(result.regularity.isEmpty)
        #expect(result.weekdays.count == 7)
        #expect(!result.routes.isMeaningful)
    }
}
