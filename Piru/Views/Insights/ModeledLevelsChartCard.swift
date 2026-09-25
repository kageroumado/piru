import SwiftUI

/// The Modeled Levels card on the In Your Body screen: the body-load chart, its
/// scrub readout, the category chips and the legend. What it draws is narrowed
/// by ``ModeledLevelsFilter``, which the screen's toolbar also edits.
struct ModeledLevelsChartCard: View {
    let trail: BodyLoadTrail
    let range: UsageTimeRange
    let filter: ModeledLevelsFilter

    @State private var selectedDate: Date?

    var body: some View {
        let markers = filter.markers(trail.series)
        let chartSeries = filter.chartSeries(trail.series)
        UsageSectionCard(title: "Modeled levels over time", subtitle: "Each line as a share of its own peak") {
            if chartSeries.isEmpty {
                Text("None of the chosen substances have a modeled curve in this range")
                    .captionSecondary()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xxl)
            } else {
                BodyLoadChart(series: chartSeries, markers: markers, dates: trail.dates, selectedDate: $selectedDate)
                if let selectedDate {
                    BodyLoadReadout(series: chartSeries, markers: markers, date: selectedDate)
                }
            }
            let categories = filter.categoryCounts(trail.series)
            if categories.count > 1 {
                ModeledLevelsCategoryChips(categories: categories, filter: filter)
            }
            ModeledLevelsLegend(series: filter.legendSeries(trail.series), markers: markers, filter: filter)
        }
        .onChange(of: range) { selectedDate = nil }
        .onChange(of: filter.selectedSubstances) { filter.reconcile(with: trail.series) }
    }
}

// MARK: - Category chips

private struct ModeledLevelsCategoryChips: View {
    let categories: [(category: SubstanceCategory, count: Int)]
    let filter: ModeledLevelsFilter

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { filter.selectCategory(nil) }
            } label: {
                HStack(spacing: Spacing.xs) {
                    DifferentiatedSelectionMark(isSelected: filter.selectedCategory == nil)
                    Text("All")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 5)
                .background(filter.selectedCategory == nil ? Theme.accent.opacity(0.15) : Color.platformTertiarySystemFill)
                .foregroundStyle(filter.selectedCategory == nil ? Theme.accent : .primary)
                .clipShape(skinChipShape())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(filter.selectedCategory == nil ? [.isSelected] : [])

            ForEach(categories, id: \.category) { entry in
                let isSelected = filter.selectedCategory == entry.category
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { filter.selectCategory(entry.category) }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        DifferentiatedSelectionMark(isSelected: isSelected)
                        LegendDot(color: entry.category.color, size: .compact)
                        Text(entry.category.displayName)
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 5)
                    .background(isSelected ? entry.category.color.opacity(0.15) : Color.platformTertiarySystemFill)
                    .foregroundStyle(isSelected ? entry.category.color : .primary)
                    .clipShape(skinChipShape())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Legend

private struct ModeledLevelsLegend: View {
    let series: [BodyLoadTrail.Series]
    let markers: [String: ChartSeriesMarker]
    let filter: ModeledLevelsFilter

    var body: some View {
        FlowLayout(spacing: Spacing.md) {
            ForEach(uniqueNames, id: \.name) { item in
                chip(name: item.name, color: item.color)
            }
        }
    }

    /// One chip per substance: a substance drawn in two unit families shares
    /// one marker and one hide toggle.
    private var uniqueNames: [(name: String, color: Color)] {
        var seen: Set<String> = []
        return series.compactMap { item in
            seen.insert(item.displayName).inserted ? (item.displayName, item.color) : nil
        }
    }

    private func chip(name: String, color: Color) -> some View {
        let isHidden = filter.hidden.contains(name)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { filter.toggleHidden(name) }
        } label: {
            HStack(spacing: Spacing.xs) {
                ChartSeriesKey(color: color, marker: markers[name] ?? ChartSeriesMarker(index: 0))
                    .opacity(isHidden ? 0.3 : 1)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
                    .strikethrough(isHidden)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityValue(isHidden ? Text("Hidden") : Text("Shown"))
        .accessibilityHint(Text("Toggles this substance's line"))
        .accessibilityAddTraits(isHidden ? [] : [.isSelected])
    }
}
