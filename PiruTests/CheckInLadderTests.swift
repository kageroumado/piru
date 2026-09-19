import Foundation
import Testing
@testable import Piru

/// Check-in times read off a dose's own phase boundaries rather than a fixed
/// ladder — the thing that makes a twelve-hour session and a vaporized one ask
/// a different number of questions.
@Suite("CheckInLadder")
struct CheckInLadderTests {
    private func state(
        at timestamp: Date = .init(timeIntervalSince1970: 0),
        onset: Double, comeup: Double, peak: Double, offset: Double, total: Double,
    ) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: "Test",
            colorHex: "FF66AA",
            doseTimestamp: timestamp,
            amount: 1,
            unit: "mg",
            route: "oral",
            onsetEndMinutes: onset,
            comeupEndMinutes: comeup,
            peakEndMinutes: peak,
            offsetEndMinutes: offset,
            afterglowEndMinutes: nil,
            totalMinutes: total,
        )
    }

    /// A 10-hour psychedelic: every boundary and every mid-phase.
    private var lsd: ActiveSubstanceState {
        state(onset: 45, comeup: 150, peak: 330, offset: 600, total: 600)
    }

    /// A 4-hour oral stimulant.
    private var methylphenidate: ActiveSubstanceState {
        state(onset: 30, comeup: 60, peak: 180, offset: 240, total: 240)
    }

    /// Vaporized DMT: over inside half an hour.
    private var dmt: ActiveSubstanceState {
        state(onset: 0.5, comeup: 2, peak: 8, offset: 25, total: 25)
    }

    // MARK: - Depth per class

    @Test
    func `Depth follows what a prompt can learn, not how long the drug lasts`() {
        #expect(CheckInLadder.Depth(category: .psychedelic) == .wide)
        #expect(CheckInLadder.Depth(category: .empathogen) == .wide)
        #expect(CheckInLadder.Depth(category: .opioid) == .paced)
        // A twelve-hour Concerta is still a medication with one question.
        #expect(CheckInLadder.Depth(category: .stimulant) == .light)
        #expect(CheckInLadder.Depth(category: .antidepressant) == .light)
    }

    @Test
    func `A wide session is asked about seven times, a medication twice`() {
        #expect(CheckInLadder.moments(in: lsd, depth: .wide).count == 7)
        #expect(CheckInLadder.moments(in: lsd, depth: .paced).count == 4)
        #expect(CheckInLadder.moments(in: methylphenidate, depth: .light).count == 2)
    }

    @Test
    func `The light pair is the middle of the plateau and where it turns`() {
        let moments = CheckInLadder.moments(in: methylphenidate, depth: .light)
        #expect(moments == [120, 180])
    }

    // MARK: - Rounding and range

    @Test
    func `Granularity opens up as the dose gets longer`() {
        #expect(CheckInLadder.granularity(totalMinutes: 25) == 5)
        #expect(CheckInLadder.granularity(totalMinutes: 240) == 15)
        #expect(CheckInLadder.granularity(totalMinutes: 600) == 30)
    }

    @Test
    func `A short vaporized dose yields a couple of times, never one mid-flight`() {
        let anchor = Date(timeIntervalSince1970: 0)
        let offsets = CheckInLadder.offsets(for: dmt, depth: .wide, anchor: anchor)
        #expect(!offsets.isEmpty)
        #expect(offsets.count <= 4)
        // Nothing lands before the floor — a prompt at T+1 arrives on the phone
        // still in the hand that logged the dose.
        #expect(offsets.allSatisfy { $0 >= CheckInOffsets.minimumMinutes })
    }

    @Test
    func `A long session yields many more times than a short one`() {
        let anchor = Date(timeIntervalSince1970: 0)
        let long = CheckInLadder.offsets(for: lsd, depth: .wide, anchor: anchor)
        let short = CheckInLadder.offsets(for: dmt, depth: .wide, anchor: anchor)
        #expect(long.count > short.count)
        #expect(long.allSatisfy { $0 <= CheckInOffsets.maximumMinutes })
    }

    @Test
    func `A dose taken before the anchor has its times shifted back`() {
        let anchor = Date(timeIntervalSince1970: 3_600)
        let earlier = state(
            at: anchor.addingTimeInterval(-3_600),
            onset: 30, comeup: 60, peak: 180, offset: 240, total: 240,
        )
        // The plateau midpoint is 120 min after the dose, so 60 after the anchor.
        #expect(CheckInLadder.offsets(for: earlier, depth: .light, anchor: anchor).first == 60)
    }

    // MARK: - Thinning

    @Test
    func `Thinning keeps both ends rather than spending the budget on the first hour`() {
        let many = Array(stride(from: 10, through: 10 * 30, by: 10))
        let thinned = CheckInLadder.thinned(many)
        #expect(thinned.count == CheckInOffsets.maximumCount)
        #expect(thinned.first == many.first)
        #expect(thinned.last == many.last)
    }

    @Test
    func `A list under the cap is left alone`() {
        #expect(CheckInLadder.thinned([30, 60, 90]) == [30, 60, 90])
    }

    @Test
    func `The summary reads as relative times`() {
        #expect(CheckInLadder.summary([45, 120]) == "+45m · +2h")
        #expect(CheckInLadder.summary([]).isEmpty)
    }
}

/// What the session screen shows for a schedule that is already running.
@Suite("CheckInScheduler plan")
struct CheckInSchedulerPlanTests {
    @Test
    func `A plan keeps the times that have gone and marks them`() {
        let anchor = Date(timeIntervalSince1970: 0)
        let now = anchor.addingTimeInterval(150 * 60)
        let plan = CheckInScheduler.plan(cadence: .everyHour, anchor: anchor, now: now)

        // fireDates drops the past; the plan does not — a schedule that listed
        // only what is left could not say what had already happened.
        #expect(plan.count == CheckInScheduler.Cadence.everyHour.fixedOffsetMinutes.count)
        #expect(plan.prefix(2).allSatisfy { $0.state == .passed })
        #expect(plan.dropFirst(2).allSatisfy { $0.state != .passed })
        #expect(plan.first?.offsetMinutes == 60)
    }

    @Test
    func `A custom plan runs the session's own times`() {
        let anchor = Date(timeIntervalSince1970: 0)
        let plan = CheckInScheduler.plan(
            cadence: .custom, custom: [45, 120, 300], anchor: anchor, now: anchor,
        )
        #expect(plan.map(\.offsetMinutes) == [45, 120, 300])
        #expect(plan.allSatisfy { $0.state != .passed })
        #expect(plan[1].date == anchor.addingTimeInterval(120 * 60))
    }
}
