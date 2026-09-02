import Foundation

/// A color in Oklch — perceptual lightness `l` (0…1), chroma `c` (0 at gray,
/// ~0.37 at the most saturated displayable colors) and hue `h` in degrees.
/// Equal numeric distance is equal perceived difference, so a shift here
/// reads the same on every substance color, which no RGB arithmetic does.
///
/// Conversions go through Oklab (Björn Ottosson, 2020) from and to
/// linear-light sRGB; encoding to and from a display gamut is the caller's.
nonisolated struct Oklch: Hashable {
    var l: Double
    var c: Double
    /// Degrees, normalized to `0..<360`.
    var h: Double

    init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = Self.normalized(h)
    }

    /// From linear-light sRGB components. Out-of-gamut inputs are accepted;
    /// the math is continuous there.
    init(linearRed r: Double, green g: Double, blue b: Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let labL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let labA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let labB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        self.init(
            l: labL,
            c: sqrt(labA * labA + labB * labB),
            h: atan2(labB, labA) * 180 / .pi,
        )
    }

    /// Linear-light sRGB components, each clamped to `0…1`. A shifted color
    /// can leave the gamut; clamping keeps its hue and drops what does not
    /// fit, which is invisible at the chroma levels UI colors use.
    var linearRGB: (red: Double, green: Double, blue: Double) {
        let radians = h * .pi / 180
        let labA = c * cos(radians)
        let labB = c * sin(radians)
        let long = pow(l + 0.3963377774 * labA + 0.2158037573 * labB, 3)
        let medium = pow(l - 0.1055613458 * labA - 0.0638541728 * labB, 3)
        let short = pow(l - 0.0894841775 * labA - 1.2914855480 * labB, 3)
        func clamp(_ v: Double) -> Double {
            min(max(v, 0), 1)
        }
        return (
            red: clamp(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: clamp(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: clamp(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short),
        )
    }

    /// The same color moved by `lightness`, rotated by `hue` degrees and with
    /// its chroma scaled by `chromaScale`. Lightness clamps to `0…1`; chroma
    /// never goes negative.
    func shifted(lightness: Double = 0, hue: Double = 0, chromaScale: Double = 1) -> Oklch {
        Oklch(
            l: min(max(l + lightness, 0), 1),
            c: max(c * chromaScale, 0),
            h: h + hue,
        )
    }

    private static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
