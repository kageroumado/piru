import Charts
import SwiftData
import SwiftUI

struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var model = UsageStatsModel()
    @State private var timeRange: TimeRange = .thirtyDays
    @State private var selectedTrendSubstance: String?
    @State private var trendSearch = ""
    @State private var activityExpanded = false
    @State private var selectedCategory: SubstanceCategory?
    @State private var activityCategoryFilter: SubstanceCategory?
    @State private var categoryAngleValue: Int?
    @State private var selectedActivityDay: Date?
    @State private var trendZoom: CGFloat = 1.0
    @State private var trendGestureStartZoom: CGFloat = 1.0
    @State private var availableWidth: CGFloat = 350

    typealias DaySubstance = UsageStatsModel.DaySubstance

    enum TimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "All"
        var id: String {
            rawValue
        }

        var days: Int? {
            switch self {
            case .sevenDays: 7
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .all: nil
            }
        }

        var displayName: LocalizedStringResource {
            switch self {
            case .sevenDays: "7D"
            case .thirtyDays: "30D"
            case .ninetyDays: "90D"
            case .all: "All"
            }
        }
    }

    private func rebuild() {
        model.rebuild(entries: allEntries, colors: substanceColors, rangeDays: timeRange.days)

        // Reset stale category selection if it no longer exists in the data
        if let selected = selectedCategory,
           !model.categoryCounts.contains(where: { $0.category == selected }) {
            selectedCategory = nil
            categoryAngleValue = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allEntries.isEmpty {
                timeRangePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            ScrollView {
                LazyVStack(spacing: 20) {
                    if allEntries.isEmpty {
                        ContentUnavailableView(
                            "No Logged Entries",
                            systemImage: "chart.bar",
                            description: Text("Log some entries to see usage stats."),
                        )
                    } else if !model.filteredEntries.isEmpty {
                        summaryRow
                        frequencyChart
                        timelineChart
                        doseTrendChart
                        timeOfDayChart
                        categoryBreakdownChart
                    }
                }
                .padding()
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                availableWidth = width
            }
        }
        .background(Theme.background)
        .task(id: EntriesFingerprint.make(allEntries, colors: substanceColors)) {
            await Task.yield()
            rebuild()
        }
        .onChange(of: timeRange) { rebuild() }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $timeRange) {
            ForEach(TimeRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let entries = model.filteredEntries
        let totalDays: Double = {
            guard let days = timeRange.days else {
                guard let oldest = entries.last?.timestamp,
                      let newest = entries.first?.timestamp else { return 1 }
                return max(1, newest.timeIntervalSince(oldest) / 86_400 + 1)
            }
            return Double(days)
        }()
        let avgPerDay = Double(entries.count) / totalDays

        return VStack(spacing: 12) {
            HStack {
                statCard(value: "\(entries.count)", label: "Entries")
                statCard(value: "\(model.uniqueSubstances)", label: "Substances")
            }
            HStack {
                statCard(value: String(format: "%.1f", avgPerDay), label: "Per day")
                statCard(value: model.mostLogged, label: "Most logged")
            }
        }
    }

    private func statCard(value: String, label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .themeCard(cornerRadius: 12)
    }

    // MARK: - Frequency Chart

    private var frequencyChart: some View {
        FrequencyChartContent(data: model.frequencyData, total: model.frequencyTotal, colorMap: model.colorMap)
    }

    // MARK: - Timeline Chart

    private var timelineChart: some View {
        let data = model.timelineData
        let uniqueSubstances = model.timelineLegend

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.headline)
                    Text("Entries per day")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activityExpanded.toggle()
                    }
                } label: {
                    Image(systemName: activityExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(activityExpanded ? Text("Collapse Chart") : Text("Expand Chart"))
            }

            if activityExpanded {
                // Category filter chips
                let activityCategories: [(category: SubstanceCategory, count: Int)] = {
                    var counts: [SubstanceCategory: Int] = [:]
                    for item in data {
                        let cat = SubstanceLibrary.lookup(item.key.substance.lowercased())?.category ?? .other
                        counts[cat, default: 0] += item.count
                    }
                    return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
                }()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activityCategoryFilter = nil
                            }
                        } label: {
                            Text("All")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(activityCategoryFilter == nil ? Theme.accent : Color.clear)
                                .foregroundStyle(activityCategoryFilter == nil ? .white : .primary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.quaternary))
                        }
                        ForEach(activityCategories, id: \.category) { item in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activityCategoryFilter = activityCategoryFilter == item.category ? nil : item.category
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(item.category.color)
                                        .frame(width: 6, height: 6)
                                    Text(item.category.displayName)
                                        .font(.caption2.weight(.medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(activityCategoryFilter == item.category ? item.category.color.opacity(0.3) : Color.clear)
                                .foregroundStyle(activityCategoryFilter == item.category ? .white : .primary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.quaternary))
                            }
                        }
                    }
                }

                // Filter chart data and legend by selected category
                let chartData = if let catFilter = activityCategoryFilter {
                    data.filter { (SubstanceLibrary.lookup($0.key.substance.lowercased())?.category ?? .other) == catFilter }
                } else {
                    data
                }
                let chartMax = chartData.map(\.count).max() ?? 1

                // Expanded: scrollable + zoomable chart
                ActivityExpandedChart(
                    data: chartData,
                    colorMap: model.colorMap,
                    maxCount: chartMax,
                    strideComponent: strideComponent,
                    strideCount: strideCount,
                    dateFormat: dateFormat,
                )

                let legendSubstances = if let catFilter = activityCategoryFilter {
                    uniqueSubstances.filter { (SubstanceLibrary.lookup($0.name.lowercased())?.category ?? .other) == catFilter }
                } else {
                    uniqueSubstances
                }

                FlowLayout(spacing: 8) {
                    ForEach(legendSubstances, id: \.name) { sub in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(sub.color)
                                .frame(width: 8, height: 8)
                            Text(sub.name)
                                .font(.caption2)
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                // Compact: aggregated daily totals (1 bar per day for performance)
                Chart(model.dailyTotals, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.count),
                    )
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.horizontal, 12)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: strideComponent, count: strideCount)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Theme.secondaryLabel.opacity(0.6))
                        AxisValueLabel(format: dateFormat)
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartXSelection(value: $selectedActivityDay)

                // Selected day detail
                if let day = selectedActivityDay {
                    let calendar = Calendar.current
                    let dayEntries = data.filter { calendar.isDate($0.key.date, inSameDayAs: day) }
                    if !dayEntries.isEmpty {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            ForEach(dayEntries, id: \.key) { item in
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(model.colorMap[item.key.substance.lowercased()] ?? Theme.accent)
                                        .frame(width: 6, height: 6)
                                    Text("\(item.count)")
                                        .font(.caption2.weight(.medium))
                                }
                            }
                            Text("· \(dayEntries.map(\.count).reduce(0, +)) total")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding()
        .themeCard()
    }

    private var strideComponent: Calendar.Component {
        switch timeRange {
        case .sevenDays: .day
        case .thirtyDays: .weekOfYear
        case .ninetyDays: .month
        case .all: .month
        }
    }

    private var strideCount: Int {
        1
    }

    private var dateFormat: Date.FormatStyle {
        switch timeRange {
        case .sevenDays:
            .dateTime.weekday(.abbreviated)
        case .thirtyDays:
            .dateTime.month(.abbreviated).day()
        case .ninetyDays, .all:
            .dateTime.month(.abbreviated)
        }
    }

    // MARK: - Dose Trends

    @ViewBuilder
    private var doseTrendChart: some View {
        let substances = model.trendSubstances
        if !substances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dose Trends")
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.secondaryLabel)
                        .font(.subheadline)
                    TextField("Search substances...", text: $trendSearch)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                }
                .padding(8)
                .themeCapsule()

                let names = substances.map(\.name)
                let filtered = trendSearch.isEmpty
                    ? names
                    : names.filter { $0.localizedCaseInsensitiveContains(trendSearch) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filtered, id: \.self) { name in
                            let isSelected = selectedTrendSubstance == name
                            Button {
                                selectedTrendSubstance = isSelected ? nil : name
                            } label: {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        isSelected
                                            ? (model.colorMap[name.lowercased()] ?? Theme.accent)
                                            : Color.clear,
                                    )
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(.quaternary))
                            }
                        }
                    }
                }

                if let selected = selectedTrendSubstance,
                   names.contains(selected) {
                    let (data, unit, weekly, maLookup, mixedUnits) = model.trendData(for: selected, zoom: trendZoom)
                    let color = model.colorMap[selected.lowercased()] ?? Theme.accent

                    if data.isEmpty {
                        Text("No entries for \(selected)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } else {
                        let trendChartWidth = max(CGFloat(data.count) * 56 * trendZoom, availableWidth - 64)
                        let pointSpacing = data.count > 1 ? trendChartWidth / CGFloat(data.count - 1) : trendChartWidth
                        let strideN = max(1, Int(ceil(90 / pointSpacing)))

                        DoseTrendInnerChart(
                            data: data,
                            maLookup: maLookup,
                            color: color,
                            unit: unit,
                            weekly: weekly,
                            mixedUnits: mixedUnits,
                            chartWidth: trendChartWidth,
                            strideN: strideN,
                            zoom: $trendZoom,
                            gestureStartZoom: $trendGestureStartZoom,
                        )
                    }
                } else {
                    Text("Select a substance to see dose trends")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
            .padding()
            .themeCard()
        }
    }

    // MARK: - Time of Day

    private var timeOfDayChart: some View {
        TimeOfDayChartContent(buckets: model.timeOfDayBuckets)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownChart: some View {
        CategoryBreakdownContent(
            categoryCounts: model.categoryCounts,
            substanceCounts: model.categorySubstanceCounts,
            colorMap: model.colorMap,
            selectedCategory: $selectedCategory,
            categoryAngleValue: $categoryAngleValue,
        )
    }
}

// MARK: - Extracted Chart Views

// Each struct has its own `body`, so SwiftUI type-checks them independently.

private struct FrequencyChartContent: View {
    let data: [(substance: String, count: Int)]
    let total: Int
    let colorMap: [String: Color]

    var body: some View {
        let maxCount = data.first?.count ?? 1

        VStack(alignment: .leading, spacing: 12) {
            Text("Frequency")
                .font(.headline)

            ForEach(data, id: \.substance) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.substance)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            let fraction = CGFloat(item.count) / CGFloat(maxCount)
                            Capsule()
                                .fill(colorMap[item.substance.lowercased()] ?? Theme.accent)
                                .frame(width: max(fraction * geo.size.width, 8))
                        }
                        .frame(height: 12)
                        let pct = total > 0 ? Int(round(Double(item.count) / Double(total) * 100)) : 0
                        Text("\(item.count) · \(pct)%")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(minWidth: 48, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .themeCard()
    }
}

private struct TimeOfDayChartContent: View {
    let buckets: [Int]

    private struct TimeBucket: Identifiable {
        let name: String
        let count: Int
        let color: Color
        var id: String {
            name
        }
    }

    var body: some View {
        let total = buckets.reduce(0, +)
        let items = [
            TimeBucket(name: String(localized: "Morning\n6–12"), count: buckets[0], color: .orange),
            TimeBucket(name: String(localized: "Afternoon\n12–18"), count: buckets[1], color: .yellow),
            TimeBucket(name: String(localized: "Evening\n18–0"), count: buckets[2], color: .indigo),
            TimeBucket(name: String(localized: "Night\n0–6"), count: buckets[3], color: .blue),
        ]

        VStack(alignment: .leading, spacing: 8) {
            Text("Time of Day")
                .font(.headline)

            Chart(items) { bucket in
                BarMark(
                    x: .value("Time", bucket.name),
                    y: .value("Count", bucket.count),
                )
                .foregroundStyle(bucket.color)
                .cornerRadius(6)
                .annotation(position: .top, spacing: 4) {
                    if bucket.count > 0 {
                        let pct = total > 0 ? Int(round(Double(bucket.count) / Double(total) * 100)) : 0
                        Text("\(bucket.count) · \(pct)%")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            .frame(height: 180)
            .chartPlotStyle { plotArea in
                plotArea.padding(.horizontal, 12)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(0.6))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
        .padding()
        .themeCard()
    }
}

private struct DoseTrendInnerChart: View {
    let data: [UsageStatsModel.TrendDataPoint]
    let maLookup: [Date: Double]
    let color: Color
    let unit: String
    let weekly: Bool
    let mixedUnits: Bool
    let chartWidth: CGFloat
    let strideN: Int
    @Binding var zoom: CGFloat
    @Binding var gestureStartZoom: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let yMax = data.map(\.total).max() ?? 1
            let yStep: Double = {
                guard yMax > 0 else { return 1 }
                let rough = yMax / 4
                let mag = pow(10, floor(log10(rough)))
                let norm = rough / mag
                if norm <= 1 { return mag }
                if norm <= 2 { return 2 * mag }
                if norm <= 5 { return 5 * mag }
                return 10 * mag
            }()

            Chart(data) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Dose", point.total),
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                    y: .value("Dose", point.total),
                    series: .value("S", "data"),
                )
                .foregroundStyle(color.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                    y: .value("Dose", point.total),
                )
                .foregroundStyle(color)
                .symbolSize(30)

                if let maValue = maLookup[point.date] {
                    LineMark(
                        x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                        y: .value("Avg", maValue),
                        series: .value("S", "avg"),
                    )
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            .frame(width: chartWidth)
            .chartYScale(domain: 0 ... yMax * 1.08)
            .chartPlotStyle { plotArea in
                plotArea.frame(height: 220)
            }
            .chartXAxis {
                let comp: Calendar.Component = weekly ? .weekOfYear : .day
                AxisMarks(values: .stride(by: comp, count: strideN)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(0.6))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .stride(by: yStep)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(0.6))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxisLabel(position: .trailing) {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = max(0.5, min(6.0, gestureStartZoom * value.magnification))
                    }
                    .onEnded { _ in
                        gestureStartZoom = zoom
                    },
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.trailing)

        if weekly {
            Text("Daily average per week")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }

        if !maLookup.isEmpty {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(color.opacity(0.35))
                    .frame(width: 14, height: 1.5)
                    .overlay {
                        Rectangle()
                            .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: 14, height: 1.5)
                    }
                Text("\(weekly ? 4 : 7)-\(weekly ? "wk" : "day") avg")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }

        if mixedUnits {
            Text("Showing \(unit) entries only — other units excluded")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}

private struct CategoryBreakdownContent: View {
    let categoryCounts: [(category: SubstanceCategory, count: Int)]
    let substanceCounts: [SubstanceCategory: [(substance: String, count: Int)]]
    let colorMap: [String: Color]
    @Binding var selectedCategory: SubstanceCategory?
    @Binding var categoryAngleValue: Int?

    var body: some View {
        let sorted = categoryCounts
        let total = sorted.reduce(0) { $0 + $1.count }

        VStack(alignment: .leading, spacing: 8) {
            if let selected = selectedCategory {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedCategory = nil
                            categoryAngleValue = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Back"))
                    Text(selected.displayName)
                        .font(.headline)
                }
            } else {
                Text("Categories")
                    .font(.headline)
            }

            if sorted.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            } else if let selected = selectedCategory {
                drillDownContent(category: selected, total: total)
            } else {
                Chart(sorted, id: \.category) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.618),
                        angularInset: 1.5,
                    )
                    .foregroundStyle(item.category.color)
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .chartLegend(.hidden)
                .chartAngleSelection(value: $categoryAngleValue)
                .onChange(of: categoryAngleValue) { _, newValue in
                    if let newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedCategory = findCategory(for: newValue, in: sorted)
                        }
                    }
                }

                FlowLayout(spacing: 8) {
                    ForEach(sorted, id: \.category) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedCategory = item.category
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(item.category.color)
                                    .frame(width: 8, height: 8)
                                Text(item.category.displayName)
                                    .font(.caption2)
                                Text("\(item.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryLabel)
                                if total > 0 {
                                    Text("(\(Int(round(Double(item.count) / Double(total) * 100)))%)")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .themeCard()
    }

    @ViewBuilder
    private func drillDownContent(category: SubstanceCategory, total _: Int) -> some View {
        let counts = substanceCounts[category] ?? []
        let drillTotal = counts.reduce(0) { $0 + $1.count }

        if counts.isEmpty {
            Text("No data for \(String(localized: category.displayName))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            Chart(counts, id: \.substance) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.5,
                )
                .foregroundStyle(colorMap[item.substance.lowercased()] ?? category.color)
                .cornerRadius(4)
            }
            .frame(height: 200)
            .chartLegend(.hidden)

            FlowLayout(spacing: 8) {
                ForEach(counts, id: \.substance) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorMap[item.substance.lowercased()] ?? category.color)
                            .frame(width: 8, height: 8)
                        Text(item.substance)
                            .font(.caption2)
                        Text("\(item.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                        if drillTotal > 0 {
                            Text("(\(Int(round(Double(item.count) / Double(drillTotal) * 100)))%)")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
            }
        }
    }

    private func findCategory(for value: Int, in data: [(category: SubstanceCategory, count: Int)]) -> SubstanceCategory? {
        var cumulative = 0
        for item in data {
            cumulative += item.count
            if value <= cumulative {
                return item.category
            }
        }
        return data.last?.category
    }
}
