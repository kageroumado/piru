import CoreGraphics
import Foundation
import Testing
@testable import Piru

@Suite("Split pane geometry")
struct SplitPaneGeometryTests {
    @Test
    func `list uses full width until selection`() {
        let panes = SplitPaneGeometry(size: CGSize(width: 951, height: 635), hasSelection: false)
        #expect(!panes.showsBoth)
        #expect(panes.listWidth == 951)
    }

    @Test
    func `flat list is a sidebar beside the record`() {
        let panes = SplitPaneGeometry(size: CGSize(width: 951, height: 635), hasSelection: true)
        #expect(panes.showsBoth)
        #expect(panes.listWidth == SplitPaneGeometry.minimumPaneWidth)
    }

    @Test
    func `fold defines the boundary`() {
        let fold = CGRect(x: 450, y: 0, width: 30, height: 635)
        let panes = SplitPaneGeometry(size: CGSize(width: 951, height: 635), hasSelection: true, division: fold)
        #expect(panes.showsBoth)
        #expect(panes.listWidth == 450)
    }

    @Test(arguments: [CGSize(width: 466, height: 678), CGSize(width: 669, height: 951), CGSize(width: 700, height: 600)])
    func `compact and portrait use one pane`(size: CGSize) {
        let panes = SplitPaneGeometry(size: size, hasSelection: true)
        #expect(!panes.showsBoth)
        #expect(panes.listWidth == size.width)
    }

    @Test
    func `larger text gets one readable pane`() {
        let panes = SplitPaneGeometry(size: CGSize(width: 951, height: 635), hasSelection: true, minimumPaneWidth: 500)
        #expect(!panes.showsBoth)
    }

    @Test
    func `narrow side of fold uses one pane`() {
        let panes = SplitPaneGeometry(
            size: CGSize(width: 951, height: 635),
            hasSelection: true,
            division: CGRect(x: 300, y: 0, width: 24, height: 635),
        )
        #expect(!panes.showsBoth)
    }
}

@Suite("Split path")
struct SplitPathTests {
    private let category = PushRoute.libraryCategory(.stimulant)
    private let mdma = PushRoute.substance(name: "MDMA")
    private let caffeine = PushRoute.substance(name: "Caffeine")
    private let data = PushRoute.substanceData(name: "MDMA", section: .pharmacology)

    @Test
    func `list levels stay in the list column`() {
        let split = SplitPath([category])
        #expect(split.list == [category])
        #expect(split.record == nil)
    }

    @Test
    func `the first record and what it pushed form the detail`() {
        let split = SplitPath([category, mdma, data])
        #expect(split.list == [category])
        #expect(split.detail == [mdma, data])
    }

    @Test
    func `a record opened from the list replaces the open one`() {
        let split = SplitPath([category, mdma, data])
        #expect(split.listChanged(to: [category, caffeine]) == [category, caffeine])
        #expect(split.opening(caffeine) == [category, caffeine])
    }

    @Test
    func `moving through the list keeps the open record`() {
        let split = SplitPath([category, mdma])
        #expect(split.listChanged(to: []) == [mdma])
        #expect(split.opening(.libraryFavorites) == [category, .libraryFavorites, mdma])
    }

    @Test
    func `the detail column pushes and pops above its record`() {
        let split = SplitPath([category, mdma])
        #expect(split.detailChanged(to: [data]) == [category, mdma, data])
        #expect(SplitPath([category, mdma, data]).detailChanged(to: []) == [category, mdma])
    }
}
