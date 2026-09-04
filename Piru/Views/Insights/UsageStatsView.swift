import SwiftData
import SwiftUI

/// Insights → Usage. A thin coordinator: it owns the time range, the metric
/// lens, the substance filter, and the analytics model, and hands each section
/// of `Specs/usage-graphs-v2.md` its own slice of the result.
///
/// The controls live in one toolbar filter menu rather than inline above the
/// charts, so the screen leads with data. Each section that has churning UI
/// state (the heatmap's day/category selection, the trend legend, the dose-level
/// substance picker) still owns that state itself, so a tap in one section
/// doesn't re-evaluate the others — this screen renders eight charts, and one
/// shared invalidation boundary across all of them was the old design's problem.
struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var model = UsageAnalyticsModel()
    @State private var range: UsageTimeRange = .thirtyDays
    /// Entries vs common-dose units — one global lens for every card that has
    /// one (they each used to carry their own copy). Common doses by default: it
    /// weighs each dose by its typical size, the more representative view.
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
        .background(Theme.background)
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

    private var filterActive: Bool {
        !selectedSubstances.isEmpty
    }

    private var filterMenu: some View {
        Menu {
            Picker("Time Range", selection: $range) {
                ForEach(UsageTimeRange.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            Picker("Measure", selection: $metric) {
                Text("Common doses").tag(UsageRankMetric.commonDoses)
                Text("Entries").tag(UsageRankMetric.entries)
            }
            if model.allSubstances.count > 1 {
                Button {
                    showingSubstanceSheet = true
                } label: {
                    // No leading icon (the pickers above carry none) and a
                    // trailing ellipsis — the HIG signal for a row that opens
                    // further UI (here, the substance-filter sheet) before it
                    // takes effect, rather than toggling a value inline.
                    Text(verbatim: substancesMenuLabel + "\u{2026}")
                }
            }
        } label: {
            filterLabel
        }
    }

    /// The toolbar glyph. `line.3.horizontal.decrease` has no `.fill` variant and
    /// a Menu button can't be tinted, so the active state is carried by a
    /// selected-count badge beside the glyph rather than a color or fill swap.
    @ViewBuilder
    private var filterLabel: some View {
        if filterActive {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(verbatim: "\(selectedSubstances.count)")
            }
            .accessibilityLabel(Text("Filter"))
        } else {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
    }

    /// The substance-picker menu row: the count when a subset is active, else "all".
    private var substancesMenuLabel: String {
        filterActive
            ? String(localized: "Substances (\(selectedSubstances.count))")
            : String(localized: "All Substances")
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
            metric: metric,
        )

        UsageTrendsSection(trends: result.trends, style: style, range: result.range, metric: metric)

        UsageWeekdaySection(buckets: result.weekdays, metric: metric)

        UsageDoseLevelSection(
            breakdown: result.doseLevels,
            style: style,
            weekly: result.range.usesWeeklyBuckets,
        )

        UsageCoUseSection(pairs: result.coUse, style: style, categories: result.categories)

        UsageRegularitySection(rows: result.regularity, style: style)

        UsageRouteSection(breakdown: result.routes, style: style, metric: metric)
    }
}
