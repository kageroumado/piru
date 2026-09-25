import SwiftUI

/// One logged dose on the vertical timeline — a Liquid Glass bubble floating
/// over the curve lane. Full style gives the name the whole first row and
/// puts dose + route chip on the second, with the readout trailing on that
/// row; compact puts name and dose on one line, drops the chip, and trails
/// the readout beside them. The readout is the effect's phase progress (the
/// same bar the dose hero and the Active Now card draw) in effect mode, and
/// the elimination percentage in body-load mode.
struct TimelineDoseBubble: View {
    let item: TimelineDayLayout.CardItem
    let style: TimelineBubbleStyle
    /// Body-load mode: the trailing readout is what remains in the body.
    let pkMode: Bool
    /// Whether the bubble carries its long-press menu and swipe; `false` for
    /// the menu's own preview of it.
    var actionable = true
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rendersTimelineFlat) private var rendersFlat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let cornerRadius: CGFloat = 14

    /// The bubble's width on the strip, per style.
    static func width(for style: TimelineBubbleStyle) -> CGFloat {
        switch style {
        case .full: 236
        case .compact: 224
        }
    }

    /// The bubble's height on the strip, per style: its height at the default
    /// text size, grown by ``heightScale``. The strip packs bubbles by this
    /// height, so it is what keeps a larger name clear of the next bubble.
    static func height(for style: TimelineBubbleStyle) -> CGFloat {
        let base: CGFloat = switch style {
        case .full: 58
        case .compact: 40
        }
        return (base * heightScale).rounded()
    }

    /// How much the bubble's text has grown over the default content size,
    /// capped: past the cap a bubble would outgrow the gaps between doses and
    /// the strip would stop reading as a timeline. Text in a capped bubble
    /// stays on one line and truncates.
    static var heightScale: CGFloat {
        #if canImport(UIKit)
            min(UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 1), maximumHeightScale)
        #else
            1
        #endif
    }

    private static let maximumHeightScale: CGFloat = 2

    private var isActive: Bool {
        (item.remainingFraction ?? 0) > 0.03
    }

    private var displayName: String {
        item.displayName
    }

    private var doseText: String {
        "\(item.isUnknownDose ? "?" : item.amount.doseFormatted) \(item.unit)"
    }

    var body: some View {
        if actionable {
            bubble.timelineDoseActions(item, bubbleWidth: Self.width(for: style)) {
                // The actionless bubble, flat: the preview renders outside the
                // strip, with no backdrop for glass to sample.
                TimelineDoseBubble(item: item, style: style, pkMode: pkMode, actionable: false) {}
                    .frame(width: Self.width(for: style))
                    .environment(\.rendersTimelineFlat, true)
            }
        } else {
            bubble
        }
    }

    private var bubble: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                switch style {
                case .full:
                    fullContent
                case .compact:
                    compactLeading
                    Spacer(minLength: 4)
                    trailingReadout
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.lg)
            .frame(height: Self.height(for: style))
            .contentShape(.rect)
            .modifier(BubbleSurface(tint: item.color, flat: rendersFlat))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(TimelineGlass.edgeHighlight(colorScheme: colorScheme), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(TimelineGlass.shadowOpacity(colorScheme: colorScheme)), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Name across the whole first row; dose, route chip and the readout
    /// share the second.
    private var fullContent: some View {
        HStack(spacing: Spacing.md) {
            LegendDot(color: isActive ? item.color : item.color.opacity(Theme.Opacity.muted))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(displayName)
                    .sectionLabel()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Spacing.xs) {
                    Text(verbatim: doseText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                    // At accessibility sizes the route pill would squeeze the
                    // dose to "90…"; the dose and the readout keep the row.
                    if !dynamicTypeSize.isAccessibilitySize {
                        ROAPill(route: item.route, size: .compact)
                    }
                    Spacer(minLength: 4)
                    trailingReadout
                }
            }
        }
    }

    private var compactLeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(displayName)
                .sectionLabel()
                .lineLimit(1)
            Text(verbatim: doseText)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var trailingReadout: some View {
        if pkMode {
            if let remaining = item.remainingFraction, isActive {
                Text("\(Int(remaining * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.color)
            }
        } else if let state = item.state, state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60) > DebugClock.now {
            // Only a dose still inside its window gets the minute clock; every
            // historical bubble would otherwise schedule its own timer and a
            // subgraph that evaluates to nothing.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = DebugClock.override ?? context.date
                let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
                if now >= state.doseTimestamp, now < end {
                    DosePhaseProgressBar(state: state, now: now, style: .compact)
                }
            }
        }
    }
}

/// The bubble's surface: Liquid Glass on screen, and a plain tinted card fill
/// where glass cannot exist.
private struct BubbleSurface: ViewModifier {
    let tint: Color
    let flat: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TimelineDoseBubble.cornerRadius, style: .continuous)
        if flat {
            content.background {
                shape.fill(Theme.cardBackground)
                shape.fill(tint.opacity(TimelineGlass.tintOpacity))
            }
        } else {
            content.glassEffect(.regular.tint(tint.opacity(TimelineGlass.tintOpacity)), in: .rect(cornerRadius: TimelineDoseBubble.cornerRadius))
        }
    }
}

extension EnvironmentValues {
    /// Set by an offscreen render of the timeline. An `ImageRenderer` has no
    /// backdrop to sample, so it draws Liquid Glass as an opaque smear of
    /// whatever lies under it; the bubbles take a card fill there instead.
    @Entry var rendersTimelineFlat = false
}

/// The volumetric recipe every glass surface on the strip shares — a whisper
/// of the substance color in the glass, a top-edge highlight that says "lit
/// from above", and a soft drop shadow that lifts the bubble off the lane.
enum TimelineGlass {
    /// Opacity of the substance color tinting a bubble's glass.
    static let tintOpacity = 0.06

    /// Opacity of the white top-edge highlight.
    static func highlightOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.12 : 0.25
    }

    /// Opacity of the drop shadow under a bubble.
    static func shadowOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.30 : 0.06
    }

    /// A top-down stroke gradient: the highlight at the top edge fading to
    /// `floor` (transparent by default) at the bottom.
    static func edgeHighlight(colorScheme: ColorScheme, floor: Color = .clear) -> LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(highlightOpacity(colorScheme: colorScheme)), floor],
            startPoint: .top,
            endPoint: .bottom,
        )
    }
}
