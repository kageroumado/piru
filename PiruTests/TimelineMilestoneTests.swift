import Foundation
import Testing
@testable import Piru

/// Where a curve milestone's mark may sit on the vertical timeline, and when it
/// has to give way — the pure geometry behind the phase glyphs in the lane.
@Suite("TimelineMilestoneLane")
struct TimelineMilestoneLaneTests {
    private func milestone(y: CGFloat, kind: TimelineDayLayout.Milestone.Kind = .peak) -> TimelineDayLayout.Milestone {
        TimelineDayLayout.Milestone(
            doseKey: "Testine|0",
            kind: kind,
            time: .now,
            y: y,
            curveFraction: 0.5,
            affectsSleep: false,
            clearOfCards: true,
        )
    }

    @Test
    func `Marks share one column at the lane's outer edge`() {
        #expect(TimelineMilestoneLane.markX(axisX: 16, curveWidth: 140) == 16 + 140 + TimelineMilestoneLane.curveGap)
    }

    @Test
    func `A row with a bubble on it is bounded by the bubble column`() {
        let x = TimelineMilestoneLane.markX(axisX: 16, curveWidth: 140)
        #expect(!TimelineMilestoneLane.fits(markX: x, bubbleLeft: x + 20, trailingEdge: x + 220, clearOfCards: false))
        #expect(TimelineMilestoneLane.fits(markX: x, bubbleLeft: x + 20, trailingEdge: x + 220, clearOfCards: true))
    }

    @Test
    func `A row overlapping a card stack is not clear`() {
        let spans = [(top: CGFloat(140), bottom: CGFloat(200))]
        #expect(!TimelineMilestoneLane.clearOfCards(y: 150, spans: spans))
        #expect(!TimelineMilestoneLane.clearOfCards(y: 132, spans: spans))
        #expect(TimelineMilestoneLane.clearOfCards(y: 100, spans: spans))
        #expect(TimelineMilestoneLane.clearOfCards(y: 240, spans: spans))
    }

    @Test
    func `Two boundaries on the same pixel keep only the earlier one`() {
        let kept = TimelineMilestoneLane.thinned([milestone(y: 100), milestone(y: 103, kind: .offset)])
        #expect(kept.count == 1)
        #expect(kept[0].y == 100)
    }

    @Test
    func `Boundaries with a row each are all kept, in axis order`() {
        let kept = TimelineMilestoneLane.thinned([milestone(y: 200, kind: .offset), milestone(y: 100)])
        #expect(kept.map(\.y) == [100, 200])
    }

    @Test
    func `A wake-promoting dose ends on the moon rather than the checkmark`() {
        let sleepy = TimelineDayLayout.Milestone(
            doseKey: "Testine|0", kind: .end, time: .now, y: 0,
            curveFraction: 0, affectsSleep: true, clearOfCards: true,
        )
        #expect(sleepy.symbolName == DosePhaseGlyph.sleep)
        #expect(milestone(y: 0, kind: .end).symbolName == DosePhaseGlyph.ended)
    }
}
