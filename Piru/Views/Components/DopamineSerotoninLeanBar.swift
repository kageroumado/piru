import SwiftUI

/// The dopamine ↔ serotonin lean spectrum — a gradient bar with a marker at `leanPosition`, the two
/// endpoint labels, and the lean label with its optional DAT:SERT ratio beneath. Rendered by the
/// unified Pharmacology card, and collapsed into a single VoiceOver element (the marker/gradient are
/// decorative on their own).
struct DopamineSerotoninLeanBar: View {
    let leanPosition: Double?
    let leanLabel: LocalizedStringResource
    let ratioText: String?
    /// When false, the word lean-label ("Serotonin-leaning…") is dropped from the
    /// visible layout and folded into the a11y value instead — the unified
    /// Pharmacology card uses this because the bar plus the ratio line already
    /// convey the lean, so the restated words are noise (design review §3.3).
    var showsLeanLabel: Bool = true
    /// A ready-made ratio line ("SERT : DAT release ≈ 13 : 1") that replaces the
    /// raw "DAT:SERT <n>" caption when provided.
    var ratioLine: String?
    var onInfo: (() -> Void)?

    private var serotoninColor: Color {
        SubstanceCategory.empathogen.color
    }
    private var dopamineColor: Color {
        SubstanceCategory.stimulant.color
    }

    /// Half the knob; the ratio label centers on this and is clamped by it.
    private static let knobRadius: CGFloat = 8
    private static let ratioLabelWidth: CGFloat = 190
    /// Vertical room reserved above the track for the ratio label.
    private static let ratioRowHeight: CGFloat = 18

    /// Centered on the knob, then clamped so neither end escapes the track. At the
    /// extremes the text also switches its own alignment, so a clamped label hugs
    /// the edge it belongs to instead of drifting away from the knob.
    private func ratioOffset(knobX: CGFloat, width: CGFloat) -> CGFloat {
        let ideal = knobX - Self.ratioLabelWidth / 2
        return min(max(ideal, 0), max(0, width - Self.ratioLabelWidth))
    }

    private func ratioAlignment(knobX: CGFloat, width: CGFloat) -> TextAlignment {
        if knobX < Self.ratioLabelWidth / 2 { return .leading }
        if knobX > width - Self.ratioLabelWidth / 2 { return .trailing }
        return .center
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { geo in
                let knobX = geo.size.width * (leanPosition ?? 0.5)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [serotoninColor, dopamineColor], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .offset(y: Self.ratioRowHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.black.opacity(Theme.Opacity.hairline), lineWidth: 0.5))
                        .shadow(color: .black.opacity(Theme.Opacity.emphasis), radius: 2, y: 1)
                        .offset(x: knobX - Self.knobRadius, y: Self.ratioRowHeight)
                    // The ratio rides directly above the knob, so it reads as that
                    // position's value rather than a caption about the whole bar —
                    // far left when a compound is serotonin-dominant, far right when
                    // it is dopamine-dominant. Clamped so it stays inside the track
                    // at either extreme.
                    if let ratioLine {
                        Text(verbatim: ratioLine)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: Self.ratioLabelWidth)
                            .multilineTextAlignment(ratioAlignment(knobX: knobX, width: geo.size.width))
                            .offset(x: ratioOffset(knobX: knobX, width: geo.size.width))
                    }
                }
                .frame(height: 16 + Self.ratioRowHeight)
            }
            .frame(height: 16 + Self.ratioRowHeight)

            HStack {
                Text("Serotonin").font(.caption2.weight(.medium)).foregroundStyle(serotoninColor)
                Spacer()
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("About monoamine profile")
                    Spacer()
                }
                Text("Dopamine").font(.caption2.weight(.medium)).foregroundStyle(dopamineColor)
            }

            if showsLeanLabel || (ratioLine == nil && ratioText != nil) {
                VStack(alignment: .leading, spacing: 1) {
                    if showsLeanLabel {
                        Text(leanLabel).font(.caption.weight(.semibold))
                    }
                    if ratioLine == nil, let ratioText {
                        Text("DAT:SERT \(ratioText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dopamine–serotonin lean"))
        .accessibilityValue(Text(leanLabel))
    }
}
