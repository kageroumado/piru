import Foundation

// MARK: - Time range

/// The window the Usage screen aggregates over.
///
/// `nonisolated` (like everything else in this file) because the whole
/// aggregation runs off the main actor — the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a bare `enum` here would be
/// main-isolated and unusable from the detached compute task.
nonisolated enum UsageTimeRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear
    case all

    var id: String {
        rawValue
    }

    /// Length of the selected window in days; `nil` for "All".
    var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .oneYear: 365
        case .all: nil
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .sevenDays: "7D"
        case .thirtyDays: "30D"
        case .ninetyDays: "90D"
        case .oneYear: "1Y"
        case .all: "All"
        }
    }

    /// Whether the trend / dose-level buckets are one week wide (else one day).
    /// Matches `Specs/usage-graphs-v2.md` §3's aggregation table.
    var usesWeeklyBuckets: Bool {
        switch self {
        case .sevenDays, .thirtyDays: false
        case .ninetyDays, .oneYear, .all: true
        }
    }

    /// Rolling window, in days, behind each trend point (§3). 7D shows raw daily
    /// buckets — a rolling week over a seven-day range is just the range, so its
    /// window is a single day; 30D smooths over a week; the longer ranges over
    /// four.
    var rollingWindowDays: Int {
        switch self {
        case .sevenDays: 1
        case .thirtyDays: 7
        default: 28
        }
    }

    /// Whether the trend line reads as a per-week rate. 7D reads as raw per-day
    /// buckets instead — a weekly rate across a single week is meaningless.
    var trendPerWeek: Bool {
        self != .sevenDays
    }
}

// MARK: - Inputs

/// One logged dose, reduced to the plain values the aggregation needs.
///
/// Everything that requires a `SubstanceLibrary` lookup (category, dose level)
/// is resolved on the main actor while building these, and carried here as an
/// **index** rather than as the enum itself: `SubstanceCategory`,
/// `RouteOfAdministration`, and `DoseLevel` are all main-actor-isolated types
/// under the target's default isolation, so grouping by them off-main would not
/// compile. Indices are plain `Int`s and make the dictionary keys cheaper too.
nonisolated struct UsageEntrySnapshot: Sendable {
    /// Index into ``UsageAnalyticsResult/substances``.
    let substanceIndex: Int
    /// Index into `SubstanceCategory.allCases`.
    let categoryIndex: Int
    /// Index into `RouteOfAdministration.allCases`.
    let routeIndex: Int
    /// Index into `DoseLevel.allCases`, or `nil` when the dose could not be
    /// placed on a ladder (substance unknown, no ladder for that route, or the
    /// logged unit is not convertible to the ladder's unit).
    let doseLevelIndex: Int?
    let amount: Double
    /// This dose expressed as a multiple of the substance's *common* dose —
    /// `amount ÷ midpoint(common)`, so `1.0` is one textbook common dose and
    /// `2.5` is two-and-a-half of them. `nil` on the same footing as
    /// ``doseLevelIndex``: no common tier for this ladder, or a logged unit that
    /// doesn't convert to the ladder's. It is what lets a milligram stimulant and
    /// a gram-dosed botanical be counted in the same currency, instead of ranking
    /// them by how *often* they were logged.
    let commonDoses: Double?
    let timestamp: Date

    init(
        substanceIndex: Int,
        categoryIndex: Int,
        routeIndex: Int,
        doseLevelIndex: Int?,
        amount: Double,
        commonDoses: Double? = nil,
        timestamp: Date,
    ) {
        self.substanceIndex = substanceIndex
        self.categoryIndex = categoryIndex
        self.routeIndex = routeIndex
        self.doseLevelIndex = doseLevelIndex
        self.amount = amount
        self.commonDoses = commonDoses
        self.timestamp = timestamp
    }
}

/// A distinct substance in the snapshot: index → names + category.
nonisolated struct UsageSubstanceRef: Sendable, Hashable {
    /// The canonical name as logged (also the `colorMap` key, lowercased).
    let name: String
    /// The name to show the user (user relabels applied).
    let displayName: String
    /// Index into `SubstanceCategory.allCases`.
    let categoryIndex: Int
}

// MARK: - Outputs

/// §1 — the four overview cards.
nonisolated struct UsageOverview: Sendable {
    let entryCount: Int
    /// Entry count in the same-length window immediately before the selected
    /// range; `nil` for "All" (there is nothing before it).
    let previousEntryCount: Int?
    /// Signed fractional change vs. the previous period (`0.12` = +12%).
    /// `nil` when there is no previous period, or it was empty.
    let percentChange: Double?
    /// Seven equal buckets across the selected range, oldest first.
    let sparkline: [Int]
    let uniqueSubstances: Int
    /// Substances whose first-ever logged dose falls inside the selected range.
    let newSubstances: Int
    let averagePerDay: Double
    /// Weekday component (1 = Sunday) that carries the most entries; `nil` when
    /// there are none.
    let busiestWeekday: Int?
    /// Entries whose dose resolved to a ladder level.
    let doseResolvedCount: Int
    /// Of those, how many landed at Common or above.
    let commonOrAboveCount: Int
    /// Of those, how many landed at Heavy.
    let heavyCount: Int

    /// Share of *resolvable* entries at Common or above, `0…1`. `nil` when
    /// nothing resolved, so the card can say so instead of showing a fake 0%.
    var doseIntensity: Double? {
        guard doseResolvedCount > 0 else { return nil }
        return Double(commonOrAboveCount) / Double(doseResolvedCount)
    }
}

/// One day cell in the §2 heatmap.
nonisolated struct UsageHeatmapCell: Sendable, Hashable, Identifiable {
    /// Session-day start (see `Calendar.sessionDayStart`).
    let date: Date
    let total: Int
    /// Σ commonDoses on this day (`0` when none of its entries carried one).
    let commonTotal: Double
    /// Category index → entry count on this day.
    let byCategory: [Int: Int]
    /// Category index → Σ commonDoses on this day.
    let byCategoryCommon: [Int: Double]
    /// `false` for the leading/trailing cells that pad the first and last week
    /// columns outside the selected range — drawn blank, never colored.
    let inRange: Bool

    var id: Date {
        date
    }
}

/// §2 — GitHub-style contribution grid: columns are weeks, rows are weekdays.
nonisolated struct UsageHeatmap: Sendable {
    /// Week-start dates, oldest first — one per column.
    let weekStarts: [Date]
    /// The seven weekday components (1 = Sunday) in the user's display order.
    let rowWeekdays: [Int]
    /// `weekStarts.count * 7` cells in column-major order (column 0's Monday…
    /// Sunday, then column 1's…).
    let cells: [UsageHeatmapCell]
    /// Busiest day's count, the denominator for the entry-count color ramp.
    let maxCount: Int
    /// Busiest day's common-dose total, the denominator for the common-dose ramp.
    let maxCommon: Double

    /// The cell at `(column, row)`, or `nil` if out of bounds.
    func cell(column: Int, row: Int) -> UsageHeatmapCell? {
        let index = column * 7 + row
        guard cells.indices.contains(index) else { return nil }
        return cells[index]
    }
}

/// Twenty-four hour-of-day bins, overall and split by category.
nonisolated struct UsageHourBins: Sendable {
    /// 24 counts, index = clock hour.
    let total: [Int]
    /// Category index → 24 counts.
    let byCategory: [Int: [Int]]
    /// 24 common-dose sums, index = clock hour.
    let totalCommon: [Double]
    /// Category index → 24 common-dose sums.
    let byCategoryCommon: [Int: [Double]]

    static let empty = UsageHourBins(
        total: Array(repeating: 0, count: 24), byCategory: [:],
        totalCommon: Array(repeating: 0, count: 24), byCategoryCommon: [:],
    )

    /// The entry-count bins for a category filter (`nil` = all categories).
    func bins(category: Int?) -> [Int] {
        guard let category else { return total }
        return byCategory[category] ?? Array(repeating: 0, count: 24)
    }

    /// The common-dose bins for a category filter (`nil` = all categories).
    func commonBins(category: Int?) -> [Double] {
        guard let category else { return totalCommon }
        return byCategoryCommon[category] ?? Array(repeating: 0, count: 24)
    }
}

/// §2's lower half — the hour histogram, overall and per selected day.
nonisolated struct UsageHourProfile: Sendable {
    let all: UsageHourBins
    /// Session-day start → that day's bins, for the tap-a-cell drill-down.
    let byDay: [Date: UsageHourBins]
}

/// One point on a §3 rolling-frequency line.
nonisolated struct UsageTrendPoint: Sendable, Hashable, Identifiable {
    let date: Date
    /// Entries per week over the trailing rolling window.
    let value: Double
    /// Common-dose units per week over the same window — the sum of each
    /// entry's ``UsageEntrySnapshot/commonDoses``, normalized per week. Zero when
    /// nothing in the window had a common-dose value.
    let commonValue: Double

    var id: Date {
        date
    }
}

/// One substance's §3 line. Zero-filled across every bucket, so a dry spell
/// draws the line at zero instead of breaking it.
nonisolated struct UsageTrendSeries: Sendable, Identifiable {
    let substanceIndex: Int
    let entryCount: Int
    let points: [UsageTrendPoint]
    /// Whether any of this substance's entries carried a common-dose value. A
    /// line with none would sit flat on zero in common-dose mode and read as
    /// "unused", so the section drops it there instead of drawing a false floor.
    let hasCommonDoses: Bool

    var id: Int {
        substanceIndex
    }
}

/// One time bucket's §4 dose-level histogram.
nonisolated struct UsageDoseLevelBucket: Sendable, Hashable, Identifiable {
    let date: Date
    /// `DoseLevel.allCases` index → count.
    let counts: [Int: Int]

    var id: Date {
        date
    }

    var total: Int {
        counts.values.reduce(0, +)
    }
}

/// §4 — dose-level distribution over time, plus the coverage the section is
/// gated on.
nonisolated struct UsageDoseLevelBreakdown: Sendable {
    /// Buckets across every entry that resolved to a level.
    let overall: [UsageDoseLevelBucket]
    /// Substance index → that substance's buckets, for the substance selector.
    /// Only substances with at least one resolved dose appear.
    let bySubstance: [Int: [UsageDoseLevelBucket]]
    /// Substances offered in the selector, most-logged first.
    let selectableSubstances: [Int]
    /// Entries whose dose resolved to a level.
    let resolvedEntries: Int
    /// Entries considered (the whole selected range).
    let totalEntries: Int

    /// `0…1` share of entries with usable dose data.
    var coverage: Double {
        totalEntries > 0 ? Double(resolvedEntries) / Double(totalEntries) : 0
    }

    /// §4's own rule: below 30% coverage the section demotes itself to a
    /// collapsed disclosure rather than presenting a chart built from a
    /// minority of the data.
    var isLowCoverage: Bool {
        coverage < 0.3
    }
}

/// One substance's ranked row: its entry total, its common-dose total, and the
/// route split of each.
nonisolated struct UsageRouteRow: Sendable, Identifiable {
    let substanceIndex: Int
    let total: Int
    /// Σ of this substance's ``UsageEntrySnapshot/commonDoses``; `nil` when none
    /// of its entries had a common-dose value (no common band, or a
    /// non-convertible unit). Distinct from `0`: the substance was logged, it
    /// just can't be placed in common-dose currency.
    let commonTotal: Double?
    /// `RouteOfAdministration.allCases` index → (count, common-dose sum),
    /// most-used first.
    let byRoute: [(routeIndex: Int, count: Int, common: Double)]

    var id: Int {
        substanceIndex
    }
}

/// The two dimensions the ranking can be measured in.
nonisolated enum UsageRankMetric: String, CaseIterable, Sendable, Identifiable {
    /// How *often* a substance was logged.
    case entries
    /// How much was taken, each dose counted as a multiple of its common dose —
    /// comparable across substances a raw count can't compare.
    case commonDoses

    var id: String {
        rawValue
    }
}

/// The substance ranking, colored by route, ranked by either metric.
nonisolated struct UsageRouteBreakdown: Sendable {
    /// Every substance in the range, most-logged first — the view re-sorts and
    /// truncates per the selected metric.
    let rows: [UsageRouteRow]
    /// Route indices present anywhere in the range, most-used first.
    let distinctRoutes: [Int]

    /// Whether route color adds anything: a one-route history draws every bar the
    /// same color, so the ranking falls back to a single substance-colored bar.
    var routesAreMeaningful: Bool {
        distinctRoutes.count >= 2
    }

    /// How many substances carry a common-dose total — the denominator for the
    /// "N of M" footnote when the ranking is shown in common-dose units.
    var commonDoseSubstances: Int {
        rows.count { $0.commonTotal != nil }
    }
}

/// One §6 co-use pair.
nonisolated struct UsageCoUsePair: Sendable, Hashable, Identifiable {
    let firstIndex: Int
    let secondIndex: Int
    /// Days on which both appear.
    let days: Int
    /// Days on which *either* appears — the denominator for ``overlap``.
    let unionDays: Int

    var id: Int {
        firstIndex &* 1_000_003 &+ secondIndex
    }

    /// Jaccard overlap, `0…1`: of the days either substance was logged, the
    /// share on which both were.
    var overlap: Double {
        unionDays > 0 ? Double(days) / Double(unionDays) : 0
    }
}

/// One substance's §7 regularity readout.
nonisolated struct UsageRegularity: Sendable, Identifiable {
    let substanceIndex: Int
    let entryCount: Int
    /// Mean gap, in days, between consecutive *days* on which the substance was
    /// logged.
    let meanIntervalDays: Double
    /// Coefficient of variation of those gaps — lower is more regular.
    let coefficientOfVariation: Double

    var id: Int {
        substanceIndex
    }

    /// Bar fill, `0…1`: `1 - min(CV, 1.5) / 1.5` per §7.
    var fill: Double {
        1 - min(coefficientOfVariation, 1.5) / 1.5
    }

    var tier: UsageRegularityTier {
        UsageRegularityTier(coefficientOfVariation: coefficientOfVariation)
    }
}

/// §7's four regularity bands.
nonisolated enum UsageRegularityTier: Sendable, CaseIterable {
    case veryRegular
    case somewhatRegular
    case irregular
    case sporadic

    init(coefficientOfVariation cv: Double) {
        switch cv {
        case ..<0.3: self = .veryRegular
        case ..<0.6: self = .somewhatRegular
        case ..<1.0: self = .irregular
        default: self = .sporadic
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .veryRegular: "Very regular"
        case .somewhatRegular: "Somewhat regular"
        case .irregular: "Irregular"
        case .sporadic: "Sporadic"
        }
    }
}

/// One weekday column in §8.
nonisolated struct UsageWeekdayBucket: Sendable, Identifiable {
    /// Weekday component, 1 = Sunday.
    let weekday: Int
    let total: Int
    /// Σ of this weekday's ``UsageEntrySnapshot/commonDoses``; `nil` when none of
    /// its entries had a common-dose value.
    let commonTotal: Double?
    /// How many times this weekday actually occurred inside the range — the
    /// denominator for ``average``, so a partial range doesn't make Monday look
    /// quiet just because it came around once fewer.
    let occurrences: Int

    var id: Int {
        weekday
    }

    var average: Double {
        occurrences > 0 ? Double(total) / Double(occurrences) : 0
    }

    /// Common-dose units per occurrence of this weekday; `nil` when the weekday
    /// carries no common-dose data.
    var commonAverage: Double? {
        guard let commonTotal, occurrences > 0 else { return nil }
        return commonTotal / Double(occurrences)
    }
}

/// Everything the Usage screen renders, computed in one detached pass.
nonisolated struct UsageAnalyticsResult: Sendable {
    let range: UsageTimeRange
    /// Start of the selected window (earliest entry for "All").
    let rangeStart: Date
    let rangeEnd: Date
    let substances: [UsageSubstanceRef]
    let entryCount: Int
    let overview: UsageOverview
    let heatmap: UsageHeatmap
    let hours: UsageHourProfile
    let trends: [UsageTrendSeries]
    let doseLevels: UsageDoseLevelBreakdown
    let routes: UsageRouteBreakdown
    let coUse: [UsageCoUsePair]
    let regularity: [UsageRegularity]
    let weekdays: [UsageWeekdayBucket]
    /// Category indices present in the range, most-logged first — the filter
    /// pills above the heatmap.
    let categories: [(categoryIndex: Int, count: Int)]

    var isEmpty: Bool {
        entryCount == 0
    }
}

// MARK: - The aggregation

/// Every derived value on the Usage screen, computed from `Sendable` snapshots
/// so the whole pass can run off the main actor.
///
/// Each step is a `static` function over explicit inputs, which is what makes
/// bucketing, rolling windows, period-over-period deltas, dose-level resolution,
/// and co-occurrence pairing unit-testable without a `ModelContainer` or a view.
nonisolated enum UsageAnalytics {
    /// The index of `DoseLevel.common` in `DoseLevel.allCases`
    /// (sub · threshold · light · **common** · strong · heavy).
    /// Hard-coded rather than looked up because
    /// `DoseLevel` is main-actor-isolated and this runs off-main; a test pins
    /// the two together.
    static let commonLevelIndex = 3
    static let heavyLevelIndex = 5
    /// §6 — a pair must co-occur on at least this many days to be shown.
    static let minimumCoUseDays = 2
    /// §6 — how many pairs to keep, even on "All".
    static let maximumCoUsePairs = 15
    /// §7 — a substance needs this many entries before a regularity stat is
    /// anything but noise.
    static let minimumRegularityEntries = 5
    /// §3 — lines drawn by default before "Show all".
    static let defaultTrendSubstances = 5
    /// §3 — hard cap on lines even with "Show all" on; more than this is an
    /// unreadable tangle, not an insight.
    static let maximumTrendSubstances = 10
    /// §5 — substances listed in the route breakdown.
    static let maximumRouteRows = 10

    // MARK: Entry point

    /// Aggregate everything. `entries` is the **complete** history (so the
    /// previous-period comparison and the "new this period" count have
    /// something to look back at); `range` selects the window.
    static func compute(
        entries: [UsageEntrySnapshot],
        substances: [UsageSubstanceRef],
        range: UsageTimeRange,
        calendar: Calendar,
        now: Date,
    ) -> UsageAnalyticsResult {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let bounds = self.bounds(for: range, entries: sorted, now: now)
        let inRange = sorted.filter { $0.timestamp >= bounds.start && $0.timestamp <= bounds.end }

        let dayIndex = groupByDay(inRange, calendar: calendar)
        let overview = self.overview(
            all: sorted, inRange: inRange, bounds: bounds, calendar: calendar,
        )
        // The activity heatmap is a full-history contribution graph: it colors
        // every day the user ever logged, not just the selected range, so a 30-day
        // range still reveals a year of rhythm. The range drives the hour
        // histogram and every other section — but graying out real earlier data
        // here just to match the picker hid history the user actually has.
        let historyBounds = Bounds(
            start: sorted.first?.timestamp ?? bounds.start,
            end: bounds.end,
            lengthDays: bounds.lengthDays,
            hasPreviousPeriod: false,
        )
        let heatmap = self.heatmap(
            dayIndex: groupByDay(sorted, calendar: calendar),
            bounds: historyBounds, calendar: calendar,
        )
        let hours = hourProfile(inRange, calendar: calendar)
        let bucketStarts = self.bucketStarts(bounds: bounds, weekly: range.usesWeeklyBuckets, calendar: calendar)
        let ranking = substanceRanking(inRange)
        let trends = self.trends(
            inRange, ranking: ranking, bucketStarts: bucketStarts,
            bucketDays: range.usesWeeklyBuckets ? 7 : 1,
            windowDays: range.rollingWindowDays,
            rangeEnd: bounds.end,
            ratePerWeek: range.trendPerWeek,
        )
        let doseLevels = self.doseLevels(inRange, ranking: ranking, bucketStarts: bucketStarts, calendar: calendar)
        let routes = routeBreakdown(inRange, ranking: ranking)
        let coUse = coUsePairs(dayIndex: dayIndex)
        let regularity = self.regularity(dayIndex: dayIndex, counts: ranking)
        let weekdays = weekdayBreakdown(inRange, bounds: bounds, calendar: calendar)
        let categories = categoryRanking(inRange)

        return UsageAnalyticsResult(
            range: range,
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            substances: substances,
            entryCount: inRange.count,
            overview: overview,
            heatmap: heatmap,
            hours: hours,
            trends: trends,
            doseLevels: doseLevels,
            routes: routes,
            coUse: coUse,
            regularity: regularity,
            weekdays: weekdays,
            categories: categories,
        )
    }

    // MARK: Windowing

    nonisolated struct Bounds: Sendable {
        let start: Date
        let end: Date
        /// Length of the window in days — the denominator for "per day" and the
        /// offset back to the previous period.
        let lengthDays: Double
        /// `false` for "All", where there is no earlier window to compare to.
        let hasPreviousPeriod: Bool
    }

    /// The selected window. "All" spans the first entry to now; every other
    /// range is a fixed-length window ending now.
    static func bounds(
        for range: UsageTimeRange,
        entries: [UsageEntrySnapshot],
        now: Date,
    ) -> Bounds {
        guard let days = range.days else {
            let start = entries.first?.timestamp ?? now
            let length = max(1, now.timeIntervalSince(start) / 86_400)
            return Bounds(start: start, end: now, lengthDays: length, hasPreviousPeriod: false)
        }
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return Bounds(start: start, end: now, lengthDays: Double(days), hasPreviousPeriod: true)
    }

    /// Session-day start → the entries logged that day. Session days (not
    /// calendar days) so a 02:00 dose counts toward the night it belongs to —
    /// the same boundary the journal and every other screen uses.
    static func groupByDay(_ entries: [UsageEntrySnapshot], calendar: Calendar) -> [Date: [UsageEntrySnapshot]] {
        var index: [Date: [UsageEntrySnapshot]] = [:]
        for entry in entries {
            index[calendar.sessionDayStart(for: entry.timestamp), default: []].append(entry)
        }
        return index
    }

    // MARK: §1 Overview

    static func overview(
        all: [UsageEntrySnapshot],
        inRange: [UsageEntrySnapshot],
        bounds: Bounds,
        calendar: Calendar,
    ) -> UsageOverview {
        let previousCount: Int?
        if bounds.hasPreviousPeriod {
            let previousStart = bounds.start.addingTimeInterval(-bounds.lengthDays * 86_400)
            previousCount = all.count { $0.timestamp >= previousStart && $0.timestamp < bounds.start }
        } else {
            previousCount = nil
        }

        let change: Double? = if let previousCount, previousCount > 0 {
            (Double(inRange.count) - Double(previousCount)) / Double(previousCount)
        } else {
            nil
        }

        var seen = Set<Int>()
        for entry in inRange {
            seen.insert(entry.substanceIndex)
        }
        // "New" = first-ever dose falls inside the window. `all` is sorted, so
        // the first sighting of a substance is its debut.
        var debuts: [Int: Date] = [:]
        for entry in all where debuts[entry.substanceIndex] == nil {
            debuts[entry.substanceIndex] = entry.timestamp
        }
        let newCount = seen.count { index in
            guard let debut = debuts[index] else { return false }
            return debut >= bounds.start
        }

        var weekdayCounts: [Int: Int] = [:]
        var resolved = 0
        var commonOrAbove = 0
        var heavy = 0
        for entry in inRange {
            weekdayCounts[calendar.component(.weekday, from: entry.timestamp), default: 0] += 1
            guard let level = entry.doseLevelIndex else { continue }
            resolved += 1
            if level >= commonLevelIndex { commonOrAbove += 1 }
            if level >= heavyLevelIndex { heavy += 1 }
        }
        // Ties break toward the earlier weekday so the readout is stable across
        // recomputes rather than flipping with dictionary order.
        let busiest = weekdayCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .first?.key

        return UsageOverview(
            entryCount: inRange.count,
            previousEntryCount: previousCount,
            percentChange: change,
            sparkline: sparkline(inRange, bounds: bounds),
            uniqueSubstances: seen.count,
            newSubstances: newCount,
            averagePerDay: Double(inRange.count) / max(1, bounds.lengthDays),
            busiestWeekday: busiest,
            doseResolvedCount: resolved,
            commonOrAboveCount: commonOrAbove,
            heavyCount: heavy,
        )
    }

    /// Seven equal-width buckets across the window, oldest first (§1).
    static func sparkline(_ entries: [UsageEntrySnapshot], bounds: Bounds, buckets: Int = 7) -> [Int] {
        var counts = Array(repeating: 0, count: buckets)
        let span = bounds.end.timeIntervalSince(bounds.start)
        guard span > 0 else {
            counts[buckets - 1] = entries.count
            return counts
        }
        for entry in entries {
            let offset = entry.timestamp.timeIntervalSince(bounds.start) / span
            let index = min(buckets - 1, max(0, Int(offset * Double(buckets))))
            counts[index] += 1
        }
        return counts
    }

    // MARK: §2 Heatmap + hours

    static func heatmap(
        dayIndex: [Date: [UsageEntrySnapshot]],
        bounds: Bounds,
        calendar: Calendar,
    ) -> UsageHeatmap {
        let rowWeekdays = (0 ..< 7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: bounds.start)?.start,
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: bounds.end)?.start else {
            return UsageHeatmap(weekStarts: [], rowWeekdays: rowWeekdays, cells: [], maxCount: 0, maxCommon: 0)
        }

        var weekStarts: [Date] = []
        var cursor = firstWeek
        // Guard against a pathological range producing an unbounded column list.
        while cursor <= lastWeek, weekStarts.count < 600 {
            weekStarts.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        let startDay = calendar.sessionDayStart(for: bounds.start)
        let endDay = calendar.sessionDayStart(for: bounds.end)

        var cells: [UsageHeatmapCell] = []
        cells.reserveCapacity(weekStarts.count * 7)
        var maxCount = 0
        var maxCommon = 0.0
        for weekStart in weekStarts {
            for row in 0 ..< 7 {
                // Noon, so adding days never lands on a DST-skipped hour.
                let noon = calendar.date(byAdding: .day, value: row, to: weekStart)?
                    .addingTimeInterval(12 * 3_600) ?? weekStart
                let day = calendar.sessionDayStart(for: noon)
                let entries = dayIndex[day] ?? []
                var byCategory: [Int: Int] = [:]
                var byCategoryCommon: [Int: Double] = [:]
                var commonTotal = 0.0
                for entry in entries {
                    byCategory[entry.categoryIndex, default: 0] += 1
                    if let common = entry.commonDoses {
                        byCategoryCommon[entry.categoryIndex, default: 0] += common
                        commonTotal += common
                    }
                }
                maxCount = max(maxCount, entries.count)
                maxCommon = max(maxCommon, commonTotal)
                cells.append(UsageHeatmapCell(
                    date: day,
                    total: entries.count,
                    commonTotal: commonTotal,
                    byCategory: byCategory,
                    byCategoryCommon: byCategoryCommon,
                    inRange: day >= startDay && day <= endDay,
                ))
            }
        }

        return UsageHeatmap(weekStarts: weekStarts, rowWeekdays: rowWeekdays, cells: cells, maxCount: maxCount, maxCommon: maxCommon)
    }

    /// 24-bin hour-of-day histograms — overall, per category, and per day.
    static func hourProfile(_ entries: [UsageEntrySnapshot], calendar: Calendar) -> UsageHourProfile {
        var total = Array(repeating: 0, count: 24)
        var byCategory: [Int: [Int]] = [:]
        var perDayTotal: [Date: [Int]] = [:]
        var perDayCategory: [Date: [Int: [Int]]] = [:]
        var totalCommon = Array(repeating: 0.0, count: 24)
        var byCategoryCommon: [Int: [Double]] = [:]
        var perDayCommon: [Date: [Double]] = [:]
        var perDayCategoryCommon: [Date: [Int: [Double]]] = [:]

        for entry in entries {
            let hour = calendar.component(.hour, from: entry.timestamp)
            let day = calendar.sessionDayStart(for: entry.timestamp)
            total[hour] += 1
            byCategory[entry.categoryIndex, default: Array(repeating: 0, count: 24)][hour] += 1
            perDayTotal[day, default: Array(repeating: 0, count: 24)][hour] += 1
            perDayCategory[day, default: [:]][entry.categoryIndex, default: Array(repeating: 0, count: 24)][hour] += 1
            guard let common = entry.commonDoses else { continue }
            totalCommon[hour] += common
            byCategoryCommon[entry.categoryIndex, default: Array(repeating: 0.0, count: 24)][hour] += common
            perDayCommon[day, default: Array(repeating: 0.0, count: 24)][hour] += common
            perDayCategoryCommon[day, default: [:]][entry.categoryIndex, default: Array(repeating: 0.0, count: 24)][hour] += common
        }

        var byDay: [Date: UsageHourBins] = [:]
        for (day, bins) in perDayTotal {
            byDay[day] = UsageHourBins(
                total: bins, byCategory: perDayCategory[day] ?? [:],
                totalCommon: perDayCommon[day] ?? Array(repeating: 0.0, count: 24),
                byCategoryCommon: perDayCategoryCommon[day] ?? [:],
            )
        }
        return UsageHourProfile(
            all: UsageHourBins(
                total: total, byCategory: byCategory,
                totalCommon: totalCommon, byCategoryCommon: byCategoryCommon,
            ),
            byDay: byDay,
        )
    }

    // MARK: Bucketing

    /// The bucket start dates spanning the window — one per day, or one per
    /// week when `weekly`. Always includes the final partial bucket.
    static func bucketStarts(bounds: Bounds, weekly: Bool, calendar: Calendar) -> [Date] {
        let component: Calendar.Component = weekly ? .weekOfYear : .day
        let first: Date = if weekly {
            calendar.dateInterval(of: .weekOfYear, for: bounds.start)?.start
                ?? calendar.sessionDayStart(for: bounds.start)
        } else {
            calendar.sessionDayStart(for: bounds.start)
        }
        let last: Date = if weekly {
            calendar.dateInterval(of: .weekOfYear, for: bounds.end)?.start ?? first
        } else {
            calendar.sessionDayStart(for: bounds.end)
        }

        var result: [Date] = []
        var cursor = first
        while cursor <= last, result.count < 800 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// The bucket a timestamp falls into, given ascending `bucketStarts`.
    /// Returns the last bucket whose start is `<=` the timestamp.
    static func bucket(for date: Date, in bucketStarts: [Date]) -> Date? {
        guard let firstStart = bucketStarts.first, date >= firstStart else {
            return bucketStarts.first
        }
        var low = 0
        var high = bucketStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if bucketStarts[mid] <= date {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return bucketStarts[low]
    }

    /// Substance indices ranked by entry count, descending; ties by index so the
    /// order is stable.
    static func substanceRanking(_ entries: [UsageEntrySnapshot]) -> [(substanceIndex: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for entry in entries {
            counts[entry.substanceIndex, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (substanceIndex: $0.key, count: $0.value) }
    }

    static func categoryRanking(_ entries: [UsageEntrySnapshot]) -> [(categoryIndex: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for entry in entries {
            counts[entry.categoryIndex, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (categoryIndex: $0.key, count: $0.value) }
    }

    // MARK: §3 Trends

    /// Rolling frequency (entries per week) per substance, sampled once per
    /// bucket.
    ///
    /// Each point is plotted at its bucket's start but its window **closes at
    /// the bucket's end** (clamped to `rangeEnd`), so the newest point reflects
    /// everything logged up to now instead of dipping toward zero just because
    /// the current week is young. The window is half-open on the left:
    /// `(close - window, close]`.
    ///
    /// The value is always normalized to entries **per week**, whatever the
    /// window is, so the y-axis means the same thing on 7D and on All.
    static func trends(
        _ entries: [UsageEntrySnapshot],
        ranking: [(substanceIndex: Int, count: Int)],
        bucketStarts: [Date],
        bucketDays: Int,
        windowDays: Int,
        rangeEnd: Date,
        ratePerWeek: Bool = true,
    ) -> [UsageTrendSeries] {
        guard !bucketStarts.isEmpty, windowDays > 0 else { return [] }
        let top = ranking.prefix(maximumTrendSubstances)
        let window = Double(windowDays) * 86_400
        let bucketSpan = Double(bucketDays) * 86_400
        // Per-week rate normalizes the window to a week; raw (7D) leaves each
        // bucket as its own count, which with a one-day window is a per-day bucket.
        let perWeek = ratePerWeek ? 7.0 / Double(windowDays) : 1.0

        // Each entry carried as (timestamp, common-dose value) so a bucket's
        // window can sum both the count and the common-dose total in one pass.
        var eventsBySubstance: [Int: [(date: Date, common: Double?)]] = [:]
        for entry in entries {
            eventsBySubstance[entry.substanceIndex, default: []]
                .append((entry.timestamp, entry.commonDoses))
        }

        return top.map { item in
            let events = (eventsBySubstance[item.substanceIndex] ?? []).sorted { $0.date < $1.date }
            let hasCommon = events.contains { $0.common != nil }
            let points = bucketStarts.map { start in
                let close = min(start.addingTimeInterval(bucketSpan), rangeEnd)
                let lower = close.addingTimeInterval(-window)
                var count = 0
                var common = 0.0
                for event in events where event.date > lower && event.date <= close {
                    count += 1
                    common += event.common ?? 0
                }
                return UsageTrendPoint(
                    date: start,
                    value: Double(count) * perWeek,
                    commonValue: common * perWeek,
                )
            }
            return UsageTrendSeries(
                substanceIndex: item.substanceIndex,
                entryCount: item.count,
                points: points,
                hasCommonDoses: hasCommon,
            )
        }
    }

    // MARK: §4 Dose levels

    static func doseLevels(
        _ entries: [UsageEntrySnapshot],
        ranking: [(substanceIndex: Int, count: Int)],
        bucketStarts: [Date],
        calendar _: Calendar,
    ) -> UsageDoseLevelBreakdown {
        var overall: [Date: [Int: Int]] = [:]
        var perSubstance: [Int: [Date: [Int: Int]]] = [:]
        var resolved = 0

        for entry in entries {
            guard let level = entry.doseLevelIndex,
                  let bucketDate = bucket(for: entry.timestamp, in: bucketStarts) else { continue }
            resolved += 1
            overall[bucketDate, default: [:]][level, default: 0] += 1
            perSubstance[entry.substanceIndex, default: [:]][bucketDate, default: [:]][level, default: 0] += 1
        }

        func buckets(from map: [Date: [Int: Int]]) -> [UsageDoseLevelBucket] {
            map.sorted { $0.key < $1.key }
                .map { UsageDoseLevelBucket(date: $0.key, counts: $0.value) }
        }

        let selectable = ranking
            .map(\.substanceIndex)
            .filter { perSubstance[$0] != nil }

        return UsageDoseLevelBreakdown(
            overall: buckets(from: overall),
            bySubstance: perSubstance.mapValues(buckets(from:)),
            selectableSubstances: selectable,
            resolvedEntries: resolved,
            totalEntries: entries.count,
        )
    }

    // MARK: §5 Routes

    /// Every substance's row: entry total, common-dose total, and the per-route
    /// split of each. Emits **all** substances (not a top-N slice) so the view
    /// can rank by entries *or* common-dose units — the two orderings differ, and
    /// truncating to the count leaders here would hide the substances that only
    /// lead once each dose is weighed by its common dose.
    static func routeBreakdown(
        _ entries: [UsageEntrySnapshot],
        ranking: [(substanceIndex: Int, count: Int)],
    ) -> UsageRouteBreakdown {
        var routeTotals: [Int: Int] = [:]
        var perSubstanceCount: [Int: [Int: Int]] = [:]
        var perSubstanceCommon: [Int: [Int: Double]] = [:]
        // Tracked separately from the summed common total so a substance with a
        // real 0-sum (every dose rounds to nothing) stays distinct from one with
        // no common-dose data at all.
        var hasCommon: Set<Int> = []
        for entry in entries {
            routeTotals[entry.routeIndex, default: 0] += 1
            perSubstanceCount[entry.substanceIndex, default: [:]][entry.routeIndex, default: 0] += 1
            if let common = entry.commonDoses {
                perSubstanceCommon[entry.substanceIndex, default: [:]][entry.routeIndex, default: 0] += common
                hasCommon.insert(entry.substanceIndex)
            }
        }

        let rows = ranking.compactMap { item -> UsageRouteRow? in
            guard let split = perSubstanceCount[item.substanceIndex] else { return nil }
            let commonByRoute = perSubstanceCommon[item.substanceIndex] ?? [:]
            let sorted = split
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { (routeIndex: $0.key, count: $0.value, common: commonByRoute[$0.key] ?? 0) }
            let commonTotal = hasCommon.contains(item.substanceIndex)
                ? commonByRoute.values.reduce(0, +)
                : nil
            return UsageRouteRow(
                substanceIndex: item.substanceIndex,
                total: item.count,
                commonTotal: commonTotal,
                byRoute: sorted,
            )
        }

        let distinct = routeTotals
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)

        return UsageRouteBreakdown(rows: rows, distinctRoutes: distinct)
    }

    // MARK: §6 Co-use

    /// Substance pairs logged on the same session day, ranked by how many days
    /// they co-occur. Below ``minimumCoUseDays`` a pair is a coincidence, not a
    /// habit, so it never surfaces.
    static func coUsePairs(dayIndex: [Date: [UsageEntrySnapshot]]) -> [UsageCoUsePair] {
        var pairDays: [PairKey: Int] = [:]
        var soloDays: [Int: Int] = [:]

        for (_, dayEntries) in dayIndex {
            var present = Set<Int>()
            for entry in dayEntries {
                present.insert(entry.substanceIndex)
            }
            for index in present {
                soloDays[index, default: 0] += 1
            }
            let ordered = present.sorted()
            guard ordered.count >= 2 else { continue }
            for i in 0 ..< (ordered.count - 1) {
                for j in (i + 1) ..< ordered.count {
                    pairDays[PairKey(first: ordered[i], second: ordered[j]), default: 0] += 1
                }
            }
        }

        let ranked = pairDays
            .filter { $0.value >= minimumCoUseDays }
            .map { key, days in
                let union = (soloDays[key.first] ?? 0) + (soloDays[key.second] ?? 0) - days
                return UsageCoUsePair(
                    firstIndex: key.first, secondIndex: key.second,
                    days: days, unionDays: max(union, days),
                )
            }
            .sorted {
                if $0.days != $1.days { return $0.days > $1.days }
                if $0.firstIndex != $1.firstIndex { return $0.firstIndex < $1.firstIndex }
                return $0.secondIndex < $1.secondIndex
            }
        return Array(ranked.prefix(maximumCoUsePairs))
    }

    nonisolated struct PairKey: Hashable, Sendable {
        let first: Int
        let second: Int
    }

    // MARK: §7 Regularity

    /// Mean gap and coefficient of variation between the *days* a substance was
    /// logged.
    ///
    /// Deliberately day-level, not dose-level: a supplement taken three times
    /// daily has ~8 h and ~16 h gaps, whose CV would label a rock-steady routine
    /// "Sporadic". The question §7 asks — "do I use on a schedule?" — is about
    /// days, and the spec's own example output ("Magnesium · every 1.0 days")
    /// only comes out of a day-level pass.
    static func regularity(
        dayIndex: [Date: [UsageEntrySnapshot]],
        counts ranking: [(substanceIndex: Int, count: Int)],
    ) -> [UsageRegularity] {
        var daysBySubstance: [Int: Set<Date>] = [:]
        for (day, entries) in dayIndex {
            for entry in entries {
                daysBySubstance[entry.substanceIndex, default: []].insert(day)
            }
        }

        let countLookup = Dictionary(ranking.map { ($0.substanceIndex, $0.count) }, uniquingKeysWith: { first, _ in first })

        return daysBySubstance.compactMap { index, days -> UsageRegularity? in
            let entryCount = countLookup[index] ?? 0
            guard entryCount >= minimumRegularityEntries, days.count >= 3 else { return nil }
            let sorted = days.sorted()
            let intervals = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
            guard let stats = intervalStatistics(intervals) else { return nil }
            return UsageRegularity(
                substanceIndex: index,
                entryCount: entryCount,
                meanIntervalDays: stats.mean,
                coefficientOfVariation: stats.coefficientOfVariation,
            )
        }
        .sorted {
            if $0.coefficientOfVariation != $1.coefficientOfVariation {
                return $0.coefficientOfVariation < $1.coefficientOfVariation
            }
            return $0.substanceIndex < $1.substanceIndex
        }
    }

    /// Mean, population standard deviation, and CV of a set of gaps. `nil` when
    /// there is nothing to describe (no gaps, or a mean of zero).
    static func intervalStatistics(_ intervals: [Double]) -> (mean: Double, standardDeviation: Double, coefficientOfVariation: Double)? {
        guard !intervals.isEmpty else { return nil }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return nil }
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
        let deviation = variance.squareRoot()
        return (mean, deviation, deviation / mean)
    }

    // MARK: §8 Day of week

    static func weekdayBreakdown(
        _ entries: [UsageEntrySnapshot],
        bounds: Bounds,
        calendar: Calendar,
    ) -> [UsageWeekdayBucket] {
        var totals: [Int: Int] = [:]
        var commonTotals: [Int: Double] = [:]
        var hasCommon: Set<Int> = []
        for entry in entries {
            let weekday = calendar.component(.weekday, from: entry.timestamp)
            totals[weekday, default: 0] += 1
            if let common = entry.commonDoses {
                commonTotals[weekday, default: 0] += common
                hasCommon.insert(weekday)
            }
        }

        let occurrences = weekdayOccurrences(bounds: bounds, calendar: calendar)
        let rowWeekdays = (0 ..< 7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return rowWeekdays.map { weekday in
            UsageWeekdayBucket(
                weekday: weekday,
                total: totals[weekday] ?? 0,
                commonTotal: hasCommon.contains(weekday) ? commonTotals[weekday] : nil,
                occurrences: occurrences[weekday] ?? 0,
            )
        }
    }

    /// How many times each weekday falls inside the window — so §8's "average
    /// per weekday" divides by the right denominator on a partial range.
    static func weekdayOccurrences(bounds: Bounds, calendar: Calendar) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        var cursor = calendar.startOfDay(for: bounds.start)
        let end = bounds.end
        var guardRail = 0
        while cursor <= end, guardRail < 4_000 {
            counts[calendar.component(.weekday, from: cursor), default: 0] += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardRail += 1
        }
        return counts
    }
}
