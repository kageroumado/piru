import SwiftUI

/// A miniature of the Journal wearing `skin`, in two layers: the skin's live
/// animated backdrop, and over it a picture of the real vertical timeline drawn
/// in that skin (``SkinPreviewTimeline``).
///
/// Both layers are laid out at a phone's size and scaled down, rather than drawn
/// small, so the scene keeps the density it has on a real screen and the
/// timeline keeps its real proportions — a skin looks here the way it will look
/// once worn. Nothing in it can be tapped: the timeline is a picture and the
/// backdrop takes no touches.
struct SkinPreviewCard: View {
    let skin: Skin
    /// Only the card in front should tick; the rest hold one still frame, so a
    /// carousel costs one live canvas however many skins it holds.
    var animates = false
    var width: CGFloat = Metrics.defaultWidth

    @State private var timeline = SkinPreviewTimeline.shared
    @State private var skins = SkinStore.shared
    @State private var picture: Image?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private enum Metrics {
        static let defaultWidth: CGFloat = 176
        static let cornerRadius: CGFloat = 24
    }

    var body: some View {
        let screen = SkinPreviewTimeline.screenSize
        let scale = width / screen.width
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        ZStack {
            SkinBackdrop(skin: skin, animates: animates)
            // The card in front wears the skin the app is trying on, so there —
            // and only there — the timeline can be the live views: real glass
            // over the moving scene. Everywhere else it is the picture.
            if animates, skin == skins.current, !timeline.days.isEmpty {
                SkinPreviewScreen(days: timeline.days, skin: skin)
                    .allowsHitTesting(false)
                    // Its rows are real journal buttons; in a picture of a
                    // journal they would read as controls that do nothing.
                    .accessibilityHidden(true)
            } else {
                picture?.resizable()
            }
        }
        .frame(width: screen.width, height: screen.height)
        .scaleEffect(scale, anchor: .topLeading)
        // A fixed frame, whatever the skin: the carousel must not move as the
        // faces and card styles inside it change.
        .frame(width: width, height: screen.height * scale, alignment: .topLeading)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
        // Rendered from a task, never from `body`: a render evaluates a whole
        // view tree of its own. Keyed on the scheme, which changes the picture.
        .task(id: colorScheme) {
            await timeline.prepare()
            picture = timeline.snapshot(for: skin, dark: colorScheme == .dark, scale: displayScale)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(skin.displayName))
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
