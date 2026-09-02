import CoreGraphics
import SwiftUI
import Testing
@testable import Piru

@Suite("TimelineNoteLane")
struct TimelineNoteLaneTests {
    private func point(_ y: CGFloat, _ v: Double) -> TimelineDayLayout.CurvePoint {
        TimelineDayLayout.CurvePoint(y: y, v: v)
    }

    private func series(_ points: [TimelineDayLayout.CurvePoint]) -> TimelineDayLayout.CurveSeries {
        TimelineDayLayout.CurveSeries(color: .pink, points: points)
    }

    // MARK: - How much lane a curve takes at a note's height

    @Test
    func `A note between two samples reads the curve interpolated at its own height`() {
        let curve = series([point(0, 0), point(100, 1)])
        #expect(abs(TimelineStripBuilder.curveFraction(at: 25, series: [curve]) - 0.25) < 0.0001)
        #expect(abs(TimelineStripBuilder.curveFraction(at: 100, series: [curve]) - 1) < 0.0001)
    }

    @Test
    func `The widest curve at that height is the one the note must clear`() {
        let narrow = series([point(0, 0.1), point(100, 0.1)])
        let wide = series([point(0, 0.8), point(100, 0.8)])
        #expect(abs(TimelineStripBuilder.curveFraction(at: 50, series: [narrow, wide]) - 0.8) < 0.0001)
    }

    @Test
    func `A height no curve reaches leaves the lane empty`() {
        let curve = series([point(200, 0.9), point(300, 0.9)])
        #expect(TimelineStripBuilder.curveFraction(at: 400, series: [curve]) == 0)
        #expect(TimelineStripBuilder.curveFraction(at: 50, series: []) == 0)
    }

    // MARK: - Placement in the lane

    /// The strip's real geometry on a 402 pt screen: the axis, the lane, and
    /// the bubbles' left edge in each bubble style.
    private let axisX: CGFloat = 16
    private let laneWidth: CGFloat = 232
    private let fullBubbleLeft: CGFloat = 150
    private let compactBubbleLeft: CGFloat = 162

    @Test
    func `A note clears the curve at its height, and the gutter mark beside it`() {
        // With the lane clear, the gutter's hour pill sets the start; a curve
        // reaching past it pushes the note further right.
        #expect(
            TimelineNoteLane.glyphX(axisX: axisX, curveWidth: 200, curveFraction: 0, besideCapsule: false)
                == TimelineNoteLane.laneStart(besideCapsule: false),
        )
        #expect(
            TimelineNoteLane.glyphX(axisX: axisX, curveWidth: 200, curveFraction: 0.75, besideCapsule: false)
                == axisX + 150 + TimelineNoteLane.curveGap,
        )
    }

    @Test
    func `A dose capsule at the same height pushes the note further into the lane`() {
        let beside = TimelineNoteLane.glyphX(axisX: axisX, curveWidth: 200, curveFraction: 0, besideCapsule: true)
        let alone = TimelineNoteLane.glyphX(axisX: axisX, curveWidth: 200, curveFraction: 0, besideCapsule: false)
        #expect(beside > alone)
    }

    @Test
    func `Compact bubbles leave room for a note's text beside a slim curve`() {
        let width = TimelineNoteLane.textWidth(
            glyphX: TimelineNoteLane.glyphX(axisX: axisX, curveWidth: laneWidth, curveFraction: 0.05, besideCapsule: false),
            bubbleLeft: compactBubbleLeft,
        )
        #expect(width >= TimelineNoteLane.minimumTextWidth)
    }

    @Test
    func `A peak in the lane squeezes the text out and leaves the glyph`() {
        for bubbleLeft in [fullBubbleLeft, compactBubbleLeft] {
            let width = TimelineNoteLane.textWidth(
                glyphX: TimelineNoteLane.glyphX(axisX: axisX, curveWidth: laneWidth, curveFraction: 0.3, besideCapsule: false),
                bubbleLeft: bubbleLeft,
            )
            #expect(width < TimelineNoteLane.minimumTextWidth)
        }
    }

    @Test
    func `A glyph pushed past the bubble column leaves no negative width`() {
        #expect(TimelineNoteLane.textWidth(glyphX: 400, bubbleLeft: 380) == 0)
    }
}
