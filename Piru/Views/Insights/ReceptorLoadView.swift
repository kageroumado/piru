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

    @State private var range: UsageTimeRange = .opening
    @State private var series: [ReceptorLoadSeries] = []
    @State private var loaded = false
    @State private var hidden: Set<String> = []
    @State private var selectedDate: Date?
    /// The span the chart draws: the whole selected range, ending now.
    @State private var span: ClosedRange<Date> = Date.now ... Date.now

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
                } else if series.isEmpty {
                    empty(
                        "Nothing to Model",
                        "None of your logged substances in this range drive a modeled mechanism.",
                    )
                } else {
                    chartCard
                    disclaimer
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
        let classes = ToleranceStore.shared.states.values
            .sorted { $0.severity > $1.severity }
            .map(\.receptorClass)

        let now = Date.now
        let pastHorizon: TimeInterval = if let days = range.days {
            Double(days) * 86_400
        } else {
            now.timeIntervalSince(allEntries.map(\.timestamp).min() ?? now.addingTimeInterval(-90 * 86_400))
        }
        let step = Self.step(forWindow: pastHorizon)
        span = now.addingTimeInterval(-pastHorizon) ... now

        var built: [ReceptorLoadSeries] = []
        for receptorClass in classes.prefix(6) {
            let trail = await ToleranceStore.shared.loadTrail(
                for: receptorClass, from: allEntries, now: now,
                pastHorizon: pastHorizon, horizon: 0, step: step,
            )
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
        series = built.sorted { $0.peak > $1.peak }
        loaded = true
    }

    /// Sample spacing for the trail: coarser as the window widens, so a year's
    /// trace isn't an unreadable comb. `loadTrail` defaults to 3 h.
    private static func step(forWindow seconds: TimeInterval) -> TimeInterval {
        switch seconds {
        case ..<(31 * 86_400): 3 * 3_600
        case ..<(91 * 86_400): 6 * 3_600
        case ..<(366 * 86_400): 12 * 3_600
        default: max(12 * 3_600, seconds / 1_000)
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        // The title names the span, the one thing the toolbar menu changes.
        UsageSectionCard(title: Text(range.windowName), subtitle: "Relative to your recent baseline") {
            let visible = series.filter { !hidden.contains($0.id) }
            let shown = visible.isEmpty ? series : visible
            ReceptorLoadChart(series: shown, selectedDate: $selectedDate, span: span)
            if let selectedDate {
                ReceptorLoadReadout(series: shown, date: selectedDate)
            }
            legend
        }
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

    private var disclaimer: some View {
        Text("Modeled from your logged doses: receptor drive, not how you feel.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
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
    let span: ClosedRange<Date>

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
        .chartXScale(domain: span)
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
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
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

    var body: some View {
        let rows = series.compactMap { item -> (series: ReceptorLoadSeries, load: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item, point.load)
        }
        .filter { $0.load > 0.005 }
        .sorted { $0.load > $1.load }

        ChartScrubReadout(
            title: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
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
        item.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
