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
/// gap wider than the session's *current* sleep ceiling passes — whichever comes
/// first:
///
/// ```
/// effectEnd  = max over the session's *non-background* doses of (t + k·duration),
///              each dose's tail clamped to ``effectTailCap``
/// lastTime   = the most recent dose in the session (background included)
/// elapsed    = lastTime − sessionStart          // how long the session has run
/// gap        = newDose.t − lastTime
/// ceiling    = decaying function of elapsed (see below)
/// join  ⇔  newDose.t − sessionStart < horizon   // hard 24 h cap
///          &&  gap ≤ ceiling
///          &&  (gap ≤ floor  ||  newDose.t ≤ effectEnd)
/// ```
///
/// - ``floor`` (3 h): doses this close always group, even for short-acting or
///   unknown-duration substances.
/// - **Decaying ceiling** — the safety valve that stops a long-half-life
///   compound *or* nonstop redosing from holding a session open indefinitely.
///   Instead of a flat window, the ceiling *tightens as the session ages*, so a
///   fresh session tolerates a full night's gap but a day-old one splits on the
///   next real break:
///     - ``Constants/freshCeiling(peakTail:)`` at `elapsed == 0` — a fresh
///       session absorbs a short night's sleep. At least ``ceilingMax`` (6 h),
///       widened toward ``ceilingDurationMax`` (9 h) by how long-acting the
///       session's doses actually are, so an 8 h substance redosed 6.5 h later
///       stays one session while a 12 h one redosed after 10 h does not.
///     - decays linearly to ``ceilingKnee`` (3 h) at ``knee`` (21 h), then
///     - decays linearly to ``ceilingEnd`` (~1 min) at ``horizon`` (24 h), so
///       the last few hours before the cap only absorb back-to-back doses.
///   Past ``knee`` the ceiling drops below ``floor`` and *becomes* the binding
///   constraint (the always-join floor shrinks with it). This is what a flat
///   ceiling — and PsychonautWiki's flat 15 h window — lacks: heavy users whose
///   only rest is a sub-ceiling daytime crash used to chain days into one 60 h+
///   session.
/// - **Hard cap** (``horizon``, 24 h): a dose more than 24 h after the session's
///   *first* dose always starts a new session, no matter how tightly spaced —
///   sessions are day-scoped (the timeline graph only renders 24 h), so nothing
///   is allowed to exceed a day. The user re-attaches days with an explicit
///   merge if they really were one run.
/// - ``k`` (1.2): how far past the modeled wear-off still counts as the same
///   session — people redose into the comedown and still call it one session.
/// - ``effectTailCap`` (9 h): the per-dose effect tail is clamped to this for
///   *clustering* purposes, so a long-acting compound (memantine, a depot) can't
///   glue the next day's doses onto the session via a multi-day modeled tail.
///   (This only bounds session grouping; the timeline still draws the full
///   pharmacological curve.) The decaying ceiling already gates `effectEnd`, so
///   this is belt-and-braces against the "long tail links days" failure mode.
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
        /// The sleep ceiling for a *fresh* session (`elapsed == 0`) — a short
        /// night's sleep. The effective ceiling decays from here as the session
        /// ages (see ``ceiling(elapsed:)``).
        static let ceilingMax: TimeInterval = 6 * 60 * 60
        /// The ceiling at the ``knee`` (21 h in) — the first decay segment runs
        /// ``ceilingMax`` → this.
        static let ceilingKnee: TimeInterval = 3 * 60 * 60
        /// The ceiling as `elapsed` approaches ``horizon`` — near-zero, so the
        /// final hours only absorb back-to-back doses before the hard cap. Not
        /// literally zero so the boundary is smooth rather than a cliff.
        static let ceilingEnd: TimeInterval = 60
        /// Where the ceiling's decay slope changes (``ceilingMax`` → ``ceilingKnee``
        /// before this, ``ceilingKnee`` → ``ceilingEnd`` after).
        static let knee: TimeInterval = 21 * 60 * 60
        /// The hard cap: a dose more than this after the session's *first* dose
        /// always starts a new session. Sessions are day-scoped.
        static let horizon: TimeInterval = 24 * 60 * 60
        /// Multiplier on a dose's modeled effect duration for the session tail.
        static let k: Double = 1.2
        /// The per-dose effect tail used for clustering is clamped to this, so a
        /// long-acting compound can't hold a session open across a day.
        ///
        /// Was 6 h, which silently disabled the duration-awareness ``k`` promises:
        /// `6 h / 1.2 = 5 h`, so the "redosed into the comedown" clause could never
        /// reach past five hours for *any* substance. Matched to
        /// ``ceilingDurationMax`` so the two bounds agree — the 24 h ``horizon``
        /// remains the guarantee that a session cannot chain days.
        static let effectTailCap: TimeInterval = 9 * 60 * 60
        /// Effect duration assumed for a dose with no modeled curve, in minutes.
        static let fallbackEffectMinutes: Double = 240

        /// Upper bound on a fresh session's ceiling once the substance's own
        /// duration widens it. Keeps a very long-acting compound (LSD, a depot)
        /// from tolerating an entire night's sleep as "still the same session";
        /// past this, a quiescent gap really is a break.
        static let ceilingDurationMax: TimeInterval = 9 * 60 * 60

        /// The ceiling a *fresh* session tolerates, given the longest modeled
        /// effect tail among its doses so far.
        ///
        /// A flat ``ceilingMax`` made the ceiling the binding constraint for every
        /// substance past about five hours: an 8 h dose at 19:00 redosed at 01:30
        /// had a 6.5 h gap against a 6 h ceiling and split, while the 19:00 curve
        /// was still being drawn to 03:00 on screen. Scaling the fresh ceiling with
        /// the modeled tail is what ``k`` always promised — "people redose into the
        /// comedown and still call it one session" — and it is bounded on both
        /// sides: never tighter than ``ceilingMax``, never wider than
        /// ``ceilingDurationMax``. The age decay below is unchanged, so a session
        /// that has already run long still splits on the next real break.
        static func freshCeiling(peakTail: TimeInterval?) -> TimeInterval {
            guard let peakTail else { return ceilingMax }
            return min(max(ceilingMax, peakTail), ceilingDurationMax)
        }

        /// The effective sleep ceiling for a hop, given how long the session has
        /// already run. Two linear segments: `fresh` → ``ceilingKnee`` over
        /// `[0, knee]`, then ``ceilingKnee`` → ``ceilingEnd`` over `[knee, horizon]`.
        /// Clamped outside that range.
        static func ceiling(elapsed: TimeInterval, fresh: TimeInterval = ceilingMax) -> TimeInterval {
            let e = max(0, elapsed)
            if e >= horizon { return ceilingEnd }
            if e <= knee {
                return fresh - (fresh - ceilingKnee) * (e / knee)
            }
            return ceilingKnee - (ceilingKnee - ceilingEnd) * ((e - knee) / (horizon - knee))
        }
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

        /// The end of this dose's modeled effect, scaled by ``Constants/k`` and
        /// clamped to ``Constants/effectTailCap`` so a long-acting compound can't
        /// stretch a session across a day. Only meaningful for non-background
        /// doses (background doses don't extend a session's bounds), but defined
        /// for all so the fallback lives here.
        var scaledEffectEnd: Date {
            timestamp.addingTimeInterval(scaledTail)
        }

        /// How far past this dose its effect is still considered to run, for
        /// clustering purposes — the modeled duration scaled by ``Constants/k``
        /// and clamped to ``Constants/effectTailCap``.
        var scaledTail: TimeInterval {
            let minutes = effectDurationMinutes ?? Constants.fallbackEffectMinutes
            return min(Constants.k * minutes * 60, Constants.effectTailCap)
        }
    }

    /// The running bounds of the session currently being extended — the only
    /// candidate a newly-logged or swept dose can join (doses are processed in
    /// ascending time order, and sessions never overlap).
    struct OpenSession {
        /// Timestamp of the session's *first* dose — the anchor for the elapsed
        /// time that drives the decaying ceiling and the 24 h hard cap. Set once;
        /// ``extend(with:)`` never moves it.
        let startTime: Date
        /// Latest `t + k·duration` across the session's non-background doses, or
        /// `nil` for a maintenance session (no recreational effect window).
        var effectEnd: Date?
        /// Timestamp of the most recent dose, background included — the anchor
        /// for the quiescent-gap (sleep) guard.
        var lastTime: Date
        /// `true` while every dose so far is a background medication.
        var isMaintenance: Bool

        /// Longest scaled effect tail contributed by any non-background dose so
        /// far — the session's own sense of "how long-acting is this". Drives
        /// ``Constants/freshCeiling(peakTail:)``. `nil` for a maintenance session.
        var peakTail: TimeInterval?

        /// The ceiling this session tolerates while fresh, widened by whatever it
        /// actually contains.
        var freshCeiling: TimeInterval {
            Constants.freshCeiling(peakTail: peakTail)
        }

        /// Seed an open session from its first dose.
        init(firstDose dose: Dose) {
            startTime = dose.timestamp
            effectEnd = dose.isBackgroundMed ? nil : dose.scaledEffectEnd
            lastTime = dose.timestamp
            isMaintenance = dose.isBackgroundMed
            peakTail = dose.isBackgroundMed ? nil : dose.scaledTail
        }

        /// Reconstruct the running state of an existing session from its doses,
        /// so a single newly-logged dose can be placed against it without
        /// re-clustering history. `doses` must be in ascending time order;
        /// returns `nil` for an empty session.
        init?(doses: [Dose]) {
            guard let first = doses.first else { return nil }
            self.init(firstDose: first)
            for dose in doses.dropFirst() {
                extend(with: dose)
            }
        }

        /// Fold a dose into this session (caller has already decided it joins).
        mutating func extend(with dose: Dose) {
            lastTime = max(lastTime, dose.timestamp)
            if !dose.isBackgroundMed {
                isMaintenance = false
                let end = dose.scaledEffectEnd
                effectEnd = effectEnd.map { max($0, end) } ?? end
                peakTail = peakTail.map { max($0, dose.scaledTail) } ?? dose.scaledTail
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

        // Hard 24 h cap: a dose more than a day after the session's first dose
        // always starts a new session, however tightly spaced — sessions are
        // day-scoped. This is the guarantee that nonstop redosing can't chain
        // days. (Out-of-order inserts have a negative span and never trip it.)
        if dose.timestamp.timeIntervalSince(current.startTime) >= Constants.horizon {
            return .newSession
        }

        let gap = dose.timestamp.timeIntervalSince(current.lastTime)
        // A quiescent gap wider than the session's *current* sleep ceiling always
        // splits — even for a background med, even mid-effect. The ceiling
        // tightens as the session ages (see ``Constants/ceiling(elapsed:)``), so a
        // fresh session tolerates a night's gap but a day-old one splits on the
        // next real break. (Negative gaps — an out-of-order insert — never trip
        // this; they fall through to the windows below.)
        let ceiling = Constants.ceiling(
            elapsed: current.lastTime.timeIntervalSince(current.startTime),
            fresh: current.freshCeiling,
        )
        if gap > ceiling { return .newSession }

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
    /// True when the dose already falls inside the span, or within a fresh
    /// session's sleep ``Constants/ceilingMax`` of either edge — the widest reach
    /// the clustering heuristic ever allows. A move to a farther session must
    /// re-time the dose so the session stays a coherent single span; this is the
    /// predicate the reassign UI uses to decide whether to ask for a new time.
    static func canJoinKeepingTime(doseTime: Date, sessionFirst: Date, sessionLast: Date) -> Bool {
        if doseTime >= sessionFirst, doseTime <= sessionLast { return true }
        let gap = doseTime < sessionFirst
            ? sessionFirst.timeIntervalSince(doseTime)
            : doseTime.timeIntervalSince(sessionLast)
        return gap <= Constants.ceilingMax
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
