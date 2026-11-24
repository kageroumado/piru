import Foundation
import Testing
@testable import Piru

/// The interaction timeline's "both active" window and the hours its chart shows.
@Suite("InteractionOverlap")
struct InteractionOverlapTests {
    /// A short curve (t½ 3 h, fast absorption) and a long one (t½ 43 h).
    private func curves(offsetB: Double = 0) -> (InteractionOverlap.Curve, InteractionOverlap.Curve) {
        let shortKe = Foundation.log(2.0) / 180, longKe = Foundation.log(2.0) / (43 * 60)
        return (
            InteractionOverlap.Curve(ke: shortKe, ka: 0.03, offsetMinutes: 0),
            InteractionOverlap.Curve(ke: longKe, ka: 0.02, offsetMinutes: offsetB),
        )
    }

    @Test
    func `Doses taken together are both active within minutes`() throws {
        let (a, b) = curves()
        let window = try #require(InteractionOverlap.window(a, b, horizonMinutes: 300 * 60))
        #expect(window.lowerBound < 10)
        // The short curve sets the end: about five half-lives past its peak.
        #expect(window.upperBound > 10 * 60 && window.upperBound < 24 * 60)
    }

    @Test
    func `A second dose taken after the first has worn off never overlaps`() {
        let (a, b) = curves(offsetB: 40 * 60)
        #expect(InteractionOverlap.window(a, b, horizonMinutes: 300 * 60) == nil)
    }

    @Test
    func `A short overlap beside a curve lasting days fills the chart`() {
        let visible = InteractionOverlap.visibleHours(totalHours: 150, overlap: 0.1 ... 16)
        #expect(visible == 24)
    }

    @Test
    func `Both whole curves show when they never overlap or the overlap is most of them`() {
        #expect(InteractionOverlap.visibleHours(totalHours: 150, overlap: nil) == 150)
        #expect(InteractionOverlap.visibleHours(totalHours: 20, overlap: 0 ... 15) == 20)
    }

    @Test
    func `A very short overlap still shows a few hours`() {
        #expect(InteractionOverlap.visibleHours(totalHours: 100, overlap: 0 ... 1) == InteractionOverlap.minimumVisibleHours)
    }
}
