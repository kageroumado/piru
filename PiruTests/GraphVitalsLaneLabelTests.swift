import CoreGraphics
import Foundation
import Testing
@testable import Piru

/// The lanes under the curves: each caption sits in its own row above its
/// lane, the heart-rate lane is labeled on round bpm values, and blood pressure
/// sits in a row of its own whose labels never print over each other.
@Suite("GraphVitalsLaneLabel")
struct GraphVitalsLaneLabelTests {
    private let band = CGRect(x: 0, y: 200, width: 300, height: 54)
    private let labelSize = CGSize(width: 50, height: 10)

    private var row: CGRect {
        TimelineGraphRenderer.bloodPressureRowRect(band: band)
    }

    private func frame(markerX: CGFloat = 150, taken: [CGRect] = []) -> CGRect? {
        TimelineGraphRenderer.bloodPressureLabelFrame(markerX: markerX, labelSize: labelSize, row: row, taken: taken)
    }

    @Test
    func `A caption row sits wholly above its lane`() {
        let bandTop: CGFloat = 200
        let center = TimelineGraphRenderer.laneCaptionCenterY(bandTop: bandTop)
        #expect(center + GraphMetrics.laneCaption / 2 <= bandTop)
    }

    @Test
    func `The lanes reserve their caption rows`() {
        #expect(GraphMetrics.vitalsBandTotal(enlarged: false)
            == GraphMetrics.vitalsBand(enlarged: false) + GraphMetrics.vitalsBandGap + GraphMetrics.laneCaption)
        #expect(GraphMetrics.shulginLaneTotal
            == GraphMetrics.shulginLane + GraphMetrics.shulginLaneGap + GraphMetrics.laneCaption)
    }

    @Test
    func `Blood pressure gets a row of its own below the heart-rate band`() {
        #expect(GraphMetrics.vitalsBandTotal(enlarged: false, bloodPressure: true)
            == GraphMetrics.vitalsBandTotal(enlarged: false) + GraphMetrics.bloodPressureRowGap + GraphMetrics.bloodPressureRow)
        #expect(row.minY > band.maxY)
        #expect(!row.intersects(band))
    }

    @Test
    func `With nothing nearby the label sits right of its marker, inside the row`() throws {
        let placed = try #require(frame())
        #expect(placed.minX == 155)
        #expect(row.contains(placed))
    }

    @Test
    func `A label in the way moves the label left of its marker`() throws {
        let other = CGRect(x: 160, y: row.minY, width: 40, height: row.height)
        let placed = try #require(frame(taken: [other]))
        #expect(placed.maxX <= 145)
        #expect(!placed.intersects(other))
    }

    @Test
    func `A marker near the right edge keeps its label inside the row`() throws {
        let placed = try #require(frame(markerX: 296))
        #expect(row.contains(placed))
        #expect(placed.maxX <= 291)
    }

    @Test
    func `With both sides taken the marker stands unlabeled`() {
        #expect(frame(taken: [row]) == nil)
    }

    @Test
    func `bpm guides sit on round values that cover a resting-to-elevated range`() {
        let guides = TimelineGraphRenderer.bpmGuides(axis: 50 ... 120, plotHeight: 44)
        #expect(guides == [60, 80, 100, 120])
    }

    @Test
    func `A narrow range still carries at least two bpm guides`() {
        let guides = TimelineGraphRenderer.bpmGuides(axis: 60 ... 80, plotHeight: 44)
        #expect(guides.count >= 2)
        #expect(guides.allSatisfy { $0.truncatingRemainder(dividingBy: 10) == 0 })
    }

    @Test
    func `Neighboring bpm guides never sit closer than the minimum spacing`() {
        for axis: ClosedRange<Double> in [50 ... 120, 40 ... 200, 60 ... 80, 50 ... 160] {
            let plotHeight: CGFloat = 44
            let guides = TimelineGraphRenderer.bpmGuides(axis: axis, plotHeight: plotHeight)
            for (a, b) in zip(guides, guides.dropFirst()) {
                let spacing = CGFloat((b - a) / (axis.upperBound - axis.lowerBound)) * plotHeight
                #expect(spacing >= TimelineGraphRenderer.bpmGuideMinSpacing)
            }
            #expect(guides.allSatisfy { axis.contains($0) })
        }
    }
}
