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

/// Which curve sets the horizontal graph may annotate. The rule lives in the
/// app because it turns on drug class; the graph itself compiles into the
/// widget targets and is only ever handed the verdict.
@Suite("CurveMilestonePolicy")
@MainActor
struct CurveMilestonePolicyTests {
    private func state(_ name: String) -> ActiveSubstanceState? {
        ActiveSubstanceState(
            name: name,
            colorHex: "#FF0000",
            timestamp: .now,
            amount: 10,
            unit: "mg",
            routeDisplayName: "Oral",
            duration: DurationProfile(
                onset: DurationRange(min: 20, max: 40),
                comeup: DurationRange(min: 20, max: 40),
                peak: DurationRange(min: 150, max: 210),
                offset: DurationRange(min: 90, max: 150),
                afterglow: nil,
                total: DurationRange(min: 420, max: 540),
            ),
            category: .stimulant,
        )
    }

    @Test
    func `Nothing to annotate is not annotated`() {
        #expect(!CurveMilestonePolicy.allows([]))
    }

    @Test
    func `Three curves are past the point of reading them`() throws {
        let three = try (0 ..< 3).map { try #require(state("Sub\($0)")) }
        #expect(!CurveMilestonePolicy.allows(three))
    }

    @Test
    func `One curve is always annotated`() throws {
        #expect(try CurveMilestonePolicy.allows([#require(state("Methylphenidate"))]))
    }

    @Test
    func `Two stimulants land their boundaries on the same minutes, so neither is annotated`() throws {
        let pair = try [state("Methylphenidate"), state("Caffeine")].map { try #require($0) }
        #expect(!CurveMilestonePolicy.allows(pair))
    }

    @Test
    func `A stimulant beside something that moves differently stays legible`() throws {
        let pair = try [state("Methylphenidate"), state("L-Theanine")].map { try #require($0) }
        #expect(CurveMilestonePolicy.allows(pair))
    }
}
