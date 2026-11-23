import CoreGraphics
import Foundation
import Testing
@testable import Piru

/// A milestone's clock time sits clear of its own curve, even where the curve
/// climbs steeply under the time's width.
@Suite("GraphMilestoneClearance")
struct GraphMilestoneClearanceTests {
    private typealias Metrics = TimelineGraphRenderer.MilestoneMetrics
    private let geom = TimelineGraphRenderer.GraphGeometry(inset: 12, top: 40, width: 300, height: 120)
    private let labelWidth: CGFloat = 49

    private func centerY(x: CGFloat, curve: @escaping (CGFloat) -> Double?) -> CGFloat? {
        TimelineGraphRenderer.milestoneCenterY(
            x: x,
            labelCenterX: TimelineGraphRenderer.milestoneLabelCenterX(x, labelWidth: labelWidth, geom: geom),
            labelWidth: labelWidth,
            geom: geom,
            curveValue: curve,
        )
    }

    /// The curve's canvas y at a normalized height.
    private func curveY(_ value: Double) -> CGFloat {
        geom.top + geom.height * CGFloat(1 - value)
    }

    @Test
    func `On a flat curve the stack keeps its lift above the curve`() throws {
        let y = try #require(centerY(x: 150) { _ in 0.5 })
        #expect(y == curveY(0.5) - Metrics.liftAboveCurve)
    }

    @Test
    func `On a rising curve the time clears the highest point under it`() throws {
        // Climbs 0.01 per point: 25 pt right of the glyph it is a quarter higher.
        let rising: (CGFloat) -> Double? = { px in min(1, max(0, 0.1 + Double(px - 150) * 0.01)) }
        let y = try #require(centerY(x: 150, curve: rising))
        let labelBottom = y + Metrics.stackHeight / 2
        let right = 150 + labelWidth / 2
        let highest = try #require(rising(right))
        #expect(labelBottom <= curveY(highest) - Metrics.labelClearance + 0.001)
    }

    @Test
    func `A time slid inward at the edge clears the curve where it lands`() throws {
        // At the plot's left edge the time slides right, over the climb.
        let x = geom.inset + 4
        let rising: (CGFloat) -> Double? = { px in min(1, max(0, Double(px - x) * 0.012)) }
        let y = try #require(centerY(x: x, curve: rising))
        let labelRight = TimelineGraphRenderer.milestoneLabelCenterX(x, labelWidth: labelWidth, geom: geom) + labelWidth / 2
        let highest = try #require(rising(labelRight))
        #expect(y + Metrics.stackHeight / 2 <= curveY(highest) - Metrics.labelClearance + 0.001)
    }

    @Test
    func `A milestone where its curve is not drawn is left out`() {
        #expect(centerY(x: 150) { _ in nil } == nil)
    }

    @Test
    func `The stack never rises past the canvas top`() throws {
        let y = try #require(centerY(x: 150) { _ in 1 })
        #expect(y >= Metrics.minimumCenterY)
    }
}
