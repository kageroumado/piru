import Foundation

/// The duration-aware heuristic that groups doses into sessions by temporal
/// proximity — the replacement for fixed calendar-day bucketing.
///
/// Pure value-level logic (no SwiftData, no `SubstanceLibrary`): a caller maps
/// its `DoseEntry`s to ``Dose`` values — resolving each dose's modeled effect
/// duration via `ActiveSubstanceCalculator` — and gets back groupings. This keeps
/// the heuristic unit-testable with hand-fed durations and reusable across the
/// app, widget, and Live Activity targets.
///
/// ## The rule
/// A session stays "open" until either its modeled effect ends *or* a quiescent
/// gap longer than a short night's sleep passes — whichever comes first:
///
/// ```
/// effectEnd  = max over the session's *non-background* doses of (t + k·duration)
/// lastTime   = the most recent dose in the session (background included)
/// gap        = newDose.t − lastTime
/// join  ⇔  gap ≤ ceiling  &&  (gap ≤ floor  ||  newDose.t ≤ effectEnd)
/// ```
///
/// - ``floor`` (3 h): doses this close always group, even for short-acting or
///   unknown-duration substances.
/// - ``ceiling`` (8 h): a quiescent gap longer than this *always* splits,
///   regardless of how long-acting the drug is — the safety valve that stops a
///   long-half-life compound from holding a session open across sleep. (This is
///   what PsychonautWiki's flat 15 h window lacks.)
/// - ``k`` (1.2): how far past the modeled wear-off still counts as the same
///   session — people redose into the comedown and still call it one session.
///
/// Tracking the session's *peak* `effectEnd` (not just the last dose's) is what
/// makes a quick short-acting dose dropped into a long trip stay in that trip,
/// instead of prematurely closing it.
///
/// ## Background medications
/// A background-med dose (``Dose/isBackgroundMed``) never opens or extends a
/// *recreational* session and never contributes to `effectEnd`. It folds into
/// the current recreational session only while that session is genuinely active
/// (`t ≤ effectEnd`); otherwise it clusters with other background meds (within
/// ``floor``) into a *maintenance* session, or stands alone as one. A maintenance
/// session is rendered compactly rather than as a full timeline card.
///
/// ## Decided once, persisted
/// Clustering runs at log time (per new dose) and once over history in the
/// migration's populate pass; it is **not** re-run on every render. The user owns
/// the result afterwards via merge / split / reassign.
enum SessionClustering {
    enum Constants {
        /// Doses within this gap always group (the close-together floor).
        static let floor: TimeInterval = 3 * 60 * 60
        /// Gaps beyond this always split (the sleep safety valve).
        static let ceiling: TimeInterval = 8 * 60 * 60
        /// Multiplier on a dose's modeled effect duration for the session tail.
        static let k: Double = 1.2
        /// Effect duration assumed for a dose with no modeled curve, in minutes.
        static let fallbackEffectMinutes: Double = 240
    }

    /// One dose's clustering-relevant facts, decoupled from `DoseEntry`.
    struct Dose {
        var timestamp: Date
        /// Modeled total effect duration in minutes; `nil` uses the fallback.
        var effectDurationMinutes: Double?
        var isBackgroundMed: Bool

        init(timestamp: Date, effectDurationMinutes: Double?, isBackgroundMed: Bool = false) {
            self.timestamp = timestamp
            self.effectDurationMinutes = effectDurationMinutes
            self.isBackgroundMed = isBackgroundMed
        }

        /// The end of this dose's modeled effect, scaled by ``Constants/k``.
        /// Only meaningful for non-background doses (background doses don't extend
        /// a session's bounds), but defined for all so the fallback lives here.
        var scaledEffectEnd: Date {
            let minutes = effectDurationMinutes ?? Constants.fallbackEffectMinutes
            return timestamp.addingTimeInterval(Constants.k * minutes * 60)
        }
    }

    /// The running bounds of the session currently being extended — the only
    /// candidate a newly-logged or swept dose can join (doses are processed in
    /// ascending time order, and sessions never overlap).
    struct OpenSession {
        /// Latest `t + k·duration` across the session's non-background doses, or
        /// `nil` for a maintenance session (no recreational effect window).
        var effectEnd: Date?
        /// Timestamp of the most recent dose, background included — the anchor
        /// for the quiescent-gap (sleep) guard.
        var lastTime: Date
        /// `true` while every dose so far is a background medication.
        var isMaintenance: Bool

        /// Seed an open session from its first dose.
        init(firstDose dose: Dose) {
            effectEnd = dose.isBackgroundMed ? nil : dose.scaledEffectEnd
            lastTime = dose.timestamp
            isMaintenance = dose.isBackgroundMed
        }

        /// Reconstruct the running state of an existing session from its doses,
        /// so a single newly-logged dose can be placed against it without
        /// re-clustering history. `doses` must be in ascending time order;
        /// returns `nil` for an empty session.
        init?(doses: [Dose]) {
            guard let first = doses.first else { return nil }
            self.init(firstDose: first)
            for dose in doses.dropFirst() { extend(with: dose) }
        }

        /// Fold a dose into this session (caller has already decided it joins).
        mutating func extend(with dose: Dose) {
            lastTime = max(lastTime, dose.timestamp)
            if !dose.isBackgroundMed {
                isMaintenance = false
                let end = dose.scaledEffectEnd
                effectEnd = effectEnd.map { max($0, end) } ?? end
            }
        }
    }

    /// Where the next dose goes relative to the current open session.
    enum Placement: Equatable {
        /// Append to the current session and extend its bounds.
        case join
        /// Start a fresh session with this dose.
        case newSession
    }

    /// Decide whether `dose` joins `current` (the most recent open session) or
    /// starts a new one. `current == nil` means there is no prior session.
    ///
    /// This is the single source of truth used by both ``cluster(_:)`` (history)
    /// and log-time assignment of one new dose.
    static func placement(of dose: Dose, into current: OpenSession?) -> Placement {
        guard let current else { return .newSession }

        let gap = dose.timestamp.timeIntervalSince(current.lastTime)
        // A quiescent gap longer than the sleep ceiling always splits — even for
        // a background med, even mid-effect. (Negative gaps — an out-of-order
        // insert — never trip this; they fall through to the windows below.)
        if gap > Constants.ceiling { return .newSession }

        if dose.isBackgroundMed {
            // Fold into the current recreational session only while it's active.
            if !current.isMaintenance, let end = current.effectEnd, dose.timestamp <= end {
                return .join
            }
            // Cluster co-administered background meds into a maintenance session.
            if current.isMaintenance, gap <= Constants.floor {
                return .join
            }
            // Otherwise the med stands as / starts its own maintenance session —
            // it never glues onto a recreational session it isn't part of.
            return .newSession
        }

        // A normal dose only ever extends a recreational session.
        if current.isMaintenance { return .newSession }
        if gap <= Constants.floor { return .join }
        if let end = current.effectEnd, dose.timestamp <= end { return .join }
        return .newSession
    }

    /// Whether a dose at `doseTime` is close enough to an existing session
    /// spanning `[sessionFirst, sessionLast]` to be moved into it *keeping its
    /// timestamp*, without stretching that session across a long quiescent gap.
    ///
    /// True when the dose already falls inside the span, or within the sleep
    /// ``Constants/ceiling`` of either edge — the same reach the clustering
    /// heuristic uses. A move to a farther session must re-time the dose so the
    /// session stays a coherent single span; this is the predicate the reassign
    /// UI uses to decide whether to ask for a new time.
    static func canJoinKeepingTime(doseTime: Date, sessionFirst: Date, sessionLast: Date) -> Bool {
        if doseTime >= sessionFirst, doseTime <= sessionLast { return true }
        let gap = doseTime < sessionFirst
            ? sessionFirst.timeIntervalSince(doseTime)
            : doseTime.timeIntervalSince(sessionLast)
        return gap <= Constants.ceiling
    }

    /// Cluster time-sorted doses into sessions, returned as groups of indices
    /// into the input array. Input **must** be sorted ascending by timestamp;
    /// the result preserves that order and partitions every index exactly once
    /// (no dose orphaned or duplicated).
    static func cluster(_ doses: [Dose]) -> [[Int]] {
        var groups: [[Int]] = []
        var current: OpenSession?

        for (index, dose) in doses.enumerated() {
            switch placement(of: dose, into: current) {
            case .join:
                groups[groups.count - 1].append(index)
                current?.extend(with: dose)
            case .newSession:
                groups.append([index])
                current = OpenSession(firstDose: dose)
            }
        }
        return groups
    }
}
