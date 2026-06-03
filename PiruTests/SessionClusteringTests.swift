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
            timestamp: base.addingTimeInterval(hours * 3600),
            effectDurationMinutes: effectHours.map { $0 * 60 },
            isBackgroundMed: background,
        )
    }

    /// Flattened group membership, for invariant checks.
    private func allIndices(_ groups: [[Int]]) -> [Int] { groups.flatMap { $0 }.sorted() }

    // MARK: - Canonical cases from the plan

    @Test("9 AM coffee and 3:45 AM next-dose are different sessions")
    func falseMergeIsSplit() {
        // Caffeine at 09:00 (~5 h effect), then a dose ~18.75 h later (next pre-dawn).
        let doses = [dose(0, effectHours: 5), dose(18.75, effectHours: 4)]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0], [1]])
    }

    @Test("All-nighter re-dosing every 2.5 h is one session crossing the clock cutoff")
    func allNighterMerges() {
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

    @Test("A short hit dropped into a long trip stays in the trip")
    func shortDoseDoesNotCloseLongSession() {
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

    @Test("The sleep ceiling splits even a long-acting drug across a quiescent night")
    func ceilingOverridesEffectWindow() {
        // LSD effect window runs ~14 h, but a 10 h quiescent gap (sleep) still splits.
        let doses = [dose(0, effectHours: 12), dose(10, effectHours: 12)]
        let groups = SessionClustering.cluster(doses)
        #expect(groups == [[0], [1]])
    }

    // MARK: - Floor / fallback behavior

    @Test("Unknown-duration doses within the floor group; beyond the effect window split")
    func unknownDurationUsesFallback() {
        // Fallback effect is 4 h → scaled end 4.8 h.
        #expect(SessionClustering.cluster([dose(0, effectHours: nil), dose(2, effectHours: nil)]) == [[0, 1]])
        #expect(SessionClustering.cluster([dose(0, effectHours: nil), dose(6, effectHours: nil)]) == [[0], [1]])
    }

    // MARK: - Background medications

    @Test("A lone background med is its own session")
    func loneBackgroundMedStandsAlone() {
        let groups = SessionClustering.cluster([dose(0, effectHours: nil, background: true)])
        #expect(groups == [[0]])
    }

    @Test("A background med taken during an active session folds into it")
    func backgroundMedJoinsActiveSession() {
        // LSD at 0 (active ~14 h), maintenance pill at +2 h.
        let doses = [dose(0, effectHours: 12), dose(2, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0, 1]])
    }

    @Test("A background med after the active window does not glue onto the ended session")
    func backgroundMedAfterWindowSplits() {
        // Caffeine (2 h → window 2.4 h) at 0, pill at +4 h (within ceiling, past the window).
        let doses = [dose(0, effectHours: 2), dose(4, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    @Test("Co-administered background meds form one maintenance session")
    func coAdministeredMedsMerge() {
        let doses = [
            dose(0, effectHours: nil, background: true),
            dose(0.1, effectHours: nil, background: true),
            dose(0.2, effectHours: nil, background: true),
        ]
        #expect(SessionClustering.cluster(doses) == [[0, 1, 2]])
    }

    @Test("Morning and evening meds are separate maintenance sessions")
    func medsFarApartSplit() {
        let doses = [dose(0, effectHours: nil, background: true), dose(12, effectHours: nil, background: true)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    @Test("A normal dose never absorbs a preceding maintenance session")
    func normalDoseDoesNotJoinMaintenance() {
        // Morning vitamin (background), then a recreational dose 1 h later.
        let doses = [dose(0, effectHours: nil, background: true), dose(1, effectHours: 5)]
        #expect(SessionClustering.cluster(doses) == [[0], [1]])
    }

    // MARK: - Invariants

    @Test("Every dose lands in exactly one session; nothing orphaned or duplicated")
    func partitionInvariant() {
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
        #expect(groups.flatMap { $0 }.count == doses.count) // no duplicates
    }

    @Test("Clustering is idempotent: re-running over the same doses is identical")
    func idempotent() {
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

    @Test("Empty input produces no sessions")
    func emptyInput() {
        #expect(SessionClustering.cluster([]).isEmpty)
    }
}
