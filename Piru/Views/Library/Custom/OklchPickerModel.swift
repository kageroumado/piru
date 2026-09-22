import CoreGraphics
import Foundation
import Observation

/// The color being edited in ``SubstanceColorPickerView``, in the space it is
/// edited in. Lightness and chroma move on the plane, hue on the rail; chroma
/// is held under the Display P3 ceiling so the thumb never leaves what the
/// panel can show.
@Observable
@MainActor
final class OklchPickerModel {
    /// The plane's extent. Lightness stops short of both ends: a substance
    /// color has to read as a dot or a curve on the light card and the dark.
    nonisolated enum Plane {
        static let lightness = 0.45 ... 0.92
        static let chroma = 0.0 ... 0.34
    }

    private(set) var color: Oklch
    /// Whether the color is still the substance's class color. Cleared by any
    /// edit, set again by ``restoreDefault()``.
    private(set) var usesDefault: Bool
    let defaultColor: Oklch

    init(current: P3Color, usesDefault: Bool, defaultTint: P3Color) {
        defaultColor = Oklch(displayP3: defaultTint)
        color = usesDefault ? defaultColor : Oklch(displayP3: current)
        self.usesDefault = usesDefault
    }

    var tint: P3Color {
        color.displayP3
    }

    var choice: SubstanceColorChoice {
        usesDefault ? .default : .custom(tint)
    }

    /// The chroma ceiling at the current lightness and hue.
    var chromaCeiling: Double {
        Oklch.displayP3ChromaCeiling(l: color.l, h: color.h)
    }

    func setPlane(lightness: Double, chroma: Double) {
        let l = min(max(lightness, Plane.lightness.lowerBound), Plane.lightness.upperBound)
        let ceiling = Oklch.displayP3ChromaCeiling(l: l, h: color.h)
        color = Oklch(l: l, c: min(max(chroma, 0), ceiling), h: color.h)
        usesDefault = false
    }

    func setHue(_ hue: Double) {
        let ceiling = Oklch.displayP3ChromaCeiling(l: color.l, h: hue)
        color = Oklch(l: color.l, c: min(color.c, ceiling), h: hue)
        usesDefault = false
    }

    func restoreDefault() {
        color = defaultColor
        usesDefault = true
    }
}

/// Bitmaps for the picker's two surfaces, drawn in Display P3 so a color past
/// sRGB shows as itself.
nonisolated enum OklchPickerRenderer {
    private static let planeSize = (width: 160, height: 120)
    private static let railWidth = 360

    /// Lightness (x) × chroma (y, up) at `hue`. Chroma above a column's
    /// Display P3 ceiling paints as the ceiling color, so the bitmap has no
    /// edge of its own: the view clips it with ``gamutCeilings(hue:)``, and
    /// the gamut's outline stays crisp at any size.
    static func plane(hue: Double) -> CGImage? {
        let (width, height) = planeSize
        let chroma = OklchPickerModel.Plane.chroma
        let ceilings = gamutCeilings(hue: hue, columns: width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for x in 0 ..< width {
            let l = lightness(atColumn: x, of: width)
            for y in 0 ..< height {
                let c = min(chroma.upperBound * (1 - (Double(y) + 0.5) / Double(height)), ceilings[x])
                write(Oklch(l: l, c: c, h: hue).displayP3, to: &pixels, at: (y * width + x) * 4)
            }
        }
        return image(pixels, width: width, height: height)
    }

    /// The Display P3 chroma ceiling at each of `columns` evenly spaced
    /// lightness steps across the plane.
    static func gamutCeilings(hue: Double, columns: Int) -> [Double] {
        (0 ..< columns).map { Oklch.displayP3ChromaCeiling(l: lightness(atColumn: $0, of: columns), h: hue) }
    }

    private static func lightness(atColumn x: Int, of columns: Int) -> Double {
        let range = OklchPickerModel.Plane.lightness
        return range.lowerBound + (range.upperBound - range.lowerBound) * (Double(x) + 0.5) / Double(columns)
    }

    /// Every hue at `lightness`, each at `chroma` or its own ceiling when that
    /// is lower, so the rail shows the colors the thumb would actually land on.
    static func hueRail(lightness: Double, chroma: Double) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: railWidth * 4)
        for x in 0 ..< railWidth {
            let hue = 360 * (Double(x) + 0.5) / Double(railWidth)
            write(Oklch(l: lightness, c: chroma, h: hue).displayP3, to: &pixels, at: x * 4)
        }
        return image(pixels, width: railWidth, height: 1)
    }

    private static func write(_ p3: P3Color, to pixels: inout [UInt8], at offset: Int) {
        pixels[offset] = UInt8((p3.red * 255).rounded())
        pixels[offset + 1] = UInt8((p3.green * 255).rounded())
        pixels[offset + 2] = UInt8((p3.blue * 255).rounded())
        pixels[offset + 3] = 255
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let provider = CGDataProvider(data: Data(pixels) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent,
        )
    }
}
