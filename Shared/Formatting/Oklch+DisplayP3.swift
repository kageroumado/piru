import Foundation

/// Display P3 is the gamut every substance color lives in: Oklch is where a
/// color is chosen and adjusted, P3 is where it is stored and shown.
nonisolated extension Oklch {
    private enum Gamut {
        /// Slack on the `0…1` test, so a color sitting exactly on the gamut
        /// surface passes despite rounding in the matrix chain.
        static let tolerance = 1e-4
        /// Bisection steps for the chroma ceiling; 24 halvings of a 0.4 span
        /// resolve chroma to ~2e-8, far below one 8-bit code value.
        static let ceilingIterations = 24
        /// Above every displayable chroma, so the search always brackets.
        static let chromaSearchLimit = 0.4
    }

    /// From encoded Display P3 components.
    init(displayP3 p3: P3Color) {
        let r = Self.decoded(p3.red)
        let g = Self.decoded(p3.green)
        let b = Self.decoded(p3.blue)
        // Linear Display P3 → linear sRGB (extended range).
        self.init(
            linearRed: 1.2249401763 * r - 0.2249401763 * g,
            green: -0.0420569547 * r + 1.0420569547 * g,
            blue: -0.0196375546 * r - 0.0786360456 * g + 1.0982736002 * b,
        )
    }

    /// Linear-light Display P3 components in extended range.
    private var extendedLinearP3: (red: Double, green: Double, blue: Double) {
        let rgb = extendedLinearRGB
        return (
            red: 0.8224621209 * rgb.red + 0.1775378791 * rgb.green,
            green: 0.0331941989 * rgb.red + 0.9668058011 * rgb.green,
            blue: 0.0170826307 * rgb.red + 0.0723974407 * rgb.green + 0.9105199286 * rgb.blue,
        )
    }

    /// Whether the color is displayable in Display P3.
    var isInDisplayP3: Bool {
        let p3 = extendedLinearP3
        let range = -Gamut.tolerance ... 1 + Gamut.tolerance
        return range.contains(p3.red) && range.contains(p3.green) && range.contains(p3.blue)
    }

    /// The largest chroma Display P3 can show at this lightness and hue.
    static func displayP3ChromaCeiling(l: Double, h: Double) -> Double {
        var low = 0.0
        var high = Gamut.chromaSearchLimit
        for _ in 0 ..< Gamut.ceilingIterations {
            let mid = (low + high) / 2
            if Oklch(l: l, c: mid, h: h).isInDisplayP3 {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    /// The same lightness and hue with chroma reduced to fit Display P3 —
    /// the CSS Color 4 gamut map, which holds hue where clipping RGB
    /// components would rotate it.
    var fittedToDisplayP3: Oklch {
        guard !isInDisplayP3 else { return self }
        return Oklch(l: l, c: min(c, Self.displayP3ChromaCeiling(l: l, h: h)), h: h)
    }

    /// Encoded Display P3 components of the gamut-fitted color.
    var displayP3: P3Color {
        let p3 = fittedToDisplayP3.extendedLinearP3
        return P3Color(
            red: Self.encoded(p3.red),
            green: Self.encoded(p3.green),
            blue: Self.encoded(p3.blue),
        )
    }

    /// The sRGB transfer function, which Display P3 shares.
    private static func encoded(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static func decoded(_ encoded: Double) -> Double {
        let v = min(max(encoded, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
