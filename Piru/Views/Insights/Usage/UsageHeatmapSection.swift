import Charts
import SwiftUI

/// §2 — "when do I tend to use?" A GitHub-style contribution grid (columns are
/// weeks, rows are weekdays) over an hour-of-day histogram.
///
/// The grid is a grid, not a chart, so it is drawn with rectangles rather than
/// Swift Charts; the histogram underneath is a real chart with 24 bins, which
/// is where the old four-bucket "Time of Day" detail moved.
struct UsageHeatmapSection: View {
    let heatmap: UsageHeatmap
    let hours: UsageHourProfile
    let categories: [(categoryIndex: Int, count: Int)]

    @State private var categoryFilter: Int?
    @State private var selectedDay: Date?

    private var accent: Color {
        categoryFilter.map { UsageAxes.category($0).color } ?? Theme.accent
    }

    var body: some View {
        UsageSectionCard(title: "Activity", subtitle: "Which days and hours you log on") {
            if categories.count > 1 {
                UsageCategoryFilterBar(categories: categories, selection: $categoryFilter)
            }

            UsageHeatmapGrid(
                heatmap: heatmap,
                categoryFilter: categoryFilter,
                accent: accent,
                selectedDay: $selectedDay,
            )

            UsageHourHistogram(
                bins: activeBins,
                accent: accent,
                selectedDay: selectedDay,
                onClearDay: { selectedDay = nil },
            )
        }
        .onChange(of: heatmap.weekStarts.first) { selectedDay = nil }
    }

    /// The histogram's data: the selected day's hours if a cell is tapped, else
    /// the whole range — either way narrowed by the category filter.
    private var activeBins: [Int] {
        if let selectedDay, let day = hours.byDay[selectedDay] {
            return day.bins(category: categoryFilter)
        }
        return hours.all.bins(category: categoryFilter)
    }
}

// MARK: - The grid

/// The contribution grid itself: one column per week, seven rows per column,
/// horizontally scrollable and anchored to the most recent week.
private struct UsageHeatmapGrid: View {
    let heatmap: UsageHeatmap
    let categoryFilter: Int?
    let accent: Color
    @Binding var selectedDay: Date?

    /// §2's sizing: ~14 pt cells with 2 pt gutters, which lands 13 columns —
    /// about 90 days — in a phone's width without scrolling.
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: cellSpacing) {
                    // The weekday letters ride inside the scroll content rather
                    // than sitting beside it: a fixed sidebar next to a
                    // horizontal `ScrollView` leaves the grid centered in the
                    // leftover width, which floats a five-column 30D heatmap in
                    // the middle of the card with a hole where it should start.
                    weekdayLabels
                        .padding(.trailing, 4)
                    ForEach(Array(heatmap.weekStarts.enumerated()), id: \.offset) { column, weekStart in
                        VStack(spacing: cellSpacing) {
                            monthLabel(for: column, weekStart: weekStart)
                            ForEach(0 ..< 7, id: \.self) { row in
                                cell(column: column, row: row)
                            }
                        }
                        .id(column)
                    }
                    // No `drawingGroup()` here, despite §2's implementation
                    // note: it rasterizes the subtree into one layer, which
                    // takes the per-cell hit-testing and the per-day VoiceOver
                    // elements with it. A tappable, readable grid is worth more
                    // than the composite. Cost is contained instead by the cells
                    // being plain `RoundedRectangle`s over precomputed counts —
                    // no work in `body` beyond a dictionary read.
                }
                .padding(.vertical, 1)
                .onAppear {
                    // A year of columns opens on the most recent week; a range
                    // that already fits doesn't move.
                    proxy.scrollTo(heatmap.weekStarts.count - 1, anchor: .trailing)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Activity heatmap"))
        .accessibilityHint(Text("Days with entries are listed one by one. Select a day to filter the hour chart below."))
    }

    private var weekdayLabels: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: cellSpacing) {
            Color.clear.frame(height: 11)
            ForEach(Array(heatmap.rowWeekdays.enumerated()), id: \.offset) { row, weekday in
                Group {
                    // Every other row, so seven one-letter labels don't crowd
                    // a 14 pt cell stack.
                    if row.isMultiple(of: 2), symbols.indices.contains(weekday - 1) {
                        Text(symbols[weekday - 1])
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.secondaryLabel)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 14, height: cellSize)
            }
        }
        .accessibilityHidden(true)
    }

    /// A month abbreviation above the first column that starts a new month.
    private func monthLabel(for column: Int, weekStart: Date) -> some View {
        let calendar = Calendar.current
        let previous = column > 0 ? heatmap.weekStarts[column - 1] : nil
        let isNewMonth = previous.map {
            calendar.component(.month, from: $0) != calendar.component(.month, from: weekStart)
        } ?? true
        return Text(isNewMonth ? weekStart.formatted(.dateTime.month(.abbreviated)) : "")
            .font(.system(size: 8))
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize()
            .frame(width: cellSize, height: 11, alignment: .leading)
            .accessibilityHidden(true)
    }

    private func cell(column: Int, row: Int) -> some View {
        let cell = heatmap.cell(column: column, row: row)
        let count = displayCount(cell)
        let isSelected = cell.map { selectedDay == $0.date && $0.total > 0 } ?? false
        return RoundedRectangle(cornerRadius: 3)
            .fill(fill(for: cell, count: count))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let cell, cell.total > 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDay = selectedDay == cell.date ? nil : cell.date
                }
            }
            .accessibilityHidden(count == 0)
            .accessibilityLabel(cell.map { Text($0.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) } ?? Text(""))
            .accessibilityValue(Text("\(count) entries"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The count the cell should render — narrowed to the filtered category
    /// when one is active.
    private func displayCount(_ cell: UsageHeatmapCell?) -> Int {
        guard let cell, cell.inRange else { return 0 }
        guard let categoryFilter else { return cell.total }
        return cell.byCategory[categoryFilter] ?? 0
    }

    private func fill(for cell: UsageHeatmapCell?, count: Int) -> Color {
        guard let cell, cell.inRange else { return .clear }
        guard count > 0 else { return Color(.tertiarySystemFill) }
        let peak = max(heatmap.maxCount, 1)
        // Four visible steps, floored well above zero so a single entry still
        // reads as present rather than as an empty day.
        let fraction = min(1, Double(count) / Double(peak))
        return accent.opacity(0.28 + 0.72 * fraction)
    }
}

// MARK: - Hour histogram

/// Twenty-four bins across the clock. Replaces the old four coarse buckets.
private struct UsageHourHistogram: View {
    let bins: [Int]
    let accent: Color
    let selectedDay: Date?
    let onClearDay: () -> Void

    private struct Bin: Identifiable {
        let hour: Int
        let count: Int
        var id: Int {
            hour
        }

        /// The plotted x. `Double`, not `Int`: the axis domain below is a
        /// `ClosedRange<Double>`, and mixing the two silently produces a chart
        /// with axes and no marks.
        var x: Double {
            Double(hour)
        }
    }

    var body: some View {
        let items = bins.enumerated().map { Bin(hour: $0.offset, count: $0.element) }
        let total = bins.reduce(0, +)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Hour of day")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                if let selectedDay {
                    Button {
                        onClearDay()
                    } label: {
                        HStack(spacing: 3) {
                            Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                    }
                    .accessibilityLabel(Text("Clear selected day"))
                }
            }

            Chart(items) { bin in
                BarMark(
                    x: .value("Hour", bin.x),
                    y: .value("Entries", bin.count),
                    // `.fixed`, not `.ratio`: the x-axis here is continuous
                    // (hours 0–23 as numbers, so the axis can label 0/6/12/18),
                    // and a ratio width has no step to be a ratio *of* — it
                    // resolves to zero and the chart draws axes with no bars.
                    width: .fixed(8),
                )
                .foregroundStyle(accent)
                .cornerRadius(2)
            }
            .frame(height: 110)
            .chartXScale(domain: -0.5 ... 23.5)
            .chartXAxis {
                AxisMarks(values: [0.0, 6.0, 12.0, 18.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.secondaryLabel.opacity(0.5))
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(hourLabel(Int(hour)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartSummaryAccessibility(
                label: Text("Entries by hour of day"),
                value: Text(summary(total: total)),
            )
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let components = DateComponents(hour: hour)
        guard let date = Calendar.current.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    private func summary(total: Int) -> String {
        guard total > 0, let peak = bins.indices.max(by: { bins[$0] < bins[$1] }) else {
            return String(localized: "No entries in this window")
        }
        return String(localized: "\(total) entries, busiest around \(hourLabel(peak))")
    }
}
