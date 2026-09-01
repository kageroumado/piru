import SwiftUI

/// The vertical timeline's left-edge geometry. The axis line is the left
/// content edge (16 pt); the 8 pt strip left of it holds only the time
/// capsules' overflow, so the gutter is that strip plus one capsule width and
/// every gutter label — capsule digits, hour numerals, sun/moon, the Now tag —
/// centers on one column just right of the axis.
nonisolated enum TimelineGutter {
    /// Nothing sits closer to the screen edge than this.
    static let edgeInset: CGFloat = 8
    /// The time axis, x from the slice's leading edge.
    static let axisX: CGFloat = 16
    /// A dose capsule spans `edgeInset ..< edgeInset + capsuleWidth`, hanging
    /// across the axis with its dose dot in the leading margin.
    static let capsuleWidth: CGFloat = 34
    static let capsuleHeight: CGFloat = 30
    /// The gutter's trailing edge.
    static var end: CGFloat {
        edgeInset + capsuleWidth
    }

    /// Center x of every gutter label's digits — the column between the dose
    /// dot's clearance and the capsule's trailing padding.
    static var labelCenterX: CGFloat {
        (axisX + 6 + end - 4) / 2
    }

    /// The bare 24 h hour, two digits, whatever the device's 12/24 h setting —
    /// the gutter has no room for AM/PM, and the sun/moon glyphs carry the
    /// day-half.
    static func hourNumeral(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.hour, from: date))
    }

    static func minuteNumeral(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.minute, from: date))
    }
}

/// A dose's timestamp as a small tag: the 24 h hour over the minutes, the
/// minutes lighter and smaller so the pair reads as one number (`19` / `06`).
/// Opaque, so the axis and ruler it hangs across stay covered behind it.
struct TimelineTimeCapsule: View {
    let date: Date

    var body: some View {
        VStack(spacing: -1) {
            Text(verbatim: TimelineGutter.hourNumeral(date))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            Text(verbatim: TimelineGutter.minuteNumeral(date))
                .font(.system(size: 9, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.trailing, TimelineGutter.end - TimelineGutter.labelCenterX - 7)
        .frame(width: TimelineGutter.capsuleWidth, height: TimelineGutter.capsuleHeight, alignment: .trailing)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(date: .omitted, time: .shortened)))
    }
}
