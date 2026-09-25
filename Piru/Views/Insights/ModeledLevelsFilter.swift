import SwiftUI

/// What the Modeled Levels chart shows out of a body-load trail: the substance
/// filter from the toolbar (the same ``SubstanceFilterSheet`` the Usage screen
/// uses), the category chips under the chart, and the lines hidden from the
/// legend. Each narrows the one before it.
///
/// Substances are keyed by display name, the name the trail's series carry; a
/// substance drawn as two series (one per unit family) filters as one.
@Observable
@MainActor
final class ModeledLevelsFilter {
    /// Display names to include; empty means every substance. Edited in
    /// ``SubstanceFilterSheet``, which collapses "every substance chosen" back
    /// to empty.
    var selectedSubstances: Set<String> = []
    /// The category chip picked under the chart, `nil` for All.
    var selectedCategory: SubstanceCategory?
    /// Display names hidden by tapping their legend chip.
    var hidden: Set<String> = []

    /// Each series' category, by display name. Filled from the library when a
    /// trail arrives; a name missing here files under `.other`.
    private(set) var categories: [String: SubstanceCategory] = [:]

    /// Whether the toolbar substance filter narrows the chart.
    var isFiltering: Bool {
        !selectedSubstances.isEmpty
    }

    func setCategories(_ categories: [String: SubstanceCategory]) {
        self.categories = categories
    }

    func category(of series: BodyLoadTrail.Series) -> SubstanceCategory {
        categories[series.displayName] ?? .other
    }

    // MARK: - Narrowing

    /// The trail's series that pass the toolbar substance filter.
    func substanceFiltered(_ series: [BodyLoadTrail.Series]) -> [BodyLoadTrail.Series] {
        guard isFiltering else { return series }
        return series.filter { selectedSubstances.contains($0.displayName) }
    }

    /// The series the legend lists: the substance filter, then the category chip.
    func legendSeries(_ series: [BodyLoadTrail.Series]) -> [BodyLoadTrail.Series] {
        let narrowed = substanceFiltered(series)
        guard let selectedCategory else { return narrowed }
        return narrowed.filter { category(of: $0) == selectedCategory }
    }

    /// The series the chart draws: the legend's, less the hidden ones. Hiding
    /// every line would leave an empty plot with no way back, so the legend can
    /// never zero the chart out.
    func chartSeries(_ series: [BodyLoadTrail.Series]) -> [BodyLoadTrail.Series] {
        let listed = legendSeries(series)
        let shown = listed.filter { !hidden.contains($0.displayName) }
        return shown.isEmpty ? listed : shown
    }

    /// The category chips for what the substance filter leaves, most series first.
    func categoryCounts(_ series: [BodyLoadTrail.Series]) -> [(category: SubstanceCategory, count: Int)] {
        var counts: [SubstanceCategory: Int] = [:]
        for item in substanceFiltered(series) {
            counts[category(of: item), default: 0] += 1
        }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return String(localized: lhs.key.displayName) < String(localized: rhs.key.displayName)
        }
        return sorted.map { (category: $0.key, count: $0.value) }
    }

    /// One row per substance for ``SubstanceFilterSheet``, in trail order.
    func substanceRefs(_ series: [BodyLoadTrail.Series]) -> [UsageSubstanceRef] {
        let categoryIndices = Dictionary(
            SubstanceCategory.allCases.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var seen: Set<String> = []
        return series.compactMap { item in
            guard seen.insert(item.displayName).inserted else { return nil }
            return UsageSubstanceRef(
                name: item.displayName,
                displayName: item.displayName,
                categoryIndex: categoryIndices[category(of: item)] ?? 0,
            )
        }
    }

    /// A marker per display name from its position in the whole trail, so a
    /// line keeps its dash and symbol while others are filtered or hidden.
    func markers(_ series: [BodyLoadTrail.Series]) -> [String: ChartSeriesMarker] {
        var markers: [String: ChartSeriesMarker] = [:]
        for item in series where markers[item.displayName] == nil {
            markers[item.displayName] = ChartSeriesMarker(index: markers.count)
        }
        return markers
    }

    // MARK: - Edits

    func toggleHidden(_ displayName: String) {
        if hidden.contains(displayName) {
            hidden.remove(displayName)
        } else {
            hidden.insert(displayName)
        }
    }

    /// Picks a category chip, or clears it when it is already picked; either
    /// way the legend starts over with every line shown.
    func selectCategory(_ category: SubstanceCategory?) {
        selectedCategory = selectedCategory == category ? nil : category
        hidden.removeAll()
    }

    /// Drops a picked category the substance filter has since emptied, so the
    /// chips never point at a category with nothing in it.
    func reconcile(with trail: [BodyLoadTrail.Series]) {
        guard let picked = selectedCategory else { return }
        let remaining = categoryCounts(trail).map(\.category)
        if !remaining.contains(picked) {
            selectedCategory = nil
        }
    }
}
