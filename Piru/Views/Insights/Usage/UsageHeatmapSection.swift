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
    @State private var metric: UsageRankMetric = .entries

    private var accent: Color {
        categoryFilter.map { UsageAxes.category($0).color } ?? Theme.accent
    }

    var body: some View {
        UsageSectionCard(title: "Activity", subtitle: subtitle) {
            metricPicker
            if categories.count > 1 {
                UsageCategoryFilterBar(categories: categories, selection: $categoryFilter)
            }

            UsageHeatmapGrid(
                heatmap: heatmap,
                categoryFilter: categoryFilter,
                metric: metric,
                accent: accent,
                selectedDay: $selectedDay,
            )

            UsageHourHistogram(
                bins: activeBins,
                metric: metric,
                accent: accent,
                selectedDay: selectedDay,
                onClearDay: { selectedDay = nil },
            )
        }
        .onChange(of: heatmap.weekStarts.first) { selectedDay = nil }
    }

    private var metricPicker: some View {
        Picker("Measure", selection: $metric) {
            Text("Entries").tag(UsageRankMetric.entries)
            Text("Common doses").tag(UsageRankMetric.commonDoses)
        }
        .pickerStyle(.segmented)
    }

    private var subtitle: LocalizedStringKey {
        metric == .commonDoses ? "Which days and hours, by common-dose units" : "Which days and hours you log on"
    }

    /// The histogram's data in the active metric: the selected day's hours if a
    /// cell is tapped, else the whole range — either way narrowed by the filter.
    private var activeBins: [Double] {
        let source = selectedDay.flatMap { hours.byDay[$0] } ?? hours.all
        return metric == .commonDoses
            ? source.commonBins(category: categoryFilter)
            : source.bins(category: categoryFilter).map(Double.init)
    }
}

// MARK: - The grid

/// The contribution grid itself: one column per week, seven rows per column.
///
/// GitHub-style: the grid **fills the card width**. A short range (a few weeks of
/// data) is padded on the left with earlier week columns so the block spans the
/// card instead of floating in the top-left; a long range keeps a fixed cell and
/// scrolls, anchored to the most recent week. Every past day is a square —
/// colored by intensity when something was logged, gray when nothing was — so an
/// empty stretch reads as a real quiet run, not a hole. Only future days (the
/// rest of the current week) stay blank.
private struct UsageHeatmapGrid: View {
    let heatmap: UsageHeatmap
    let categoryFilter: Int?
    let metric: UsageRankMetric
    let accent: Color
    @Binding var selectedDay: Date?

    /// Width of the whole grid area (card content width). Measured on the outer
    /// container — not the ScrollView, whose width feeds back through its content.
    @State private var containerWidth: CGFloat = 0

    private let cellSpacing: CGFloat = 3
    /// The cell edge a filled grid aims for; the actual size stretches a little
    /// past this to divide the width evenly, and holds here when scrolling.
    private let baseCell: CGFloat = 15
    /// Width of the leading weekday-label sidebar — wide enough for a three-letter
    /// abbreviation ("Wed") rather than an ambiguous single letter.
    private let labelWidth: CGFloat = 30

    var body: some View {
        let layout = layout(for: containerWidth)
        // The weekday labels are a *fixed* sidebar, outside the ScrollView: the
        // grid opens scrolled to the most recent week, and labels that rode inside
        // the scroll content scrolled off the leading edge with it. The grid always
        // fills or overflows the remaining width, so the old "fixed sidebar floats
        // a narrow grid" worry no longer applies.
        HStack(alignment: .top, spacing: cellSpacing) {
            weekdayLabels(cellSize: layout.cell)
                .frame(width: labelWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(Array(layout.weekStarts.enumerated()), id: \.offset) { column, weekStart in
                            VStack(spacing: cellSpacing) {
                                monthLabel(weekStarts: layout.weekStarts, column: column, weekStart: weekStart, cellSize: layout.cell)
                                ForEach(0 ..< 7, id: \.self) { row in
                                    cell(weekStart: weekStart, row: row, layout: layout)
                                }
                            }
                            .id(column)
                        }
                    }
                    .padding(.vertical, 1)
                    .onAppear {
                        // A year of columns opens on the most recent week; a range
                        // that already fills the width doesn't move.
                        proxy.scrollTo(layout.weekStarts.count - 1, anchor: .trailing)
                    }
                }
            }
            // Pin the scroll viewport to the exact remaining width. Without it the
            // ScrollView's width is inferred from its (wide) content, which pushed
            // the grid past the card and floated the sidebar inward.
            .frame(width: max(0, containerWidth - labelWidth - cellSpacing))
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Activity heatmap"))
        .accessibilityHint(Text("Days with entries are listed one by one. Select a day to filter the hour chart below."))
    }

    // MARK: Layout

    /// The columns to draw and the cell size, resolved against the available
    /// width. Short ranges gain leading gray weeks and a slightly larger cell to
    /// fill the card; long ranges keep ``baseCell`` and scroll.
    private struct GridLayout {
        let weekStarts: [Date]
        let cell: CGFloat
        /// Session-day start → its cell, for an O(1) lookup from any drawn day.
        let cellByDate: [Date: UsageHeatmapCell]
        /// The most recent day inside the selected range — days past it are the
        /// future and stay blank rather than gray.
        let lastInRange: Date
    }

    private func layout(for width: CGFloat) -> GridLayout {
        let cellByDate = Dictionary(heatmap.cells.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let lastInRange = heatmap.cells.filter(\.inRange).map(\.date).max() ?? .distantPast
        let actual = heatmap.weekStarts

        // Before the first geometry pass, draw the range's own weeks at the base
        // size; the measured pass immediately refines it. `width` is the whole
        // grid area; the fixed sidebar and its gutter come off the top.
        guard width > labelWidth + baseCell, !actual.isEmpty else {
            return GridLayout(weekStarts: actual, cell: baseCell, cellByDate: cellByDate, lastInRange: lastInRange)
        }

        let available = width - labelWidth - cellSpacing
        let fit = max(1, Int((available + cellSpacing) / (baseCell + cellSpacing)))
        guard actual.count < fit, let first = actual.first else {
            // Already fills (or overflows) the width — fixed cell, scrollable.
            return GridLayout(weekStarts: actual, cell: baseCell, cellByDate: cellByDate, lastInRange: lastInRange)
        }

        // Pad on the left with empty earlier weeks to reach the fill count, and
        // divide the width evenly so the block spans the card exactly.
        let calendar = Calendar.current
        let padded = stride(from: fit - actual.count, through: 1, by: -1)
            .compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: first) }
        let weekStarts = padded + actual
        let cell = (available - CGFloat(weekStarts.count - 1) * cellSpacing) / CGFloat(weekStarts.count)
        return GridLayout(weekStarts: weekStarts, cell: cell, cellByDate: cellByDate, lastInRange: lastInRange)
    }

    // MARK: Cells

    private func cell(weekStart: Date, row: Int, layout: GridLayout) -> some View {
        let day = dayDate(weekStart: weekStart, row: row)
        let cellData = layout.cellByDate[day]
        let value = displayValue(cellData)
        let isFuture = day > layout.lastInRange
        let isSelected = cellData.map { selectedDay == $0.date && value > 0 } ?? false
        return RoundedRectangle(cornerRadius: 3)
            .fill(fill(value: value, isFuture: isFuture))
            .frame(width: layout.cell, height: layout.cell)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let cellData, value > 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDay = selectedDay == cellData.date ? nil : cellData.date
                }
            }
            .accessibilityHidden(value == 0)
            .accessibilityLabel(cellData.map { Text($0.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) } ?? Text(""))
            .accessibilityValue(Text(valueLabel(cellData)))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The active metric's spoken value for a cell.
    private func valueLabel(_ cell: UsageHeatmapCell?) -> String {
        switch metric {
        case .entries:
            return String(localized: "\(cell?.total ?? 0) entries")
        case .commonDoses:
            let v = displayValue(cell).formatted(.number.precision(.fractionLength(0 ... 1)))
            return String(localized: "\(v) common-dose units")
        }
    }

    /// The session-day start a `(weekStart, row)` cell stands for. Noon before
    /// the day-start conversion so adding days never lands on a DST-skipped hour —
    /// the same construction the aggregation used to build the cells.
    private func dayDate(weekStart: Date, row: Int) -> Date {
        let calendar = Calendar.current
        let noon = calendar.date(byAdding: .day, value: row, to: weekStart)?
            .addingTimeInterval(12 * 3_600) ?? weekStart
        return calendar.sessionDayStart(for: noon)
    }

    private func weekdayLabels(cellSize: CGFloat) -> some View {
        // Short names ("Sun", "Tue") rather than single letters, which repeat —
        // "S T T S" reads the same for Sunday/Saturday and Tuesday/Thursday.
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return VStack(spacing: cellSpacing) {
            // Matches the month-label row atop each column so the letters line up
            // with their rows.
            Color.clear.frame(height: 11)
            ForEach(Array(heatmap.rowWeekdays.enumerated()), id: \.offset) { row, weekday in
                Group {
                    // Every other row, so the labels don't crowd the cell stack;
                    // the gaps between named rows are unambiguous once the names
                    // are spelled out.
                    if row.isMultiple(of: 2), symbols.indices.contains(weekday - 1) {
                        Text(symbols[weekday - 1])
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: labelWidth, height: cellSize, alignment: .leading)
            }
        }
        .padding(.vertical, 1)
        .accessibilityHidden(true)
    }

    /// A month abbreviation above the first column that starts a new month.
    private func monthLabel(weekStarts: [Date], column: Int, weekStart: Date, cellSize: CGFloat) -> some View {
        let calendar = Calendar.current
        let previous = column > 0 ? weekStarts[column - 1] : nil
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

    /// The active metric's value for the cell — narrowed to the filtered
    /// category when one is active. `nil` (a padded, out-of-range day) reads as
    /// zero, as does a day with entries but no common-dose data in common mode.
    private func displayValue(_ cell: UsageHeatmapCell?) -> Double {
        guard let cell, cell.inRange else { return 0 }
        switch metric {
        case .entries:
            return Double(categoryFilter.map { cell.byCategory[$0] ?? 0 } ?? cell.total)
        case .commonDoses:
            return categoryFilter.map { cell.byCategoryCommon[$0] ?? 0 } ?? cell.commonTotal
        }
    }

    private func fill(value: Double, isFuture: Bool) -> Color {
        // Future days (the rest of the current week) haven't happened — blank,
        // not gray. Every past day is a square: gray when empty, so a quiet run
        // reads as a real absence rather than a gap in the grid.
        if isFuture { return .clear }
        guard value > 0 else { return Color(.tertiarySystemFill) }
        let peak = max(metric == .commonDoses ? heatmap.maxCommon : Double(heatmap.maxCount), 0.0001)
        let fraction = min(1, value / peak)
        return accent.opacity(0.28 + 0.72 * fraction)
    }
}

// MARK: - Hour histogram

/// Twenty-four bins across the clock. Replaces the old four coarse buckets.
private struct UsageHourHistogram: View {
    let bins: [Double]
    let metric: UsageRankMetric
    let accent: Color
    let selectedDay: Date?
    let onClearDay: () -> Void

    private struct Bin: Identifiable {
        let hour: Int
        let value: Double
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
        let items = bins.enumerated().map { Bin(hour: $0.offset, value: $0.element) }
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
                    y: .value("Amount", bin.value),
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

    private func summary(total: Double) -> String {
        guard total > 0, let peak = bins.indices.max(by: { bins[$0] < bins[$1] }) else {
            return String(localized: "No entries in this window")
        }
        switch metric {
        case .entries:
            return String(localized: "\(Int(total)) entries, busiest around \(hourLabel(peak))")
        case .commonDoses:
            let t = total.formatted(.number.precision(.fractionLength(0 ... 1)))
            return String(localized: "\(t) common-dose units, busiest around \(hourLabel(peak))")
        }
    }
}
