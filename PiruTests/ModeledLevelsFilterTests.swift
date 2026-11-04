import Foundation
import SwiftUI
import Testing
@testable import Piru

/// Which lanes the Modeled Levels chart draws: the six logged most by default,
/// or the toolbar's pick, plus the series markers that keep a lane's dash and
/// symbol stable whatever is picked.
@MainActor
@Suite("ModeledLevelsFilter")
struct ModeledLevelsFilterTests {
    private func series(_ id: Int, _ name: String) -> BodyLoadTrail.Series {
        BodyLoadTrail.Series(id: id, displayName: name, color: .red, unit: "mg", peak: 1, doseCount: 1, points: [])
    }

    private var trail: [BodyLoadTrail.Series] {
        [series(0, "Caffeine"), series(1, "LSD"), series(2, "Methylphenidate"), series(3, "Lorazepam")]
    }

    private var longTrail: [BodyLoadTrail.Series] {
        (0 ..< 9).map { series($0, "S\($0)") }
    }

    private func names(_ series: [BodyLoadTrail.Series]) -> [String] {
        series.map(\.displayName)
    }

    @Test
    func `A short trail draws every lane`() {
        let filter = ModeledLevelsFilter()
        #expect(!filter.isFiltering)
        #expect(names(filter.chartSeries(trail)) == names(trail))
    }

    @Test
    func `A long trail draws its first six lanes`() {
        let filter = ModeledLevelsFilter()
        #expect(names(filter.chartSeries(longTrail)) == ["S0", "S1", "S2", "S3", "S4", "S5"])
        #expect(filter.defaultNames(longTrail) == ["S0", "S1", "S2", "S3", "S4", "S5"])
    }

    @Test
    func `A substance drawn in two unit families counts as one lane`() {
        let doubled = [series(0, "S0"), series(1, "S0")] + (1 ..< 9).map { series($0 + 1, "S\($0)") }
        let filter = ModeledLevelsFilter()
        #expect(filter.defaultNames(doubled).count == 6)
        #expect(filter.chartSeries(doubled).count == 7)
    }

    @Test
    func `A toolbar pick replaces the default lanes`() {
        let filter = ModeledLevelsFilter()
        filter.selectedSubstances = ["S7", "S1"]
        #expect(filter.isFiltering)
        #expect(names(filter.chartSeries(longTrail)) == ["S1", "S7"])
        filter.selectedSubstances = Set(names(longTrail))
        #expect(filter.chartSeries(longTrail).count == 9)
    }

    @Test
    func `Sheet rows are one per substance, keyed by display name`() {
        let filter = ModeledLevelsFilter()
        filter.setCategories(["Caffeine": .stimulant, "LSD": .psychedelic])
        let doubled = trail + [series(4, "Caffeine")]
        let refs = filter.substanceRefs(doubled)
        #expect(refs.map(\.name) == ["Caffeine", "LSD", "Methylphenidate", "Lorazepam"])
        #expect(refs.map(\.displayName) == refs.map(\.name))
        let stimulant = SubstanceCategory.allCases.firstIndex(of: .stimulant)
        #expect(refs.first?.categoryIndex == stimulant)
    }

    @Test
    func `Markers follow trail order and ignore the pick`() {
        let filter = ModeledLevelsFilter()
        let before = filter.markers(trail)
        filter.selectedSubstances = ["Lorazepam"]
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
