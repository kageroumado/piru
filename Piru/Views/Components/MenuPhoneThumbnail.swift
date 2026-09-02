import SwiftUI

/// A line-art iPhone silhouette drawn in a single color (accent when selected, gray otherwise),
/// its screen sketched by the caller — the Mail-style "view options" thumbnail used by the
/// Tolerance and Journal options popovers. Proportions are taken from the Apple iPhone 17 bezel
/// (aspect ≈ 0.485, continuous corners) so it reads as a phone rather than an arbitrary
/// rectangle. No image assets.
struct MenuPhoneThumbnail: View {
    let selected: Bool
    /// Draws the screen content into the given rect with the pre-tinted color.
    let sketch: (GraphicsContext, CGRect, Color) -> Void

    var body: some View {
        Canvas { context, size in
            let color: Color = selected ? Theme.accent : .secondary
            let line = max(1.6, size.width * 0.03)

            // Phone body — inset so the stroke sits fully inside the frame. Corner radius 0.16·width
            // (the measured iPhone 17 corner extent, continuous), not a pill.
            let body = CGRect(x: line, y: line, width: size.width - line * 2, height: size.height - line * 2)
            let bodyPath = Path(roundedRect: body, cornerRadius: size.width * 0.16, style: .continuous)
            context.stroke(bodyPath, with: .color(color), lineWidth: line)

            // The Dynamic Island floats inside the screen near the top (a display cutout, not part of
            // the frame): center ≈ 0.05·height down, a ~3.4:1 pill — the measured iPhone 17 geometry.
            let islandW = body.width * 0.32
            let islandH = body.height * 0.045
            let island = CGRect(
                x: body.midX - islandW / 2,
                y: body.minY + body.height * 0.052 - islandH / 2,
                width: islandW, height: islandH,
            )
            context.fill(Path(roundedRect: island, cornerRadius: islandH / 2), with: .color(color))

            // Content sits below the island with even side margins and a matching bottom inset, so it
            // never touches the frame — every sketch shares the same top edge.
            let sideInset = body.width * 0.13
            let contentTop = island.maxY + body.height * 0.04
            let content = CGRect(
                x: body.minX + sideInset,
                y: contentTop,
                width: body.width - sideInset * 2,
                height: body.maxY - body.height * 0.06 - contentTop,
            )
            sketch(context, content, color.opacity(Theme.Opacity.dimmed))
        }
    }
}
