import Charts
import SwiftData
import SwiftUI

/// Insights → In your body over time. The historic counterpart to
/// ``InYourSystemView`` (which shows only "now"): one line per substance tracing
/// its estimated in-body amount across the selected range, so the daily rhythm
/// and — for longer-acting drugs — accumulation between doses become visible.
///
/// Each line is normalized to its own peak, because summing milligrams of
/// different substances (let alone across mL/IU) would be a dishonest quantity.
/// The scrub readout restores the real amount, in each substance's own unit.
struct BodyLoadView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var manager = BodyLevelsManager.shared
    @State private var range: UsageTimeRange = .thirtyDays
    @State private var hidden: Set<Int> = []
    @State private var selectedDate: Date?
    @State private var selectedCategory: SubstanceCategory?
    @State private var projections: [SteadyStateProjection] = []
    /// Series id → category, resolved once per refresh — `body` re-evaluates
    /// on every chart-scrub frame, so it must never run substance lookups.
    @State private var seriesCategories: [Int: SubstanceCategory] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "No Logged Entries",
                        systemImage: "waveform.path.ecg",
                        description: Text("Log some doses to see what's been in your body over time."),
                    )
                    .padding(.top, 40)
                } else if let trail = manager.trail {
                    if trail.isEmpty {
                        emptyState
                    } else {
                        chartCard(trail)
                        if !projections.isEmpty {
                            steadyStateSection
                        }
                        disclaimer
                    }
                } else {
                    ProgressView()
                        .padding(.top, 60)
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { rangeMenu }
            }
        }
        .task(id: refreshToken) {
            await SubstanceStore.shared.ensureAllLoaded()
            await manager.refresh(entries: allEntries, colors: substanceColors, range: range)
            projections = SteadyStateProjectionBuilder.compute(entries: allEntries, colorMap: substanceColors.colorMap)
            if let trail = manager.trail {
                seriesCategories = Dictionary(uniqueKeysWithValues: trail.series.map {
                    ($0.id, SubstanceLibrary.lookup($0.displayName)?.category ?? .other)
                })
            }
        }
    }

    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        hasher.combine(range)
        return hasher.finalize()
    }

    // MARK: - Toolbar

    private var rangeMenu: some View {
        Menu {
            Picker("Time Range", selection: $range) {
                ForEach(UsageTimeRange.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Text(range.displayName)
                .font(.subheadline.weight(.semibold))
        }
        .onChange(of: range) { selectedDate = nil }
    }

    // MARK: - Chart card

    private func chartCard(_ trail: BodyLoadTrail) -> some View {
        UsageSectionCard(title: "In your body over time", subtitle: "Estimated amount still circulating, each line a share of its own peak") {
            let filtered = filteredSeries(from: trail)
            let visible = filtered.filter { !hidden.contains($0.id) }
            let series = visible.isEmpty ? filtered : visible
            BodyLoadChart(series: series, dates: trail.dates, selectedDate: $selectedDate)
            if let selectedDate {
                BodyLoadReadout(series: series, date: selectedDate)
            }
            if categories(for: trail).count > 1 {
                categoryFilter(trail)
            }
            legend(trail)
        }
    }

    // MARK: - Category filter

    private func categories(for trail: BodyLoadTrail) -> [(category: SubstanceCategory, count: Int)] {
        var counts: [SubstanceCategory: Int] = [:]
        for item in trail.series {
            counts[seriesCategories[item.id] ?? .other, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func filteredSeries(from trail: BodyLoadTrail) -> [BodyLoadTrail.Series] {
        guard let cat = selectedCategory else { return trail.series }
        return trail.series.filter { (seriesCategories[$0.id] ?? .other) == cat }
    }

    private func categoryFilter(_ trail: BodyLoadTrail) -> some View {
        FlowLayout(spacing: 6) {
            let cats = categories(for: trail)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = nil
                    hidden.removeAll()
                }
            } label: {
                Text("All")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selectedCategory == nil ? Theme.accent.opacity(0.15) : Color(.tertiarySystemFill))
                    .foregroundStyle(selectedCategory == nil ? Theme.accent : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ForEach(cats, id: \.category) { entry in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = selectedCategory == entry.category ? nil : entry.category
                        hidden.removeAll()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.category.color)
                            .frame(width: 7, height: 7)
                        Text(entry.category.displayName)
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selectedCategory == entry.category ? entry.category.color.opacity(0.15) : Color(.tertiarySystemFill))
                    .foregroundStyle(selectedCategory == entry.category ? entry.category.color : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Legend

    private func legend(_ trail: BodyLoadTrail) -> some View {
        let filtered = filteredSeries(from: trail)
        return FlowLayout(spacing: 8) {
            ForEach(filtered) { item in
                legendChip(item)
            }
        }
    }

    private func legendChip(_ item: BodyLoadTrail.Series) -> some View {
        let isHidden = hidden.contains(item.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isHidden { hidden.remove(item.id) } else { hidden.insert(item.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                    .opacity(isHidden ? 0.3 : 1)
                Text(item.displayName)
                    .font(.caption2)
                    .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.displayName))
        .accessibilityValue(isHidden ? Text("Hidden") : Text("Shown"))
        .accessibilityHint(Text("Toggles this substance's line"))
        .accessibilityAddTraits(isHidden ? [] : [.isSelected])
    }

    // MARK: - Steady state (merged from the standalone projection screen)

    private var steadyStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.circle")
                    .foregroundStyle(.mint)
                    .font(.subheadline)
                Text("Projected Steady State")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Where each regularly dosed substance settles, based on your log's cadence")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            ForEach(projections) { projection in
                SteadyStateProjectionCard(projection: projection)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing to Model",
            systemImage: "waveform.path.ecg",
            description: Text("None of your logged substances in this range have a modeled elimination curve."),
        )
        .padding(.top, 40)
    }

    private var disclaimer: some View {
        Text("An estimate from a one-compartment model, not a measurement. How much is in your body doesn't always match how strong the effects feel, or how long a substance stays detectable.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Chart

private struct BodyLoadChart: View {
    let series: [BodyLoadTrail.Series]
    let dates: [Date]
    @Binding var selectedDate: Date?

    private var span: (length: Double, windowStart: Date?) {
        guard let first = dates.first, let last = dates.last, last > first else { return (1, nil) }
        return (last.timeIntervalSince(first), last.addingTimeInterval(-usageChartWindowSeconds))
    }

    var body: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Body load", point.fraction),
                        series: .value("Substance", item.id),
                    )
                    .foregroundStyle(item.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
            }
            RuleMark(x: .value("Now", Date.now))
                .foregroundStyle(Theme.accent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: 200)
        .chartXSelection(value: $selectedDate)
        .chartXScrollWindow(fullLength: span.length, window: usageChartWindowSeconds, initialX: span.windowStart)
        .chartYScale(domain: 0 ... 1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
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
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
        }
        .chartSummaryAccessibility(label: Text("In your body over time"), value: Text(summary))
    }

    private var summary: String {
        guard !series.isEmpty else { return String(localized: "No data") }
        let parts = series.prefix(4).map { item -> String in
            let current = item.points.last?.amount ?? 0
            return String(localized: "\(item.displayName) now at \(current.doseFormatted) \(item.unit)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scrub readout

/// The tooltip for `chartXSelection`: the estimated real amount of each substance
/// in the body at the scrubbed instant — restoring the magnitude the normalized
/// lines drop.
private struct BodyLoadReadout: View {
    let series: [BodyLoadTrail.Series]
    let date: Date

    var body: some View {
        let rows = series.compactMap { item -> (series: BodyLoadTrail.Series, amount: Double)? in
            guard let point = nearestPoint(in: item) else { return nil }
            return (item, point.amount)
        }
        .filter { $0.amount > 0 }
        .sorted { $0.amount > $1.amount }

        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour()))
                .font(.caption.weight(.semibold))
            ForEach(rows, id: \.series.id) { row in
                HStack(spacing: 5) {
                    Circle()
                        .fill(row.series.color)
                        .frame(width: 6, height: 6)
                    Text(row.series.displayName)
                        .font(.caption2)
                    Spacer(minLength: 8)
                    Text("\(row.amount.doseFormatted) \(row.series.unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            if rows.isEmpty {
                Text("Nothing in your body at this time")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func nearestPoint(in item: BodyLoadTrail.Series) -> BodyLoadTrail.Point? {
        item.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
