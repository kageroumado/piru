import SwiftUI

// The form layer of the skin system: how buttons, chips and stickers are
// drawn under each `SkinSurface`. Colour comes from `Theme` / `Skin`; this file
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
        }
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
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(shadow).offset(pressed ? .zero : shadowOffset)
                shape.fill(prominence == .prominent ? skin.accentMark : skin.cardBackground)
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
    func skinChip(text: Color, fill: Color, font: Font, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
        switch SkinStore.shared.current.surface {
        case .glass:
            base
                .background(fill.opacity(0.10), in: Capsule())
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
    func skinOutlineChip(stroke: Color, font: Font, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .foregroundStyle(Theme.secondaryLabel)
        switch SkinStore.shared.current.surface {
        case .glass:
            base.overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        case .edged:
            base.overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(stroke, lineWidth: 1.5))
        }
    }
}

/// A tab sticker: the skin's label for a group — a day on the timeline, a
/// section on a card. Glass skins show a material capsule; edged skins the
/// site's `.tab`: accent fill, stroke, a hard shadow in the eyebrow colour.
struct SkinSticker<Label: View>: View {
    let isAccented: Bool
    @ViewBuilder let label: Label

    var body: some View {
        let skin = SkinStore.shared.current
        switch skin.surface {
        case .glass:
            label
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: .capsule)
        case let .edged(stroke, strokeWidth, _, shadowOffset):
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            label
                .foregroundStyle(isAccented ? skin.onAccent : skin.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    shape.fill(skin.eyebrow).offset(shadowOffset)
                    shape.fill(isAccented ? skin.accentMark : skin.cardBackground)
                    shape.stroke(stroke, lineWidth: strokeWidth)
                }
        }
    }
}
