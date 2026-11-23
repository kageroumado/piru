import SwiftUI

/// What a chip's text is, which decides its case.
///
/// **The rule for pill text.** A chip that carries a word the app supplies — a
/// route, a strength, a severity, a class, a state — is lowercase when the chip
/// is small (``CapsuleChipSize/compact``, ``CapsuleChipSize/regular``: "oral",
/// "strong", "dangerous", "stimulant") and capitalized when it is the larger hero
/// chip ("Oral", "Strong", "Empathogen"). A chip that carries a name or a value
/// keeps it exactly as written: a substance, a product, a person, a tag the
/// person typed ("trip"), a count. Never all capitals.
///
/// The case comes from the chip, through `textCase`, so every source string is
/// authored in its normal (capitalized) form and reads correctly where the same
/// value is printed in a sentence or a list. Never `.lowercased()` a chip's text
/// at a call site. `textCase` does nothing to Chinese.
///
/// The HIG sets no case for badges or tags; its rule is to pick one
/// capitalization per element type and apply it everywhere (`writing.md`). The
/// size split is the owner's call within that rule.
enum ChipLabel {
    /// A word the app supplies; cased by the chip's size.
    case word
    /// A name or value; shown as written.
    case name
}

/// The three sizes the filled capsule chip comes in.
///
/// Size here is optical, not semantic: the same badge is `.compact` on a dense
/// row and `.hero` standing alone, so it keeps a constant relationship to the
/// text beside it.
enum CapsuleChipSize {
    /// caption2-semibold, 8·3 — a badge on a list row.
    case compact
    /// caption2-semibold, 10·4 — a badge in a card header.
    case regular
    /// caption-semibold, 10·5 — a badge standing alone beside a hero value,
    /// matching `ROAPill`'s `.regular` metrics.
    case hero

    /// The case a ``ChipLabel/word`` takes at this size: lowercase on the small
    /// chips, as written (capitalized) on the hero chip.
    var wordCase: Text.Case? {
        switch self {
        case .compact, .regular: .lowercase
        case .hero: nil
        }
    }

    /// The text style, not a `Font`: the skin's chip primitive sets the face.
    var textStyle: Font.TextStyle {
        switch self {
        case .compact, .regular: .caption2
        case .hero: .caption
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: Spacing.md
        case .regular, .hero: Spacing.lg
        }
    }

    /// Off-ladder on purpose at `.compact` and `.hero`: a capsule's vertical
    /// inset sets its cap height against the text beside it, so these are
    /// optical values matched to a font, not layout gaps drawn from ``Spacing``.
    var verticalPadding: CGFloat {
        switch self {
        case .compact: 3
        case .regular: Spacing.xs
        case .hero: 5
        }
    }
}

extension Text {
    /// The shared badge grammar for categorical labels on a row — the route pill
    /// ("oral") and the dose-strength chip ("heavy") render identically so they
    /// read as one visual language: caption2-semibold text on a tinted chip.
    /// `text` is the gated label color, `fill` the mark color the chip is
    /// tinted from. They must differ: a color drawn on a tint of itself tops out
    /// around 4.5:1, below WCAG AA for small text. Every scale in
    /// `design-system/color/` ships both variants for this call. The form
    /// (capsule or blinky) is the skin's; see ``skinChip``. `label` sets the
    /// case (``ChipLabel``).
    func capsuleChip(
        text: Color, fill: Color, size: CapsuleChipSize = .compact, label: ChipLabel = .word,
    ) -> some View {
        skinChip(
            text: text,
            fill: fill,
            style: size.textStyle,
            weight: .semibold,
            horizontal: size.horizontalPadding,
            vertical: size.verticalPadding,
        )
        .textCase(label == .word ? size.wordCase : nil)
    }

    /// The chip at the larger **hero** size — same grammar as ``capsuleChip``
    /// but matching ``ROAPill``'s `.regular` metrics so a strength or salt badge
    /// sits the same height as the route pill in a standalone hero.
    func heroChip(text: Color, fill: Color, label: ChipLabel = .word) -> some View {
        capsuleChip(text: text, fill: fill, size: .hero, label: label)
    }

    /// The outline grammar at the **hero** size: ``capsuleOutlineChip(stroke:)``'s
    /// identity-colored stroke on ``ROAPill``'s `.regular` line box, so an
    /// ester badge beside the route pill is one height with it.
    func heroOutlineChip(stroke: Color) -> some View {
        skinOutlineChip(
            stroke: stroke,
            style: CapsuleChipSize.hero.textStyle,
            weight: .semibold,
            horizontal: CapsuleChipSize.hero.horizontalPadding,
            vertical: CapsuleChipSize.hero.verticalPadding,
        )
    }

    /// A bordered, **unfilled** chip for freeform tags — deliberately a
    /// different grammar from the filled ``capsuleChip`` (route/strength/severity)
    /// so a rarely-used tag reads as a quiet annotation rather than competing with
    /// the dose's categorical badges. Secondary text, hairline outline.
    func capsuleOutlineChip() -> some View {
        capsuleOutlineChip(stroke: Color.secondary.opacity(0.3))
    }

    /// The outline grammar carrying an **identity** color in its stroke.
    ///
    /// This is how a per-substance color appears on a chip. It cannot be the
    /// label color: identity colors are chosen by the user, or by an FNV-1a
    /// hash of the substance name, so nothing constrains their lightness — and
    /// clearing 4.5:1 as 11pt text on a tint of itself needs Oklab L <= 0.50,
    /// which the app's own palette mostly exceeds. A stroke is a non-text mark
    /// at the 3:1 floor, so the color still identifies the row while the label
    /// stays readable.
    func capsuleOutlineChip(stroke: Color) -> some View {
        skinOutlineChip(stroke: stroke, style: .caption2, weight: .medium, horizontal: Spacing.md, vertical: 3)
    }
}

/// A substance's identity color as a dot leading a chip's label.
///
/// A chip that stands for a substance carries its color here and keeps its text
/// in the label color: identity colors are unconstrained in lightness, so the
/// color as text on a tint of itself falls to about 2:1 in light mode. The dot
/// only identifies; the label beside it is what is read.
struct SubstanceChipDot: View {
    let color: Color
    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
