import SwiftUI

/// Paper grain and CRT scanlines as small tiles, rendered once per
/// appearance and painted by tiling — one fill per frame instead of tens of
/// thousands of dots. `ImagePaint` for SwiftUI shapes (cards), `Image` for
/// the canvas (`GraphicsContext.Shading.tiledImage`).
@MainActor
enum SkinTextures {
    struct Tiles: Sendable {
        var grain: Image?
        var scanlines: Image?
    }

    private static var cache: [String: Image] = [:]

    /// The tiles a scene needs; empty for scenes without textures.
    static func tiles(for scene: SkinScene, dark: Bool, scale: CGFloat) -> Tiles {
        switch scene {
        case .paper: Tiles(grain: grainTile(dark: dark, scale: scale), scanlines: nil)
        case .arcade: Tiles(grain: nil, scanlines: dark ? scanlineTile(scale: scale) : nil)
        default: Tiles()
        }
    }

    /// Origami's `WashiBackground` grain — 1.5pt dots on a 3pt stride at
    /// 1–4% — as a shape style for the paper surface.
    static func grain(_ color: Color, dark: Bool) -> ImagePaint {
        ImagePaint(image: grainTile(dark: dark, scale: 3) ?? Image(systemName: "circle"), scale: 1 / 3)
    }

    static func grainTile(dark: Bool, scale: CGFloat) -> Image? {
        let key = "grain|\(dark)|\(scale)"
        if let cached = cache[key] { return cached }
        let side: CGFloat = 96
        let renderer = ImageRenderer(content: Canvas { context, _ in
            var rng = SeededRNG(seed: 0x6A1)
            for y in stride(from: 0, to: side, by: 3) {
                for x in stride(from: 0, to: side, by: 3) {
                    let alpha = 0.01 + rng.unit() * (dark ? 0.05 : 0.03)
                    let jitter = rng.unit() * 1.2
                    context.fill(
                        Path(ellipseIn: CGRect(x: x + jitter, y: y + jitter, width: 1.5, height: 1.5)),
                        with: .color((dark ? Color.white : Color.brown).opacity(alpha)),
                    )
                }
            }
        }.frame(width: side, height: side))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return nil }
        let image = Image(decorative: cg, scale: scale)
        cache[key] = image
        return image
    }

    /// One dark line every third row.
    static func scanlineTile(scale: CGFloat) -> Image? {
        let key = "scan|\(scale)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 2, width: 12, height: 1)), with: .color(.black.opacity(0.35)))
        }.frame(width: 12, height: 3))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return nil }
        let image = Image(decorative: cg, scale: scale)
        cache[key] = image
        return image
    }
}
