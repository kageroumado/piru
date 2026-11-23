import CoreGraphics
import Foundation
import Testing
@testable import Piru

/// The lanes under the curves: each caption sits in its own row above its
/// lane, and a blood-pressure reading's label never prints over the heart-rate
/// line, a bpm number or another label.
@Suite("GraphVitalsLaneLabel")
struct GraphVitalsLaneLabelTests {
    private let band = CGRect(x: 0, y: 200, width: 300, height: 54)
    private let labelSize = CGSize(width: 30, height: 10)

    private func frame(barX: CGFloat = 150, line: [[CGPoint]] = [], taken: [CGRect] = []) -> CGRect? {
        TimelineGraphRenderer.bloodPressureLabelFrame(
            barX: barX, systolicY: 220, diastolicY: 236, labelSize: labelSize,
            band: band, lines: line, taken: taken,
        )
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
    func `With nothing nearby the label sits right of the upper cap`() throws {
        let placed = try #require(frame())
        #expect(placed.minX == 154)
        #expect(placed.maxY <= 220)
    }

    @Test
    func `A heart-rate line through the upper spots moves the label below the bar`() throws {
        let line = [[CGPoint(x: 0, y: 213), CGPoint(x: 300, y: 213)]]
        let placed = try #require(frame(line: line))
        #expect(placed.minY >= 236)
        #expect(!TimelineGraphRenderer.polyline(line[0], crosses: placed))
    }

    @Test
    func `A bpm number right of the bar moves the label to its left`() throws {
        let number = CGRect(x: 160, y: 205, width: 12, height: 9)
        let placed = try #require(frame(taken: [number]))
        #expect(placed.maxX <= 146)
        #expect(!placed.intersects(number))
    }

    @Test
    func `A bar near the left edge keeps its label inside the band`() throws {
        let placed = try #require(frame(barX: 4))
        #expect(band.contains(placed))
    }

    @Test
    func `With every spot taken the bar stands unlabeled`() {
        #expect(frame(taken: [band]) == nil)
    }

    @Test
    func `A line beside a rect does not cross it`() {
        let rect = CGRect(x: 100, y: 100, width: 20, height: 10)
        #expect(!TimelineGraphRenderer.polyline([CGPoint(x: 0, y: 130), CGPoint(x: 300, y: 130)], crosses: rect))
        #expect(TimelineGraphRenderer.polyline([CGPoint(x: 0, y: 90), CGPoint(x: 300, y: 120)], crosses: rect))
    }
}
