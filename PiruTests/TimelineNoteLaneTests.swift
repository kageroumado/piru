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

@Suite("Timeline heart-rate trace")
struct TimelineHeartRateTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Slice-local y, one point per minute, later time higher up.
    private func localY(_ date: Date) -> CGFloat {
        CGFloat(600 - date.timeIntervalSince(start) / 60)
    }

    private func samples(_ bpms: [Double]) -> [HeartRateSample] {
        bpms.enumerated().map { HeartRateSample(date: start.addingTimeInterval(Double($0.offset) * 300), bpm: $0.element) }
    }

    private func points(_ bpms: [Double], to end: TimeInterval = 86_400) -> [TimelineDayLayout.CurvePoint] {
        TimelineStripBuilder.heartRatePoints(
            samples: samples(bpms),
            from: start,
            to: start.addingTimeInterval(end),
            localY: localY,
        )
    }

    @Test
    func `A scatter of samples draws nothing`() {
        #expect(points([60, 70, 80, 90, 100]).isEmpty)
        #expect(points([]).isEmpty)
    }

    @Test
    func `Six samples are enough to make a line`() {
        #expect(points([60, 70, 80, 90, 100, 110]).count == 6)
    }

    @Test
    func `The band maps 40 bpm to the axis and 160 to the lane's full width`() {
        let mapped = points([40, 100, 160, 70, 130, 90])
        #expect(mapped.first { $0.y == localY(start) }?.v == 0)
        let atFull = points([40, 100, 160, 70, 130, 90]).map(\.v).max()
        #expect(atFull == 1)
        // 100 bpm sits halfway up the band.
        let middle = mapped.first { abs($0.v - 0.5) < 0.0001 }
        #expect(middle != nil)
    }

    @Test
    func `Rates outside the band flatten against its ends`() {
        let mapped = points([20, 30, 200, 220, 100, 100])
        #expect(mapped.allSatisfy { $0.v >= 0 && $0.v <= 1 })
        #expect(mapped.contains { $0.v == 0 })
        #expect(mapped.contains { $0.v == 1 })
    }

    @Test
    func `Only the samples inside the slice count`() {
        // Six samples five minutes apart, but the slice ends after fifteen
        // minutes: four are in it, which is a scatter.
        #expect(points([60, 70, 80, 90, 100, 110], to: 16 * 60).isEmpty)
    }

    @Test
    func `Points come back in y order, newest first`() {
        let mapped = points([60, 70, 80, 90, 100, 110])
        #expect(mapped == mapped.sorted { $0.y < $1.y })
    }
}
