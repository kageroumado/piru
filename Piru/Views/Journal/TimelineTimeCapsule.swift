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

    /// The bare 24 h hour, two digits, whatever the device's 12/24 h setting —
    /// a dose capsule has no room for AM/PM, and the hour ruler beside it
    /// carries the day-half.
    static func hourNumeral(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.hour, from: date))
    }

    static func minuteNumeral(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.minute, from: date))
    }
}

/// A dose's timestamp as a gutter mark: `00:31` on one line, the hour in the
/// primary weight and the `:31` smaller and lighter so the colon is the
/// visual shift. On the strip the capsule leaves a slot at its leading edge
/// for the dose dot, which sits on the axis; the list layout (axis off) has
/// no dot and drops the slot.
struct TimelineTimeCapsule: View {
    let date: Date
    /// Leave room at the leading edge for the dose dot on the axis.
    var hasDotSlot = true

    var body: some View {
        TimelineGutterMark(lines: .one) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: TimelineGutter.hourNumeral(date))
                    .font(TimelineGutterMarkMetrics.primaryFont)
                Text(verbatim: ":" + TimelineGutter.minuteNumeral(date))
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
