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

    private var chartWidth: CGFloat {
        let dayCount = Set(data.map { Calendar.current.startOfDay(for: $0.key.date) }).count
        let basePtPerDay: CGFloat = 24
        return max(CGFloat(dayCount) * basePtPerDay * zoom, 300)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Chart(data, id: \.key) { item in
                BarMark(
                    x: .value("Date", item.key.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(colorMap[item.key.substance.lowercased()] ?? .accentColor)
                .cornerRadius(4)
            }
            .frame(width: chartWidth, height: 300)
            .chartPlotStyle { plotArea in
                plotArea.padding(.leading, 4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, Int(3.0 / zoom)))) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
        .frame(height: 320)
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = max(0.5, min(5.0, gestureStartZoom * value.magnification))
                }
                .onEnded { _ in
                    gestureStartZoom = zoom
                }
        )
    }
}
