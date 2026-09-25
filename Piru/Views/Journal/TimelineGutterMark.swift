import SwiftUI

/// The one recipe every mark in the vertical timeline's gutter is built from
/// — the day tag, the "Now" tag, the hour ruler pills and the dose time
/// capsules share this fill, corner radius, padding and type ramp, so the
/// gutter reads as one family of labels. Marks are opaque: each hangs across
/// the axis from the strip's leading edge and covers the ruler behind it.
///
/// Type ramp (``TimelineGutterFont``): primary 13 pt semibold, secondary
/// 11 pt; the day tag alone steps up to 14/12 so the day word stays legible
/// as the strip's landmark. All four scale with Dynamic Type to a cap.
struct TimelineGutterMark<Content: View>: View {
    /// A mark's line count decides its height at the default text size, so
    /// the gutter's collision rules (``TimelineGutterLabels``) match what is
    /// drawn.
    enum Lines {
        case one
        case two
    }

    let lines: Lines
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .lineLimit(1)
            .padding(.horizontal, TimelineGutterMarkMetrics.horizontalPadding)
            .frame(minHeight: lines == .one ? TimelineGutterMarkMetrics.singleLineHeight : TimelineGutterMarkMetrics.twoLineHeight)
            .background {
                RoundedRectangle(cornerRadius: TimelineGutterMarkMetrics.cornerRadius, style: .continuous)
                    .fill(Theme.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: TimelineGutterMarkMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: TimelineGutterMarkMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(Theme.Opacity.hairline), lineWidth: 1)
                    }
            }
    }
}

/// The recipe's measurements and type ramp, shared by every mark and by the
/// gutter's collision rules.
enum TimelineGutterMarkMetrics {
    static let cornerRadius: CGFloat = 8
    static let horizontalPadding: CGFloat = 5
    /// Height of a one-line mark at the default text size.
    static let singleLineHeight: CGFloat = 22
    /// Height of a two-line mark (the day tag) at the default text size.
    static let twoLineHeight: CGFloat = 40
    /// Diameter of the dot a mark carries on the axis (Today, Now).
    static let dotSize: CGFloat = 6
    /// Extra leading padding, inside the recipe's own, that centers a mark's
    /// dot on the axis: the mark starts at ``TimelineGutter/edgeInset`` and
    /// the axis sits at ``TimelineGutter/axisX``.
    static let dotLeadingPadding: CGFloat = TimelineGutter.axisX - TimelineGutter.edgeInset - dotSize / 2 - horizontalPadding
    /// Gap between a mark's dot and its text.
    static let dotSpacing: CGFloat = 4
}

/// The gutter's type ramp. Each role scales with Dynamic Type up to a cap:
/// the gutter is a fixed lane beside the curves, and past the cap a mark would
/// run under the dose bubbles instead of getting more legible. Marks grow
/// taller with their text, from ``TimelineGutterMarkMetrics/singleLineHeight``.
enum TimelineGutterFont {
    case primary
    case secondary
    case dayPrimary
    case daySecondary
}

extension View {
    func timelineGutterFont(_ role: TimelineGutterFont) -> some View {
        switch role {
        case .primary:
            scaledSystemFont(size: 13, weight: .semibold, design: .rounded, relativeTo: .footnote, maximumSize: 17, monospacedDigit: true)
        case .secondary:
            scaledSystemFont(size: 11, design: .rounded, relativeTo: .caption2, maximumSize: 14, monospacedDigit: true)
        case .dayPrimary:
            scaledSystemFont(size: 14, weight: .semibold, design: .rounded, relativeTo: .footnote, maximumSize: 18)
        case .daySecondary:
            scaledSystemFont(size: 12, design: .rounded, relativeTo: .caption, maximumSize: 15, monospacedDigit: true)
        }
    }
}

// MARK: - Hour ruler

/// One hour on the ruler, as the locale writes an hour on its own — "1 AM"
/// where the day runs in twelves, "13" where it runs to twenty-four.
struct TimelineHourMark: View {
    let text: String

    var body: some View {
        TimelineGutterMark(lines: .one) {
            Text(verbatim: text)
                .timelineGutterFont(.primary)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .accessibilityHidden(true)
    }

    /// The hour-only label for `date` in the current locale and the user's
    /// 12/24 h preference.
    static func label(for date: Date) -> String {
        date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
    }
}

// MARK: - Now

/// The "Now" tag: the accent dot on the axis and the word, on the shared mark
/// recipe with the accent tint.
struct TimelineNowMark: View {
    var body: some View {
        TimelineGutterMark(lines: .one) {
            HStack(alignment: .center, spacing: TimelineGutterMarkMetrics.dotSpacing) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: TimelineGutterMarkMetrics.dotSize, height: TimelineGutterMarkMetrics.dotSize)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                Text("Now")
                    .timelineGutterFont(.primary)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.leading, TimelineGutterMarkMetrics.dotLeadingPadding)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day tag

/// The day marker at the top of each slice — the relative day or weekday
/// over the date, on the shared mark recipe one type step up. Today carries
/// the accent dot on the axis.
struct TimelineDayHeader: View {
    let date: Date
    let isToday: Bool

    var body: some View {
        TimelineGutterMark(lines: .two) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: TimelineGutterMarkMetrics.dotSpacing) {
                    if isToday {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: TimelineGutterMarkMetrics.dotSize, height: TimelineGutterMarkMetrics.dotSize)
                    }
                    Text(primaryText)
                        .timelineGutterFont(.dayPrimary)
                        .foregroundStyle(isToday ? .primary : Theme.secondaryLabel)
                }
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .timelineGutterFont(.daySecondary)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.leading, isToday ? TimelineGutterMarkMetrics.dotLeadingPadding : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
