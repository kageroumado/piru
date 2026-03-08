import Charts
import SwiftData
import SwiftUI

struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var timeRange: TimeRange = .thirtyDays
    @State private var selectedTrendSubstance: String?
    @State private var trendSearch = ""
    @State private var activityExpanded = false
    @State private var selectedCategory: SubstanceCategory?
    @State private var activityCategoryFilter: SubstanceCategory?
    @State private var categoryAngleValue: Int?
    @State private var filteredEntries: [DoseEntry] = []
    @State private var selectedActivityDay: Date?
    @State private var selectedTrendDay: Date?
    @State private var trendZoom: CGFloat = 1.0
    @State private var trendGestureStartZoom: CGFloat = 1.0

    struct DaySubstance: Hashable {
        let date: Date
        let substance: String
    }

    struct TrendDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let total: Double
    }

    enum TimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "All"
        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .sevenDays: 7
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .all: nil
            }
        }
    }

    private func rebuildFilteredEntries() {
        if let days = timeRange.days {
            let cutoff = Date.now.addingTimeInterval(-Double(days) * 86400)
            filteredEntries = allEntries.filter { $0.timestamp >= cutoff }
        } else {
            filteredEntries = allEntries
        }
        cachedColorMap = substanceColors.colorMap
    }

    @State private var cachedColorMap: [String: Color] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if !allEntries.isEmpty {
                timeRangePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            ScrollView {
                VStack(spacing: 20) {
                    if allEntries.isEmpty {
                        ContentUnavailableView(
                            "No Logged Entries",
                            systemImage: "chart.bar",
                            description: Text("Log some entries to see usage stats.")
                        )
                    } else if !filteredEntries.isEmpty {
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
        }
        .task { rebuildFilteredEntries() }
        .onChange(of: timeRange) { rebuildFilteredEntries() }
        .onChange(of: allEntries.count) { rebuildFilteredEntries() }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $timeRange) {
            ForEach(TimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let entries = filteredEntries
        let uniqueCount = Set(entries.map { $0.substance.lowercased() }).count
        let totalDays: Double = {
            guard let days = timeRange.days else {
                guard let first = entries.last?.timestamp else { return 1 }
                return max(1, Date.now.timeIntervalSince(first) / 86400)
            }
            return Double(days)
        }()
        let avgPerDay = Double(entries.count) / totalDays
        let mostLogged: String = {
            var counts: [String: Int] = [:]
            for entry in entries { counts[entry.substance, default: 0] += 1 }
            return counts.max(by: { $0.value < $1.value })?.key ?? "—"
        }()

        return VStack(spacing: 12) {
            HStack {
                statCard(value: "\(entries.count)", label: "Entries")
                statCard(value: "\(uniqueCount)", label: "Substances")
            }
            HStack {
                statCard(value: String(format: "%.1f", avgPerDay), label: "Per day")
                statCard(value: mostLogged, label: "Most logged")
            }
        }
    }

    private func statCard(value: String, label: String) -> some View {
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
        let entries = filteredEntries
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.substance, default: 0] += 1 }
        let sorted = counts.sorted { $0.value > $1.value }
        let top = Array(sorted.prefix(10))

        let maxCount = top.first?.value ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("Frequency")
                .font(.headline)

            ForEach(top, id: \.key) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.key)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            let fraction = CGFloat(item.value) / CGFloat(maxCount)
                            Capsule()
                                .fill(cachedColorMap[item.key.lowercased()] ?? Theme.accent)
                                .frame(width: max(fraction * geo.size.width, 8))
                        }
                        .frame(height: 12)
                        Text("\(item.value)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(width: 24, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Timeline Chart

    private var timelineChart: some View {
        let entries = filteredEntries
        let calendar = Calendar.current

        // Group entries by day and substance
        var buckets: [DaySubstance: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            buckets[DaySubstance(date: day, substance: entry.substance), default: 0] += 1
        }

        let data = buckets.map { (key: $0.key, count: $0.value) }
            .sorted { $0.key.date < $1.key.date }

        let uniqueSubstances: [(name: String, color: Color)] = {
            var seen = Set<String>()
            var result: [(String, Color)] = []
            for item in data {
                let name = item.key.substance
                if seen.insert(name.lowercased()).inserted {
                    result.append((name, cachedColorMap[name.lowercased()] ?? Theme.accent))
                }
            }
            return result.sorted { $0.0 < $1.0 }
        }()

        _ = data.map(\.count).max() ?? 1

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activityExpanded.toggle()
                    }
                } label: {
                    Image(systemName: activityExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
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
                                    Text(item.category.rawValue)
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
                    colorMap: cachedColorMap,
                    maxCount: chartMax,
                    strideComponent: strideComponent,
                    strideCount: strideCount,
                    dateFormat: dateFormat
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
                // Compact: fixed chart
                Chart(data, id: \.key) { item in
                    BarMark(
                        x: .value("Date", item.key.date, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(cachedColorMap[item.key.substance.lowercased()] ?? Theme.accent)
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
                                        .fill(cachedColorMap[item.key.substance.lowercased()] ?? Theme.accent)
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

    private var strideCount: Int { 1 }

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

    /// Substances with 2+ entries on 2+ different days within the selected time range
    private var trendSubstances: [(name: String, count: Int)] {
        let calendar = Calendar.current

        var substanceEntries: [String: [DoseEntry]] = [:]
        for entry in filteredEntries {
            substanceEntries[entry.substance, default: []].append(entry)
        }

        var result: [(name: String, count: Int)] = []
        for (name, sEntries) in substanceEntries {
            guard sEntries.count >= 2 else { continue }
            let days = Set(sEntries.map { calendar.startOfDay(for: $0.timestamp) })
            guard days.count >= 2 else { continue }
            result.append((name: name, count: sEntries.count))
        }

        return result.sorted { $0.count > $1.count }
    }

    /// Build trend data from filtered entries for a substance, auto-aggregating to daily averages per week if span exceeds threshold.
    /// The threshold scales with zoom — zooming in deep enough reveals individual daily data points.
    private func trendData(for substance: String) -> (points: [TrendDataPoint], unit: String, weekly: Bool) {
        let entries = filteredEntries
            .filter { $0.substance == substance }
            .sorted { $0.timestamp < $1.timestamp }

        guard !entries.isEmpty else { return ([], "mg", false) }

        let calendar = Calendar.current
        let unit = entries.first?.unit ?? "mg"

        let span = (entries.last?.timestamp.timeIntervalSince(entries.first?.timestamp ?? .now) ?? 0) / 86400
        let weekly = span > 90 * Double(trendZoom)

        var buckets: [Date: Double] = [:]
        for entry in entries {
            let key: Date
            if weekly {
                key = calendar.dateInterval(of: .weekOfYear, for: entry.timestamp)?.start
                    ?? calendar.startOfDay(for: entry.timestamp)
            } else {
                key = calendar.startOfDay(for: entry.timestamp)
            }
            buckets[key, default: 0] += entry.amount
        }

        // When aggregating weekly, convert totals to daily averages
        if weekly {
            let now = Date.now
            for (weekStart, total) in buckets {
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                // Partial weeks at the edges get fewer days
                let days = max(1, calendar.dateComponents([.day], from: weekStart, to: min(weekEnd, now)).day ?? 7)
                buckets[weekStart] = total / Double(days)
            }
        }

        let points = buckets.map { TrendDataPoint(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }

        return (points, unit, weekly)
    }

    @ViewBuilder
    private var doseTrendChart: some View {
        let substances = trendSubstances
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
                                selectedTrendDay = nil
                            } label: {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        isSelected
                                            ? (cachedColorMap[name.lowercased()] ?? Theme.accent)
                                            : Color.clear
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
                    let (data, unit, weekly) = trendData(for: selected)
                    let color = cachedColorMap[selected.lowercased()] ?? Theme.accent

                    if data.isEmpty {
                        Text("No entries for \(selected)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } else {
                        let trendChartWidth = max(CGFloat(data.count) * 56 * trendZoom, UIScreen.main.bounds.width - 64)
                        let visibleLabelCount = max(3, Int(8 / trendZoom))
                        let strideN = weekly ? max(1, visibleLabelCount / 4) : max(1, data.count / visibleLabelCount)

                        ScrollView(.horizontal, showsIndicators: false) {
                            Chart(data) { point in
                                BarMark(
                                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                                    y: .value("Dose", point.total),
                                    width: .fixed(max(4, 8 * trendZoom))
                                )
                                .foregroundStyle(color.opacity(0.6))
                                .cornerRadius(4)

                                LineMark(
                                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                                    y: .value("Dose", point.total)
                                )
                                .foregroundStyle(color.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.monotone)

                                PointMark(
                                    x: .value("Date", point.date, unit: weekly ? .weekOfYear : .day),
                                    y: .value("Dose", point.total)
                                )
                                .foregroundStyle(color)
                                .symbolSize(20)
                            }
                            .frame(width: trendChartWidth, height: 280)
                            .chartPlotStyle { plotArea in
                                plotArea
                                    .padding(.top, 16)
                                    .padding(.bottom, 24)
                                    .padding(.leading, 4)
                                    .padding(.trailing, 24)
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
                                AxisMarks(position: .trailing) { _ in
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
                                        trendZoom = max(0.5, min(6.0, trendGestureStartZoom * value.magnification))
                                    }
                                    .onEnded { _ in
                                        trendGestureStartZoom = trendZoom
                                    }
                            )
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .defaultScrollAnchor(.trailing)
                        .frame(height: 280)

                        if weekly {
                            Text("Daily average per week")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
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


    @ViewBuilder
    private func trendDayDetail(substance: String, date: Date, total: Double, unit: String, color: Color) -> some View {
        let dayEntries = allEntries
            .filter { $0.substance == substance && Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f %@ total", total, unit))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
            }

            if !dayEntries.isEmpty {
                Divider()
                ForEach(dayEntries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(width: 52, alignment: .leading)
                        Text(String(format: "%.1f %@", entry.amount, entry.unit))
                            .font(.caption.weight(.semibold))
                        Text("\u{00B7} \(entry.route.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                        if let notes = entry.notes, !notes.isEmpty {
                            Spacer()
                            Text(notes)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .themeCard(cornerRadius: 10)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Time of Day

    private var timeOfDayChart: some View {
        let entries = filteredEntries
        let calendar = Calendar.current

        var morning = 0, afternoon = 0, evening = 0, night = 0

        for entry in entries {
            let hour = calendar.component(.hour, from: entry.timestamp)
            switch hour {
            case 6..<12: morning += 1
            case 12..<18: afternoon += 1
            case 18..<24: evening += 1
            default: night += 1
            }
        }

        struct TimeBucket: Identifiable {
            let name: String
            let count: Int
            let color: Color
            var id: String { name }
        }

        let buckets = [
            TimeBucket(name: "Morning\n6–12", count: morning, color: .orange),
            TimeBucket(name: "Afternoon\n12–18", count: afternoon, color: .yellow),
            TimeBucket(name: "Evening\n18–0", count: evening, color: .indigo),
            TimeBucket(name: "Night\n0–6", count: night, color: .blue),
        ]

        return VStack(alignment: .leading, spacing: 8) {
            Text("Time of Day")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.name),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(bucket.color)
                .cornerRadius(6)
                .annotation(position: .top, spacing: 4) {
                    if bucket.count > 0 {
                        Text("\(bucket.count)")
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

    // MARK: - Category Breakdown

    private var categoryBreakdownChart: some View {
        let entries = filteredEntries

        var categoryCounts: [SubstanceCategory: Int] = [:]
        for entry in entries {
            if let substance = SubstanceLibrary.lookup(entry.substance.lowercased()) {
                categoryCounts[substance.category, default: 0] += 1
            } else {
                categoryCounts[.other, default: 0] += 1
            }
        }

        let sorted = categoryCounts
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value) }

        let total = sorted.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: 8) {
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
                    }
                    Text(selected.rawValue)
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
                categoryDrillDownContent(category: selected, entries: entries)
            } else {
                Chart(sorted, id: \.category) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.618),
                        angularInset: 1.5
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
                                Text(item.category.rawValue)
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
    private func categoryDrillDownContent(category: SubstanceCategory, entries: [DoseEntry]) -> some View {
        let substanceCounts: [(substance: String, count: Int)] = {
            var counts: [String: Int] = [:]
            for entry in entries {
                let sub = SubstanceLibrary.lookup(entry.substance.lowercased())
                let cat = sub?.category ?? .other
                if cat == category {
                    counts[entry.substance, default: 0] += 1
                }
            }
            return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        }()

        let drillTotal = substanceCounts.reduce(0) { $0 + $1.count }

        Chart(substanceCounts, id: \.substance) { item in
            SectorMark(
                angle: .value("Count", item.count),
                innerRadius: .ratio(0.618),
                angularInset: 1.5
            )
            .foregroundStyle(cachedColorMap[item.substance.lowercased()] ?? category.color)
            .cornerRadius(4)
        }
        .frame(height: 200)
        .chartLegend(.hidden)

        FlowLayout(spacing: 8) {
            ForEach(substanceCounts, id: \.substance) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(cachedColorMap[item.substance.lowercased()] ?? category.color)
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
