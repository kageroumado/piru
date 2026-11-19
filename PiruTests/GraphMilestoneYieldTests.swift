import CoreGraphics
import Foundation
import Testing
@testable import Piru

/// On the horizontal graph a phase milestone gives way to a note glyph: the
/// note is the person's own record and a button, the milestone is the model's
/// annotation.
@Suite("GraphMilestoneYield")
struct GraphMilestoneYieldTests {
    private let geom = TimelineGraphRenderer.GraphGeometry(inset: 12, top: 40, width: 300, height: 120)
    private let label = "~10:10 PM"

    /// A note glyph's frame at `x`, in the band above the curves.
    private func note(at x: CGFloat) -> CGRect {
        let size = TimelineGraphRenderer.NoteGlyphMetrics.size
        let y = TimelineGraphRenderer.NoteGlyphMetrics.centerY(geom: geom)
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// The stack's center for a curve at the very top of the plot, which is
    /// where a peak's milestone reaches up into the note band.
    private var peakY: CGFloat {
        max(
            TimelineGraphRenderer.MilestoneMetrics.minimumCenterY,
            geom.top - TimelineGraphRenderer.MilestoneMetrics.liftAboveCurve,
        )
    }

    private func yield(x: CGFloat, y: CGFloat, notes: [CGRect]) -> TimelineGraphRenderer.MilestoneYield {
        TimelineGraphRenderer.milestoneYield(x: x, y: y, label: label, geom: geom, notes: notes)
    }

    @Test
    func `A milestone keeps its glyph and time with no note in the graph`() {
        #expect(yield(x: 150, y: peakY, notes: []) == .whole)
    }

    @Test
    func `A note far along the axis leaves the milestone whole`() {
        #expect(yield(x: 150, y: peakY, notes: [note(at: 260)]) == .whole)
    }

    @Test
    func `A note over the time's place hides the time and keeps the glyph`() {
        // 22 pt from the glyph: clear of it, inside the 49 pt label's half width.
        #expect(yield(x: 150, y: peakY, notes: [note(at: 172)]) == .glyphOnly)
    }

    @Test
    func `A note on the glyph leaves the milestone out`() {
        #expect(yield(x: 150, y: peakY, notes: [note(at: 154)]) == .hidden)
    }

    @Test
    func `A milestone low on its curve is clear of the note band`() {
        #expect(yield(x: 150, y: geom.top + 80, notes: [note(at: 150)]) == .whole)
    }
}
