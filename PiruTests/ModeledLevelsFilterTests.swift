import Foundation
import SwiftUI
import Testing
@testable import Piru

/// The Modeled Levels chart's narrowing: the toolbar substance filter, the
/// category chips and the legend's hide toggles, plus the series markers that
/// keep a line's dash and symbol stable under all three.
@MainActor
@Suite("ModeledLevelsFilter")
struct ModeledLevelsFilterTests {
    private func series(_ id: Int, _ name: String) -> BodyLoadTrail.Series {
        BodyLoadTrail.Series(id: id, displayName: name, color: .red, unit: "mg", peak: 1, points: [])
    }

    private var trail: [BodyLoadTrail.Series] {
        [series(0, "Caffeine"), series(1, "LSD"), series(2, "Methylphenidate"), series(3, "Lorazepam")]
    }

    private func filter() -> ModeledLevelsFilter {
        let filter = ModeledLevelsFilter()
        filter.setCategories([
            "Caffeine": .stimulant,
            "LSD": .psychedelic,
            "Methylphenidate": .stimulant,
            "Lorazepam": .benzodiazepine,
        ])
        return filter
    }

    private func names(_ series: [BodyLoadTrail.Series]) -> [String] {
        series.map(\.displayName)
    }

    @Test
    func `An empty substance selection shows every series`() {
        let filter = filter()
        #expect(!filter.isFiltering)
        #expect(names(filter.chartSeries(trail)) == names(trail))
    }

    @Test
    func `A substance selection narrows the chart, the legend and the chips`() {
        let filter = filter()
        filter.selectedSubstances = ["Caffeine", "Lorazepam"]
        #expect(filter.isFiltering)
        #expect(names(filter.chartSeries(trail)) == ["Caffeine", "Lorazepam"])
        #expect(names(filter.legendSeries(trail)) == ["Caffeine", "Lorazepam"])
        #expect(Set(filter.categoryCounts(trail).map(\.category)) == [.stimulant, .benzodiazepine])
    }

    @Test
    func `A category chip narrows within the substance selection`() {
        let filter = filter()
        filter.selectCategory(.stimulant)
        #expect(names(filter.legendSeries(trail)) == ["Caffeine", "Methylphenidate"])
        filter.selectedSubstances = ["Methylphenidate", "LSD"]
        #expect(names(filter.legendSeries(trail)) == ["Methylphenidate"])
    }

    @Test
    func `Picking the selected chip again clears it and shows every line`() {
        let filter = filter()
        filter.selectCategory(.stimulant)
        filter.toggleHidden("Caffeine")
        filter.selectCategory(.stimulant)
        #expect(filter.selectedCategory == nil)
        #expect(filter.hidden.isEmpty)
    }

    @Test
    func `Hidden lines leave the chart but stay in the legend`() {
        let filter = filter()
        filter.toggleHidden("LSD")
        #expect(!names(filter.chartSeries(trail)).contains("LSD"))
        #expect(names(filter.legendSeries(trail)).contains("LSD"))
        filter.toggleHidden("LSD")
        #expect(names(filter.chartSeries(trail)).contains("LSD"))
    }

    @Test
    func `Hiding every line falls back to showing them all`() {
        let filter = filter()
        filter.selectedSubstances = ["LSD"]
        filter.toggleHidden("LSD")
        #expect(names(filter.chartSeries(trail)) == ["LSD"])
    }

    @Test
    func `A category the substance filter empties is dropped`() {
        let filter = filter()
        filter.selectCategory(.psychedelic)
        filter.selectedSubstances = ["Caffeine"]
        filter.reconcile(with: trail)
        #expect(filter.selectedCategory == nil)
    }

    @Test
    func `Category counts put the largest category first`() {
        let counts = filter().categoryCounts(trail)
        #expect(counts.first?.category == .stimulant)
        #expect(counts.first?.count == 2)
    }

    @Test
    func `Sheet rows are one per substance, keyed by display name`() {
        let doubled = trail + [series(4, "Caffeine")]
        let refs = filter().substanceRefs(doubled)
        #expect(refs.map(\.name) == ["Caffeine", "LSD", "Methylphenidate", "Lorazepam"])
        #expect(refs.map(\.displayName) == refs.map(\.name))
        let stimulant = SubstanceCategory.allCases.firstIndex(of: .stimulant)
        #expect(refs.first?.categoryIndex == stimulant)
    }

    @Test
    func `Markers follow trail order and ignore filtering`() {
        let filter = filter()
        let before = filter.markers(trail)
        filter.selectedSubstances = ["Lorazepam"]
        filter.toggleHidden("Caffeine")
        #expect(filter.markers(trail) == before)
        #expect(Set(before.values).count == trail.count)
        #expect(before["Caffeine"] == ChartSeriesMarker(index: 0))
    }
}

@Suite("ChartSeriesMarker")
struct ChartSeriesMarkerTests {
    @Test
    func `The first 25 series each get a distinct dash and symbol pair`() {
        let markers = (0 ..< 25).map(ChartSeriesMarker.init(index:))
        #expect(Set(markers).count == 25)
    }

    @Test
    func `The first series is solid with a circle`() {
        let first = ChartSeriesMarker(index: 0)
        #expect(first.dash.isEmpty)
        #expect(first.systemImage == "circle.fill")
    }

    @Test
    func `The stroke is solid unless differentiating`() {
        let dashed = ChartSeriesMarker(index: 1)
        #expect(dashed.stroke(lineWidth: 2, differentiate: false).dash.isEmpty)
        #expect(!dashed.stroke(lineWidth: 2, differentiate: true).dash.isEmpty)
    }

    @Test
    func `Symbols go to the peaks above the floor`() {
        let start = Date(timeIntervalSince1970: 0)
        let dates = (0 ..< 12).map { start.addingTimeInterval(Double($0) * 3_600) }
        let values: [Double] = [0, 0.5, 0.9, 0.2, 0, 0, 0.05, 0.3, 0.1, 0, 0, 0]
        let indices = ChartSeriesMarker.symbolIndices(
            dates: dates, values: values, window: 6 * 3_600, slots: 2, floor: 0.1,
        )
        #expect(indices == [2, 7])
    }

    @Test
    func `A line with no peak still gets its last point`() {
        let start = Date(timeIntervalSince1970: 0)
        let dates = (0 ..< 5).map { start.addingTimeInterval(Double($0) * 3_600) }
        let indices = ChartSeriesMarker.symbolIndices(
            dates: dates, values: [0.1, 0.2, 0.3, 0.4, 0.5], window: 5 * 3_600,
        )
        #expect(indices == [4])
    }

    @Test
    func `Peaks closer than the spacing keep only the higher one`() {
        let start = Date(timeIntervalSince1970: 0)
        let dates = (0 ..< 5).map { start.addingTimeInterval(Double($0) * 3_600) }
        let indices = ChartSeriesMarker.symbolIndices(
            dates: dates, values: [0, 0.6, 0, 0.8, 0], window: 4 * 3_600, slots: 1,
        )
        #expect(indices == [3])
    }
}
