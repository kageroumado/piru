import SwiftData
import SwiftUI

/// Owns the Usage Stats screen's *derived* state — the time-range filtered
/// entry snapshot, frequency ranking, activity timeline, time-of-day bins,
/// trend candidates, and category breakdown — so it lives outside the view's
/// `body` instead of in a web of `@State` caches.
///
/// The view passes in its `@Query` results plus the selected time range; the
/// model recomputes and publishes ready-to-render values, which SwiftUI diffs
/// as a single observable source of truth. All the maths lives in `static`
/// helpers taking explicit inputs, so unit tests can exercise bucketing,
/// ranking, and moving-average behaviour without SwiftUI.
@Observable
@MainActor
final class UsageStatsModel {
    /// Lightweight copy of DoseEntry fields — avoids SwiftData model accessor
    /// overhead in chart views.
    struct CachedEntry {
        let substance: String
        let amount: Double
        let unit: String
        let timestamp: Date
    }

    /// One (session day, substance) bucket key for the activity timeline.
    struct DaySubstance: Hashable {
        let date: Date
        let substance: String
    }

    /// One point on the dose-trend chart (a day or week bucket total).
    struct TrendDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let total: Double
    }

    /// Everything the single aggregation pass over the filtered entries
    /// produces — day buckets, per-substance day sets and counts, the
    /// distinct-name count, and the four time-of-day bins.
    struct Aggregation {
        var dayBuckets: [DaySubstance: Int] = [:]
        var substanceDays: [String: Set<Date>] = [:]
        var substanceCounts: [String: Int] = [:]
        var uniqueSubstanceCount = 0
        var timeOfDayBuckets: [Int] = [0, 0, 0, 0]
    }

    /// The filtered, snapshotted entries for the selected time range.
    private(set) var filteredEntries: [CachedEntry] = []
    /// Lowercased substance name → assigned colour.
    private(set) var colorMap: [String: Color] = [:]
    /// Per-(day, substance) entry counts, sorted by date, for the expanded chart.
    private(set) var timelineData: [(key: DaySubstance, count: Int)] = []
    /// Distinct substances in the timeline with their colours, sorted by name.
    private(set) var timelineLegend: [(name: String, color: Color)] = []
    /// Substances eligible for the trend chart (2+ entries on 2+ distinct days),
    /// most-logged first.
    private(set) var trendSubstances: [(name: String, count: Int)] = []
    /// Entry counts per category, most-logged first.
    private(set) var categoryCounts: [(category: SubstanceCategory, count: Int)] = []
    /// Per-category substance counts (most-logged first) for the drill-down.
    private(set) var categorySubstanceCounts: [SubstanceCategory: [(substance: String, count: Int)]] = [:]
    /// Top-10 substances by entry count.
    private(set) var frequencyData: [(substance: String, count: Int)] = []
    /// Aggregated entries per day (1 bar per day) for the compact chart.
    private(set) var dailyTotals: [(date: Date, count: Int)] = []
    /// Entry counts for [morning, afternoon, evening, night].
    private(set) var timeOfDayBuckets: [Int] = [0, 0, 0, 0]
    /// Number of distinct (case-insensitive) substance names.
    private(set) var uniqueSubstances = 0
    /// Name of the most-logged substance, or an em-dash placeholder.
    private(set) var mostLogged = "—"
    /// Total entry count in the selected range (denominator for percentages).
    private(set) var frequencyTotal = 0

    /// Recompute every derived value from a snapshot of the view's `@Query`
    /// results. `rangeDays` is the selected time range's day count (`nil` for
    /// "All"); `now` anchors the cutoff and is injectable for tests, as is
    /// `categoryOf` (defaulting to the substance library lookup).
    func rebuild(
        entries allEntries: [DoseEntry],
        colors: [SubstanceColor],
        rangeDays: Int?,
        now: Date = .now,
        categoryOf: @MainActor (String) -> SubstanceCategory = { SubstanceLibrary.lookup($0.lowercased())?.category ?? .other },
    ) {
        let filtered: [DoseEntry]
        if let days = rangeDays {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            filtered = allEntries.filter { $0.timestamp >= cutoff }
        } else {
            filtered = allEntries
        }

        // Snapshot SwiftData fields into lightweight structs, then aggregate
        // in a single pass (avoids repeated Calendar work in chart views).
        var entries: [CachedEntry] = []
        entries.reserveCapacity(filtered.count)
        for e in filtered {
            entries.append(CachedEntry(substance: e.substance, amount: e.amount, unit: e.unit, timestamp: e.timestamp))
        }

        let calendar = Calendar.current
        let agg = Self.aggregate(entries, calendar: calendar)

        filteredEntries = entries
        colorMap = colors.colorMap

        frequencyTotal = entries.count
        frequencyData = Self.frequencyRanking(agg.substanceCounts)

        timeOfDayBuckets = agg.timeOfDayBuckets

        uniqueSubstances = agg.uniqueSubstanceCount
        mostLogged = agg.substanceCounts.max(by: { $0.value < $1.value })?.key ?? "—"

        timelineData = Self.timelineData(from: agg.dayBuckets)
        dailyTotals = Self.dailyTotals(from: agg.dayBuckets)
        timelineLegend = Self.legend(for: timelineData, colorMap: colorMap)

        trendSubstances = Self.trendCandidates(substanceDays: agg.substanceDays, substanceCounts: agg.substanceCounts)

        let category = Self.categoryAggregation(entries: entries, categoryOf: categoryOf)
        categoryCounts = category.counts
        categorySubstanceCounts = category.substanceCounts
    }

    /// Trend chart data for one substance from the current filtered entries,
    /// auto-aggregating to daily averages per week if the span exceeds the
    /// zoom-scaled threshold.
    func trendData(
        for substance: String,
        zoom: CGFloat,
    ) -> (points: [TrendDataPoint], unit: String, weekly: Bool, maLookup: [Date: Double], mixedUnits: Bool) {
        Self.trendData(entries: filteredEntries, substance: substance, zoom: zoom, calendar: Calendar.current, now: .now)
    }

    // MARK: - Pure calculation helpers

    /// Single pass over the snapshotted entries: session-day buckets per
    /// substance, distinct-day sets, entry counts, the case-insensitive
    /// distinct-name count, and time-of-day bins.
    static func aggregate(_ entries: [CachedEntry], calendar: Calendar) -> Aggregation {
        var agg = Aggregation()
        var uniqueNames = Set<String>()
        for ce in entries {
            let day = calendar.sessionDayStart(for: ce.timestamp)
            agg.dayBuckets[DaySubstance(date: day, substance: ce.substance), default: 0] += 1
            agg.substanceDays[ce.substance, default: []].insert(day)
            agg.substanceCounts[ce.substance, default: 0] += 1
            uniqueNames.insert(ce.substance.lowercased())

            let hour = calendar.component(.hour, from: ce.timestamp)
            agg.timeOfDayBuckets[timeOfDayBucketIndex(hour: hour)] += 1
        }
        agg.uniqueSubstanceCount = uniqueNames.count
        return agg
    }

    /// Index into the [morning, afternoon, evening, night] bins for an hour
    /// of day: 6–12 morning, 12–18 afternoon, 18–24 evening, else night.
    static func timeOfDayBucketIndex(hour: Int) -> Int {
        switch hour {
        case 6 ..< 12: 0
        case 12 ..< 18: 1
        case 18 ..< 24: 2
        default: 3
        }
    }

    /// Substances ranked by entry count, descending, capped at `limit`.
    static func frequencyRanking(_ counts: [String: Int], limit: Int = 10) -> [(substance: String, count: Int)] {
        counts.sorted { $0.value > $1.value }
            .prefix(limit).map { (substance: $0.key, count: $0.value) }
    }

    /// Per-(day, substance) counts sorted by date for the expanded chart.
    static func timelineData(from dayBuckets: [DaySubstance: Int]) -> [(key: DaySubstance, count: Int)] {
        dayBuckets.map { (key: $0.key, count: $0.value) }
            .sorted { $0.key.date < $1.key.date }
    }

    /// Entries per day aggregated across substances, sorted by date.
    static func dailyTotals(from dayBuckets: [DaySubstance: Int]) -> [(date: Date, count: Int)] {
        var dailyAgg: [Date: Int] = [:]
        for (key, count) in dayBuckets {
            dailyAgg[key.date, default: 0] += count
        }
        return dailyAgg.sorted { $0.key < $1.key }
            .map { (date: $0.key, count: $0.value) }
    }

    /// Distinct substances in the timeline (case-insensitive, first-seen
    /// casing wins) with their colours, sorted by name.
    static func legend(
        for timelineData: [(key: DaySubstance, count: Int)],
        colorMap: [String: Color],
    ) -> [(name: String, color: Color)] {
        var seen = Set<String>()
        var legend: [(name: String, color: Color)] = []
        for item in timelineData {
            let name = item.key.substance
            if seen.insert(name.lowercased()).inserted {
                legend.append((name: name, color: colorMap[name.lowercased()] ?? Theme.accent))
            }
        }
        return legend.sorted { $0.name < $1.name }
    }

    /// Substances with 2+ entries on 2+ distinct days, most-logged first.
    static func trendCandidates(
        substanceDays: [String: Set<Date>],
        substanceCounts: [String: Int],
    ) -> [(name: String, count: Int)] {
        var trends: [(name: String, count: Int)] = []
        for (name, days) in substanceDays {
            let count = substanceCounts[name] ?? 0
            guard count >= 2, days.count >= 2 else { continue }
            trends.append((name: name, count: count))
        }
        return trends.sorted { $0.count > $1.count }
    }

    /// Entry counts per category (most-logged first) and the per-category
    /// substance breakdown (most-logged first) for the drill-down chart.
    static func categoryAggregation(
        entries: [CachedEntry],
        categoryOf: @MainActor (String) -> SubstanceCategory,
    ) -> (counts: [(category: SubstanceCategory, count: Int)], substanceCounts: [SubstanceCategory: [(substance: String, count: Int)]]) {
        var categoryCounts: [SubstanceCategory: Int] = [:]
        var substanceByCat: [SubstanceCategory: [String: Int]] = [:]

        for entry in entries {
            let cat = categoryOf(entry.substance)
            categoryCounts[cat, default: 0] += 1
            substanceByCat[cat, default: [:]][entry.substance, default: 0] += 1
        }

        let counts = categoryCounts
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value) }

        let substanceCounts = substanceByCat.mapValues { counts in
            counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        }

        return (counts, substanceCounts)
    }

    /// Build trend data for a substance, auto-aggregating to daily averages
    /// per week if the span exceeds the zoom-scaled threshold (zooming in deep
    /// enough reveals individual daily data points). Mixed-unit histories keep
    /// only the predominant unit's entries. The moving average uses a trailing
    /// 7-point window daily and 4-point window weekly, and only appears once
    /// there are 3+ points.
    static func trendData(
        entries allEntries: [CachedEntry],
        substance: String,
        zoom: CGFloat,
        calendar: Calendar,
        now: Date,
    ) -> (points: [TrendDataPoint], unit: String, weekly: Bool, maLookup: [Date: Double], mixedUnits: Bool) {
        let allSubstanceEntries = allEntries
            .filter { $0.substance == substance }
            .sorted { $0.timestamp < $1.timestamp }

        guard !allSubstanceEntries.isEmpty else { return ([], "mg", false, [:], false) }

        // Determine predominant unit; filter if mixed
        var unitCounts: [String: Int] = [:]
        for e in allSubstanceEntries {
            unitCounts[e.unit, default: 0] += 1
        }
        let unit = unitCounts.max(by: { $0.value < $1.value })?.key ?? "mg"
        let mixedUnits = unitCounts.count > 1
        let entries = mixedUnits ? allSubstanceEntries.filter { $0.unit == unit } : allSubstanceEntries

        guard !entries.isEmpty else { return ([], unit, false, [:], mixedUnits) }

        let span = (entries.last?.timestamp.timeIntervalSince(entries.first?.timestamp ?? now) ?? 0) / 86_400
        let weekly = span > 90 * Double(zoom)

        var buckets: [Date: Double] = [:]
        for entry in entries {
            let key: Date = if weekly {
                calendar.dateInterval(of: .weekOfYear, for: entry.timestamp)?.start
                    ?? calendar.sessionDayStart(for: entry.timestamp)
            } else {
                calendar.sessionDayStart(for: entry.timestamp)
            }
            buckets[key, default: 0] += entry.amount
        }

        // When aggregating weekly, convert totals to daily averages
        if weekly {
            for (weekStart, total) in buckets {
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let isComplete = weekEnd <= now
                let days = isComplete ? 7 : max(1, (calendar.dateComponents([.day], from: weekStart, to: now).day ?? 0) + 1)
                buckets[weekStart] = total / Double(days)
            }
        }

        let points = buckets.map { TrendDataPoint(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }

        // Compute moving average lookup
        var maLookup: [Date: Double] = [:]
        if points.count >= 3 {
            let window = weekly ? 4 : 7
            for i in 0 ..< points.count {
                let start = max(0, i - window + 1)
                let slice = points[start ... i]
                maLookup[points[i].date] = slice.map(\.total).reduce(0, +) / Double(slice.count)
            }
        }

        return (points, unit, weekly, maLookup, mixedUnits)
    }
}
