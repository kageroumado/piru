import CoreGraphics
import Testing
@testable import Piru

@Suite("TimelineGutterLabels")
struct TimelineGutterLabelsTests {
    // MARK: - Frames

    @Test
    func `Frames touching within the gap collide`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 113, height: 12) // 1 pt apart, gap is 6
        #expect(a.collides(with: b))
        #expect(b.collides(with: a))
    }

    @Test
    func `Frames separated by more than the gap are clear`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 120, height: 12) // 8 pt apart
        #expect(!a.collides(with: b))
    }

    // MARK: - Dose capsules vs Now

    @Test
    func `Without a Now tag every dose capsule draws`() {
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [20, 21, 22], nowY: nil)
        #expect(visible == [true, true, true])
    }

    @Test
    func `A dose capsule on the Now tag yields to it`() {
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [40, 44, 120], nowY: 40)
        #expect(visible == [false, false, true])
    }

    @Test
    func `A dose capsule just clear of the Now tag survives`() {
        // Capsule 22/2 + Now 22/2 = 22, plus the 6 pt gap → 28 pt is the first clear spacing.
        let visible = TimelineGutterLabels.doseLabelsVisible(doseYs: [68, 67], nowY: 40)
        #expect(visible == [true, false])
    }

    @Test
    func `Every one-line mark shares the recipe's height`() {
        #expect(TimelineGutterLabels.hourLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.doseLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.nowLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.dayTagHeight == TimelineGutterMarkMetrics.twoLineHeight)
    }

    // MARK: - Hour labels vs everything above them

    @Test
    func `An hour label on the Now tag is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 40, doseYs: [], nowY: 40))
        #expect(!TimelineGutterLabels.hourLabelFits(y: 52, doseYs: [], nowY: 40))
    }

    @Test
    func `An hour label on a dose capsule is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [206], nowY: nil))
        // 22/2 + 22/2 + 6 = 28 → 27 pt away still touches.
        #expect(!TimelineGutterLabels.hourLabelFits(y: 227, doseYs: [200], nowY: nil))
    }

    @Test
    func `An hour label clear of both draws`() {
        #expect(TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [240], nowY: 40))
        // 22/2 + 22/2 + 6 = 28 → 28 pt away is clear.
        #expect(TimelineGutterLabels.hourLabelFits(y: 228, doseYs: [200], nowY: nil))
    }

    @Test
    func `An hour label under the day tag is suppressed`() {
        // The tag reserves the top 44 pt; a 22 pt label needs its top edge
        // 6 pt below that → center ≥ 61.
        #expect(!TimelineGutterLabels.hourLabelFits(y: 50, doseYs: [], nowY: nil, reservedTop: 44))
        #expect(!TimelineGutterLabels.hourLabelFits(y: 60, doseYs: [], nowY: nil, reservedTop: 44))
        #expect(TimelineGutterLabels.hourLabelFits(y: 61, doseYs: [], nowY: nil, reservedTop: 44))
    }
}
