import SwiftUI

/// A miniature of the app wearing `skin`: its ground, its real animated scene,
/// its card treatment, its accent and its display face.
///
/// The screen is laid out at ``referenceSize`` and scaled down, rather than
/// drawn small, so the scene keeps the density it has on a real screen and the
/// cards keep their real proportions — a skin looks here the way it will look
/// once worn. Everything resolves from `skin`, never from the skin the app is
/// wearing, so a row of these shows every skin at once.
struct SkinPreviewCard: View {
    let skin: Skin
    /// Only the card in front should tick; the rest hold one still frame, so a
    /// carousel costs one live canvas however many skins it holds.
    var animates = false
    var width: CGFloat = Metrics.defaultWidth

    private enum Metrics {
        static let defaultWidth: CGFloat = 176
        static let referenceSize = CGSize(width: 330, height: 570)
        static let cornerRadius: CGFloat = 24
        static let mockCardRadius: CGFloat = 22
        static let titleSize: CGFloat = 32
    }

    var body: some View {
        let scale = width / Metrics.referenceSize.width
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        screen
            .frame(width: Metrics.referenceSize.width, height: Metrics.referenceSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: Metrics.referenceSize.height * scale, alignment: .topLeading)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
            .accessibilityElement()
            .accessibilityLabel(Text(skin.displayName))
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(skin.displayName)
                .font(titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 36)
            entryCard(dots: 3)
            entryCard(dots: 2)
            HStack(spacing: 10) {
                chip(filled: true)
                chip(filled: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { SkinBackdrop(skin: skin, animates: animates) }
    }

    /// A stand-in journal card: marks in the skin's accent, bars where the copy
    /// would be. Shapes rather than words, so the miniature reads at any size
    /// and in any language.
    private func entryCard(dots: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0 ..< dots, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle().fill(skin.accentMark).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(.primary).frame(width: index == 0 ? 150 : 118, height: 9)
                        Capsule().fill(skin.secondaryLabel).frame(width: index == 1 ? 96 : 72, height: 7)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ThemedBackground(
            shape: RoundedRectangle(cornerRadius: Metrics.mockCardRadius, style: .continuous),
            insetDash: true,
            skin: skin,
        ))
    }

    private func chip(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.chipCornerRadius ?? 17, style: .continuous)
        return Capsule()
            .fill(filled ? skin.onAccent : skin.accent)
            .frame(width: 54, height: 8)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background {
                if filled {
                    shape.fill(skin.accentMark)
                } else {
                    shape.strokeBorder(skin.accent, lineWidth: 1.5)
                }
            }
    }

    private var titleFont: Font {
        let typeface = skin.typeface
        guard let family = typeface.display else {
            return .system(size: Metrics.titleSize, weight: .bold, design: skin.fontDesign ?? .default)
        }
        return SkinFace.font(
            family: family, weight: .bold, size: Metrics.titleSize * typeface.displayScale,
            relativeTo: .largeTitle, scaling: false,
        )
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 16) {
            ForEach(Skin.available) { skin in
                SkinPreviewCard(skin: skin, animates: skin == .jellyfish)
            }
        }
        .padding()
    }
}
