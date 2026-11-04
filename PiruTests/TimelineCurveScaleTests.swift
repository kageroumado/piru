import Foundation
import Testing
@testable import Piru

/// ``TimelineStripBuilder/relativeWeights(states:lookback:)`` — the per-dose
/// weights behind the relative ``TimelineCurveScale`` choices: each dose is
/// measured against the tallest crest in the window before it.
@Suite("TimelineCurveScale")
struct TimelineCurveScaleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86400

    /// A four-hour curve peaking between 30 and 120 minutes.
    private func dose(daysIn: Double, magnitude: Double, amount: Double = 1, unscaled: Bool = false) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: "Amphetamine",
            tint: P3Color(red: 0.929, green: 0.439, blue: 0.660),
            doseTimestamp: start.addingTimeInterval(daysIn * day),
            amount: amount,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: 20,
            comeupEndMinutes: 30,
            peakEndMinutes: 120,
            offsetEndMinutes: 240,
            afterglowEndMinutes: nil,
            totalMinutes: 240,
            doseIntensity: min(magnitude, 1),
            doseMagnitude: magnitude,
            doseIsUnscaled: unscaled,
            tachyphylaxis: 0,
            comeupSpreadMinutes: nil,
            peakSpreadMinutes: nil,
            offsetSpreadMinutes: nil,
        )
    }

    @Test
    func `A lone dose fills the lane whatever its strength`() {
        let weights = TimelineStripBuilder.relativeWeights(states: [dose(daysIn: 0, magnitude: 0.2)], lookback: 7 * day)
        let crestShape = TimelineCurveModel.intensity(at: 75, for: dose(daysIn: 0, magnitude: 0.2))
        #expect(abs(weights[0] * crestShape - 1) < 1e-9)
    }

    @Test
    func `A lighter dose inside the window reads as a fraction of the larger one`() {
        let states = [dose(daysIn: 0, magnitude: 0.8), dose(daysIn: 3, magnitude: 0.4)]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(weights[1] / weights[0] - 0.5) < 1e-9)
    }

    @Test
    func `A larger dose that has aged out of the window no longer shrinks the new one`() {
        let states = [dose(daysIn: 0, magnitude: 0.8), dose(daysIn: 10, magnitude: 0.4)]
        let week = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(week[1] - week[0]) < 1e-9)
        let month = TimelineStripBuilder.relativeWeights(states: states, lookback: 30 * day)
        #expect(abs(month[1] / month[0] - 0.5) < 1e-9)
    }

    @Test
    func `All time measures an earlier dose against a later, larger one too`() {
        let states = [dose(daysIn: 0, magnitude: 0.4), dose(daysIn: 100, magnitude: 0.8)]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: .infinity)
        #expect(abs(weights[0] / weights[1] - 0.5) < 1e-9)
    }

    @Test
    func `A substance with no ladder is measured by its amounts`() {
        let states = [
            dose(daysIn: 0, magnitude: 0.6, amount: 200, unscaled: true),
            dose(daysIn: 1, magnitude: 0.6, amount: 50, unscaled: true),
        ]
        let weights = TimelineStripBuilder.relativeWeights(states: states, lookback: 7 * day)
        #expect(abs(weights[1] / weights[0] - 0.25) < 1e-9)
    }

    @Test
    func `A redose that stacks sets a taller reference than either dose alone`() {
        let single = TimelineStripBuilder.relativeWeights(states: [dose(daysIn: 0, magnitude: 0.5)], lookback: 7 * day)
        let redosed = TimelineStripBuilder.relativeWeights(
            states: [dose(daysIn: 0, magnitude: 0.5), dose(daysIn: 1.0 / 24, magnitude: 0.5)],
            lookback: 7 * day,
        )
        #expect(redosed[0] < single[0])
    }

    // MARK: - Stacking within the lane

    /// The stacked value of `states` drawn with `weights`, sampled every five
    /// minutes across their curves.
    private func stackedSamples(_ states: [ActiveSubstanceState], weights: [Double]) -> [Double] {
        let ends = states.map(TimelineStripBuilder.drawMinutes(for:))
        let first = states.map(\.doseTimestamp).min()!
        let last = zip(states, ends).map { $0.doseTimestamp.addingTimeInterval($1 * 60) }.max()!
        return stride(from: 0.0, through: last.timeIntervalSince(first), by: 300).map { offset in
            TimelineStripBuilder.effectValue(at: first.addingTimeInterval(offset), states: states, weights: weights, ends: ends)
        }
    }

    @Test
    func `A lone dose keeps its own weight`() {
        let states = [dose(daysIn: 0, magnitude: 0.9)]
        let ends = states.map(TimelineStripBuilder.drawMinutes(for:))
        #expect(TimelineStripBuilder.stackDivisors(states: states, weights: [0.9], ends: ends) == [1])
    }

    @Test
    func `Doses far apart keep their own weights`() {
        let states = [dose(daysIn: 0, magnitude: 1), dose(daysIn: 1, magnitude: 1)]
        let ends = states.map(TimelineStripBuilder.drawMinutes(for:))
        #expect(TimelineStripBuilder.stackDivisors(states: states, weights: [1, 1], ends: ends) == [1, 1])
    }

    @Test
    func `Two full doses an hour apart stack to the lane's edge with their shape kept`() throws {
        let states = [dose(daysIn: 0, magnitude: 1), dose(daysIn: 1.0 / 24, magnitude: 1)]
        let ends = states.map(TimelineStripBuilder.drawMinutes(for:))
        let divisors = TimelineStripBuilder.stackDivisors(states: states, weights: [1, 1], ends: ends)
        #expect(divisors.allSatisfy { $0 > 1 })
        let raw = stackedSamples(states, weights: [1, 1])
        let scaled = stackedSamples(states, weights: zip([1.0, 1.0], divisors).map { $0 / $1 })
        #expect(try #require(raw.max()) > 1.2)
        // Crest sampling can miss the true top by a hair; the clamp takes that.
        #expect(try #require(scaled.max()) <= 1.02)
        #expect(try #require(scaled.max()) > 0.9)
        // Scaled, not clipped: no long run of samples pinned at the edge.
        let pinned = scaled.count(where: { $0 > 0.99 })
        #expect(pinned < raw.count(where: { $0 > 1 }))
    }

    @Test
    func `A curve is drawn until it has settled onto the axis`() {
        // A profile whose total sits inside its own offset: the shape there is
        // still well above baseline, so the drawn end runs past it.
        let base = dose(daysIn: 0, magnitude: 1)
        let cut = ActiveSubstanceState(
            substanceName: base.substanceName,
            tint: base.tint,
            doseTimestamp: base.doseTimestamp,
            amount: 1,
            unit: "g",
            route: "oral",
            onsetEndMinutes: 20,
            comeupEndMinutes: 30,
            peakEndMinutes: 120,
            offsetEndMinutes: 300,
            afterglowEndMinutes: nil,
            totalMinutes: 240,
            doseIntensity: 1,
            doseMagnitude: 1,
            doseIsUnscaled: false,
            tachyphylaxis: 0,
            comeupSpreadMinutes: nil,
            peakSpreadMinutes: nil,
            offsetSpreadMinutes: nil,
        )
        #expect(TimelineCurveModel.intensity(at: cut.totalMinutes, for: cut) > 0.05)
        let end = TimelineStripBuilder.drawMinutes(for: cut)
        #expect(end > cut.totalMinutes)
        #expect(TimelineCurveModel.intensity(at: end, for: cut) < 0.02)
        // A profile that already lands by its total keeps it.
        let landed = dose(daysIn: 0, magnitude: 1)
        #expect(TimelineStripBuilder.drawMinutes(for: landed) >= landed.totalMinutes)
    }

    @Test
    func `A dose drawn at a quarter of the lane ends where its width falls below the floor`() {
        let state = dose(daysIn: 0, magnitude: 0.25)
        let full = TimelineStripBuilder.drawMinutes(for: state)
        let end = TimelineStripBuilder.visibleDrawMinutes(for: state, weight: 0.25, drawEnd: full)
        #expect(end < full)
        // The closed form ignores the crest dome, which only lowers the curve, so
        // the cut lands at the floor or just under it.
        let drawn = 0.25 * TimelineCurveModel.intensity(at: end, for: state)
        #expect(drawn <= 0.02 && drawn > 0.015)
    }

    @Test
    func `A dose drawn at the lane's edge ends where the curve lands on the axis`() {
        let state = dose(daysIn: 0, magnitude: 1)
        let full = TimelineStripBuilder.drawMinutes(for: state)
        let end = TimelineStripBuilder.visibleDrawMinutes(for: state, weight: 1, drawEnd: full)
        #expect(end <= full && full - end < 15)
    }

    @Test
    func `A dose too small to clear the floor keeps its full end`() {
        let state = dose(daysIn: 0, magnitude: 0.01)
        let full = TimelineStripBuilder.drawMinutes(for: state)
        #expect(TimelineStripBuilder.visibleDrawMinutes(for: state, weight: 0.01, drawEnd: full) == full)
    }
}
