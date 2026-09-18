import SwiftUI

extension TimelineDayLayout {
    /// One modeled moment of a dose's arc, marked on the vertical timeline: a
    /// dot on the curve where the phase turns, a faint connector out to the
    /// lane, and a glyph with the clock time it lands at.
    ///
    /// The four moments answer, in order, "when does it start", "when is it
    /// full", "when does it start going", "when is it out of my way" — the
    /// questions a daily med raises every day, read off the curve already
    /// drawn rather than recomputed.
    nonisolated struct Milestone: Identifiable, Equatable, Codable {
        enum Kind: String, Codable, CaseIterable {
            /// The onset ends and the curve starts climbing.
            case comeup
            /// The climb reaches the plateau.
            case peak
            /// The plateau ends and the curve starts down.
            case offset
            /// The acute curve has run out.
            case end
        }

        /// The dose this marks, as substance plus its moment — the layout
        /// carries no entry identity and two doses can never share both.
        let doseKey: String
        let kind: Kind
        let time: Date
        let y: CGFloat
        /// How far into the curve lane the curve reaches here, `0…1`. The dot
        /// sits on the line; the connector runs from it to the lane's edge.
        let curveFraction: Double
        /// The dose is one whose whole point is wakefulness, so its end is
        /// worth stating as a bedtime rather than a checkmark.
        let affectsSleep: Bool
        /// No dose bubble shares this row. The curve lane alone is too narrow
        /// for a mark on most screens — the room the marks actually live in is
        /// the empty stretch beside the strip, which exists wherever the bubble
        /// column happens to have nothing in it.
        let clearOfCards: Bool

        var id: String {
            "\(doseKey)|\(kind.rawValue)"
        }

        var symbolName: String {
            switch kind {
            case .comeup: DosePhaseGlyph.comeup
            case .peak: DosePhaseGlyph.peak
            case .offset: DosePhaseGlyph.offset
            case .end: DosePhaseGlyph.end(affectsSleep: affectsSleep)
            }
        }

        /// What the mark says, for VoiceOver and for anyone who needs the
        /// glyph spelled out. Every one is approximate — the duration data is
        /// a population median, so the value reads "around 5:10 PM".
        var accessibilityLabel: LocalizedStringResource {
            switch kind {
            case .comeup: "Kicks in"
            case .peak: "Full effect"
            case .offset: "Begins to wear off"
            case .end: affectsSleep ? "Clear for sleep" : "Effects end"
            }
        }
    }

    /// The plain word for what the one active dose is doing right now, shown
    /// in the timeline gutter under the "Now" tag.
    ///
    /// It answers the question the curve answers only to someone willing to
    /// read it: *is my med still working?* Present only while exactly one dose
    /// is running, for the same reason the milestones are.
    nonisolated struct WordState: Equatable, Codable {
        enum Phase: String, Codable {
            case onset
            case comingUp
            case peak
            case wearingOff
            case afterglow
        }

        let phase: Phase
        let y: CGFloat

        var word: LocalizedStringResource {
            switch phase {
            case .onset: DosePhaseWord.onset
            case .comingUp: DosePhaseWord.comingUp
            case .peak: DosePhaseWord.peak
            case .wearingOff: DosePhaseWord.wearingOff
            case .afterglow: DosePhaseWord.afterglow
            }
        }

        /// The band this state belongs to, so the gutter word takes the same
        /// tint the dose hero's phase bar would give it.
        var band: DosePhaseProgressBar.Phase {
            switch phase {
            case .onset: .onset
            case .comingUp: .comeup
            case .peak: .peak
            case .wearingOff: .offset
            case .afterglow: .after
            }
        }

        init(phase: Phase, y: CGFloat) {
            self.phase = phase
            self.y = y
        }

        /// The state a dose `elapsedMinutes` in is in, on the same boundaries
        /// ``DosePhaseProgressBar/phase(_:elapsedMinutes:)`` uses, so the
        /// gutter word and the dose hero's phase bar can never disagree.
        init(state: ActiveSubstanceState, elapsedMinutes: Double, y: CGFloat) {
            let phase: Phase = switch DosePhaseProgressBar.phase(state, elapsedMinutes: elapsedMinutes) {
            case .onset: .onset
            case .comeup: .comingUp
            case .peak: .peak
            case .offset: .wearingOff
            case .after: .afterglow
            }
            self.init(phase: phase, y: y)
        }
    }
}

/// Where a milestone's mark sits in the lane between the curves and the dose
/// bubbles, and when there is no room for it. Pure geometry so the rules are
/// testable without a layout — the sibling of ``TimelineNoteLane``.
nonisolated enum TimelineMilestoneLane {
    /// Radius of the dot on the curve.
    static let dotRadius: CGFloat = 3
    /// Gap between the curve lane's outer edge and the marks' column.
    static let curveGap: CGFloat = 10
    /// Gap the marks keep from the bubble column.
    static let columnGap: CGFloat = 10
    /// Height of one mark — also the vertical room two marks need between
    /// them before the later one is dropped.
    static let markHeight: CGFloat = 20
    /// Breathing room between two marks' frames.
    static let markGap: CGFloat = 4
    /// A mark narrower than this cannot hold a glyph and a clock time, and is
    /// dropped rather than truncated: the milestones are a courtesy, and the
    /// curve underneath already carries the shape.
    static let minimumMarkWidth: CGFloat = 62

    /// The marks' shared leading x — one column at the lane's outer edge, so
    /// the connectors read as rungs rather than the marks as scatter.
    static func markX(axisX: CGFloat, curveWidth: CGFloat) -> CGFloat {
        axisX + curveWidth + curveGap
    }

    /// Room a mark has: out to the strip's trailing edge on a row no bubble
    /// occupies, and only as far as the bubble column on a row one does.
    static func markWidth(
        markX: CGFloat,
        bubbleLeft: CGFloat,
        trailingEdge: CGFloat,
        clearOfCards: Bool,
    ) -> CGFloat {
        max(0, (clearOfCards ? trailingEdge : bubbleLeft - columnGap) - markX)
    }

    /// Whether a mark on this row has the width to draw — the frame check
    /// against the dose rows, applied per row rather than to the strip as a
    /// whole.
    static func fits(markX: CGFloat, bubbleLeft: CGFloat, trailingEdge: CGFloat, clearOfCards: Bool) -> Bool {
        markWidth(markX: markX, bubbleLeft: bubbleLeft, trailingEdge: trailingEdge, clearOfCards: clearOfCards)
            >= minimumMarkWidth
    }

    /// Whether `y`'s row is free of every bubble stack and session envelope on
    /// the slice. Spans are slice-local tops and bottoms, in any order.
    static func clearOfCards(y: CGFloat, spans: [(top: CGFloat, bottom: CGFloat)]) -> Bool {
        let top = y - markHeight / 2 - markGap
        let bottom = y + markHeight / 2 + markGap
        return spans.allSatisfy { $0.top > bottom || $0.bottom < top }
    }

    /// The milestones that still have their own row, newest first: a mark
    /// whose frame touches the last one kept is dropped. Two phase boundaries
    /// minutes apart land on the same pixel, and two glyphs there read as a
    /// rendering fault rather than as two moments.
    static func thinned(_ milestones: [TimelineDayLayout.Milestone]) -> [TimelineDayLayout.Milestone] {
        var kept: [TimelineDayLayout.Milestone] = []
        for milestone in milestones.sorted(by: { $0.y < $1.y }) {
            if let last = kept.last, milestone.y - last.y < markHeight + markGap { continue }
            kept.append(milestone)
        }
        return kept
    }
}

// MARK: - Marks

/// One milestone in the lane: its glyph and the clock time it lands at, on the
/// gutter marks' recipe so the strip reads as one family of labels. The time
/// carries a `~` because the duration data behind it is a population median,
/// never a measurement of this person.
struct TimelineMilestoneMark: View {
    let milestone: TimelineDayLayout.Milestone
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: milestone.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(verbatim: "~\(milestone.time.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: TimelineMilestoneLane.markHeight)
        .background {
            Capsule(style: .continuous)
                .fill(Theme.background)
                .overlay { Capsule(style: .continuous).fill(color.opacity(Theme.Opacity.tint)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(milestone.accessibilityLabel))
        .accessibilityValue(Text("around \(milestone.time.formatted(date: .omitted, time: .shortened))"))
    }
}

/// The word-state glance, on the gutter marks' recipe: the phase the one
/// running dose is in, tinted with that phase's own color.
struct TimelineWordStateMark: View {
    let state: TimelineDayLayout.WordState

    var body: some View {
        TimelineGutterMark(lines: .one) {
            Text(state.word)
                .font(TimelineGutterMarkMetrics.primaryFont)
                .foregroundStyle(state.band.labelColor)
        }
        .accessibilityElement(children: .combine)
    }
}
