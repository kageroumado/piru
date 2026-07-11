import SwiftUI

extension Text {
    /// The shared badge grammar for categorical labels on a row — the route pill
    /// ("oral") and the dose-strength chip ("heavy") render identically so they
    /// read as one visual language: caption2-semibold text on a 16% tint capsule.
    func capsuleChip(tint: Color) -> some View {
        font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    /// A bordered, **unfilled** capsule for freeform tags — deliberately a
    /// different grammar from the filled ``capsuleChip`` (route/strength/severity)
    /// so a rarely-used tag reads as a quiet annotation rather than competing with
    /// the dose's categorical badges. Secondary text, hairline outline.
    func capsuleOutlineChip() -> some View {
        font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Theme.secondaryLabel)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}
