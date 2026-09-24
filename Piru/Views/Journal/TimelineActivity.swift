import Foundation

/// The stateless "when is a curve active, and when does it end" math for the
/// continuous timeline strip. Effect-mode curve extents live in the shared
/// ``TimelineWindowEvaluator`` / ``TimelineCurveModel``; this is their body-load
/// (PK) sibling plus the span-merging both modes share, kept in one place so
/// the strip's framing, its dead-time compression, and the window graph's
/// culling all read the same definitions instead of re-deriving "when the curve
/// ends" independently.
///
/// Three questions, deliberately answered by three functions — they are not
/// interchangeable:
/// - **Framing** (how far past now the strip runs): ``pkActivityEnds(entries:)``
///   / the effect end from ``TimelineWindowEvaluator/activityInterval(of:)``.
///   The whole tail, so no live curve is clipped off the top.
/// - **Compression** (which spans stay at the uniform scale): ``activeSpans(states:)``
///   / ``pkActiveSpans(entries:)`` → ``protectingIntervals(_:)``. Only the part a
///   reader can actually see, so dead time can be squeezed.
/// - **Culling** (which doses a window must evaluate): the untrimmed
///   ``TimelineWindowEvaluator/activityInterval(of:)`` — a dose contributing a
///   sliver must not be dropped.
enum TimelineActivity {
    typealias PKConstants = (halfLife: Double, ke: Double, ka: Double)

    /// A curve counts as active while it is above this fraction of the
    /// tallest curve it is drawn beside; below it, the span is dead time
    /// compression may squeeze.
    nonisolated static let activeThreshold = 0.05
    /// Body-load mode: a dose stops holding the axis open this many
    /// half-lives after it, whatever fraction of its peak remains.
    nonisolated static let pkActiveHalfLives = 2.0
    /// Activity continuous for longer than this is a baseline, not an
    /// event, and a baseline does not keep dead time uniform. It caps one
    /// dose's own span in either mode, and it caps how long a substance's
    /// unbroken run of doses protects the axis. The horizontal graph frames
    /// by the same rule (``TimelineCurveModel``'s `renderedTail` drops curves
    /// that have not decayed inside ``TimelineCurveModel/maxDisplayMinutes``).
    nonisolated static let baselineMinutes = 48.0 * 60

    /// One dose's active span, tagged with its substance so runs of the
    /// same substance can be chained.
    nonisolated struct ActiveSpan {
        let key: String
        let interval: DateInterval
    }

    /// The spans that hold the axis open: per substance, the merged runs of
    /// its active spans, each run cut at ``baselineMinutes``. A substance
    /// active without a break for longer than that has become a baseline —
    /// the daily med whose curves chain into one unbroken span and would
    /// otherwise keep every night at the uniform scale. A gap below
    /// threshold resets the clock, so a med stopped and restarted protects
    /// its first two days again. The curves still draw their whole run.
    nonisolated static func protectingIntervals(_ spans: [ActiveSpan]) -> [DateInterval] {
        var result: [DateInterval] = []
        for group in Dictionary(grouping: spans, by: \.key).values {
            for run in TimelineTimeMap.merged(group.map(\.interval)) {
                result.append(run.duration > baselineMinutes * 60
                    ? DateInterval(start: run.start, duration: baselineMinutes * 60)
                    : run)
            }
        }
        return result
    }

    /// Effect mode: from each dose to the moment its curve drops below
    /// ``activeThreshold`` of the tallest curve overlapping it — its own when
    /// nothing does. Drawn beside a heavy dose, a light one sits under a
    /// device pixel long before it reaches its own baseline, and a tail
    /// nobody can see must not hold the axis open.
    nonisolated static func activeSpans(states: [ActiveSubstanceState]) -> [ActiveSpan] {
        // Sweep in dose order: two curves overlap exactly when the later dose
        // lands before the earlier curve ends, so every pair meets once,
        // while the earlier dose is still open.
        let ordered = states.sorted { $0.doseTimestamp < $1.doseTimestamp }
        let ends = ordered.map { TimelineWindowEvaluator.activityInterval(of: $0).end }
        var peers = ordered.map(\.doseMagnitude)
        var open: [Int] = []
        for i in ordered.indices {
            open.removeAll { ends[$0] < ordered[i].doseTimestamp }
            for j in open {
                peers[i] = max(peers[i], ordered[j].doseMagnitude)
                peers[j] = max(peers[j], ordered[i].doseMagnitude)
            }
            open.append(i)
        }
        return ordered.indices.map { i in
            let minutes = TimelineCurveModel.visibleExtent(
                for: ordered[i],
                peerMagnitude: peers[i],
                threshold: activeThreshold,
            )
            return ActiveSpan(
                key: ordered[i].substanceName.lowercased(),
                interval: DateInterval(
                    start: ordered[i].doseTimestamp,
                    duration: min(max(minutes, 1), baselineMinutes) * 60,
                ),
            )
        }
    }

    /// Body-load mode: minutes a dose holds the axis open — until its
    /// concentration falls below ``activeThreshold`` of its peak, but never
    /// past ``pkActiveHalfLives`` half-lives or ``baselineMinutes``.
    /// The curve itself still draws its whole tail; a 70 h half-life would
    /// otherwise keep twelve days per dose at the uniform scale.
    nonisolated static func pkActiveMinutes(halfLife: Double, ke: Double, ka: Double) -> Double {
        let toThreshold = PKModel.timeToFraction(activeThreshold, ke: ke, ka: ka)
        return max(min(toThreshold, halfLife * pkActiveHalfLives, baselineMinutes), 1)
    }

    /// Body-load mode: ``pkActiveMinutes(halfLife:ke:ka:)`` from each dose.
    /// Doses that draw no body-load curve contribute nothing.
    static func pkActiveSpans(entries: [DoseEntry]) -> [ActiveSpan] {
        var constantsCache: [String: PKConstants?] = [:]
        var spans: [ActiveSpan] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            let constants: PKConstants?
            if let cached = constantsCache[key] {
                constants = cached
            } else {
                constants = resolvePKConstants(key: key, name: entry.substance)
                constantsCache[key] = constants
            }
            guard let constants else { continue }
            let minutes = pkActiveMinutes(halfLife: constants.halfLife, ke: constants.ke, ka: constants.ka)
            spans.append(ActiveSpan(key: key, interval: DateInterval(start: entry.timestamp, duration: minutes * 60)))
        }
        return spans
    }

    /// Body-load mode's activity end per dose: six half-lives, the same cutoff
    /// ``TimelineStripBuilder/computeRemainingFractions(entries:)`` treats as
    /// cleared. Doses that draw no body-load curve (supplements, no half-life)
    /// contribute nothing.
    static func pkActivityEnds(entries: [DoseEntry]) -> [Date] {
        var substanceCache: [String: Substance?] = [:]
        var ends: [Date] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            let substance: Substance?
            if let cached = substanceCache[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                substanceCache[key] = substance
            }
            if substance?.category == .supplement { continue }
            guard let halfLife = PKResolver.halfLifeMinutes(substance: substance) else { continue }
            ends.append(entry.timestamp.addingTimeInterval(halfLife * 6 * 60))
        }
        return ends
    }

    /// PK mode: a substance's rate constants; `nil` for substances that draw
    /// no body-load curve (no half-life, supplements).
    static func resolvePKConstants(key: String, name _: String) -> PKConstants? {
        guard let substance = SubstanceLibrary.lookup(key),
              substance.category != .supplement,
              let halfLife = PKResolver.halfLifeMinutes(substance: substance),
              halfLife > 0 else { return nil }
        let (ke, ka) = PKResolver.rateConstants(
            halfLifeMinutes: halfLife,
            duration: substance.resolveDuration(for: .oral),
        )
        guard PKModel.cmax(ke: ke, ka: ka) > 0 else { return nil }
        return (halfLife, ke, ka)
    }
}
