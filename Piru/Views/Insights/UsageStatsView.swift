import SwiftData
import SwiftUI

/// Insights → Usage. A thin coordinator: it owns the time range, the metric
/// lens, the substance filter, and the analytics model, and hands each section
/// its own slice of the result.
///
/// The controls live in one toolbar filter menu rather than inline above the
/// charts, so the screen leads with data. Each section that has churning UI
/// state (the heatmap's day/category selection, the trend legend, the dose-level
/// substance picker) still owns that state itself, so a tap in one section
/// doesn't re-evaluate the others.
struct UsageStatsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Every dose, newest first, current for the dose log's revision
    /// (``DoseLogEntries``), shared with every other screen that reads it.
    private var allEntries: [DoseEntry] {
        DoseLogEntries.shared.entries(in: modelContext)
    }
    @Query private var substanceColors: [SubstanceColor]

    @State private var model = UsageAnalyticsModel()
    @State private var range: UsageTimeRange = .opening
    /// Entries vs common-dose units: one global lens for every card that has
    /// one. Common doses by default: it weighs each dose by its typical size,
    /// the more representative view.
    @State private var metric: UsageRankMetric = .commonDoses
    /// Canonical names to include; empty means every substance. Lets the user
    /// mute a substance that dominates the stats (the "2-MMC swamps everything"
    /// report) and read the rest. Edited in ``SubstanceFilterSheet``.
    @State private var selectedSubstances: Set<String> = []
    @State private var showingSubstanceSheet = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxl) {
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
        .skinBackdrop()
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .platformTopBarTrailing) { filterMenu }
            }
        }
        .sheet(isPresented: $showingSubstanceSheet) {
            SubstanceFilterSheet(substances: model.allSubstances, selection: $selectedSubstances)
        }
        .task(id: refreshToken) {
            await SubstanceStore.shared.ensureAllLoaded()
            await model.refresh(
                entries: allEntries, colors: substanceColors,
                range: range, substanceFilter: selectedSubstances,
            )
        }
        #if DEBUG
        .task {
            range = ScreenshotTour.takeStagedChart(\.usageRange) ?? range
            metric = ScreenshotTour.takeStagedChart(\.usageMetric) ?? metric
            selectedSubstances = ScreenshotTour.takeStagedChart(\.usageSubstances) ?? selectedSubstances
        }
        #endif
    }

    /// One token covering every input that changes the aggregation — the
    /// dose-log revision, colors, range, and the substance filter — so any of
    /// them re-runs the (internally memoized) refresh. The metric lens is
    /// deliberately absent: it only re-labels already-computed numbers, so it
    /// never triggers a recompute.
    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        hasher.combine(range)
        hasher.combine(selectedSubstances.sorted().joined(separator: "\u{1}"))
        return hasher.finalize()
    }

    // MARK: - Toolbar filter

    private var filterMenu: some View {
        InsightsFilterMenu(
            range: $range,
            selectedCount: selectedSubstances.count,
            offersSubstances: model.allSubstances.count > 1,
            showSubstances: { showingSubstanceSheet = true },
        ) {
            Picker("Measure", selection: $metric) {
                Text("Common doses").tag(UsageRankMetric.commonDoses)
                Text("Entries").tag(UsageRankMetric.entries)
            }
        }
    }

    /// With a substance filter on, the filter is why the range is empty, so
    /// the line names it; a longer range is the answer only without one.
    private var emptyRange: some View {
        ContentUnavailableView(
            "Nothing in This Range",
            systemImage: "calendar",
            description: selectedSubstances.isEmpty
                ? Text("Pick a longer time range to see your history.")
                : Text("No entries match the substance filter in this range."),
        )
        .padding(.top, 40)
    }

    @ViewBuilder
    private func sections(_ result: UsageAnalyticsResult) -> some View {
        let style = UsageSubstanceStyle(substances: result.substances, colorMap: model.colorMap)
        // A range where no entry has a common dose reads in entries: weighed
        // by common doses, every chart on the screen would be empty.
        let metric: UsageRankMetric = result.commonDoseEntryCount == 0 ? .entries : self.metric
        let coverage = UsageCommonDoseCoverage(
            metric: metric, covered: result.commonDoseEntryCount, total: result.entryCount,
        )

        UsageOverviewSection(overview: result.overview, range: result.range)

        UsageHeatmapSection(
            heatmap: result.heatmap,
            hours: result.hours,
            categories: result.categories,
            metric: metric,
            range: result.range,
            coverage: coverage,
        )

        UsageTrendsSection(
            trends: result.trends, style: style, range: result.range, metric: metric,
            timeAxis: result.timeAxis, coverage: coverage,
        )

        UsageWeekdaySection(buckets: result.weekdays, metric: metric, coverage: coverage)

        UsageDoseLevelSection(
            breakdown: result.doseLevels,
            style: style,
            weekly: result.range.usesWeeklyBuckets,
            timeAxis: result.timeAxis,
        )

        UsageCoUseSection(pairs: result.coUse, style: style, categories: result.categories)

        UsageRegularitySection(rows: result.regularity, style: style)

        UsageRouteSection(breakdown: result.routes, style: style, metric: metric)
    }
}
