import Foundation
import SwiftData
import Testing
@testable import Piru

@MainActor
@Suite("SessionService")
struct SessionServiceTests {
    /// An in-memory store with the full current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A name guaranteed absent from the substance library, so effect duration
    /// falls back to the heuristic default (240 min → ~4.8 h effect window) and
    /// the tests are independent of bundled data.
    private let unknown = "ZZTestSubstanceNotInLibrary"

    private func insert(_ context: ModelContext, hoursFromNow: Double, background: Bool = false) -> DoseEntry {
        let entry = DoseEntry(
            substance: unknown,
            amount: 100,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(hoursFromNow * 3_600),
            isBackgroundMed: background,
        )
        context.insert(entry)
        return entry
    }

    private func sessions(_ context: ModelContext) throws -> [Session] {
        try context.fetch(FetchDescriptor<Session>())
    }

    // MARK: - Populate (history backfill)

    @Test
    func `Populate assigns every dose to exactly one session — none orphaned or duplicated`() throws {
        let context = try makeContext()
        let doses = [0.0, 1, 2, 20, 21, 48].map { insert(context, hoursFromNow: $0) }
        try context.save()

        SessionService.assignUnassignedDoses(in: context)

        for dose in doses {
            #expect(dose.session != nil)
        }
        let assigned = try sessions(context).flatMap(\.orderedDoses)
        #expect(assigned.count == doses.count) // no duplicates
        #expect(Set(assigned.map(\.persistentModelID)).count == doses.count)
    }

    @Test
    func `Populate splits widely-spaced doses and groups close ones`() throws {
        let context = try makeContext()
        // Three clusters: {0,1,2}, {20,21}, {48}.
        _ = [0.0, 1, 2, 20, 21, 48].map { insert(context, hoursFromNow: $0) }
        try context.save()

        SessionService.assignUnassignedDoses(in: context)
        #expect(try sessions(context).count == 3)
    }

    @Test
    func `resplitOverlongSessions breaks a multi-day session at its rest gaps and keeps the title on the first piece`() throws {
        let context = try makeContext()
        // Build ONE session that the old flat-ceiling heuristic would have chained:
        // dense 2 h-spaced doses spanning ~30 h with sub-ceiling crash gaps.
        let session = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000), title: "Bender")
        context.insert(session)
        let stamps = stride(from: 0.0, through: 30.0, by: 2.0)
        for hours in stamps {
            let dose = insert(context, hoursFromNow: hours)
            dose.session = session
        }
        session.refreshStartDate()
        try context.save()
        #expect(try sessions(context).count == 1)

        // Force the one-time gate open, then run the migration.
        UserDefaults.standard.set(false, forKey: "didResplitOverlongSessionsV1")
        SessionService.resplitOverlongSessions(in: context)

        let result = try sessions(context)
        #expect(result.count > 1) // the multi-day session was broken up
        // No resulting session exceeds the 24 h day cap.
        for piece in result {
            let doses = piece.orderedDoses
            if let first = doses.first?.timestamp, let last = doses.last?.timestamp {
                #expect(last.timeIntervalSince(first) < SessionClustering.Constants.horizon)
            }
        }
        // The title rides with the earliest piece (the retained original session).
        let earliest = result.min { $0.startDate < $1.startDate }
        #expect(earliest?.title == "Bender")
        // Every dose still belongs to exactly one session — nothing orphaned.
        let assigned = result.flatMap(\.orderedDoses)
        #expect(assigned.count == Array(stamps).count)
    }

    @Test
    func `resplitOverlongSessions runs once — a second call is a no-op even on a fresh overlong session`() throws {
        let context = try makeContext()
        UserDefaults.standard.set(false, forKey: "didResplitOverlongSessionsV1")
        // First run trips the flag (no sessions to split here — just arm it).
        SessionService.resplitOverlongSessions(in: context)

        // A user later merges two days into a >24 h session on purpose.
        let session = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(session)
        for hours in stride(from: 0.0, through: 30.0, by: 2.0) {
            insert(context, hoursFromNow: hours).session = session
        }
        session.refreshStartDate()
        try context.save()

        // The gate is spent, so the deliberate overlong session survives.
        SessionService.resplitOverlongSessions(in: context)
        #expect(try sessions(context).count == 1)
    }

    @Test
    func `Populate is idempotent — a second run creates no new sessions`() throws {
        let context = try makeContext()
        _ = [0.0, 1, 20].map { insert(context, hoursFromNow: $0) }
        try context.save()

        SessionService.assignUnassignedDoses(in: context)
        let first = try sessions(context).count
        SessionService.assignUnassignedDoses(in: context)
        #expect(try sessions(context).count == first)
    }

    @Test
    func `ensureSessionsPopulated clusters session-less doses unconditionally (recovery regression)`() throws {
        // Mirrors the post-recovery state: doses exist with no session (e.g.
        // restored from a pre-session backup). This must cluster them even though
        // a prior empty-launch may have set the old "already populated" flag —
        // the flag gating was the bug that left every dose as its own session.
        let context = try makeContext()
        let doses = [0.0, 1, 2, 20, 21, 48].map { insert(context, hoursFromNow: $0) }
        try context.save()
        for dose in doses {
            #expect(dose.session == nil)
        }

        SessionService.ensureSessionsPopulated(in: context)

        for dose in doses {
            #expect(dose.session != nil)
        }
        #expect(try sessions(context).count == 3) // {0,1,2} {20,21} {48}
    }

    @Test
    func `startDate equals the session's earliest dose`() throws {
        let context = try makeContext()
        _ = [0.0, 1, 2].map { insert(context, hoursFromNow: $0) }
        try context.save()
        SessionService.assignUnassignedDoses(in: context)

        let session = try #require(try sessions(context).first)
        #expect(session.startDate == session.orderedDoses.first?.timestamp)
    }

    // MARK: - Log-time assignment

    @Test
    func `A close follow-up dose joins; a distant one starts a new session`() throws {
        let context = try makeContext()

        let a = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: a, in: context)
        #expect(try sessions(context).count == 1)

        let b = insert(context, hoursFromNow: 1) // within the effect window → joins
        SessionService.assignSession(for: b, in: context)
        #expect(try sessions(context).count == 1)
        #expect(b.session === a.session)

        let c = insert(context, hoursFromNow: 20) // past the sleep ceiling → new
        SessionService.assignSession(for: c, in: context)
        #expect(try sessions(context).count == 2)
        #expect(c.session !== a.session)
    }

    @Test
    func `A back-dated dose just before a session's first dose prepends into it`() throws {
        // TestFlight feedback (build 15): a dose logged "15 minutes ago" right
        // after another dose had opened a session got its own session because
        // assignment only looked backwards (in-span / extend), never forwards.
        let context = try makeContext()

        let kratom = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: kratom, in: context)
        #expect(try sessions(context).count == 1)

        let backdated = insert(context, hoursFromNow: -0.25) // 15 min earlier
        SessionService.assignSession(for: backdated, in: context)

        #expect(backdated.session === kratom.session)
        #expect(try sessions(context).count == 1)
        // The session's start follows its new earliest dose.
        #expect(kratom.session?.startDate == backdated.timestamp)
    }

    @Test
    func `A back-dated dose far before a session still starts its own`() throws {
        let context = try makeContext()

        let a = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: a, in: context)

        let distant = insert(context, hoursFromNow: -20) // past the ceiling
        SessionService.assignSession(for: distant, in: context)

        #expect(distant.session !== a.session)
        #expect(try sessions(context).count == 2)
    }

    // MARK: - Background medications

    @Test
    func `A lone background med forms its own maintenance session`() throws {
        let context = try makeContext()
        let med = insert(context, hoursFromNow: 0, background: true)
        SessionService.assignSession(for: med, in: context)

        let session = try #require(med.session)
        #expect(session.isMaintenance)
    }

    @Test
    func `A background med during an active session folds in and the session stays non-maintenance`() throws {
        let context = try makeContext()
        let rec = insert(context, hoursFromNow: 0) // recreational, ~4.8 h window
        SessionService.assignSession(for: rec, in: context)

        let med = insert(context, hoursFromNow: 2, background: true)
        SessionService.assignSession(for: med, in: context)

        #expect(med.session === rec.session)
        #expect(try sessions(context).count == 1)
        #expect(rec.session?.isMaintenance == false)
    }

    // MARK: - Manual overrides

    @Test
    func `Merge moves all doses into the target and deletes the source`() throws {
        let context = try makeContext()
        let a = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: a, in: context)
        let b = insert(context, hoursFromNow: 20) // separate session
        SessionService.assignSession(for: b, in: context)
        let target = try #require(a.session)
        let source = try #require(b.session)
        #expect(try sessions(context).count == 2)

        SessionService.merge(source, into: target, in: context)

        #expect(try sessions(context).count == 1)
        #expect(b.session === target)
        #expect(target.orderedDoses.count == 2)
        #expect(target.startDate == a.timestamp) // earliest preserved
    }

    @Test
    func `Split moves the pivot and later doses into a new session`() throws {
        let context = try makeContext()
        let doses = [0.0, 1, 2, 3].map { insert(context, hoursFromNow: $0) }
        SessionService.assignUnassignedDoses(in: context)
        let original = try #require(doses[0].session)
        #expect(original.orderedDoses.count == 4)

        let newSession = try #require(SessionService.split(original, at: doses[2], in: context))

        #expect(original.orderedDoses.map(\.timestamp) == [doses[0], doses[1]].map(\.timestamp))
        #expect(newSession.orderedDoses.map(\.timestamp) == [doses[2], doses[3]].map(\.timestamp))
        #expect(newSession.startDate == doses[2].timestamp)
        #expect(try sessions(context).count == 2)
    }

    @Test
    func `Splitting at the first dose is a no-op`() throws {
        let context = try makeContext()
        let doses = [0.0, 1].map { insert(context, hoursFromNow: $0) }
        SessionService.assignUnassignedDoses(in: context)
        let original = try #require(doses[0].session)
        #expect(SessionService.split(original, at: doses[0], in: context) == nil)
        #expect(try sessions(context).count == 1)
    }

    @Test
    func `Moving the last dose out of a session deletes the empty source`() throws {
        let context = try makeContext()
        let a = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: a, in: context)
        let b = insert(context, hoursFromNow: 20)
        SessionService.assignSession(for: b, in: context)
        let target = try #require(a.session)
        let source = try #require(b.session)

        SessionService.move(b, to: target, in: context)

        #expect(b.session === target)
        #expect(try sessions(context).count == 1)
        #expect((source.doses ?? []).isEmpty)
    }

    @Test
    func `Setting and clearing a title`() throws {
        let context = try makeContext()
        let a = insert(context, hoursFromNow: 0)
        SessionService.assignSession(for: a, in: context)
        let session = try #require(a.session)

        SessionService.setTitle("  Festival  ", for: session)
        #expect(session.title == "Festival")
        SessionService.setTitle("   ", for: session)
        #expect(session.title == nil)
    }
}
