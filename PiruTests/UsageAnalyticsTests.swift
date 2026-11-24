import Foundation
import Testing
@testable import Piru

/// The aggregation behind Insights → Usage.
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
        commonDoses: Double? = nil,
        at timestamp: Date,
    ) -> UsageEntrySnapshot {
        UsageEntrySnapshot(
            substanceIndex: substance, categoryIndex: category, routeIndex: route,
            doseLevelIndex: level, commonDoses: commonDoses, timestamp: timestamp,
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

    /// A new product of a substance already in the journal is not a new substance, and the
    /// two rows count as one.
    @Test
    func `Products of one molecule count as one substance`() {
        let now = date(2_026, 6, 15)
        let window = bounds(now.addingTimeInterval(-7 * 86_400), now)
        let all = [
            // Ritalin since long ago; Concerta, the same molecule, first logged this week.
            UsageEntrySnapshot(substanceIndex: 1, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: now.addingTimeInterval(-40 * 86_400)),
            UsageEntrySnapshot(substanceIndex: 1, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: now.addingTimeInterval(-2 * 86_400)),
            UsageEntrySnapshot(substanceIndex: 0, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: now.addingTimeInterval(-86_400)),
        ]
        let inRange = all.filter { $0.timestamp >= window.start }
        let overview = UsageAnalytics.overview(all: all, inRange: inRange, bounds: window, calendar: utc)

        #expect(overview.uniqueSubstances == 1)
        #expect(overview.newSubstances == 0)
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
    func `The window count splits the window into equal buckets`() {
        let start = date(2_026, 6, 1, 0)
        let end = date(2_026, 6, 8, 0)
        let window = bounds(start, end)
        // One entry per day for seven days → one per bucket.
        let stamps = (0 ..< 7).map { start.addingTimeInterval(Double($0) * 86_400 + 3_600) }

        #expect(UsageAnalytics.windowCount(stamps, bounds: window).buckets == [1, 1, 1, 1, 1, 1, 1])
    }

    @Test
    func `Per day divides by the days the journal covers, not the whole range`() {
        // A journal that began a week ago: 28 entries, four a day.
        let now = date(2_026, 6, 15, 12)
        let first = now.addingTimeInterval(-7 * 86_400)
        let stamps = (0 ..< 28).map { first.addingTimeInterval(Double($0) * 6 * 3_600) }

        // The same four a day on every range, All included.
        for range in UsageTimeRange.allCases {
            let count = UsageAnalytics.windowCount(stamps, range: range, now: now, calendar: utc, boundaryHour: 0)
            #expect(count.entryCount == 28)
            #expect(count.averagePerDay == 4)
        }
    }

    @Test
    func `Per day divides by the range once the journal is older than it`() {
        let now = date(2_026, 6, 15, 12)
        // One entry a day for 100 days: 30 of them fall in the 30-day range.
        let stamps = (0 ..< 100).map { now.addingTimeInterval(-Double($0) * 86_400 - 3_600) }
        let count = UsageAnalytics.windowCount(stamps, range: .thirtyDays, now: now, calendar: utc, boundaryHour: 0)

        #expect(count.entryCount == 30)
        #expect(count.averagePerDay == 1)
    }

    @Test
    func `A substance filter leaves per day on the journal's days`() {
        // The journal began 20 days ago; the filtered substance was logged twice, yesterday.
        let now = date(2_026, 6, 15, 12)
        let filtered = [snapshot(at: now.addingTimeInterval(-86_400)), snapshot(at: now.addingTimeInterval(-80_000))]
        let result = UsageAnalytics.compute(
            entries: filtered, substances: [], range: .thirtyDays, calendar: utc, now: now,
            journalStart: now.addingTimeInterval(-20 * 86_400),
        )

        #expect(result.overview.averagePerDay == 0.1)
    }

    @Test
    func `A rate above zero never reads as zero`() {
        #expect(UsageAnalytics.rateText(0) == "0")
        #expect(UsageAnalytics.rateText(0.02) == "<" + 0.1.formatted(.number.precision(.fractionLength(1))))
        #expect(UsageAnalytics.rateText(0.06) == 0.1.formatted(.number.precision(.fractionLength(1))))
        #expect(UsageAnalytics.rateText(4) == "4")
    }

    @Test
    func `An entry at the very end of the window lands in the last bucket`() {
        let start = date(2_026, 6, 1, 0)
        let end = date(2_026, 6, 8, 0)
        let window = bounds(start, end)

        #expect(UsageAnalytics.windowCount([end], bounds: window).buckets == [0, 0, 0, 0, 0, 0, 1])
        #expect(UsageAnalytics.windowCount([start], bounds: window).buckets == [1, 0, 0, 0, 0, 0, 0])
    }

    @Test
    func `The window count leaves out entries past now and before the window`() {
        let now = date(2_026, 6, 15, 9, 41)
        let stamps = [
            now.addingTimeInterval(-31 * 86_400), // before a 30-day window
            now.addingTimeInterval(-29 * 86_400),
            now.addingTimeInterval(-3_600),
            now.addingTimeInterval(1_140), // 10:00, later than now
        ]
        let count = UsageAnalytics.windowCount(stamps, range: .thirtyDays, now: now, calendar: utc, boundaryHour: 0)

        #expect(count.entryCount == 2)
        // 30 days ending at 09:41 touch 31 calendar days.
        #expect(count.buckets.count == 31)
        #expect(count.buckets.reduce(0, +) == 2)
        #expect(count.averagePerDay == 2.0 / 30)
    }

    /// The Insights card's bars are journal days: at 10:00, a dose at 23:00
    /// yesterday and one at 08:00 today are two bars, and with a 4 AM day start
    /// a 02:00 dose belongs to the evening before it.
    @Test
    func `The Insights card buckets by journal day`() throws {
        let now = date(2_026, 6, 15, 10)
        let stamps = [date(2_026, 6, 14, 23), date(2_026, 6, 15, 8), date(2_026, 6, 14, 2)]
        let count = UsageAnalytics.windowCount(stamps, range: .thirtyDays, now: now, calendar: utc, boundaryHour: 4)
        #expect(count.entryCount == 3)
        let today = try #require(count.buckets.last)
        #expect(today == 1)
        #expect(count.buckets[count.buckets.count - 2] == 1)
        #expect(count.buckets[count.buckets.count - 3] == 1)
        #expect(count.buckets.reduce(0, +) == 3)
    }

    @Test
    func `The Insights card and the Usage screen count the same entries`() {
        let now = date(2_026, 6, 15, 9, 41)
        let entries = (0 ..< 40).map { snapshot(at: now.addingTimeInterval(Double($0) * -86_400 * 0.9 + 1_800)) }
        let screen = UsageAnalytics.compute(
            entries: entries, substances: [UsageSubstanceRef(name: "A", displayName: "A", categoryIndex: 0)],
            range: UsageTimeRange.opening, calendar: utc, now: now,
        )
        let card = UsageAnalytics.windowCount(entries.map(\.timestamp), range: UsageTimeRange.opening, now: now, calendar: utc)

        #expect(card.entryCount == screen.overview.entryCount)
        #expect(card.averagePerDay == screen.overview.averagePerDay)
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
    func `A trend point at the range's start averages the days before the range`() {
        // One dose a day for 40 days; the chart shows the last 10.
        let start = date(2_026, 6, 1, 0)
        let entries = (0 ..< 40).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let starts = (30 ..< 40).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 10)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(40 * 86_400),
            journalStart: start,
        )

        // Seven a week from the first point on: no climb from zero at the left edge.
        #expect(series[0].points.count == 10)
        #expect(series[0].points.allSatisfy { $0.value == 7 })
    }

    @Test
    func `A trend line begins once a full window of journal lies behind it`() {
        // The journal began on day 0 with a dose a day; the range shows days 0 to 9.
        let start = date(2_026, 6, 1, 0)
        let entries = (0 ..< 10).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let starts = (0 ..< 10).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 10)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(10 * 86_400),
            journalStart: start,
        )

        // Days 0 to 5 have under a week behind them and are left out.
        #expect(series[0].points.map(\.date) == Array(starts[6...]))
        #expect(series[0].points.allSatisfy { $0.value == 7 })

        // The scrub readout finds no value before the line begins, rather than the first point's.
        #expect(series[0].point(nearest: starts[2]) == nil)
        #expect(series[0].point(nearest: starts[6].addingTimeInterval(-6 * 3_600))?.date == starts[6])
        #expect(series[0].point(nearest: starts[9].addingTimeInterval(20 * 3_600))?.date == starts[9])
    }

    @Test
    func `A journal younger than the rolling window draws no trend line`() {
        // Five days of entries against a four-week window.
        let now = date(2_026, 6, 15, 12)
        let entries = (0 ..< 5).map { snapshot(at: now.addingTimeInterval(-Double($0) * 86_400 - 3_600)) }
        let result = UsageAnalytics.compute(
            entries: entries, substances: [], range: .ninetyDays, calendar: utc, now: now,
        )

        #expect(result.trends.count == 1)
        #expect(result.trends[0].points.isEmpty)
    }

    @Test
    func `Raw daily buckets include the journal's first day`() {
        // 7D draws each day's own count, so the first day has a full window behind it.
        let now = date(2_026, 6, 15, 12)
        let entries = (0 ..< 3).map { snapshot(at: now.addingTimeInterval(-Double($0) * 86_400 - 3_600)) }
        let result = UsageAnalytics.compute(
            entries: entries, substances: [], range: .sevenDays, calendar: utc, now: now,
        )

        #expect(result.trends[0].points.count == 3)
    }

    @Test
    func `The time axis spans the selected range, however little of it is logged`() {
        let now = date(2_026, 6, 15, 12)
        let result = UsageAnalytics.compute(
            entries: [snapshot(at: now.addingTimeInterval(-3_600))], substances: [],
            range: .thirtyDays, calendar: utc, now: now,
        )

        #expect(result.timeAxis.lowerBound == utc.sessionDayStart(for: now.addingTimeInterval(-30 * 86_400)))
        #expect(result.timeAxis.upperBound == utc.sessionDayStart(for: now).addingTimeInterval(86_400))
    }

    @Test
    func `The common-dose entry count says how much the lens can weigh`() {
        let now = date(2_026, 6, 15, 12)
        let entries = [
            snapshot(commonDoses: 1, at: now.addingTimeInterval(-3_600)),
            snapshot(substance: 1, at: now.addingTimeInterval(-7_200)),
            snapshot(substance: 1, at: now.addingTimeInterval(-90_000)),
        ]
        let result = UsageAnalytics.compute(entries: entries, substances: [], range: .sevenDays, calendar: utc, now: now)

        #expect(result.entryCount == 3)
        #expect(result.commonDoseEntryCount == 1)
    }

    @Test
    func `A trend point also sums common-dose units per week`() {
        let start = date(2_026, 6, 1, 0)
        // One dose a day for ten days, each worth 2 common doses.
        let entries = (0 ..< 10).map {
            snapshot(commonDoses: 2.0, at: start.addingTimeInterval(Double($0) * 86_400 + 3_600))
        }
        let starts = (0 ..< 10).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 10)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(10 * 86_400),
        )

        #expect(series[0].hasCommonDoses)
        // Day 6 on: seven daily doses × 2 common each = 14 common doses per week.
        #expect(series[0].points[6].commonValue == 14)
        // The entry-count value is unchanged alongside it.
        #expect(series[0].points[6].value == 7)
    }

    @Test
    func `A series with no common-dose data reports zero and is flagged`() {
        let start = date(2_026, 6, 1, 0)
        let entries = (0 ..< 5).map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let starts = (0 ..< 5).map { start.addingTimeInterval(Double($0) * 86_400) }

        let series = UsageAnalytics.trends(
            entries, ranking: [(substanceIndex: 0, count: 5)], bucketStarts: starts,
            bucketDays: 1, windowDays: 7, rangeEnd: start.addingTimeInterval(5 * 86_400),
        )

        #expect(!series[0].hasCommonDoses)
        #expect(series[0].points.allSatisfy { $0.commonValue == 0 })
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
            levelIndex(mdmaLadder, "mg", amount, "mg")
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
            levelIndex(mdmaLadder, "mg", 0.09, "g")
                == UsageAnalyticsModel.index(of: .common),
        )
        // Both spellings of micro must work; only one of them is MICRO SIGN.
        let microgram = DoseRange(threshold: 20, light: 50 ... 100, common: 100 ... 150, strong: 150 ... 200, heavy: 200)
        #expect(
            levelIndex(microgram, "µg", 0.12, "mg")
                == UsageAnalyticsModel.index(of: .common),
        )
    }

    @Test
    func `An incomparable unit drops out instead of being read across`() {
        // A volume against a mass ladder: 5 mL is not 5 mg.
        #expect(levelIndex(mdmaLadder, "mg", 5, "mL") == nil)
        #expect(levelIndex(mdmaLadder, "mg", 5, "IU") == nil)
        // A qualified unit states a basis; folding it onto plain mg would
        // compare a freebase amount against a salt ladder.
        #expect(levelIndex(mdmaLadder, "mg", 90, "mg (freebase)") == nil)
    }

    @Test
    func `An empty ladder places nothing`() {
        #expect(levelIndex(DoseRange(), "mg", 90, "mg") == nil)
    }

    @Test
    func `A common dose is expressed as a multiple of the common midpoint`() {
        /// MDMA common band is 75–110, midpoint 92.5.
        func common(_ amount: Double, _ unit: String = "mg") -> Double? {
            commonDoses(mdmaLadder, "mg", amount, unit)
        }
        // A dose at the midpoint is exactly one common dose.
        #expect(common(92.5) == 1.0)
        // Double the midpoint is two common doses.
        #expect(common(185) == 2.0)
        // Converted from grams first: 0.0925 g = 92.5 mg = 1.0.
        #expect(common(0.0925, "g") == 1.0)
    }

    @Test
    func `Common-dose units need a common band and a convertible unit`() {
        // No common tier: threshold/heavy only.
        let noCommon = DoseRange(threshold: 20, heavy: 200)
        #expect(commonDoses(noCommon, "mg", 50, "mg") == nil)
        // Incomparable unit against a mass ladder.
        #expect(commonDoses(mdmaLadder, "mg", 5, "mL") == nil)
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

    /// Concerta in the morning and a Ritalin booster are one drug, methylphenidate: their rows
    /// never pair, and together they make one methylphenidate pair with a different substance.
    @Test
    func `Two products of one molecule are not a pair`() throws {
        let concerta = 0, ritalin = 1, caffeine = 2
        let entries = (1 ... 3).flatMap { day in
            [
                UsageEntrySnapshot(substanceIndex: concerta, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, day, 8)),
                UsageEntrySnapshot(substanceIndex: ritalin, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, day, 14)),
                UsageEntrySnapshot(substanceIndex: caffeine, moleculeIndex: 1, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, day, 9)),
            ]
        }
        let pairs = UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc))
        try #require(pairs.count == 1)
        let pair = pairs[0]
        #expect(pair.firstIndex == concerta)
        #expect(pair.secondIndex == caffeine)
        #expect(pair.days == 3)
        #expect(pair.firstSpansRows)
        #expect(!pair.secondSpansRows)
    }

    /// Concerta with Adderall one day and Ritalin with Adderall the next are two
    /// days of one methylphenidate-and-amphetamine pair, enough to surface.
    @Test
    func `Products of one molecule add their days to one pair`() throws {
        let concerta = 0, ritalin = 1, adderall = 2
        let entries = [
            UsageEntrySnapshot(substanceIndex: concerta, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, 1, 8)),
            UsageEntrySnapshot(substanceIndex: adderall, moleculeIndex: 1, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, 1, 9)),
            UsageEntrySnapshot(substanceIndex: ritalin, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, 2, 8)),
            UsageEntrySnapshot(substanceIndex: adderall, moleculeIndex: 1, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, 2, 9)),
            UsageEntrySnapshot(substanceIndex: ritalin, moleculeIndex: 0, categoryIndex: 0, routeIndex: 0, doseLevelIndex: nil, timestamp: date(2_026, 6, 3, 8)),
        ]
        let pairs = UsageAnalytics.coUsePairs(dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc))
        try #require(pairs.count == 1)
        let pair = pairs[0]
        // Ritalin is the molecule's most-logged row; the pair names it by its molecule.
        #expect(pair.firstIndex == ritalin)
        #expect(pair.secondIndex == adderall)
        #expect(pair.days == 2)
        #expect(pair.unionDays == 3)
        #expect(pair.firstSpansRows)
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
    func `Interval statistics report the median gap and the spread around it`() {
        let stats = UsageAnalytics.intervalStatistics([1, 1, 1, 1])
        #expect(stats?.median == 1)
        #expect(stats?.variation == 0)

        // Median 2; each gap is 1 away from it, half the median.
        let uneven = UsageAnalytics.intervalStatistics([1, 3])
        #expect(uneven?.median == 2)
        #expect(uneven?.variation == 0.5)

        #expect(UsageAnalytics.intervalStatistics([]) == nil)
        #expect(UsageAnalytics.intervalStatistics([0, 0]) == nil)
    }

    @Test
    func `A daily med with one long pause still reads as very regular, every day`() {
        // Sixty mornings, three weeks off, sixty more: 118 one-day gaps and one
        // of 22 days. Standard deviation over mean grades this "Sporadic".
        let start = date(2_026, 1, 1, 9)
        let days = Array(0 ..< 60) + Array(81 ..< 141)
        let entries = days.map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400)) }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: entries.count)],
        )

        #expect(rows[0].typicalIntervalDays == 1)
        #expect(abs(rows[0].gapVariation - 21.0 / 119.0) < 0.0001)
        #expect(rows[0].tier == .veryRegular)
    }

    @Test
    func `A daily habit reads as very regular at one day apart`() {
        let entries = (1 ... 8).map { snapshot(at: date(2_026, 6, $0, 9)) }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: 8)],
        )

        #expect(rows.count == 1)
        #expect(abs(rows[0].typicalIntervalDays - 1) < 0.0001)
        #expect(rows[0].gapVariation == 0)
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
        #expect(abs(rows[0].typicalIntervalDays - 1) < 0.0001)
    }

    @Test
    func `A bursty history reads as sporadic`() {
        // Bursts and droughts in turn: gaps of 1, 1, 12, 1, 15, 2 days.
        let days = [1, 2, 3, 15, 16, 31, 33]
        let start = date(2_026, 6, 1, 9)
        let entries = days.map { snapshot(at: start.addingTimeInterval(Double($0) * 86_400)) }
        let rows = UsageAnalytics.regularity(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc),
            counts: [(substanceIndex: 0, count: 7)],
        )

        // Median gap 1.5 days; the gaps sit 26 days from it in all, 4.33 each.
        #expect(rows[0].typicalIntervalDays == 1.5)
        #expect(rows[0].gapVariation > 1)
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
    func `Regularity tiers follow the spec's cut points`() {
        #expect(UsageRegularityTier(gapVariation: 0.2) == .veryRegular)
        #expect(UsageRegularityTier(gapVariation: 0.3) == .somewhatRegular)
        #expect(UsageRegularityTier(gapVariation: 0.59) == .somewhatRegular)
        #expect(UsageRegularityTier(gapVariation: 0.6) == .irregular)
        #expect(UsageRegularityTier(gapVariation: 0.99) == .irregular)
        #expect(UsageRegularityTier(gapVariation: 1.0) == .sporadic)
    }

    // MARK: - Routes (§5)

    @Test
    func `One route is not a color breakdown`() {
        let entries = (1 ... 3).map { snapshot(route: 0, at: date(2_026, 6, $0, 9)) }
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])

        #expect(breakdown.distinctRoutes == [0])
        #expect(!breakdown.routesAreMeaningful)
    }

    @Test
    func `Two routes split a substance's bar, most-used first`() {
        let entries = [
            snapshot(route: 0, at: date(2_026, 6, 1, 9)),
            snapshot(route: 0, at: date(2_026, 6, 2, 9)),
            snapshot(route: 3, at: date(2_026, 6, 3, 9)),
        ]
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])

        #expect(breakdown.routesAreMeaningful)
        #expect(breakdown.rows.count == 1)
        #expect(breakdown.rows[0].total == 3)
        #expect(breakdown.rows[0].byRoute.map(\.routeIndex) == [0, 3])
        #expect(breakdown.rows[0].byRoute.map(\.count) == [2, 1])
    }

    @Test
    func `Common-dose totals sum per substance and split by route`() throws {
        // Two oral doses at 1.0 and 2.0 common each, one rectal at 0.5.
        let entries = [
            snapshot(route: 0, commonDoses: 1.0, at: date(2_026, 6, 1, 9)),
            snapshot(route: 0, commonDoses: 2.0, at: date(2_026, 6, 2, 9)),
            snapshot(route: 3, commonDoses: 0.5, at: date(2_026, 6, 3, 9)),
        ]
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])
        let row = try #require(breakdown.rows.first)

        #expect(row.commonTotal == 3.5)
        // Route 0 carries 3.0 of it, route 3 the remaining 0.5.
        #expect(row.byRoute.first { $0.routeIndex == 0 }?.common == 3.0)
        #expect(row.byRoute.first { $0.routeIndex == 3 }?.common == 0.5)
        #expect(breakdown.commonDoseSubstances == 1)
    }

    @Test
    func `A substance with no common-dose data has a nil total, not zero`() throws {
        // Logged, but nothing resolved to a common-dose value.
        let entries = (1 ... 3).map { snapshot(route: 0, at: date(2_026, 6, $0, 9)) }
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: [(substanceIndex: 0, count: 3)])
        let row = try #require(breakdown.rows.first)

        #expect(row.total == 3)
        #expect(row.commonTotal == nil)
        #expect(breakdown.commonDoseSubstances == 0)
    }

    @Test
    func `The ranking keeps every substance, not a top-N slice`() {
        // Twelve substances, one entry each — more than the view's row cap. The
        // compute must return all so the view can re-rank by common-dose units.
        let entries = (0 ..< 12).map { snapshot(substance: $0, at: date(2_026, 6, 1, 9 + $0)) }
        let ranking = (0 ..< 12).map { (substanceIndex: $0, count: 1) }
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: ranking)

        #expect(breakdown.rows.count == 12)
    }

    @Test
    func `Under common doses a substance without one stays in Most logged, below the weighed ones`() {
        // Twelve weighed substances fill the row cap; substance 12, logged most
        // often, has no common dose.
        var entries = (0 ..< 12).map { snapshot(substance: $0, commonDoses: Double(12 - $0), at: date(2_026, 6, 1, 9)) }
        entries += (0 ..< 20).map { _ in snapshot(substance: 12, at: date(2_026, 6, 1, 10)) }
        let ranking = [(substanceIndex: 12, count: 20)] + (0 ..< 12).map { (substanceIndex: $0, count: 1) }
        let breakdown = UsageAnalytics.routeBreakdown(entries, ranking: ranking)

        let rows = breakdown.rankedRows(metric: .commonDoses, limit: 10)
        #expect(rows.count == 11)
        #expect(rows.first?.substanceIndex == 0)
        #expect(rows.last?.substanceIndex == 12)
        #expect(rows.last?.total == 20)
        #expect(breakdown.rankedRows(metric: .entries, limit: 10).first?.substanceIndex == 12)
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
    func `The heatmap spans the history and marks the selected range's days`() {
        // History from Wednesday 2026-06-03; "Last 7 Days" ends 06-16 09:00.
        let history = bounds(date(2_026, 6, 3, 9), date(2_026, 6, 16, 9))
        let window = bounds(date(2_026, 6, 9, 9), date(2_026, 6, 16, 9))
        let entries = [snapshot(at: date(2_026, 6, 3, 10)), snapshot(at: date(2_026, 6, 15, 10))]
        let heatmap = UsageAnalytics.heatmap(
            dayIndex: UsageAnalytics.groupByDay(entries, calendar: utc), bounds: history, window: window, calendar: utc,
        )
        let windowDays = heatmap.cells.filter(\.inWindow).map(\.date)

        // 06-09 (the window's partial first day) through 06-16.
        #expect(windowDays.count == 8)
        #expect(windowDays.first == utc.sessionDayStart(for: date(2_026, 6, 9, 12)))
        // The older logged day is still drawn, outside the range.
        let older = heatmap.cells.first { $0.date == utc.sessionDayStart(for: date(2_026, 6, 3, 10)) }
        #expect(older?.total == 1)
        #expect(older?.inRange == true)
        #expect(older?.inWindow == false)
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
            snapshot(at: date(2_026, 6, 1, 9)), // Monday, no common-dose value
            snapshot(at: date(2_026, 6, 8, 9)), // Monday, no common-dose value
            snapshot(commonDoses: 2.5, at: date(2_026, 6, 6, 9)), // Saturday
        ]
        let buckets = UsageAnalytics.weekdayBreakdown(entries, bounds: window, calendar: utc)

        #expect(buckets.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
        let monday = buckets.first { $0.weekday == 2 }
        #expect(monday?.total == 2)
        #expect(monday?.occurrences == 2)
        #expect(monday?.average == 1)
        // No common-dose value on either Monday entry — nil, not zero.
        #expect(monday?.commonTotal == nil)
        let saturday = buckets.first { $0.weekday == 7 }
        #expect(saturday?.total == 1)
        #expect(saturday?.commonTotal == 2.5)
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

    @Test
    func `A journal younger than the range averages each weekday over the ones it has seen`() {
        // A 30-day range over a journal that began on Monday June 8: one Monday so far.
        let window = UsageAnalytics.Bounds(
            start: date(2_026, 5, 10, 12), end: date(2_026, 6, 9, 12), lengthDays: 30,
            hasPreviousPeriod: true, loggedStart: date(2_026, 6, 8, 9),
        )
        let entries = [snapshot(at: date(2_026, 6, 8, 9)), snapshot(at: date(2_026, 6, 8, 18))]
        let buckets = UsageAnalytics.weekdayBreakdown(entries, bounds: window, calendar: utc)
        let monday = buckets.first { $0.weekday == 2 }

        #expect(monday?.occurrences == 1)
        #expect(monday?.average == 2)
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
        #expect(result.overview.window.buckets.reduce(0, +) == 21)
        #expect(result.trends.count == 2)
        #expect(result.doseLevels.resolvedEntries == 14)
        #expect(result.routes.routesAreMeaningful)
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
        #expect(!result.routes.routesAreMeaningful)
    }
}

/// A dose of `amount` `unit` placed on `range` written in `ladderUnit`, as the
/// §4 tier index.
private func levelIndex(_ range: DoseRange, _ ladderUnit: String, _ amount: Double, _ unit: String) -> Int? {
    DoseLadder(range: range, unit: ladderUnit).level(of: DoseQuantity(amount, unit: unit)).map(UsageAnalyticsModel.index(of:))
}

/// A dose of `amount` `unit` as a multiple of `range`'s common dose.
private func commonDoses(_ range: DoseRange, _ ladderUnit: String, _ amount: Double, _ unit: String) -> Double? {
    DoseLadder(range: range, unit: ladderUnit).commonDoses(of: DoseQuantity(amount, unit: unit))
}
