import SwiftUI
import Testing
@testable import Piru

/// The dock's resting-detent rule for a non-empty tray (`DockDetentPolicy`).
/// Every staging handler resolves its move through it, and only the last
/// move of a transaction survives — so the rule, not the handler order, is
/// what decides where a `stageDraft` lands.
@MainActor
@Suite("QuickLogDock detent policy")
struct QuickLogDockDetentTests {
    private let peek = QuickLogDockMetrics.peekDetent
    private let compact = PresentationDetent.height(260)

    /// The sliders pill from the bare dock: the draft is staged expanded, and
    /// the one move goes straight to `.medium` — never via compact, whose
    /// landing collapses every row.
    @Test
    func `staging an expanded draft at peek lands on medium`() {
        let selection = DockDetentPolicy.stagedSelection(
            current: peek, wasCompact: false, compact: compact, hasExpandedRows: true,
        )
        #expect(selection == .medium)
    }

    @Test
    func `staging a collapsed chip at peek lands on compact`() {
        let selection = DockDetentPolicy.stagedSelection(
            current: peek, wasCompact: false, compact: compact, hasExpandedRows: false,
        )
        #expect(selection == compact)
    }

    /// The sliders pill while other rows rest collapsed at compact: the
    /// re-minted compact is skipped for `.medium`, with the new row open.
    @Test
    func `staging an expanded draft at compact lands on medium`() {
        let selection = DockDetentPolicy.stagedSelection(
            current: compact, wasCompact: true, compact: .height(300), hasExpandedRows: true,
        )
        #expect(selection == .medium)
    }

    @Test
    func `a taller stack at compact re-mints compact`() {
        let taller = PresentationDetent.height(300)
        let selection = DockDetentPolicy.stagedSelection(
            current: compact, wasCompact: true, compact: taller, hasExpandedRows: false,
        )
        #expect(selection == taller)
    }

    /// Resting at medium or large is already a staged member: no move, whatever
    /// the rows are doing.
    @Test(arguments: [PresentationDetent.medium, .large], [true, false])
    func `a staged member keeps its selection`(current: PresentationDetent, expanded: Bool) {
        let selection = DockDetentPolicy.stagedSelection(
            current: current, wasCompact: false, compact: compact, hasExpandedRows: expanded,
        )
        #expect(selection == current)
    }
}
