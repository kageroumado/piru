import Foundation
import SwiftData

/// Assigns `DoseEntry`s to ``Session``s — the app-side bridge between the pure
/// ``SessionClustering`` heuristic and the SwiftData store.
///
/// Two entry points:
/// - ``assignSession(for:in:)`` places a single freshly-logged dose (join the
///   session it follows, or start a new one). Used at every log site.
/// - ``ensureSessionsPopulated(in:)`` backfills sessions over all history once,
///   at launch, for stores that predate the session model. Idempotent and
///   failure-isolated: it only ever sets the optional ``DoseEntry/session``
///   relationship, never touching dose data.
///
/// Sessions are decided here at log time and persisted; they are **not** re-run
/// on render. The user owns the result afterwards via merge / split / reassign.
@MainActor
enum SessionService {
    /// Map a dose to clustering input, resolving its modeled effect duration from
    /// the substance library (the curve length the timeline would draw).
    static func clusterDose(for entry: DoseEntry) -> SessionClustering.Dose {
        SessionClustering.Dose(
            timestamp: entry.timestamp,
            effectDurationMinutes: ActiveSubstanceState.from(entry: entry, colorHex: "")?.totalMinutes,
            isBackgroundMed: entry.isBackgroundMed,
        )
    }

    // MARK: - Single-dose assignment (log time)

    /// Assign `entry` to the session it belongs to, or a new one. Precedence:
    /// 1. **In-span** — if the dose's timestamp falls inside an existing
    ///    session's `[first … last]` dose range, it belongs to that session
    ///    (even when logged out of order), so it joins rather than spawning an
    ///    overlapping session. Among any transitional overlaps the most recent
    ///    start wins.
    /// 2. **Extend** — otherwise the candidate is the most recent session whose
    ///    last dose is at or before this dose; the clustering heuristic decides
    ///    join-vs-new from the trailing gap.
    /// 3. **New** — failing both, start a fresh session.
    ///
    /// The user still owns the result afterwards via merge / split / reassign.
    @discardableResult
    static func assignSession(for entry: DoseEntry, in context: ModelContext) -> Session {
        let target = entry.timestamp
        let sessions = (try? context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]),
        )) ?? []

        // 1. In-span join — a dose inside a session's active window is part of
        //    it, no gap to weigh. Keeps sessions from overlapping.
        for session in sessions {
            let stamps = session.orderedDoses.filter { $0 !== entry }.map(\.timestamp)
            guard let first = stamps.min(), let last = stamps.max() else { continue }
            if target >= first, target <= last {
                entry.session = session
                session.refreshStartDate()
                return session
            }
        }

        // 2. Extend the session this dose follows.
        var candidate: Session?
        var candidateLast = Date.distantPast
        for session in sessions {
            let priorDoses = session.orderedDoses.filter { $0 !== entry }
            guard let last = priorDoses.map(\.timestamp).max(), last <= target else { continue }
            if last > candidateLast {
                candidate = session
                candidateLast = last
            }
        }

        let openState = candidate.flatMap { session in
            SessionClustering.OpenSession(doses: session.orderedDoses.filter { $0 !== entry }.map(clusterDose))
        }

        if case .join = SessionClustering.placement(of: clusterDose(for: entry), into: openState),
           let candidate {
            entry.session = candidate
            candidate.refreshStartDate()
            return candidate
        }

        // 3. Prepend — a back-dated dose may immediately precede an existing
        //    session (logged late, e.g. "15 minutes ago" right after a dose
        //    that already opened one). Mirror the extend heuristic: would the
        //    session's first dose join a session that ends with this one?
        var nextSession: Session?
        var nextFirstDose: DoseEntry?
        for session in sessions {
            let laterDoses = session.orderedDoses.filter { $0 !== entry }
            guard let first = laterDoses.min(by: { $0.timestamp < $1.timestamp }),
                  first.timestamp >= target else { continue }
            if nextFirstDose == nil || first.timestamp < nextFirstDose!.timestamp {
                nextSession = session
                nextFirstDose = first
            }
        }
        if let nextSession, let nextFirstDose {
            let endingWithEntry = SessionClustering.OpenSession(doses: [clusterDose(for: entry)])
            if case .join = SessionClustering.placement(of: clusterDose(for: nextFirstDose), into: endingWithEntry) {
                entry.session = nextSession
                nextSession.refreshStartDate()
                return nextSession
            }
        }

        let session = Session(startDate: entry.timestamp)
        context.insert(session)
        entry.session = session
        return session
    }

    // MARK: - Bulk backfill (history / import)

    /// Cluster every session-less dose into new sessions. Used by the launch
    /// populate pass and after a data import. Clusters the unassigned doses among
    /// themselves (existing sessions are left intact), so a fresh store gets a
    /// complete, correct grouping and an import builds its own sessions.
    static func assignUnassignedDoses(in context: ModelContext) {
        let all = (try? context.fetch(
            FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]),
        )) ?? []
        let unassigned = all.filter { $0.session == nil }
        guard !unassigned.isEmpty else { return }

        let groups = SessionClustering.cluster(unassigned.map(clusterDose))
        for group in groups {
            let doses = group.map { unassigned[$0] }
            guard let start = doses.map(\.timestamp).min() else { continue }
            let session = Session(startDate: start)
            context.insert(session)
            for dose in doses {
                dose.session = session
            }
        }
        try? context.save()
    }

    // MARK: - Manual overrides (the user owns the grouping)

    /// Merge `source` entirely into `target`; every source dose is reassigned and
    /// the now-empty source session is deleted. The user's explicit say-so, so no
    /// heuristic re-evaluation. No-op if they're the same session.
    static func merge(_ source: Session, into target: Session, in context: ModelContext) {
        guard source.persistentModelID != target.persistentModelID else { return }
        for dose in source.orderedDoses {
            dose.session = target
        }
        context.delete(source)
        target.refreshStartDate()
    }

    /// Split `session` so that `pivot` and every later dose move into a new
    /// session, returned. No-op (returns `nil`) if `pivot` is the first dose —
    /// there'd be nothing left in the original.
    @discardableResult
    static func split(_ session: Session, at pivot: DoseEntry, in context: ModelContext) -> Session? {
        let doses = session.orderedDoses
        guard let index = doses.firstIndex(where: { $0 === pivot }), index > 0 else { return nil }
        let moving = Array(doses[index...])
        let newSession = Session(startDate: pivot.timestamp)
        context.insert(newSession)
        for dose in moving {
            dose.session = newSession
        }
        session.refreshStartDate()
        newSession.refreshStartDate()
        return newSession
    }

    /// Move a single `dose` to `target`. The source session is deleted if it
    /// becomes empty, otherwise its `startDate` is refreshed.
    static func move(_ dose: DoseEntry, to target: Session, in context: ModelContext) {
        let source = dose.session
        guard source?.persistentModelID != target.persistentModelID else { return }
        dose.session = target
        target.refreshStartDate()
        if let source {
            if (source.doses ?? []).isEmpty {
                context.delete(source)
            } else {
                source.refreshStartDate()
            }
        }
    }

    /// Set (or clear) a session's user title; blank trims to `nil`.
    static func setTitle(_ title: String, for session: Session) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.isEmpty ? nil : trimmed
    }

    /// Set (or clear) a session's note; blank trims to `nil`.
    static func setNote(_ note: String, for session: Session) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = trimmed.isEmpty ? nil : trimmed
    }

    /// Sweep every session-less dose into a session. Safe and cheap to call on
    /// each launch: ``assignUnassignedDoses(in:)`` only touches `session == nil`
    /// doses (a no-op once everything is grouped) and never disturbs the user's
    /// manual merges / splits.
    ///
    /// This deliberately has **no** "already done" flag. The previous flag-gated
    /// version stranded data: a launch that ran on an empty in-memory store (while
    /// the persistent store was temporarily unavailable — see StoreRecovery) set
    /// the flag with zero doses, so when the real data was later recovered every
    /// dose stayed session-less and rendered as its own session. Sweeping
    /// unconditionally self-heals that, and any pre-session / imported / recovered
    /// history, without ever re-clustering doses that already have a session.
    static func ensureSessionsPopulated(in context: ModelContext) {
        assignUnassignedDoses(in: context)
    }
}
