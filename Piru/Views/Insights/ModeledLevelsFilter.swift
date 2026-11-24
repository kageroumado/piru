import SwiftUI

/// Which lanes the Modeled Levels chart draws out of a body-load trail: the
/// substances picked in the toolbar's ``SubstanceFilterSheet``, or with no pick
/// every substance listed under Modeled as Active plus the ones logged most, up
/// to ``defaultLineCount`` lanes.
///
/// Substances are keyed by display name, the name the trail's series carry; a
/// substance drawn as two series (one per unit family) filters as one.
@Observable
@MainActor
final class ModeledLevelsFilter {
    /// Display names to draw; empty means the default lanes. Edited in
    /// ``SubstanceFilterSheet``, which collapses a pick of exactly the default
    /// lanes back to empty.
    var selectedSubstances: Set<String> = []

    /// Each series' category, by display name, for grouping the sheet's rows.
    /// Filled from the library when a trail arrives; a name missing here files
    /// under `.other`.
    private(set) var categories: [String: SubstanceCategory] = [:]

    /// Lowercased canonical names of the substances listed under Modeled as
    /// Active. Each gets a lane with no pick, past ``defaultLineCount`` if need be,
    /// so the chart never leaves out a substance the screen calls active.
    private(set) var activeNames: Set<String> = []

    /// Lanes drawn with no pick. A month of a varied journal is thirty-odd
    /// substances, so the ones logged most come first and the rest wait in the
    /// toolbar's sheet.
    static let defaultLineCount = 6

    /// Whether the toolbar pick replaces the default lanes.
    var isFiltering: Bool {
        !selectedSubstances.isEmpty
    }

    func setCategories(_ categories: [String: SubstanceCategory]) {
        self.categories = categories
    }

    func setActiveNames(_ names: Set<String>) {
        activeNames = Set(names.map { $0.lowercased() })
    }

    func category(of series: BodyLoadTrail.Series) -> SubstanceCategory {
        categories[series.displayName] ?? .other
    }

    /// The display names drawn with no pick: every active substance, then the
    /// rest in trail order (most logged first) until ``defaultLineCount`` lanes.
    func defaultNames(_ series: [BodyLoadTrail.Series]) -> Set<String> {
        var names = Set(series.filter { activeNames.contains($0.canonicalName.lowercased()) }.map(\.displayName))
        for item in series where names.count < Self.defaultLineCount {
            names.insert(item.displayName)
        }
        return names
    }

    /// How many substances the trail holds, counting a two-unit substance once.
    func substanceCount(_ series: [BodyLoadTrail.Series]) -> Int {
        Set(series.map(\.displayName)).count
    }

    /// Draw every substance in the trail.
    func showAll(_ series: [BodyLoadTrail.Series]) {
        selectedSubstances = Set(series.map(\.displayName))
    }

    /// The series the chart draws: the toolbar pick, else the default lanes.
    func chartSeries(_ series: [BodyLoadTrail.Series]) -> [BodyLoadTrail.Series] {
        let names = isFiltering ? selectedSubstances : defaultNames(series)
        return series.filter { names.contains($0.displayName) }
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
    /// lane keeps its dash and symbol while others are picked or dropped.
    func markers(_ series: [BodyLoadTrail.Series]) -> [String: ChartSeriesMarker] {
        var markers: [String: ChartSeriesMarker] = [:]
        for item in series where markers[item.displayName] == nil {
            markers[item.displayName] = ChartSeriesMarker(index: markers.count)
        }
        return markers
    }
}
