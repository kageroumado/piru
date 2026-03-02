import Charts
import SwiftData
import SwiftUI

struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var timeRange: TimeRange = .thirtyDays
    @State private var selectedTrendSubstance: String?
    @State private var activityExpanded = false
    @State private var filteredEntries: [DoseEntry] = []

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
        guard let days = timeRange.days else {
            filteredEntries = allEntries
            return
        }
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86400)
        filteredEntries = allEntries.filter { $0.timestamp >= cutoff }
    }

    private var colorMap: [String: Color] {
        substanceColors.colorMap
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "No Logged Entries",
                        systemImage: "chart.bar",
                        description: Text("Log some entries to see usage stats.")
                    )
                } else {
                    timeRangePicker
                    summaryRow
                    if !filteredEntries.isEmpty {
                        frequencyChart
                        timelineChart
                        doseTrendChart
                        timeOfDayChart
                        categoryBreakdownChart
                    }
                }
            }
            .padding()
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            let fraction = CGFloat(item.value) / CGFloat(maxCount)
                            Capsule()
                                .fill(colorMap[item.key.lowercased()] ?? Theme.accent)
                                .frame(width: max(fraction * geo.size.width, 8))
                        }
                        .frame(height: 12)
                        Text("\(item.value)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Timeline Chart

    private var timelineChart: some View {
        let entries = filteredEntries
        let calendar = Calendar.current

        // Group entries by day and substance
        struct DaySubstance: Hashable {
            let date: Date
            let substance: String
        }

        var buckets: [DaySubstance: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            buckets[DaySubstance(date: day, substance: entry.substance), default: 0] += 1
        }

        let data = buckets.map { (key: $0.key, count: $0.value) }
            .sorted { $0.key.date < $1.key.date }

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
                        .foregroundStyle(.secondary)
                }
            }

            Chart(data, id: \.key) { item in
                BarMark(
                    x: .value("Date", item.key.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(colorMap[item.key.substance.lowercased()] ?? Theme.accent)
                .cornerRadius(4)
            }
            .frame(height: activityExpanded ? 360 : 180)
            .chartPlotStyle { plotArea in
                plotArea.padding(.leading, 8)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: strideComponent, count: strideCount)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: dateFormat)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    private var uniqueSubstances: [String] {
        let entries = filteredEntries
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            if seen.insert(key).inserted {
                result.append(entry.substance)
            }
        }
        return result.sorted()
    }

    @ViewBuilder
    private var doseTrendChart: some View {
        let substances = uniqueSubstances
        if !substances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dose Trends")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(substances, id: \.self) { name in
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
                                            ? (colorMap[name.lowercased()] ?? Theme.accent)
                                            : Color.clear
                                    )
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(.quaternary))
                            }
                        }
                    }
                }

                if let selected = selectedTrendSubstance {
                    let data = filteredEntries
                        .filter { $0.substance == selected }
                        .sorted { $0.timestamp < $1.timestamp }
                    let color = colorMap[selected.lowercased()] ?? Theme.accent

                    if data.isEmpty {
                        Text("No entries for \(selected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(data) { entry in
                            LineMark(
                                x: .value("Date", entry.timestamp),
                                y: .value("Dose", entry.amount)
                            )
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", entry.timestamp),
                                y: .value("Dose", entry.amount)
                            )
                            .foregroundStyle(color)
                            .symbolSize(30)
                        }
                        .frame(height: 180)
            .chartPlotStyle { plotArea in
                plotArea.padding(.leading, 8)
            }
                        .chartYAxisLabel(data.first?.unit ?? "mg")
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                    .foregroundStyle(.secondary.opacity(0.3))
                                AxisValueLabel()
                                    .font(.caption2)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                    .foregroundStyle(.secondary.opacity(0.3))
                                AxisValueLabel()
                                    .font(.caption2)
                            }
                        }
                    }
                } else {
                    Text("Select a substance to see dose trends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 180)
            .chartPlotStyle { plotArea in
                plotArea.padding(.leading, 8)
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
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
            Text("Categories")
                .font(.headline)

            if sorted.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(sorted, id: \.category) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.618),
                        angularInset: 1.5
                    )
                    .foregroundStyle(colorForCategory(item.category))
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .chartLegend(.hidden)

                FlowLayout(spacing: 8) {
                    ForEach(sorted, id: \.category) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForCategory(item.category))
                                .frame(width: 8, height: 8)
                            Text(item.category.rawValue)
                                .font(.caption2)
                            Text("\(item.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if total > 0 {
                                Text("(\(Int(round(Double(item.count) / Double(total) * 100)))%)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func colorForCategory(_ category: SubstanceCategory) -> Color {
        switch category {
        case .stimulant: .orange
        case .psychedelic: .purple
        case .dissociative: .cyan
        case .opioid: .red
        case .benzodiazepine: .blue
        case .gabapentinoid: .indigo
        case .empathogen: .pink
        case .cannabinoid: .green
        case .nootropic: .teal
        case .depressant: .gray
        case .antidepressant: .yellow
        case .antipsychotic: .mint
        case .analgesic: .brown
        case .antihistamine: .secondary
        case .supplement: .green.opacity(0.7)
        case .other: .secondary
        }
    }
}
