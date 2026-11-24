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

    /// The range the Usage screen opens on, and the window the Insights Usage
    /// card counts over, so the card and the screen show the same numbers.
    static let opening: UsageTimeRange = .thirtyDays

    /// The window's name as a heading: "Last 30 Days", or "All Time".
    var windowName: LocalizedStringResource {
        if let days {
            "Last \(days) Days"
        } else {
            "All Time"
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
    /// The molecule behind the row: equal for every row of one substance
    /// ("Concerta", "Ritalin" and "Methylphenidate"), so co-use and the
    /// distinct-substance counts see one drug where the rows show its products.
    let moleculeIndex: Int
    /// Index into `SubstanceCategory.allCases`.
    let categoryIndex: Int
    /// Index into `RouteOfAdministration.allCases`.
    let routeIndex: Int
    /// Index into `DoseLevel.allCases`, or `nil` when the dose could not be
    /// placed on a ladder (substance unknown, no ladder for that route, or the
    /// logged unit is not convertible to the ladder's unit).
    let doseLevelIndex: Int?
    /// This dose expressed as a multiple of the substance's *common* dose —
    /// `amount ÷ midpoint(common)`, so `1.0` is one textbook common dose and
    /// `2.5` is two-and-a-half of them. `nil` on the same footing as
    /// ``doseLevelIndex``: no common tier for this ladder, or a logged unit that
    /// doesn't convert to the ladder's. It is what lets a milligram stimulant and
    /// a gram-dosed botanical be counted in the same currency, instead of ranking
    /// them by how *often* they were logged.
    let commonDoses: Double?
    let timestamp: Date

    /// `moleculeIndex` defaults to `substanceIndex`: a row that is its own molecule.
    init(
        substanceIndex: Int,
        moleculeIndex: Int? = nil,
        categoryIndex: Int,
        routeIndex: Int,
        doseLevelIndex: Int?,
        commonDoses: Double? = nil,
        timestamp: Date,
    ) {
        self.substanceIndex = substanceIndex
        self.moleculeIndex = moleculeIndex ?? substanceIndex
        self.categoryIndex = categoryIndex
        self.routeIndex = routeIndex
        self.doseLevelIndex = doseLevelIndex
        self.commonDoses = commonDoses
        self.timestamp = timestamp
    }
}

/// A distinct substance in the snapshot: index → names + category. A branded
/// product is a row of its own ("Concerta" apart from "Ritalin"), since
/// people on a branded med track the brand.
nonisolated struct UsageSubstanceRef: Sendable, Hashable {
    /// The row's identity and the substance filter's key.
    let name: String
    /// The name to show the user: the dose title (product name or relabel applied).
    let displayName: String
    /// Index into `SubstanceCategory.allCases`.
    let categoryIndex: Int
    /// The substance name as logged, the `colorMap` key (lowercased): a
    /// product row takes its substance's color.
    let colorKey: String
    /// The name to show for the row's molecule, where a figure counts every
    /// product of it as one ("Methylphenidate" for a "Concerta" row).
    let moleculeName: String

    init(name: String, displayName: String, categoryIndex: Int, colorKey: String? = nil, moleculeName: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.categoryIndex = categoryIndex
        self.colorKey = colorKey ?? name
        self.moleculeName = moleculeName ?? displayName
    }
}

// MARK: - Outputs

/// How many entries a window holds, per day and across buckets of it.
/// The Insights Usage card and the Usage screen both read this one count.
nonisolated struct UsageWindowCount: Sendable, Equatable {
    let entryCount: Int
    let averagePerDay: Double
    /// The window in buckets, oldest first (equal slices, or journal days on
    /// the Insights card); they sum to ``entryCount``.
    let buckets: [Int]

    var averagePerDayText: String {
        UsageAnalytics.rateText(averagePerDay)
    }
}

/// §1 — the overview figures.
nonisolated struct UsageOverview: Sendable {
    let window: UsageWindowCount
    /// Entry count in the same-length window immediately before the selected
    /// range; `nil` for "All" (there is nothing before it).
    let previousEntryCount: Int?
    /// Signed fractional change vs. the previous period (`0.12` = +12%).
    /// `nil` when there is no previous period, or it was empty.
    let percentChange: Double?
    let uniqueSubstances: Int
    /// Substances whose first-ever logged dose falls inside the selected range.
    let newSubstances: Int
    /// Weekday component (1 = Sunday) that carries the most entries; `nil` when
    /// there are none.
    let busiestWeekday: Int?
    /// Entries whose dose resolved to a ladder level.
    let doseResolvedCount: Int
    /// Of those, how many landed at Common or above.
    let commonOrAboveCount: Int
    /// Of those, how many landed at Heavy.
    let heavyCount: Int

    var entryCount: Int {
        window.entryCount
    }

    var averagePerDay: Double {
        window.averagePerDay
    }

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
    /// columns outside the journal's history — drawn blank, never colored.
    let inRange: Bool
    /// Whether the day falls inside the selected range: the grid spans the
    /// whole history and draws the range's days at full strength.
    let inWindow: Bool

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
    /// Session-day start → its cell, for an O(1) lookup from any drawn day —
    /// built once here rather than per layout pass in the grid view.
    let cellByDate: [Date: UsageHeatmapCell]
    /// The most recent day inside the selected range — days past it are the
    /// future and stay blank rather than gray.
    let lastInRange: Date

    init(weekStarts: [Date], rowWeekdays: [Int], cells: [UsageHeatmapCell], maxCount: Int, maxCommon: Double) {
        self.weekStarts = weekStarts
        self.rowWeekdays = rowWeekdays
        self.cells = cells
        self.maxCount = maxCount
        self.maxCommon = maxCommon
        cellByDate = Dictionary(cells.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        lastInRange = cells.filter(\.inRange).map(\.date).max() ?? .distantPast
    }

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
    let points: [UsageTrendPoint]
    /// Whether any of this substance's entries carried a common-dose value. A
    /// line with none would sit flat on zero in common-dose mode and read as
    /// "unused", so the section drops it there instead of drawing a false floor.
    let hasCommonDoses: Bool

    var id: Int {
        substanceIndex
    }

    /// The point nearest `date`, for the scrub readout; `nil` more than half a
    /// bucket before the first point, where the line has not begun and no
    /// average exists.
    func point(nearest date: Date) -> UsageTrendPoint? {
        guard let first = points.first else { return nil }
        if points.count > 1 {
            let halfBucket = points[1].date.timeIntervalSince(first.date) / 2
            if date < first.date.addingTimeInterval(-halfBucket) { return nil }
        }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
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
    /// The first molecule's row: its most-logged one over the counted days.
    let firstIndex: Int
    /// The second molecule's row, picked the same way.
    let secondIndex: Int
    /// Days on which both appear.
    let days: Int
    /// Days on which *either* appears — the denominator for ``overlap``.
    let unionDays: Int
    /// The first molecule was logged under several rows (Concerta and
    /// Ritalin), so the pair names it by its molecule rather than one row.
    var firstSpansRows = false
    /// The same for the second molecule.
    var secondSpansRows = false

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
    /// The typical gap, in days, between consecutive *days* on which the
    /// substance was logged: the median, so one long pause in a daily routine
    /// leaves it at a day.
    let typicalIntervalDays: Double
    /// How far the gaps stray from the typical one, as a share of it (see
    /// ``UsageAnalytics/intervalStatistics(_:)``) — lower is more regular.
    let gapVariation: Double

    var id: Int {
        substanceIndex
    }

    /// Bar fill, `0…1`: `1 - min(variation, 1.5) / 1.5` per §7.
    var fill: Double {
        1 - min(gapVariation, 1.5) / 1.5
    }

    var tier: UsageRegularityTier {
        UsageRegularityTier(gapVariation: gapVariation)
    }
}

/// §7's four regularity bands.
nonisolated enum UsageRegularityTier: Sendable, CaseIterable {
    case veryRegular
    case somewhatRegular
    case irregular
    case sporadic

    init(gapVariation variation: Double) {
        switch variation {
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
    let substances: [UsageSubstanceRef]
    let entryCount: Int
    /// Entries in the range that carry a common-dose value: what the
    /// common-dose lens can weigh. Zero means that lens has nothing to draw.
    let commonDoseEntryCount: Int
    /// The span every time-axis chart draws: the range's first bucket through
    /// the end of its last, so a young journal sits at the right of the range
    /// it was asked for.
    let timeAxis: ClosedRange<Date>
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
        journalStart: Date? = nil,
    ) -> UsageAnalyticsResult {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        // The journal's first entry: `entries` may be narrowed to a substance
        // filter, and a rate over days counts the days the journal existed.
        let journalStart = journalStart ?? sorted.first?.timestamp
        let bounds = self.bounds(for: range, entries: sorted, now: now, journalStart: journalStart)
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
            bounds: historyBounds, window: bounds, calendar: calendar,
        )
        let hours = hourProfile(inRange, calendar: calendar)
        let bucketStarts = self.bucketStarts(bounds: bounds, weekly: range.usesWeeklyBuckets, calendar: calendar)
        let ranking = substanceRanking(inRange)
        let bucketDays = range.usesWeeklyBuckets ? 7 : 1
        // The whole history, so a point near the range's start averages the
        // days before it rather than an empty stretch.
        let trends = self.trends(
            sorted.filter { $0.timestamp <= bounds.end }, ranking: ranking, bucketStarts: bucketStarts,
            bucketDays: bucketDays,
            windowDays: range.rollingWindowDays,
            rangeEnd: bounds.end,
            journalStart: journalStart.map { calendar.sessionDayStart(for: $0) },
            ratePerWeek: range.trendPerWeek,
        )
        let axisStart = bucketStarts.first ?? bounds.start
        let axisEnd = max(
            bounds.end,
            (bucketStarts.last ?? bounds.end).addingTimeInterval(Double(bucketDays) * 86_400),
        )
        let doseLevels = self.doseLevels(inRange, ranking: ranking, bucketStarts: bucketStarts, calendar: calendar)
        let routes = routeBreakdown(inRange, ranking: ranking)
        let coUse = coUsePairs(dayIndex: dayIndex)
        let regularity = self.regularity(dayIndex: dayIndex, counts: ranking)
        let weekdays = weekdayBreakdown(inRange, bounds: bounds, calendar: calendar)
        let categories = categoryRanking(inRange)

        return UsageAnalyticsResult(
            range: range,
            substances: substances,
            entryCount: inRange.count,
            commonDoseEntryCount: inRange.count { $0.commonDoses != nil },
            timeAxis: axisStart ... axisEnd,
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
        /// Where the journal begins inside the window: the journal's first
        /// entry when the window opens before it, else the window's start.
        let loggedStart: Date

        init(start: Date, end: Date, lengthDays: Double, hasPreviousPeriod: Bool, loggedStart: Date? = nil) {
            self.start = start
            self.end = end
            self.lengthDays = lengthDays
            self.hasPreviousPeriod = hasPreviousPeriod
            self.loggedStart = max(start, loggedStart ?? start)
        }

        /// Days of the window the journal covers, at least one — the
        /// denominator for every per-day rate, so a week-old journal read over
        /// "Last 30 Days" is averaged over its week.
        var loggedDays: Double {
            max(1, end.timeIntervalSince(loggedStart) / 86_400)
        }
    }

    /// The selected window. "All" spans the first entry to now; every other
    /// range is a fixed-length window ending now. `journalStart` is the
    /// journal's first entry when `entries` is a narrowed subset of it.
    static func bounds(
        for range: UsageTimeRange,
        entries: [UsageEntrySnapshot],
        now: Date,
        journalStart: Date? = nil,
    ) -> Bounds {
        bounds(for: range, firstTimestamp: entries.first?.timestamp, now: now, journalStart: journalStart)
    }

    /// The selected window, given the earliest entry ("All" starts there) and
    /// the journal's first entry (`firstTimestamp` when not given).
    static func bounds(for range: UsageTimeRange, firstTimestamp: Date?, now: Date, journalStart: Date? = nil) -> Bounds {
        let loggedStart = journalStart ?? firstTimestamp
        guard let days = range.days else {
            let start = firstTimestamp ?? now
            let length = max(1, now.timeIntervalSince(start) / 86_400)
            return Bounds(start: start, end: now, lengthDays: length, hasPreviousPeriod: false, loggedStart: loggedStart)
        }
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return Bounds(start: start, end: now, lengthDays: Double(days), hasPreviousPeriod: true, loggedStart: loggedStart)
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

        // Counted by molecule: a branded product and its substance are one.
        var seen = Set<Int>()
        for entry in inRange {
            seen.insert(entry.moleculeIndex)
        }
        // "New" = first-ever dose falls inside the window. `all` is sorted, so
        // the first sighting of a substance, under any of its products, is its debut.
        var debuts: [Int: Date] = [:]
        for entry in all where debuts[entry.moleculeIndex] == nil {
            debuts[entry.moleculeIndex] = entry.timestamp
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
            window: windowCount(inRange.map(\.timestamp), bounds: bounds),
            previousEntryCount: previousCount,
            percentChange: change,
            uniqueSubstances: seen.count,
            newSubstances: newCount,
            busiestWeekday: busiest,
            doseResolvedCount: resolved,
            commonOrAboveCount: commonOrAbove,
            heavyCount: heavy,
        )
    }

    /// The count every Usage surface shows: entries inside `bounds` (both ends
    /// included), their average per day the journal covers of the window, and
    /// `buckets` equal-width slices of the whole window, oldest first.
    static func windowCount(_ timestamps: [Date], bounds: Bounds, buckets: Int = 7) -> UsageWindowCount {
        var counts = Array(repeating: 0, count: max(1, buckets))
        let span = bounds.end.timeIntervalSince(bounds.start)
        var total = 0
        for timestamp in timestamps where timestamp >= bounds.start && timestamp <= bounds.end {
            total += 1
            guard span > 0 else {
                counts[counts.count - 1] += 1
                continue
            }
            let offset = timestamp.timeIntervalSince(bounds.start) / span
            counts[min(counts.count - 1, max(0, Int(offset * Double(counts.count))))] += 1
        }
        return UsageWindowCount(
            entryCount: total,
            averagePerDay: Double(total) / bounds.loggedDays,
            buckets: counts,
        )
    }

    /// The count and rate of ``windowCount(_:bounds:buckets:)`` over `range`
    /// ending `now`, from every logged timestamp, with one bucket per journal
    /// day the window touches, oldest first: the Insights card's per-day bars.
    /// The first day holds only its part inside the window, so the buckets
    /// still sum to the count.
    static func windowCount(
        _ timestamps: [Date], range: UsageTimeRange, now: Date,
        calendar: Calendar, boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> UsageWindowCount {
        let bounds = bounds(for: range, firstTimestamp: timestamps.min(), now: now)
        let firstDay = calendar.journalDay(for: bounds.start, boundaryHour: boundaryHour)
        let lastDay = calendar.journalDay(for: bounds.end, boundaryHour: boundaryHour)
        let dayCount = max(1, (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1)
        var counts = Array(repeating: 0, count: dayCount)
        var total = 0
        for timestamp in timestamps where timestamp >= bounds.start && timestamp <= bounds.end {
            total += 1
            let day = calendar.journalDay(for: timestamp, boundaryHour: boundaryHour)
            let offset = calendar.dateComponents([.day], from: firstDay, to: day).day ?? 0
            counts[min(dayCount - 1, max(0, offset))] += 1
        }
        return UsageWindowCount(entryCount: total, averagePerDay: Double(total) / bounds.loggedDays, buckets: counts)
    }

    /// A rate to one decimal. A rate that is above zero and would round to
    /// zero reads "<0.1": a zero beside a count of entries says none were logged.
    static func rateText(_ rate: Double) -> String {
        let floor = 0.1
        if rate > 0, rate < floor / 2 {
            return "<" + floor.formatted(.number.precision(.fractionLength(1)))
        }
        return rate.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    // MARK: §2 Heatmap + hours

    /// The grid over `bounds` (the history), with each cell marked for whether
    /// it falls in `window`, the selected range (`bounds` itself when not given).
    static func heatmap(
        dayIndex: [Date: [UsageEntrySnapshot]],
        bounds: Bounds,
        window: Bounds? = nil,
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
        let windowStartDay = calendar.sessionDayStart(for: max(bounds.start, (window ?? bounds).start))

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
                    inWindow: day >= windowStartDay && day <= endDay,
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
    ///
    /// `entries` is the history up to `rangeEnd`, reaching back past the first
    /// bucket, so a point at the range's start holds a true average of the days
    /// before it. `journalStart` is the day the journal begins: a bucket whose
    /// window would open before it is left out, since an average over days
    /// with no journal draws a climb from zero that never happened. A journal
    /// younger than the window has no points at all.
    static func trends(
        _ entries: [UsageEntrySnapshot],
        ranking: [(substanceIndex: Int, count: Int)],
        bucketStarts: [Date],
        bucketDays: Int,
        windowDays: Int,
        rangeEnd: Date,
        journalStart: Date? = nil,
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

        // Measured on the bucket's own end rather than the clamped close, so
        // the youngest bucket is judged like the others.
        let drawnStarts = bucketStarts.filter { start in
            guard let journalStart else { return true }
            return start.addingTimeInterval(bucketSpan - window) >= journalStart
        }
        guard let earliest = drawnStarts.first else {
            return top.map { UsageTrendSeries(substanceIndex: $0.substanceIndex, points: [], hasCommonDoses: false) }
        }
        let reach = earliest.addingTimeInterval(bucketSpan - window)

        return top.map { item in
            let events = (eventsBySubstance[item.substanceIndex] ?? [])
                .filter { $0.date > reach }
                .sorted { $0.date < $1.date }
            let hasCommon = events.contains { $0.common != nil }
            let points = drawnStarts.map { start in
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

    /// Molecule pairs logged on the same session day, ranked by how many days
    /// they co-occur. Below ``minimumCoUseDays`` a pair is a coincidence, not a
    /// habit, so it never surfaces. Every row of one molecule counts as that
    /// molecule (``UsageEntrySnapshot/moleculeIndex``): Concerta and a Ritalin
    /// booster are one substance, never a pair, and their days with Adderall
    /// add up to one methylphenidate pair.
    static func coUsePairs(dayIndex: [Date: [UsageEntrySnapshot]]) -> [UsageCoUsePair] {
        var pairDays: [PairKey: Int] = [:]
        var soloDays: [Int: Int] = [:]
        // Per molecule, the days each of its rows was logged on.
        var rowDays: [Int: [Int: Int]] = [:]

        for (_, dayEntries) in dayIndex {
            var present = Set<Int>()
            var rowsPresent = Set<Int>()
            for entry in dayEntries {
                present.insert(entry.moleculeIndex)
                if rowsPresent.insert(entry.substanceIndex).inserted {
                    rowDays[entry.moleculeIndex, default: [:]][entry.substanceIndex, default: 0] += 1
                }
            }
            for molecule in present {
                soloDays[molecule, default: 0] += 1
            }
            let ordered = present.sorted()
            guard ordered.count >= 2 else { continue }
            for i in 0 ..< (ordered.count - 1) {
                for j in (i + 1) ..< ordered.count {
                    pairDays[PairKey(first: ordered[i], second: ordered[j]), default: 0] += 1
                }
            }
        }

        // A molecule's most-logged row, the lower index on a tie.
        func row(of molecule: Int) -> Int {
            let rows = rowDays[molecule] ?? [:]
            return rows.min { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }?.key ?? molecule
        }
        func spansRows(_ molecule: Int) -> Bool {
            (rowDays[molecule]?.count ?? 0) > 1
        }

        let ranked = pairDays
            .filter { $0.value >= minimumCoUseDays }
            .map { key, days in
                let union = (soloDays[key.first] ?? 0) + (soloDays[key.second] ?? 0) - days
                let sides = [
                    (row: row(of: key.first), spans: spansRows(key.first)),
                    (row: row(of: key.second), spans: spansRows(key.second)),
                ].sorted { $0.row < $1.row }
                return UsageCoUsePair(
                    firstIndex: sides[0].row, secondIndex: sides[1].row,
                    days: days, unionDays: max(union, days),
                    firstSpansRows: sides[0].spans, secondSpansRows: sides[1].spans,
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
                typicalIntervalDays: stats.median,
                gapVariation: stats.variation,
            )
        }
        .sorted {
            if $0.gapVariation != $1.gapVariation {
                return $0.gapVariation < $1.gapVariation
            }
            return $0.substanceIndex < $1.substanceIndex
        }
    }

    /// The typical gap and how far the gaps stray from it: the median, and the
    /// mean absolute deviation from the median as a share of it. `nil` when
    /// there is nothing to describe (no gaps, or a median of zero).
    ///
    /// Measured around the median, NOT as standard deviation over mean: one
    /// three-week pause in a daily routine gives 180 one-day gaps a
    /// coefficient of variation of 1.4, which grades the steadiest substance
    /// in a journal "Sporadic".
    static func intervalStatistics(_ intervals: [Double]) -> (median: Double, variation: Double)? {
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        guard median > 0 else { return nil }
        let deviation = sorted.reduce(0) { $0 + abs($1 - median) } / Double(sorted.count)
        return (median, deviation / median)
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

    /// How many times each weekday falls inside the part of the window the
    /// journal covers — so §8's "average per weekday" divides by the right
    /// denominator on a partial range and on a journal younger than the range.
    static func weekdayOccurrences(bounds: Bounds, calendar: Calendar) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        var cursor = calendar.startOfDay(for: bounds.loggedStart)
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
