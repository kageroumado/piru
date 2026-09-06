import SwiftUI

// The form layer of the skin system: how buttons and chips are drawn under
// each `SkinSurface`. Colour comes from `Theme` / `Skin`; this file
// only decides shape, stroke and shadow. Graphs never come through here.

/// Prominence of a standalone action.
enum SkinButtonProminence {
    /// The accent-tinted primary (the system "Allow" pill).
    case prominent
    /// The plain counterpart for skip / not-now escape hatches.
    case neutral
}

extension View {
    /// The skin's button treatment. A glass skin keeps the system Liquid Glass
    /// styles; an edged skin draws a solid sticker with a stroke and a hard
    /// shadow the press sinks onto. Replaces `.buttonStyle(.glassProminent)` /
    /// `.buttonStyle(.glass)` at every standalone action.
    @ViewBuilder
    func skinButtonStyle(_ prominence: SkinButtonProminence) -> some View {
        switch SkinStore.shared.current.surface {
        case .glass:
            switch prominence {
            case .prominent: buttonStyle(.glassProminent)
            case .neutral: buttonStyle(.glass)
            }
        case let .edged(stroke, strokeWidth, shadow, shadowOffset):
            buttonStyle(EdgedButtonStyle(
                prominence: prominence,
                stroke: stroke,
                strokeWidth: strokeWidth,
                shadow: shadow,
                shadowOffset: shadowOffset,
            ))
        case let .soft(stroke, glow, glowRadius):
            buttonStyle(SoftButtonStyle(prominence: prominence, stroke: stroke, glow: glow, glowRadius: glowRadius))
        }
    }
}

/// A glowing button: solid fill, hairline, a coloured bloom beneath that
/// brightens on press — the way Tsuki signals selection.
struct SoftButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color
    let glow: Color
    let glowRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: (skin.cardCornerRadius ?? 16) - 2, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(prominence == .prominent ? skin.accent : skin.cardBackground)
                    .shadow(color: glow.opacity(pressed ? 0.7 : 0.4), radius: pressed ? glowRadius * 0.6 : glowRadius, y: 3)
                shape.stroke(stroke.opacity(prominence == .prominent ? 0.0 : 0.4), lineWidth: 1)
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// A sticker button: solid fill, stroke, hard offset shadow. Pressing moves the
/// face onto its shadow instead of dimming it — the site's buttons do the same.
struct EdgedButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color
    let strokeWidth: CGFloat
    let shadow: Color
    let shadowOffset: CGSize

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: skin.cardCornerRadius ?? 12, style: .continuous)
        let pressed = configuration.isPressed
        // Fill is the text-safe accent, not the vivid mark: `onAccent` is gated
        // against it (6.4:1 night, 4.8:1 pink), and a label is small copy.
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(shadow).offset(pressed ? .zero : shadowOffset)
                shape.fill(prominence == .prominent ? skin.accent : skin.cardBackground)
                shape.stroke(stroke, lineWidth: strokeWidth)
            }
            .offset(pressed ? shadowOffset : .zero)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension Text {
    /// The skin's chip: the badge grammar every categorical label shares
    /// (route, strength, severity, tags). `text` is the gated label colour,
    /// `fill` the mark colour. A glass skin tints a capsule from `fill` at
    /// 0.10 — never higher, a colour on a tint of itself asymptotes around
    /// 4.5:1 in dark mode. An edged skin draws the site's blinky: a square
    /// chip with a stroke in the mark colour on the input surface.
    @ViewBuilder
    func skinChip(text: Color, fill: Color, style: Font.TextStyle, weight: Font.Weight, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(.piruLabel(style, weight: weight))
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
        switch SkinStore.shared.current.surface {
        case .glass, .soft:
            base
                .background(fill.opacity(Theme.Opacity.tint), in: Capsule())
                .foregroundStyle(text)
        case .edged:
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            base
                .background(Theme.inputBackground, in: shape)
                .overlay(shape.strokeBorder(fill, lineWidth: 1.5))
                .foregroundStyle(text)
        }
    }

    /// The outline grammar — an **unfilled** chip whose stroke may carry an
    /// identity colour (a per-substance colour is a non-text mark at the 3:1
    /// floor, never the label). Capsule under glass, square under an edge.
    @ViewBuilder
    func skinOutlineChip(stroke: Color, style: Font.TextStyle, weight: Font.Weight, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(.piruLabel(style, weight: weight))
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .foregroundStyle(Theme.secondaryLabel)
        switch SkinStore.shared.current.surface {
        case .glass, .soft:
            base.overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        case .edged:
            base.overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(stroke, lineWidth: 1.5))
        }
    }
}

/// The shape of a small filled chip drawn outside the chip primitives — the
/// white-on-gradient chips on the Library cards. A capsule, or the skin's
/// squared chip corner.
func skinChipShape() -> AnyShape {
    if let radius = SkinStore.shared.current.chipCornerRadius {
        AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    } else {
        AnyShape(Capsule())
    }
}
