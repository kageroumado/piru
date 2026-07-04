import Foundation
import Testing
@testable import Piru

@Suite("SessionClustering")
struct SessionClusteringTests {
    /// A fixed, timezone-stable base instant so hour offsets are exact.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// A dose `hours` after `base` with an effect duration in `effectHours`
    /// (`nil` → use the heuristic's fallback).
    private func dose(_ hours: Double, effectHours: Double?, background: Bool = false) -> SessionClustering.Dose {
        SessionClustering.Dose(
            timestamp: base.addingTimeInterval(hours * 3_600),
            effectDurationMinutes: effectHours.map { $0 * 60 },
            isBackgroundMed: background,
        )
    }

    /// Flattened group membership, for invariant checks.
    private func allIndices(_ groups: [[Int]]) -> [Int] {
        groups.flatMap(\.self).sorted()
    }

    // MARK: - Canonical cases from the plan

    @Test
    func `9 AM coffee and 3:45 AM next-dose are different sessions`() {
        // Caffeine at 09:00 (~5 h effect), then a dose ~18.75 h later (next pre-dawn).
        let doses = [dose(0, effectHours: 5), dose(18.75, effectHours: 4)]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0], [1]])
    }

    @Test
    func `All-nighter re-dosing every 2.5 h is one session crossing the clock cutoff`() {
        // 22:00, 00:30, 03:00, 05:00 — every gap ≤ floor.
        let doses = [
            dose(0, effectHours: 4),
            dose(2.5, effectHours: 4),
            dose(5, effectHours: 4),
            dose(7, effectHours: 4),
        ]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0, 1, 2, 3]])
    }

    @Test
    func `A short hit dropped into a long trip stays in the trip`() {
        // LSD (12 h) at 0, nicotine (1 h) at +1, caffeine (5 h) at +5.
        // The nicotine must not collapse the session's effect window.
        let doses = [
            dose(0, effectHours: 12),
            dose(1, effectHours: 1),
            dose(5, effectHours: 5),
        ]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0, 1, 2]])
    }

    @Test
    func `The sleep ceiling splits even a long-acting drug across a quiescent night`() {
        // LSD effect window runs ~14 h, but a 10 h quiescent gap (sleep) still splits.
        let doses = [dose(0, effectHours: 12), dose(10, effectHours: 12)]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0], [1]])
    }

    // MARK: - Decaying ceiling / day cap

    @Test
    func `The same 4 h gap joins early in a session but splits once it has run long`() {
        // Early: a 4 h gap on a fresh session (ceiling ~6 h) is one session.
        #expect(SessionClustering.cluster([dose(0, effectHours: 4), dose(4, effectHours: 4)]) == [[0, 1]])

        // Late: fill 18 h with 2 h-spaced doses, then the same 4 h gap. By 18 h in
        // the ceiling has decayed to ~3.4 h, so the 4 h gap now starts a new session.
        var doses = stride(from: 0.0, through: 18.0, by: 2.0).map { dose($0, effectHours: 4) }
        doses.append(dose(22, effectHours: 4)) // 4 h after the 18 h dose
        let groups = SessionClustering.cluster(doses)
        #expect(groups.count == 2)
        #expect(groups.last == [doses.count - 1])
    }

    @Test
    func `Nonstop redosing is hard-capped at 24 h into separate day sessions`() throws {
        // A dose every 2 h from 0…26 h — no gap ever exceeds the ceiling, but the
        // 24 h hard cap forces a new session for the dose a full day after the
        // first, so days can't chain.
        let doses = stride(from: 0.0, through: 26.0, by: 2.0).map { dose($0, effectHours: 4) }
        let groups = SessionClustering.cluster(doses)
        // First session spans < 24 h; the 24 h dose opens the second.
        #expect(groups.count == 2)
        let firstSpan = try doses[#require(groups[0].last)].timestamp.timeIntervalSince(doses[#require(groups[0].first)].timestamp)
        #expect(firstSpan < SessionClustering.Constants.horizon)
        #expect(groups[1].contains(doses.count - 1)) // the 26 h dose joins the 24 h one
    }

    @Test
    func `A long-acting tail is clamped so it cannot glue a later dose onto the session`() {
        // A very long-acting dose (48 h modeled), a short one 3 h later, then a
        // dose 5 h after that (8 h from the first). Without the effect-tail clamp
        // the 48 h tail would keep the session "active" and absorb the last dose;
        // clamped to 6 h, the last dose falls past the window and splits off.
        let doses = [
            dose(0, effectHours: 48),
            dose(3, effectHours: 1),
            dose(8, effectHours: 1),
        ]
        #expect(SessionClustering.cluster(doses) == [[0, 1], [2]])
    }

    // MARK: - Floor / fallback behavior

    @Test
    func `Unknown-duration doses within the floor group; beyond the effect window split`() {
        // Fallback effect is 4 h → scaled end 4.8 h.
        #expect(SessionClustering.cluster([dose(0, effectHours: nil), dose(2, effectHours: nil)]) == [[0, 1]])
        #expect(SessionClustering.cluster([dose(0, effectHours: nil), dose(6, effectHours: nil)]) == [[0], [1]])
    }

    // MARK: - Background medications

    @Test
    func `A lone background med is its own session`() {
        let groups = SessionClustering.cluster([dose(0, effectHours: nil, background: true)])
        #expect(groups == [[0]])
    }

    @Test
    func `A background med taken during an active session folds into it`() {
        // LSD at 0 (active ~14 h), maintenance pill at +2 h.
        let doses = [dose(0, effectHours: 12), dose(2, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0, 1]])
    }

    @Test
    func `A background med after the active window does not glue onto the ended session`() {
        // Caffeine (2 h → window 2.4 h) at 0, pill at +4 h (within ceiling, past the window).
        let doses = [dose(0, effectHours: 2), dose(4, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    @Test
    func `Co-administered background meds form one maintenance session`() {
        let doses = [
            dose(0, effectHours: nil, background: true),
            dose(0.1, effectHours: nil, background: true),
            dose(0.2, effectHours: nil, background: true),
        ]
        #expect(SessionClustering.cluster(doses) == [[0, 1, 2]])
    }

    @Test
    func `Morning and evening meds are separate maintenance sessions`() {
        let doses = [dose(0, effectHours: nil, background: true), dose(12, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    @Test
    func `A normal dose never absorbs a preceding maintenance session`() {
        // Morning vitamin (background), then a recreational dose 1 h later.
        let doses = [dose(0, effectHours: nil, background: true), dose(1, effectHours: 5)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    // MARK: - Invariants

    @Test
    func `Every dose lands in exactly one session; nothing orphaned or duplicated`() {
        let doses = [
            dose(0, effectHours: 12),
            dose(1, effectHours: 1),
            dose(5, effectHours: 5),
            dose(20, effectHours: 4),
            dose(20.2, effectHours: nil, background: true),
            dose(40, effectHours: 6),
            dose(60, effectHours: nil, background: true),
        ]
        let groups = SessionClustering.cluster(doses)
        #expect(allIndices(groups) == Array(0 ..< doses.count))
        #expect(groups.flatMap(\.self).count == doses.count) // no duplicates
    }

    @Test
    func `Clustering is idempotent: re-running over the same doses is identical`() {
        let doses = [
            dose(0, effectHours: 8),
            dose(3, effectHours: 4),
            dose(15, effectHours: 5),
            dose(15.1, effectHours: nil, background: true),
            dose(30, effectHours: 12),
        ]
        let first = SessionClustering.cluster(doses)
        let second = SessionClustering.cluster(doses)
        #expect(first == second)
    }

    @Test
    func `Empty input produces no sessions`() {
        #expect(SessionClustering.cluster([]).isEmpty)
    }

    // MARK: - canJoinKeepingTime (reassign cross-day guard)

    @Test
    func `A dose inside the session's span can join keeping its time`() {
        let first = base
        let last = base.addingTimeInterval(4 * 3_600)
        let inside = base.addingTimeInterval(2 * 3_600)
        #expect(SessionClustering.canJoinKeepingTime(doseTime: inside, sessionFirst: first, sessionLast: last))
    }

    @Test
    func `A dose within the ceiling of an edge can join keeping its time`() {
        let first = base
        let last = base.addingTimeInterval(4 * 3_600)
        // 6h after the last dose — beyond the span but at the ceilingMax edge.
        let after = last.addingTimeInterval(6 * 3_600)
        #expect(SessionClustering.canJoinKeepingTime(doseTime: after, sessionFirst: first, sessionLast: last))
        // 5h before the first dose — within the ceiling on the leading edge too.
        let before = first.addingTimeInterval(-5 * 3_600)
        #expect(SessionClustering.canJoinKeepingTime(doseTime: before, sessionFirst: first, sessionLast: last))
    }

    @Test
    func `A dose beyond the ceiling needs re-timing (cannot join as-is)`() {
        let first = base
        let last = base.addingTimeInterval(4 * 3_600)
        // ~37h after the last dose — a different day; must re-time.
        let nextDay = last.addingTimeInterval(37 * 3_600)
        #expect(!SessionClustering.canJoinKeepingTime(doseTime: nextDay, sessionFirst: first, sessionLast: last))
        // Just past the ceilingMax on the trailing edge.
        let justPast = last.addingTimeInterval(6 * 3_600 + 60)
        #expect(!SessionClustering.canJoinKeepingTime(doseTime: justPast, sessionFirst: first, sessionLast: last))
    }
}
