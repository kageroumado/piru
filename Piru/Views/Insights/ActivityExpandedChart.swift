import Charts
import SwiftUI

struct ActivityExpandedChart: View {
    let data: [(key: UsageStatsView.DaySubstance, count: Int)]
    let colorMap: [String: Color]
    let maxCount: Int
    let strideComponent: Calendar.Component
    let strideCount: Int
    let dateFormat: Date.FormatStyle

    @State private var zoom: CGFloat = 1.0
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var selectedDay: Date?

    // Aggregate per-day totals for a cleaner look
    private var dailyTotals: [(date: Date, total: Int, substances: [(name: String, count: Int, color: Color)])] {
        let calendar = Calendar.current
        var dayMap: [Date: [String: Int]] = [:]

        for item in data {
            let day = calendar.startOfDay(for: item.key.date)
            dayMap[day, default: [:]][item.key.substance, default: 0] += item.count
        }

        return dayMap.sorted { $0.key < $1.key }.map { day, substances in
            let total = substances.values.reduce(0, +)
            let subs = substances.sorted { $0.value > $1.value }.map { name, count in
                (name: name, count: count, color: colorMap[name.lowercased()] ?? .accentColor)
            }
            return (date: day, total: total, substances: subs)
        }
    }

    private var chartWidth: CGFloat {
        let dayCount = max(dailyTotals.count, 7)
        let ptPerDay: CGFloat = 32 * zoom
        return max(CGFloat(dayCount) * ptPerDay, 300)
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Chart(data, id: \.key) { item in
                        BarMark(
                            x: .value("Date", item.key.date, unit: .day),
                            y: .value("Count", item.count),
                            width: .fixed(max(6, 16 * zoom))
                        )
                        .foregroundStyle(colorMap[item.key.substance.lowercased()] ?? .accentColor)
                        .cornerRadius(3)
                    }
                    .frame(width: chartWidth, height: 260)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .padding(.bottom, 4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                .foregroundStyle(.secondary.opacity(0.3))
                            if let date = value.as(Date.self) {
                                let calendar = Calendar.current
                                let day = calendar.component(.day, from: date)
                                let stride = xAxisStride
                                if day % stride == 0 || day == 1 {
                                    AxisValueLabel {
                                        VStack(spacing: 1) {
                                            Text(date.formatted(.dateTime.day()))
                                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                            Text(date.formatted(.dateTime.month(.abbreviated)))
                                                .font(.system(size: 7, design: .rounded))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                                .foregroundStyle(.secondary.opacity(0.2))
                            AxisValueLabel()
                                .font(.system(size: 9, design: .rounded))
                        }
                    }
                    .chartXSelection(value: $selectedDay)
                    .id("chart")
                }
                .defaultScrollAnchor(.trailing)
            }

            // Selected day detail
            if let day = selectedDay,
               let match = dailyTotals.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                HStack {
                    Text(match.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    ForEach(match.substances, id: \.name) { sub in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(sub.color)
                                .frame(width: 6, height: 6)
                            Text("\(sub.count)")
                                .font(.caption2.weight(.medium))
                        }
                    }
                    Text("· \(match.total) total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .frame(height: selectedDay != nil ? 310 : 280)
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = max(0.5, min(4.0, gestureStartZoom * value.magnification))
                }
                .onEnded { _ in
                    gestureStartZoom = zoom
                }
        )
    }

    private var xAxisStride: Int {
        if zoom > 2.0 { return 1 }
        if zoom > 1.0 { return 2 }
        if dailyTotals.count > 60 { return 7 }
        if dailyTotals.count > 30 { return 3 }
        return 2
    }
}
