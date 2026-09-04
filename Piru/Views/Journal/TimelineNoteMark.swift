import SwiftUI

/// One session note on the vertical timeline, at its own moment: the note
/// kind's glyph — the same one the session graph draws — and the first line of
/// its text beside it. It sits in the lane between the curves and the bubble
/// column, so it never competes with the gutter's dose capsules, and tapping
/// it opens the note.
struct TimelineNoteMark: View {
    let mark: TimelineDayLayout.NoteMark
    /// Room for the text before the bubble column; below
    /// ``TimelineNoteLane/minimumTextWidth`` only the glyph draws.
    let textWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: TimelineGraphView.glyph(for: mark.kind))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: TimelineNoteLane.glyphSize, height: TimelineNoteLane.glyphSize)
                    .background(Theme.accent, in: Circle())

                if textWidth >= TimelineNoteLane.minimumTextWidth, !mark.text.isEmpty {
                    Text(verbatim: mark.text)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: textWidth, alignment: .leading)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Note"))
        .accessibilityValue(Text(verbatim: mark.text))
    }
}

/// Where a note sits in the curve lane, and when its text has to go. Pure
/// geometry so the rule is testable without a layout.
nonisolated enum TimelineNoteLane {
    /// Diameter of the glyph's disc.
    static let glyphSize: CGFloat = 16
    /// Gap between the widest curve at the note's height and the glyph.
    static let curveGap: CGFloat = 8
    /// Gap the note keeps from the bubble column.
    static let columnGap: CGFloat = 10
    /// Below this, the text is dropped and the glyph stands alone — a curve
    /// peak has taken the lane. The lane from the axis to the bubble column is
    /// ~134 pt on a 402 pt screen, which leaves ~95 pt for text with the lane
    /// clear, so the threshold has to sit well under 100 or a note is never
    /// more than its glyph.
    static let minimumTextWidth: CGFloat = 70

    /// Where the lane begins for a note: past the gutter mark sharing its
    /// height. Gutter marks hang across the axis and draw over everything
    /// under them, so a note that started at the axis would be covered — an
    /// hour pill reaches ~45 pt, a dose time capsule ~75 pt.
    static func laneStart(besideCapsule: Bool) -> CGFloat {
        besideCapsule ? 82 : 52
    }

    /// The glyph's leading x: clear of the gutter mark at the note's height,
    /// and clear of the widest curve there.
    static func glyphX(axisX: CGFloat, curveWidth: CGFloat, curveFraction: Double, besideCapsule: Bool) -> CGFloat {
        max(
            axisX + curveWidth * CGFloat(curveFraction) + curveGap,
            laneStart(besideCapsule: besideCapsule),
        )
    }

    /// Room left for the note's text between the glyph and the bubbles.
    static func textWidth(glyphX: CGFloat, bubbleLeft: CGFloat) -> CGFloat {
        max(0, bubbleLeft - columnGap - (glyphX + glyphSize + 5))
    }
}
