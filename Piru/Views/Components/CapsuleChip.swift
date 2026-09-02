import SwiftUI

extension Text {
    /// The shared badge grammar for categorical labels on a row — the route pill
    /// ("oral") and the dose-strength chip ("heavy") render identically so they
    /// read as one visual language: caption2-semibold text on a tinted chip.
    /// `text` is the gated label colour, `fill` the mark colour the chip is
    /// tinted from. They are separate because they cannot be the same value:
    /// a colour drawn on a tint of *itself* tops out around 4.5:1 and fails
    /// below it, which is what put most of this app's small copy under WCAG AA.
    /// Every scale in `design-system/color/` ships both variants for exactly
    /// this call. The form (capsule or blinky) is the skin's — see ``skinChip``.
    func capsuleChip(text: Color, fill: Color) -> some View {
        skinChip(text: text, fill: fill, font: .caption2.weight(.semibold), horizontal: 8, vertical: 3)
    }

    /// The chip at the larger **hero** size — same grammar as ``capsuleChip``
    /// but matching ``ROAPill``'s `.regular` metrics (`.caption`/10·5) so a
    /// strength or salt badge sits the same height as the route pill in a
    /// standalone hero. Row chips stay on ``capsuleChip``.
    func heroChip(text: Color, fill: Color) -> some View {
        skinChip(text: text, fill: fill, font: .caption.weight(.semibold), horizontal: 10, vertical: 5)
    }

    /// A bordered, **unfilled** chip for freeform tags — deliberately a
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
        skinOutlineChip(stroke: stroke, font: .caption2.weight(.medium), horizontal: 8, vertical: 3)
    }
}
