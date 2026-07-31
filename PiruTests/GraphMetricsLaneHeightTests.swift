import Foundation
import Testing
@testable import Piru

/// Pins the lane-height budget. A pin-only lane (a substance with no modeled
/// duration, drawn as lollipops) is charged a short strip rather than a curve's
/// share — before this, `graphHeight / rowCount` gave a two-dot row the same
/// space as a full Bateman hump, so a session with several duration-less
/// substances squeezed every curve flat to pay for them.
@Suite("GraphMetrics lane heights")
struct GraphMetricsLaneHeightTests {
    private let threshold = LaneModeDefaults.thresholdDefault

    private func height(curves: Int, markers: Int, enlarged: Bool = false) -> CGFloat {
        GraphMetrics.graphHeight(
            enlarged: enlarged, curveLaneCount: curves, markerLaneCount: markers,
            laneModeEnabled: true, laneModeThreshold: threshold,
        )
    }

    @Test
    func `A pin lane costs less than a curve lane`() {
        // Same total row count, different mix: the pin-heavy day asks for less.
        #expect(height(curves: 2, markers: 4) < height(curves: 6, markers: 0))
    }

    @Test
    func `Swapping a curve lane for a pin lane frees exactly the difference`() {
        let perCurve = GraphMetrics.curveLaneHeight(enlarged: true)
        let saved = perCurve - GraphMetrics.markerLaneHeight
        #expect(saved > 0)
        // Ten lanes enlarged (500pt) clears both the floor and the 560 cap, so
        // the ideal height is what's actually returned and the swap is visible.
        let allCurves = height(curves: 10, markers: 0, enlarged: true)
        let oneSwapped = height(curves: 9, markers: 1, enlarged: true)
        #expect(abs((allCurves - oneSwapped) - saved) < 0.001)
    }

    @Test
    func `Below the lane-mode threshold the height is the fixed base`() {
        let base = height(curves: 1, markers: 0)
        #expect(base == height(curves: 2, markers: 0))
        #expect(base == GraphMetrics.embedded)
    }

    @Test
    func `Marker lanes count toward the lane-mode threshold`() {
        // The renderer draws a lane per duration-less substance, so the height
        // calc has to see them: a day of one curve and eight pins is nine rows,
        // and must be sized for nine. (A handful of pins alone stays at the
        // floor — they're cheap enough that the base height already fits them.)
        #expect(height(curves: 1, markers: 8) > GraphMetrics.embedded)
        #expect(height(curves: 1, markers: threshold) >= GraphMetrics.embedded)
    }

    @Test
    func `A pin-heavy day stays within the height cap`() {
        #expect(height(curves: 8, markers: 12, enlarged: true) <= 560)
        #expect(height(curves: 8, markers: 12) <= 380)
    }
}
