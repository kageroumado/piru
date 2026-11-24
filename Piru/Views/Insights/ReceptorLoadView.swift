import Charts
import SwiftData
import SwiftUI

/// Insights → Receptor Load. The historic
/// counterpart to the "now"-only Tolerance tool: one line per mechanism class
/// tracing how hard the receptors have been driven across the range, so drug
/// holidays read as troughs and sustained heavy use as a high plateau.
///
/// The value is `ToleranceStore.loadTrail`'s relative load — each point measured
/// against the drive peak of its own surrounding weeks — so it reads as
/// "intensity relative to your recent baseline", not an absolute occupancy.
struct ReceptorLoadView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]

    /// Opens on a week: the curves rise and fall within a day, and a month of them
    /// in one card's width is a solid block.
    @State private var range: UsageTimeRange = .sevenDays
    @State private var series: [ReceptorLoadSeries] = []
    @State private var loaded = false
    @State private var hidden: Set<String> = []
    @State private var selectedDate: Date?
    /// The span the chart draws, ending now: the selected range, or from the first dose when the
    /// log is younger than the range.
    @State private var window = ModeledChartWindow(range: .sevenDays, firstDose: nil, now: .now)

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                if allEntries.isEmpty {
                    empty(
                        "No Logged Entries",
                        "Add entries to see modeled receptor load.",
                    )
                } else if !loaded {
                    ProgressView().padding(.top, 60)
                } else {
                    chartCard
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .skinBackdrop()
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .platformTopBarTrailing) { rangeMenu }
            }
        }
        .task(id: token) { await load() }
    }

    private var token: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(range)
        return hasher.finalize()
    }

    // MARK: - Load

    private func load() async {
        guard !allEntries.isEmpty else {
            series = []
            loaded = true
            return
        }
        await ToleranceStore.shared.recompute(from: allEntries)
        let classes = Set(ToleranceStore.shared.states.keys)

        let now = Date.now
        // The trails replay the last `defaultLookbackDays`, so an older log's "All" starts there.
        let window = ModeledChartWindow(
            range: range, firstDose: allEntries.last?.timestamp, now: now,
            reach: ToleranceStore.defaultLookbackDays * 86_400,
        )

        let trails = await ToleranceStore.shared.loadTrails(
            for: classes, from: allEntries, now: now,
            pastHorizon: window.length, step: window.receptorLoadStep,
        )
        // A newer range or log revision has started its own load; this one's result is stale.
        guard !Task.isCancelled else { return }
        var built: [ReceptorLoadSeries] = []
        for (receptorClass, trail) in trails {
            guard let peak = trail.map(\.load).max(), peak > 0.02 else { continue }
            let points = trail.enumerated().map { index, sample in
                ReceptorLoadSeries.Point(id: index, date: sample.date, load: sample.load)
            }
            built.append(ReceptorLoadSeries(
                id: receptorClass.rawValue,
                name: String(localized: receptorClass.casualName),
                color: receptorClass.familyColor,
                peak: peak,
                points: points,
            ))
        }
        // Highest peak first; the class order breaks ties so the legend holds still between loads.
        series = built.sorted { $0.peak != $1.peak ? $0.peak > $1.peak : $0.id < $1.id }
        self.window = window
        loaded = true
    }

    // MARK: - Chart

    private var chartCard: some View {
        // The title names the span, the one thing the toolbar menu changes.
        UsageSectionCard(title: Text(range.windowName), subtitle: "Relative to your recent baseline") {
            if series.isEmpty {
                // The card keeps its range title, so the reader sees which span was searched.
                ContentUnavailableView(
                    "Nothing to Model",
                    systemImage: "chart.xyaxis.line",
                    description: Text("None of your logged substances in this range drive a modeled mechanism."),
                )
            } else {
                let visible = series.filter { !hidden.contains($0.id) }
                let shown = visible.isEmpty ? series : visible
                ReceptorLoadChart(series: shown, selectedDate: $selectedDate, window: window)
                if let selectedDate {
                    ReceptorLoadReadout(series: shown, date: selectedDate, step: window.receptorLoadStep)
                }
                legend
            }
        }
        #if DEBUG
        .task { selectedDate = ScreenshotTour.takeStagedSelection(.receptorLoad) ?? selectedDate }
        #endif
    }

    private var legend: some View {
        FlowLayout(spacing: Spacing.md) {
            ForEach(series) { item in
                let isHidden = hidden.contains(item.id)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isHidden { hidden.remove(item.id) } else { hidden.insert(item.id) }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        LegendDot(color: item.color)
                            .opacity(isHidden ? 0.3 : 1)
                        Text(item.name)
                            .font(.caption2)
                            .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.name))
                .accessibilityValue(isHidden ? Text("Hidden") : Text("Shown"))
                .accessibilityHint(Text("Toggles this mechanism's line"))
                .accessibilityAddTraits(isHidden ? [] : [.isSelected])
            }
        }
    }

    // MARK: - Chrome

    /// The Usage screen's filter menu, holding only the time range here: the
    /// legend below the chart already shows and hides each mechanism.
    private var rangeMenu: some View {
        InsightsFilterMenu(range: $range, selectedCount: 0, offersSubstances: false, showSubstances: {})
            .onChange(of: range) { selectedDate = nil }
    }

    private func empty(_ title: LocalizedStringKey, _ description: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: "chart.xyaxis.line", description: Text(description))
            .padding(.top, 40)
    }
}

// MARK: - Data

struct ReceptorLoadSeries: Identifiable {
    struct Point: Identifiable {
        let id: Int
        let date: Date
        let load: Double
    }

    let id: String
    let name: String
    let color: Color
    let peak: Double
    let points: [Point]
}

// MARK: - Chart view

private struct ReceptorLoadChart: View {
    let series: [ReceptorLoadSeries]
    @Binding var selectedDate: Date?
    let window: ModeledChartWindow

    var body: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Load", point.load),
                        series: .value("Mechanism", item.id),
                    )
                    .foregroundStyle(item.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.muted))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: 200)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: window.span)
        .chartYScale(domain: 0 ... 1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            if let ticks = window.axisTicks {
                AxisMarks(values: ticks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(verbatim: date.formatted(window.axisFormat)).font(.caption2)
                        }
                    }
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(verbatim: date.formatted(window.axisFormat)).font(.caption2)
                        }
                    }
                }
            }
        }
        .chartSummaryAccessibility(label: Text("Receptor Load"), value: Text(summary))
    }

    private var summary: String {
        guard !series.isEmpty else { return String(localized: "No data") }
        let parts = series.prefix(4).map { item -> String in
            let current = item.points.last?.load ?? 0
            let pct = current.formatted(.percent.precision(.fractionLength(0)))
            return String(localized: "\(item.name) now at \(pct)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scrub readout

private struct ReceptorLoadReadout: View {
    let series: [ReceptorLoadSeries]
    let date: Date
    /// The trails' sample spacing: a sample further than this from `date` belongs to another time.
    let step: TimeInterval

    var body: some View {
        let rows = series.compactMap { item -> (series: ReceptorLoadSeries, load: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item, point.load)
        }
        .filter { $0.load > 0.005 }
        .sorted { $0.load > $1.load }

        ChartScrubReadout(
            title: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour()),
            items: rows, id: \.series.id,
            emptyText: Text("Nothing driven at this time"),
            name: { $0.series.name },
            value: { Text($0.load.formatted(.percent.precision(.fractionLength(0)))) },
        ) { row in
            Circle()
                .fill(row.series.color)
                .frame(width: 6, height: 6)
        }
    }

    private func nearestPoint(in item: ReceptorLoadSeries) -> ReceptorLoadSeries.Point? {
        let nearest = item.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let nearest, abs(nearest.date.timeIntervalSince(date)) <= step else { return nil }
        return nearest
    }
}
