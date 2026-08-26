import Foundation
import Testing
@testable import Piru

/// Pins the efficacy axis's greedy two-above / two-below label packing
/// (`EfficacyLabelPacking.rows`). τ plots crowd every clinical opioid into the
/// leftmost fifth of the axis, so the stagger is load-bearing — a regression
/// here overlaps label text instead of failing loudly.
@Suite("EfficacyLabelPacking")
struct EfficacyLabelPackingTests {
    private let width: CGFloat = 340
    private let labelWidth: CGFloat = 82

    private func rows(_ centers: [CGFloat]) -> [Int] {
        EfficacyLabelPacking.rows(orderedCenters: centers, width: width, labelWidth: labelWidth)
    }

    @Test
    func `Well-separated labels all take the innermost row`() {
        #expect(rows([50, 170, 290]) == [0, 0, 0])
    }

    @Test
    func `A tau-style crowd staggers through all four rows then reuses the least crowded`() {
        // Buprenorphine 0.02 → morphine 0.18 of DAMGO plus one distant full
        // agonist, mapped onto a 340 pt track: the left cluster spills across
        // all four rows; the distant label clears row 0's occupied edge.
        #expect(rows([26.8, 33.6, 50.6, 77.8, 220.0]) == [0, 1, 2, 3, 0])
    }

    @Test
    func `Fully overlapping labels wrap back to the least crowded row`() {
        #expect(rows([100, 101, 102, 103, 104]) == [0, 1, 2, 3, 0])
    }

    @Test
    func `Edge clamping makes near-zero centers collide`() {
        // Raw centers 0 and 10 both clamp to labelWidth/2, so the second must
        // move off row 0 even though the raw positions differ.
        #expect(rows([0, 10]) == [0, 1])
    }

    @Test
    func `Every input gets a row in range`() {
        let packed = rows((0 ..< 20).map { CGFloat($0) * 17 })
        #expect(packed.count == 20)
        #expect(packed.allSatisfy { (0 ... 3).contains($0) })
    }
}
