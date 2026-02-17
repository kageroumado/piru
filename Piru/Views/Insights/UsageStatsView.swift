import Charts
import SwiftData
import SwiftUI

struct UsageStatsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var timeRange: TimeRange = .thirtyDays

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

    private var filteredEntries: [DoseEntry] {
        guard let days = timeRange.days else { return allEntries }
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86400)
        return allEntries.filter { $0.timestamp >= cutoff }
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
                    }
                }
            }
            .padding()
        }
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

        return VStack(alignment: .leading, spacing: 8) {
            Text("Frequency")
                .font(.headline)

            Chart(top, id: \.key) { item in
                BarMark(
                    x: .value("Count", item.value),
                    y: .value("Substance", item.key)
                )
                .foregroundStyle(colorMap[item.key.lowercased()] ?? Theme.accent)
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 4) {
                    Text("\(item.value)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .frame(height: CGFloat(max(top.count, 1)) * 36)
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
            Text("Activity")
                .font(.headline)

            Chart(data, id: \.key) { item in
                BarMark(
                    x: .value("Date", item.key.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(colorMap[item.key.substance.lowercased()] ?? Theme.accent)
            }
            .frame(height: 180)
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
}
