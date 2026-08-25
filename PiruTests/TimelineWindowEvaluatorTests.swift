import Foundation
import Testing
@testable import Piru

/// The continuous ribbon's window evaluator must be *exactly* the session
/// curve math, just sampled through an arbitrary window: within a dose's
/// activity window the value equals the session's Hill-merged intensity, tiles
/// agree at their shared boundary, and doses contribute iff their activity
/// window intersects the evaluated window.
@Suite("TimelineWindowEvaluator")
struct TimelineWindowEvaluatorTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// A dose with a typical oral profile: 30 min onset, come-up to 60, peak to
    /// 180, offset to 360 (mirrors `TimelineCurveModelTests`).
    private func dose(
        name: String = "Testine",
        timestamp: Date? = nil,
        amount: Double = 20,
        route: String = "oral",
        onsetEnd: Double = 30,
        comeupEnd: Double = 60,
        peakEnd: Double = 180,
        offsetEnd: Double = 360,
        total: Double = 360,
        magnitude: Double = 0.7,
    ) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: name,
            colorHex: "FF66AA",
            doseTimestamp: timestamp ?? t0,
            amount: amount,
            unit: "mg",
            route: route,
            onsetEndMinutes: onsetEnd,
            comeupEndMinutes: comeupEnd,
            peakEndMinutes: peakEnd,
            offsetEndMinutes: offsetEnd,
            afterglowEndMinutes: nil,
            totalMinutes: total,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
        )
    }

    private func minutes(_ value: Double) -> TimeInterval {
        value * 60
    }

    // MARK: - (a) Consistency with the session curve

    @Test
    func `Single dose window evaluation matches the session curve at the same instants`() throws {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)

        // Window fully inside the dose's activity (extent > 360 min here), so
        // per-dose extent clipping never bites and the values must equal the
        // session's stacked evaluation exactly.
        #expect(extent >= 360)
        let start = t0
        let end = t0.addingTimeInterval(minutes(360))
        let plot = TimelineWindowEvaluator.evaluate(doses: [s], from: start, to: end, sampleCount: 61)

        #expect(plot.series.count == 1)
        let values = try #require(plot.series.first).values
        #expect(values.count == 61)

        for (index, value) in values.enumerated() {
            let sampleDate = start.addingTimeInterval(minutes(360) * Double(index) / 60)
            let globalMinutes = sampleDate.timeIntervalSince(t0) / 60
            let expected = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: globalMinutes,
                group: [s],
                earliestDose: t0,
            )
            #expect(abs(value - expected) < 1e-12)
        }

        // The window peak is the max sample, feeding the shared y-scale.
        #expect(abs(plot.peakValue - values.max()!) < 1e-12)
    }

    @Test
    func `Redose group merges through the same Hill link as the session graph`() throws {
        let first = dose()
        let redose = dose(timestamp: t0.addingTimeInterval(minutes(90)))
        let group = [first, redose]

        let start = t0
        let end = t0.addingTimeInterval(minutes(300))
        let plot = TimelineWindowEvaluator.evaluate(doses: group, from: start, to: end, sampleCount: 31)

        // Same substance + route → one merged series, like the session's lanes.
        #expect(plot.series.count == 1)
        let values = try #require(plot.series.first).values
        for (index, value) in values.enumerated() {
            let globalMinutes = 300 * Double(index) / 30
            let expected = TimelineCurveModel.stackedIntensity(
                atGlobalMinutes: globalMinutes,
                group: group,
                earliestDose: t0,
            )
            // Both doses are within extent across this window, so the clipped
            // superposition and the session's agree exactly.
            #expect(abs(value - expected) < 1e-12)
        }
    }

    // MARK: - (b) Tile-boundary continuity

    @Test
    func `Samples are continuous across a tile boundary`() throws {
        let s = dose()
        let boundary = t0.addingTimeInterval(minutes(180))
        let left = TimelineWindowEvaluator.evaluate(
            doses: [s],
            from: t0,
            to: boundary,
            sampleCount: 61,
        )
        let right = TimelineWindowEvaluator.evaluate(
            doses: [s],
            from: boundary,
            to: t0.addingTimeInterval(minutes(360)),
            sampleCount: 61,
        )

        let leftSeries = try #require(left.series.first)
        let rightSeries = try #require(right.series.first)
        let leftEdge = try #require(leftSeries.values.last)
        let rightEdge = try #require(rightSeries.values.first)
        // Both tiles sample the exact boundary instant; the evaluated value is
        // a pure function of absolute time, so they agree to the bit.
        #expect(abs(leftEdge - rightEdge) < 1e-12)
        // And the boundary lands mid-curve — this isn't two zeros agreeing.
        #expect(leftEdge > 0.1)
    }

    @Test
    func `A dose ending before the boundary reads zero on both sides of it`() throws {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)
        // Boundary safely past the curve's draw end.
        let boundary = t0.addingTimeInterval(minutes(extent + 60))

        let left = TimelineWindowEvaluator.evaluate(
            doses: [s],
            from: t0,
            to: boundary,
            sampleCount: 61,
        )
        let right = TimelineWindowEvaluator.evaluate(
            doses: [s],
            from: boundary,
            to: boundary.addingTimeInterval(minutes(360)),
            sampleCount: 61,
        )

        // Left tile still carries the series (the dose is active earlier in the
        // window) but its boundary sample is zero — clipped at the extent, the
        // same place the session's drawn path lands on the baseline.
        #expect(try #require(left.series.first).values.last == 0)
        // Right tile: the activity window doesn't intersect — no series at all.
        #expect(right.series.isEmpty)
    }

    // MARK: - (c) Activity-window intersection

    @Test
    func `Doses contribute iff their activity window intersects the window`() throws {
        let extent = TimelineCurveModel.curveExtent(for: dose())

        // A: long over before the window. B: inside it. C: after it.
        let a = dose(name: "Beforezine", timestamp: t0)
        let b = dose(name: "Duringol", timestamp: t0.addingTimeInterval(minutes(extent + 200)))
        let c = dose(name: "Afterium", timestamp: t0.addingTimeInterval(minutes(extent + 2_000)))
        let start = t0.addingTimeInterval(minutes(extent + 100))
        let end = t0.addingTimeInterval(minutes(extent + 400))

        let plot = TimelineWindowEvaluator.evaluate(doses: [a, b, c], from: start, to: end)
        #expect(plot.series.map(\.name) == ["Duringol"])
        #expect(try #require(plot.series.first).values.contains { $0 > 0.1 })

        // A dose logged *before* the window whose curve reaches into it still
        // contributes — continuity is about activity, not the log timestamp.
        let straddling = TimelineWindowEvaluator.evaluate(
            doses: [a],
            from: t0.addingTimeInterval(minutes(100)),
            to: t0.addingTimeInterval(minutes(200)),
        )
        #expect(straddling.series.count == 1)
        #expect(try #require(straddling.series.first).values.allSatisfy { $0 > 0 })

        // Its dose tick stays out of windows that don't contain the timestamp.
        #expect(try #require(straddling.series.first).doseTimes.isEmpty)
    }

    @Test
    func `Relevant-dose culling matches the intersection rule`() {
        let s = dose()
        let extent = TimelineCurveModel.curveExtent(for: s)

        let interval = TimelineWindowEvaluator.activityInterval(of: s)
        #expect(interval.start == t0)
        #expect(abs(interval.duration - minutes(extent)) < 1e-9)

        // Just-touching windows count as intersecting; disjoint ones don't.
        let after = t0.addingTimeInterval(minutes(extent))
        #expect(TimelineWindowEvaluator.relevantDoses([s], from: after.addingTimeInterval(60), to: after.addingTimeInterval(3_600)).isEmpty)
        #expect(TimelineWindowEvaluator.relevantDoses([s], from: t0.addingTimeInterval(-3_600), to: t0.addingTimeInterval(-1)).isEmpty)
        #expect(TimelineWindowEvaluator.relevantDoses([s], from: t0.addingTimeInterval(minutes(100)), to: t0.addingTimeInterval(minutes(200))).count == 1)
    }
}
