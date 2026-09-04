import SwiftUI

/// The vertical timeline's left-edge geometry. The axis line is the left
/// content edge (16 pt); the 8 pt strip left of it holds only the gutter
/// marks' overflow — every mark starts at the edge inset and hangs across
/// the axis.
nonisolated enum TimelineGutter {
    /// Nothing sits closer to the screen edge than this.
    static let edgeInset: CGFloat = 8
    /// The time axis, x from the slice's leading edge.
    static let axisX: CGFloat = 16

    /// A dose time in the device's own short time format ("1:01 AM", "13:01"),
    /// split so the hour can carry the primary weight and the rest — minutes
    /// and any day-half — reads lighter, the colon being the visual shift.
    static func timeParts(_ date: Date) -> (hour: String, rest: String) {
        let text = date.formatted(date: .omitted, time: .shortened)
        guard let colon = text.firstIndex(of: ":") else { return (text, "") }
        return (String(text[..<colon]), String(text[colon...]))
    }
}

/// A dose's timestamp as a gutter mark, in the device's short time format on
/// one line: the hour in the primary weight and the `:31 AM` smaller and
/// lighter so the colon is the visual shift. On the strip the capsule leaves a slot at its leading edge
/// for the dose dot, which sits on the axis; the list layout (axis off) has
/// no dot and drops the slot.
struct TimelineTimeCapsule: View {
    let date: Date
    /// Leave room at the leading edge for the dose dot on the axis.
    var hasDotSlot = true

    var body: some View {
        TimelineGutterMark(lines: .one) {
            let parts = TimelineGutter.timeParts(date)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: parts.hour)
                    .font(TimelineGutterMarkMetrics.primaryFont)
                Text(verbatim: parts.rest)
                    .font(TimelineGutterMarkMetrics.secondaryFont)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.leading, hasDotSlot ? Self.dotSlotWidth : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(date: .omitted, time: .shortened)))
    }

    /// Room for the dot on the axis plus the dot gap, inside the recipe's
    /// own padding.
    private static var dotSlotWidth: CGFloat {
        TimelineGutterMarkMetrics.dotLeadingPadding + TimelineGutterMarkMetrics.dotSize + TimelineGutterMarkMetrics.dotSpacing
    }
}
