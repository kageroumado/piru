import SwiftUI

extension Text {
    /// The shared badge grammar for categorical labels on a row — the route pill
    /// ("oral") and the dose-strength chip ("heavy") render identically so they
    /// read as one visual language: caption2-semibold text on a 16% tint capsule.
    /// `text` is the gated label colour, `fill` the mark colour the capsule is
    /// tinted from. They are separate because they cannot be the same value:
    /// a colour drawn on a tint of *itself* tops out around 4.5:1 and fails
    /// below it, which is what put most of this app's small copy under WCAG AA.
    /// Every scale in `design-system/color/` ships both variants for exactly
    /// this call.
    ///
    /// The tint is 0.10 — the alpha every `text` variant is derived against.
    /// Never raise it: a colour on a tint of itself asymptotes around 4.5:1 in
    /// dark mode regardless of lightness, so a heavier tint fails the WCAG AA
    /// gate.
    func capsuleChip(text: Color, fill: Color) -> some View {
        font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fill.opacity(0.10), in: Capsule())
            .foregroundStyle(text)
    }

    /// The filled capsule at the larger **hero** size — same tint grammar as
    /// ``capsuleChip`` but matching ``ROAPill``'s `.regular` metrics
    /// (`.caption`/10·5) so a strength or salt badge sits the same height as the
    /// route pill in a standalone hero. Row chips stay on ``capsuleChip``.
    func heroChip(text: Color, fill: Color) -> some View {
        font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill.opacity(0.10), in: Capsule())
            .foregroundStyle(text)
    }

    /// A bordered, **unfilled** capsule for freeform tags — deliberately a
    /// different grammar from the filled ``capsuleChip`` (route/strength/severity)
    /// so a rarely-used tag reads as a quiet annotation rather than competing with
    /// the dose's categorical badges. Secondary text, hairline outline.
    func capsuleOutlineChip() -> some View {
        capsuleOutlineChip(stroke: Color.secondary.opacity(0.3))
    }

    /// The outline grammar carrying an **identity** colour in its stroke.
    ///
    /// This is how a per-substance colour appears on a chip. It cannot be the
    /// label colour: identity colours are chosen by the user, or by an FNV-1a
    /// hash of the substance name, so nothing constrains their lightness — and
    /// clearing 4.5:1 as 11pt text on a tint of itself needs Oklab L <= 0.50,
    /// which the app's own palette mostly exceeds. A stroke is a non-text mark
    /// at the 3:1 floor, so the colour still identifies the row while the label
    /// stays readable.
    func capsuleOutlineChip(stroke: Color) -> some View {
        font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Theme.secondaryLabel)
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }
}
