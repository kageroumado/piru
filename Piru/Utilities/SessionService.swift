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
        // Candidate window: every placement rule requires the joined span to fit
        // inside `SessionClustering.Constants.horizon` (24 h), so only sessions
        // whose persisted dose bounds come within one horizon of the target can
        // matter — rule 1's in-span sessions satisfy both bounds trivially
        // (merged sessions are bounded on both ends, not by span length), rule 2
        // needs `lastDoseDate` within a gap ≤ horizon behind the target, rule 3
        // needs `startDate` within a horizon ahead. The persisted bounds only
        // bound this fetch; placement below re-derives the true span from the
        // doses. `lastDoseDate == nil` rows (predating the field) are always
        // fetched and self-heal. The prefetch then realizes only the candidates'
        // doses — without it each span check is a lazy per-relationship fault,
        // and without the window it realized every dose in the store on every
        // logged dose.
        let lower = target.addingTimeInterval(-SessionClustering.Constants.horizon)
        let upper = target.addingTimeInterval(SessionClustering.Constants.horizon)
        // `?? lower` only gives the nil case a value that the first arm already
        // admitted; SwiftData's translator rejects forced unwrap here.
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.lastDoseDate == nil
                    || ((session.lastDoseDate ?? lower) >= lower && session.startDate <= upper)
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)],
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.doses]
        let sessions = (try? context.fetch(descriptor)) ?? []

        // Each session's doses (minus the entry being (re)assigned) and time
        // span, computed once in a single unsorted pass — min/max need no sort —
        // and shared by all three placement rules below. Order mirrors
        // `sessions` (newest `startDate` first), which rule 1 relies on.
        let spans: [(session: Session, doses: [DoseEntry], firstDose: DoseEntry, last: Date)] = sessions.compactMap { session in
            let doses = (session.doses ?? []).filter { $0 !== entry }
            guard var firstDose = doses.first else { return nil }
            var last = firstDose.timestamp
            for dose in doses.dropFirst() {
                if dose.timestamp < firstDose.timestamp { firstDose = dose }
                if dose.timestamp > last { last = dose.timestamp }
            }
            return (session, doses, firstDose, last)
        }

        // 1. In-span join — a dose inside a session's active window is part of
        //    it, no gap to weigh. Keeps sessions from overlapping.
        for span in spans where target >= span.firstDose.timestamp && target <= span.last {
            entry.session = span.session
            span.session.refreshDoseBounds()
            return span.session
        }

        // 2. Extend the session this dose follows.
        var candidate: (session: Session, doses: [DoseEntry], firstDose: DoseEntry, last: Date)?
        for span in spans where span.last <= target {
            if candidate == nil || span.last > candidate!.last {
                candidate = span
            }
        }

        // `OpenSession(doses:)` anchors its start on the first element, so the
        // one candidate's doses get sorted here — no other session pays for a
        // sort.
        let openState = candidate.flatMap { span in
            SessionClustering.OpenSession(doses: span.doses.sorted { $0.timestamp < $1.timestamp }.map(clusterDose))
        }

        if case .join = SessionClustering.placement(of: clusterDose(for: entry), into: openState),
           let candidate {
            entry.session = candidate.session
            candidate.session.refreshDoseBounds()
            return candidate.session
        }

        // 3. Prepend — a back-dated dose may immediately precede an existing
        //    session (logged late, e.g. "15 minutes ago" right after a dose
        //    that already opened one). Mirror the extend heuristic: would the
        //    session's first dose join a session that ends with this one?
        var nextSession: Session?
        var nextFirstDose: DoseEntry?
        for span in spans where span.firstDose.timestamp >= target {
            if nextFirstDose == nil || span.firstDose.timestamp < nextFirstDose!.timestamp {
                nextSession = span.session
                nextFirstDose = span.firstDose
            }
        }
        if let nextSession, let nextFirstDose {
            let endingWithEntry = SessionClustering.OpenSession(doses: [clusterDose(for: entry)])
            if case .join = SessionClustering.placement(of: clusterDose(for: nextFirstDose), into: endingWithEntry) {
                entry.session = nextSession
                nextSession.refreshDoseBounds()
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
            session.refreshDoseBounds()
        }
        try? context.save()
        DoseLogService.shared.changed()
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
        target.refreshDoseBounds()
        DoseLogService.shared.changed()
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
        session.refreshDoseBounds()
        newSession.refreshDoseBounds()
        DoseLogService.shared.changed()
        return newSession
    }

    /// Move a single `dose` to `target`. The source session is deleted if it
    /// becomes empty, otherwise its `startDate` is refreshed.
    static func move(_ dose: DoseEntry, to target: Session, in context: ModelContext) {
        let source = dose.session
        guard source?.persistentModelID != target.persistentModelID else { return }
        dose.session = target
        target.refreshDoseBounds()
        if let source {
            if (source.doses ?? []).isEmpty {
                context.delete(source)
            } else {
                source.refreshDoseBounds()
            }
        }
        DoseLogService.shared.changed()
    }

    /// Set (or clear) a session's user title; blank trims to `nil`. Signals the
    /// dose-log change so the Journal's day cards — which bake the title in at
    /// build time — re-bucket and pick it up.
    static func setTitle(_ title: String, for session: Session) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard session.title != value else { return }
        session.title = value
        DoseLogService.shared.changed()
    }

    /// Set (or clear) a session's note; blank trims to `nil`.
    static func setNote(_ note: String, for session: Session) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard session.note != value else { return }
        session.note = value
        DoseLogService.shared.changed()
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
        backfillDoseBounds(in: context)
    }

    /// Fill ``Session/lastDoseDate`` on rows that predate the field. Candidate
    /// iff `nil`, so the sweep is idempotent and data-driven (the
    /// `PSIDBackfillMigration` pattern — no flag). Correctness never depends on
    /// this having run: ``assignSession(for:in:)`` always fetches `nil`-bound
    /// rows; this pass just lets them graduate into the windowed predicate.
    private static func backfillDoseBounds(in context: ModelContext) {
        let stale = (try? context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.lastDoseDate == nil },
        ))) ?? []
        guard !stale.isEmpty else { return }
        for session in stale {
            session.refreshDoseBounds()
            // An empty session has no bounds to derive; pin the fetch bound to
            // its startDate so it leaves the nil (always-fetched) bucket.
            if session.lastDoseDate == nil {
                session.lastDoseDate = session.startDate
            }
        }
        try? context.save()
    }

    // MARK: - One-time re-split of pre-cap overlong sessions

    /// `UserDefaults` flag so ``resplitOverlongSessions(in:)`` runs exactly once.
    private static let didResplitOverlongKey = "didResplitOverlongSessionsV1"

    /// One-time migration for stores built under the *old* flat-ceiling
    /// heuristic, which let nonstop redosing or a long-acting tail chain days
    /// into a single multi-day session. Re-clusters every session whose span
    /// exceeds ``SessionClustering/Constants/horizon`` under the current
    /// (decaying-ceiling, day-capped) rule, so they break at their real rest
    /// gaps.
    ///
    /// Deliberately gated to run **once** (a `UserDefaults` flag), because the
    /// user owns grouping afterwards: an explicit merge that intentionally spans
    /// >24 h must survive relaunch, so we don't re-split on every boot. Only
    /// overlong sessions are touched — normal sessions, merges, titles and notes
    /// are left intact; a re-split session's title/note stays on its first
    /// fragment (the one that keeps the original ``Session`` object).
    static func resplitOverlongSessions(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didResplitOverlongKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: didResplitOverlongKey) }

        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        for session in sessions {
            let doses = session.orderedDoses
            guard let first = doses.first?.timestamp, let last = doses.last?.timestamp,
                  last.timeIntervalSince(first) > SessionClustering.Constants.horizon else { continue }

            // Re-cluster this session's own doses under the current heuristic.
            let groups = SessionClustering.cluster(doses.map(clusterDose))
            guard groups.count > 1 else { continue }

            // The first group stays in the original session (keeps title/note);
            // each later group moves into a fresh session.
            for group in groups.dropFirst() {
                let moving = group.map { doses[$0] }
                guard let start = moving.map(\.timestamp).min() else { continue }
                let newSession = Session(startDate: start)
                context.insert(newSession)
                for dose in moving {
                    dose.session = newSession
                }
                newSession.refreshDoseBounds()
            }
            session.refreshDoseBounds()
        }
        try? context.save()
        DoseLogService.shared.changed()
    }
}
