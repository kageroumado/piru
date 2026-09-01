import CoreGraphics
import Testing
@testable import Piru

@Suite("TimelineGutterLabels")
struct TimelineGutterLabelsTests {
    // MARK: - Frames

    @Test
    func `Frames touching within the gap collide`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 113, height: 12) // 1 pt apart, gap is 2
        #expect(a.collides(with: b))
        #expect(b.collides(with: a))
    }

    @Test
    func `Frames separated by more than the gap are clear`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 115, height: 12) // 3 pt apart
        #expect(!a.collides(with: b))
    }

    // MARK: - Dose timestamps vs Now

    @Test
    func `Without a Now tag every dose timestamp draws`() {
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [20, 21, 22], nowY: nil)
        #expect(visible == [true, true, true])
    }

    @Test
    func `A dose timestamp on the Now tag yields to it`() {
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [40, 44, 120], nowY: 40)
        #expect(visible == [false, false, true])
    }

    @Test
    func `A dose timestamp just clear of the Now tag survives`() {
        // 12 + 12 halves = 12, plus the 2 pt gap → 14 pt is the first clear spacing.
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [54, 53], nowY: 40)
        #expect(visible == [true, false])
    }

    // MARK: - Hour labels vs everything above them

    @Test
    func `An hour label on the Now tag is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 40, doseYs: [], nowY: 40))
        #expect(!TimelineGutterLabels.hourLabelFits(y: 52, doseYs: [], nowY: 40))
    }

    @Test
    func `An hour label on a dose timestamp is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [206], nowY: nil))
    }

    @Test
    func `An hour label clear of both draws`() {
        #expect(TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [230], nowY: 40))
        // 11/2 + 12/2 + 2 = 13.5 → 14 pt away is clear.
        #expect(TimelineGutterLabels.hourLabelFits(y: 214, doseYs: [200], nowY: nil))
    }
}
