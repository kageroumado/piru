import Foundation

/// Check-in times derived from what was actually taken, rather than a fixed
/// ladder someone guessed at.
///
/// Every offset is read off the dose's own modeled phase boundaries, so a
/// twelve-hour session is asked about seven times and a vaporized dose that is
/// finished inside the hour is asked about once or twice. The result is a
/// plain `[Int]` of minutes after the session's anchor dose — the same shape
/// ``Session/checkInOffsetMinutes`` stores, so a suggestion and a hand-built
/// schedule are the same kind of thing and run through the same scheduler.
@MainActor
enum CheckInLadder {
    /// How many moments a class is worth asking about.
    ///
    /// The split is about what a prompt can learn, not about how long the drug
    /// lasts — duration is already handled by reading the phase boundaries. A
    /// psychedelic session changes character several times and each change is
    /// worth a note; a medication has one question ("is it working") and one
    /// follow-up ("has it worn off"), and asking it five times a day is how a
    /// useful prompt becomes one more thing to dismiss.
    enum Depth {
        /// Every phase boundary and the middle of each phase.
        case wide
        /// The four moments where a recreational dose changes character.
        case paced
        /// Two: the middle of the plateau, and where it turns.
        case light

        init(category: SubstanceCategory) {
            switch category {
            case .psychedelic, .dissociative, .dysdelic, .deliriant, .empathogen:
                self = .wide
            case .opioid, .benzodiazepine, .depressant, .cannabinoid, .gabapentinoid,
                 .analgesic, .orexinAntagonist, .antihistamine:
                self = .paced
            default:
                self = .light
            }
        }
    }

    /// The minutes after a dose that its class is worth asking about, read off
    /// that dose's own phase boundaries. Pure, for tests.
    nonisolated static func moments(in state: ActiveSubstanceState, depth: Depth) -> [Double] {
        let onsetEnd = state.onsetEndMinutes
        let comeupEnd = state.comeupEndMinutes
        let peakEnd = state.peakEndMinutes
        let offsetEnd = max(state.offsetEndMinutes, state.totalMinutes)
        func middle(_ from: Double, _ to: Double) -> Double { (from + to) / 2 }

        switch depth {
        case .wide:
            return [
                onsetEnd,
                middle(onsetEnd, comeupEnd),
                comeupEnd,
                middle(comeupEnd, peakEnd),
                peakEnd,
                middle(peakEnd, offsetEnd),
                offsetEnd,
            ]
        case .paced:
            return [comeupEnd, middle(comeupEnd, peakEnd), peakEnd, offsetEnd]
        case .light:
            return [middle(comeupEnd, peakEnd), peakEnd]
        }
    }

    /// Rounding granularity for a dose of this length: fine enough that a short
    /// dose keeps its shape, coarse enough that a long one reads as a time
    /// somebody chose rather than a computed number.
    nonisolated static func granularity(totalMinutes: Double) -> Int {
        switch totalMinutes {
        case ..<90: 5
        case ..<360: 15
        default: 30
        }
    }

    /// Offsets in minutes after `anchor` for one dose, rounded and in range.
    nonisolated static func offsets(
        for state: ActiveSubstanceState, depth: Depth, anchor: Date,
    ) -> [Int] {
        let shift = state.doseTimestamp.timeIntervalSince(anchor) / 60
        let step = Double(granularity(totalMinutes: state.totalMinutes))
        return moments(in: state, depth: depth)
            .map { ($0 + shift) / step }
            .map { Int($0.rounded()) * Int(step) }
            .filter { $0 >= CheckInOffsets.minimumMinutes && $0 <= CheckInOffsets.maximumMinutes }
    }

    /// The suggested schedule for a session: every dose's moments, merged and
    /// normalized. Empty when nothing in the session models a curve — a dose
    /// with no duration data has no phases to read, and inventing a ladder for
    /// it would be the guess this whole type exists to replace.
    static func suggestedOffsets(for session: Session, anchor: Date? = nil) -> [Int] {
        let anchor = anchor ?? CheckInScheduler.anchor(for: session)
        var merged: [Int] = []
        for dose in session.orderedDoses {
            // The color is never read here; the state is wanted only for its
            // phase boundaries.
            guard let state = ActiveSubstanceState.from(entry: dose, colorHex: "#888888") else { continue }
            let category = SubstanceLibrary.lookup(dose.substance)?.category ?? .other
            merged += offsets(for: state, depth: Depth(category: category), anchor: anchor)
        }
        return CheckInOffsets.normalized(thinned(Array(Set(merged)).sorted()))
    }

    /// Reduce a list to at most ``CheckInOffsets/maximumCount`` by dropping
    /// from the middle, keeping the first and the last.
    ///
    /// ``CheckInOffsets/normalized(_:)`` takes the *earliest* times when a list
    /// is over the cap, which on a multi-dose session would spend the whole
    /// budget on the first dose's come-up and never ask whether the evening
    /// ended. Spacing the survivors keeps both ends.
    nonisolated static func thinned(_ offsets: [Int], limit: Int = CheckInOffsets.maximumCount) -> [Int] {
        guard offsets.count > limit, limit > 1 else { return offsets }
        let stride = Double(offsets.count - 1) / Double(limit - 1)
        return (0 ..< limit).map { offsets[Int((Double($0) * stride).rounded())] }
    }

    /// The suggestion as one line — "+45m · +2h · +4h · +7h 30m" — for the
    /// banner button and the editor's empty state.
    nonisolated static func summary(_ offsets: [Int]) -> String {
        offsets.map(CheckInOffsets.label).joined(separator: " · ")
    }
}
