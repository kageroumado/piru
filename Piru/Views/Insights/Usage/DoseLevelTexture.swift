import SwiftUI

/// A dose level's fill texture under Differentiate Without Color: each band of
/// the stacked dose-level chart, and its legend key, carries a pattern of its
/// own on top of its color, so the bands stay apart in grayscale.
///
/// Common, the band most doses land in, stays a solid fill; the others are
/// told apart by line direction and density.
enum DoseLevelTexture {
    /// Side of one square pattern tile, in points.
    static let tileSize: CGFloat = 6

    /// The fill for dose level `level` (an index into `DoseLevel.allCases`),
    /// resolved for `colorScheme` because a tile is drawn once, outside any
    /// view's environment.
    static func style(level: Int, color: Color, colorScheme: ColorScheme) -> AnyShapeStyle {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let fill = Color(color.resolve(in: environment))
        let ink = Color(Color.platformSystemBackground.resolve(in: environment)).opacity(0.8)
        let image = Image(size: CGSize(width: tileSize, height: tileSize)) { context in
            let tile = CGRect(x: 0, y: 0, width: tileSize, height: tileSize)
            context.fill(Path(tile), with: .color(fill))
            context.stroke(pattern(level: level), with: .color(ink), lineWidth: 1.2)
            if level == 0 {
                context.fill(Path(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 2.4, height: 2.4)), with: .color(ink))
            }
        }
        return AnyShapeStyle(ImagePaint(image: image))
    }

    /// The strokes of one tile. Diagonals run corner to corner and through the
    /// neighboring tiles' corners too, so the tiles join into unbroken lines.
    private static func pattern(level: Int) -> Path {
        let s = tileSize
        var path = Path()
        switch level {
        case 1: // threshold: horizontal rules
            path.move(to: CGPoint(x: 0, y: s / 2))
            path.addLine(to: CGPoint(x: s, y: s / 2))
        case 2: // light: rising diagonals
            addRising(to: &path, size: s)
        case 4: // strong: falling diagonals
            addFalling(to: &path, size: s)
        case 5: // heavy: cross-hatch
            addRising(to: &path, size: s)
            addFalling(to: &path, size: s)
        default: // sub draws a dot, common stays solid
            break
        }
        return path
    }

    private static func addRising(to path: inout Path, size s: CGFloat) {
        for k in -1 ... 1 {
            let dx = CGFloat(k) * s
            path.move(to: CGPoint(x: dx, y: s))
            path.addLine(to: CGPoint(x: dx + s, y: 0))
        }
    }

    private static func addFalling(to path: inout Path, size s: CGFloat) {
        for k in -1 ... 1 {
            let dx = CGFloat(k) * s
            path.move(to: CGPoint(x: dx, y: 0))
            path.addLine(to: CGPoint(x: dx + s, y: s))
        }
    }
}
