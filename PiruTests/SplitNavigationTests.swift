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
    func `a wide portrait screen shows both`() {
        let panes = SplitPaneGeometry(size: CGSize(width: 1032, height: 1376), hasSelection: true)
        #expect(panes.showsBoth)
        #expect(panes.listWidth == SplitPaneGeometry.minimumPaneWidth)
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

@MainActor
@Suite("Opening records beside the list")
struct OpenRecordTests {
    private let mdma = PushRoute.substance(name: "MDMA")
    private let caffeine = PushRoute.substance(name: "Caffeine")
    private let entryID = UUID()

    private func navigator(_ path: [PushRoute] = []) -> AppNavigator {
        AppNavigator(
            selectedTab: .library,
            paths: [.library: path],
            storage: makeIsolatedDefaults(),
            layout: TabLayoutStore(defaults: makeIsolatedDefaults()),
        )
    }

    @Test
    func `opening the selected record again still shows it`() {
        let nav = navigator([mdma])
        nav.openRecord(mdma, besideList: true)
        #expect(nav.path(for: .library) == [mdma])
        #expect(nav.recordReopenings[.library] == 1)
        nav.openRecord(caffeine, besideList: true)
        #expect(nav.recordReopenings[.library] == 1)
    }

    @Test
    func `a record pushed in the list column opens beside it`() {
        let category = PushRoute.libraryCategory(.stimulant)
        let nav = navigator([category, mdma])
        nav.setList([category, mdma], in: .library)
        #expect(nav.path(for: .library) == [category, mdma])
        #expect(nav.recordReopenings[.library] == 1)
        nav.setList([category, caffeine], in: .library)
        #expect(nav.path(for: .library) == [category, caffeine])
        #expect(nav.recordReopenings[.library] == 1)
    }

    @Test
    func `a record being edited waits before another opens`() {
        let nav = navigator([mdma])
        nav.setEditing(true, record: entryID)
        nav.openRecord(caffeine, besideList: true)
        #expect(nav.path(for: .library) == [mdma])
        #expect(nav.pendingRecordChange == PendingRecordChange(tab: .library, opening: caffeine))

        nav.resolvePendingRecordChange(discard: false)
        #expect(nav.path(for: .library) == [mdma])
        #expect(nav.pendingRecordChange == nil)
    }

    @Test
    func `discarding the edit opens the waiting record`() {
        let nav = navigator([mdma])
        nav.setEditing(true, record: entryID)
        nav.openRecord(caffeine, besideList: true)
        nav.resolvePendingRecordChange(discard: true)
        #expect(nav.path(for: .library) == [caffeine])
        #expect(nav.recordsBeingEdited.isEmpty)
    }

    @Test
    func `closing a record being edited waits too`() {
        let nav = navigator([mdma])
        nav.setEditing(true, record: entryID)
        nav.closeRecord(in: .library)
        #expect(nav.path(for: .library) == [mdma])
        nav.resolvePendingRecordChange(discard: true)
        #expect(nav.path(for: .library) == [])
    }

    @Test
    func `an edit in another tab does not hold this one`() {
        let nav = navigator([mdma])
        nav.selectedTab = .journal
        nav.setEditing(true, record: entryID)
        nav.selectedTab = .library
        nav.openRecord(caffeine, besideList: true)
        #expect(nav.path(for: .library) == [caffeine])
    }

    @Test
    func `a deleted record closes, or pops when nested`() {
        let session = PushRoute.session(id: UUID())
        let entry = PushRoute.entry(timestamp: .now, id: entryID)
        let nav = navigator([entry])
        #expect(nav.removeDeletedRecord { $0 == entry })
        #expect(nav.path(for: .library) == [])

        let nested = navigator([session, entry])
        #expect(nested.removeDeletedRecord { $0 == entry })
        #expect(nested.path(for: .library) == [session])
    }

    @Test
    func `a deleted record shown in a sheet is left to the sheet`() {
        let entry = PushRoute.entry(timestamp: .now, id: entryID)
        let nav = navigator([entry])
        nav.present(.settings)
        #expect(!nav.removeDeletedRecord { $0 == entry })
        #expect(nav.path(for: .library) == [entry])
    }
}

private func makeIsolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "SplitNavigationTests.\(UUID().uuidString)")!
}
