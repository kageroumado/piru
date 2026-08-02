import SwiftData
import SwiftUI

/// Insights → Usage. A thin coordinator: it owns the time range and the
/// analytics model, and hands each section of `Specs/usage-graphs-v2.md` its
/// own slice of the result.
///
/// Deliberately holds almost no state. Every section that has churning UI state
/// (the heatmap's day/category selection, the trend legend, the dose-level
/// substance picker) owns that state itself, so a tap in one section doesn't
/// re-evaluate the others — this screen renders eight charts, and one shared
/// invalidation boundary across all of them was the old design's problem.
struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var model = UsageAnalyticsModel()
    @State private var range: UsageTimeRange = .thirtyDays

    var body: some View {
        VStack(spacing: 0) {
            if !allEntries.isEmpty {
                rangePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            ScrollView {
                LazyVStack(spacing: 16) {
                    if allEntries.isEmpty {
                        ContentUnavailableView(
                            "No Logged Entries",
                            systemImage: "chart.bar",
                            description: Text("Log some entries to see usage stats."),
                        )
                        .padding(.top, 40)
                    } else if let result = model.result {
                        if result.isEmpty {
                            emptyRange
                        } else {
                            sections(result)
                        }
                    } else {
                        ProgressView()
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.background)
        .task(id: refreshToken) {
            await model.refresh(entries: allEntries, colors: substanceColors, range: range)
        }
    }

    /// One token covering both inputs, so a range change and an edit to the
    /// underlying entries both re-run the (internally memoized) refresh.
    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(EntriesFingerprint.make(allEntries, colors: substanceColors))
        hasher.combine(range)
        return hasher.finalize()
    }

    private var rangePicker: some View {
        Picker("Time Range", selection: $range) {
            ForEach(UsageTimeRange.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyRange: some View {
        ContentUnavailableView(
            "Nothing in This Range",
            systemImage: "calendar",
            description: Text("Pick a longer time range to see your history."),
        )
        .padding(.top, 40)
    }

    @ViewBuilder
    private func sections(_ result: UsageAnalyticsResult) -> some View {
        let style = UsageSubstanceStyle(substances: result.substances, colorMap: model.colorMap)

        UsageOverviewSection(overview: result.overview, range: result.range)

        UsageHeatmapSection(
            heatmap: result.heatmap,
            hours: result.hours,
            categories: result.categories,
        )

        UsageTrendsSection(trends: result.trends, style: style, range: result.range)

        UsageWeekdaySection(buckets: result.weekdays)

        UsageDoseLevelSection(
            breakdown: result.doseLevels,
            style: style,
            weekly: result.range.usesWeeklyBuckets,
        )

        UsageCoUseSection(pairs: result.coUse, style: style, categories: result.categories)

        UsageRegularitySection(rows: result.regularity, style: style)

        UsageRouteSection(breakdown: result.routes, style: style)
    }
}
