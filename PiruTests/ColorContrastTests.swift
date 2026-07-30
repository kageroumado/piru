import SwiftUI
import Testing
import UIKit
@testable import Piru

/// Build-enforced contrast floors for the app's semantic and encoding colors.
///
/// Safety net for the colour-system migration
/// (`Specs/design-system/color-audit/`). Deliberately **pure computation** — it
/// resolves colours against a trait collection and does arithmetic, never
/// renders a view — so it is fast and cannot flake.
///
/// ## What this suite is and is not
///
/// It gates what is **already fixed** and pins what is **known broken** at its
/// measured value, so outstanding work can only improve. It does *not* assert
/// the migration's end state — a safety net that fails on scheduled future work
/// is noise, and noise gets disabled.
///
/// Every known-gap expectation is two-sided: it fails if the value regresses,
/// **and** it fails once the value clears its gate, prompting whoever fixed it
/// to promote the check. Gaps cannot rot silently in either direction.
///
/// ## Why these surface constants
///
/// The light card is **`#f5f5f5`**, not white: the card fill is
/// `.ultraThinMaterial` (`Theme.ThemedBackground`), and material blends what is
/// behind it, so its rendered colour cannot be derived from source. `#f5f5f5` is
/// **measured from 43 screenshots** across every screen (`sampled.json`).
/// Testing against `#FFFFFF` is optimistic and lets real failures through —
/// that mistake put a wrong number in the audit's own findings once already.
@MainActor
@Suite("Color contrast")
struct ColorContrastTests {
    /// Measured `.ultraThinMaterial` card fill, light mode.
    static let cardLight = RGB(hex: "F5F5F5")
    /// `Theme.cardBackground` dark mode (its hardcoded `0.067`).
    static let cardDark = RGB(hex: "111111")

    /// WCAG AA, normal-size text.
    static let textGate = 4.5
    /// The alpha `ROAPill` uses for its capsule fill behind the route label.
    static let roaFillAlpha = 0.16

    // MARK: - Route tints (light) — FIXED, gated

    @Test
    func `Every route tint is legible as ~11pt text on its own 16% fill`() {
        for route in RouteOfAdministration.allCases {
            let tint = RGB(route.tintColor, style: .light)
            let ratio = tint.contrastRatio(against: tint.composited(alpha: Self.roaFillAlpha, over: Self.cardLight))
            #expect(
                ratio >= Self.textGate,
                """
                Route \(route.rawValue) light tint \(tint.hex) is \(ratio.to2dp):1 on its own \
                \(Int(Self.roaFillAlpha * 100))% fill — below \(Self.textGate). Lower its Oklab \
                lightness in `RouteOfAdministration.tintHexPair`, holding hue constant, and leave \
                headroom above 4.5 so 8-bit quantisation cannot drop it back under. \
                See Specs/design-system/color-audit/colorimetry.py.
                """,
            )
        }
    }

    // MARK: - Semantic label colours — FIXED, gated

    @Test
    func `The caution tiers that carry a darkened text variant are legible`() {
        // `InteractionSeverity.labelColor` and `DoseLevel.labelColor` swap in a
        // darkened amber for `.caution` / `.common`. Raw `.color` / `.swiftUIColor`
        // are *fill* values and measure 1.39:1 as text — reaching for those at a
        // text call site is the exact bug this catches.
        let severity = RGB(InteractionSeverity.caution.labelColor, style: .light)
        #expect(
            severity.contrastRatio(against: Self.cardLight) >= Self.textGate,
            "InteractionSeverity.caution labelColor \(severity.hex) regressed to a fill value",
        )

        let level = RGB(DoseLevel.common.labelColor, style: .light)
        #expect(
            level.contrastRatio(against: Self.cardLight) >= Self.textGate,
            "DoseLevel.common labelColor \(level.hex) regressed to a fill value",
        )
    }

    // MARK: - Known gaps, pinned so they can only improve

    /// Route pills fail in **dark** mode, and no hue retune fixes it.
    ///
    /// At 0.16 alpha over near-black, a colour on a tint of *itself* asymptotes
    /// around 4.5:1 no matter its lightness — raising the text lightness raises
    /// the fill proportionally. Every one of the 11 routes lands 2.60–3.93.
    /// The fix is lowering the fill alpha (migration Phase 5), not retuning
    /// hues, so this pins the floor rather than demanding a fix here.
    @Test
    func `Dark-mode route pills are a known self-tint gap that must not worsen`() {
        for route in RouteOfAdministration.allCases {
            let tint = RGB(route.tintColor, style: .dark)
            let ratio = tint.contrastRatio(against: tint.composited(alpha: Self.roaFillAlpha, over: Self.cardDark))
            #expect(ratio >= 2.55, "Route \(route.rawValue) dark pill regressed below its known floor")
        }
        // When Phase 5 lowers the fill alpha, this flips and the suite says so.
        let worst = RouteOfAdministration.allCases
            .map { route -> Double in
                let tint = RGB(route.tintColor, style: .dark)
                return tint.contrastRatio(against: tint.composited(alpha: Self.roaFillAlpha, over: Self.cardDark))
            }
            .min() ?? 0
        #expect(
            worst < Self.textGate,
            "Dark route pills now all clear \(Self.textGate) — promote this to a real gate and delete the known-gap note",
        )
    }

    /// Severity and dose tiers *other* than caution/common still render raw
    /// system orange and red as text, which fail on the light card (2.04–3.27).
    ///
    /// Unlike caution, these have no darkened variant yet — that arrives with
    /// the `semantic/*` tokens in migration Phase 3.
    @Test
    func `Non-caution status tiers are a known gap that must not worsen`() {
        let subjects: [(String, Color)] = [
            ("InteractionSeverity.unsafe", InteractionSeverity.unsafe.labelColor),
            ("InteractionSeverity.dangerous", InteractionSeverity.dangerous.labelColor),
            ("DoseLevel.strong", DoseLevel.strong.labelColor),
            ("DoseLevel.heavy", DoseLevel.heavy.labelColor),
        ]
        for (name, color) in subjects {
            let ratio = RGB(color, style: .light).contrastRatio(against: Self.cardLight)
            #expect(ratio >= 2.00, "\(name) regressed below its known floor")
            #expect(
                ratio < Self.textGate,
                "\(name) now clears \(Self.textGate) — promote it into the darkened-text-variant test",
            )
        }
    }

    /// `Theme.secondaryLabel` measures **3.89:1** on the real card in light mode.
    ///
    /// The original audit reported 4.25 because it computed against pure white —
    /// the exact mistake this suite's surface constants exist to prevent. It is
    /// still better than the system colour (2.17), so it is not a blind fix; it
    /// is last in the migration burndown because it has 566 call sites.
    @Test
    func `Theme.secondaryLabel light is a known gap that must not worsen`() {
        let ratio = RGB(Theme.secondaryLabel, style: .light).contrastRatio(against: Self.cardLight)
        #expect(ratio >= 3.85, "Theme.secondaryLabel light regressed below its known 3.89:1")
        #expect(
            ratio < Self.textGate,
            "Theme.secondaryLabel light now clears \(Self.textGate) — tighten this to the gate and delete the note",
        )
    }

    /// Route tints must stay as mutually distinct as they are today.
    ///
    /// The floor is the **observed** minimum, not an aspiration: 11 nominal
    /// categories share one hue wheel at a fixed lightness, so some crowding is
    /// unavoidable, and the two closest pairs are deliberate siblings —
    /// intravenous/intramuscular (0.041) and sublingual/buccal (0.048), the
    /// latter documented as siblings in `RouteOfAdministration` itself.
    /// 8 of 55 pairs sit below 0.10; median separation is 0.190.
    @Test
    func `Route tints stay at least as distinguishable as they are today`() {
        let all = RouteOfAdministration.allCases
        for outer in all.indices {
            for inner in all.indices where inner > outer {
                let a = RGB(all[outer].tintColor, style: .light)
                let b = RGB(all[inner].tintColor, style: .light)
                #expect(
                    a.oklabDistance(to: b) >= 0.040,
                    "Routes \(all[outer].rawValue) and \(all[inner].rawValue) became less distinguishable",
                )
            }
        }
    }
}

private extension Double {
    var to2dp: String {
        String(format: "%.2f", self)
    }
}

// MARK: - Minimal colour maths

/// A resolved sRGB colour plus the operations the contrast gates need.
///
/// Mirrors `Specs/design-system/color-audit/colorimetry.py`, the reference
/// implementation, which carries the self-tests against published WCAG and
/// Oklab values.
struct RGB {
    let r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    /// Resolves a (possibly dynamic) SwiftUI colour for one interface style.
    init(_ color: Color, style: UIUserInterfaceStyle) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        r = Double(red); g = Double(green); b = Double(blue)
    }

    var hex: String {
        let clamp = { (value: Double) in Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }

    var relativeLuminance: Double {
        0.2126 * Self.linear(r) + 0.7152 * Self.linear(g) + 0.0722 * Self.linear(b)
    }

    func contrastRatio(against other: RGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `self.opacity(alpha)` over `background`. Blends in **linear** light,
    /// which is what the GPU does — blending encoded values instead skews
    /// midtones and would make every ratio here slightly wrong.
    func composited(alpha: Double, over background: RGB) -> RGB {
        func blend(_ top: Double, _ bottom: Double) -> Double {
            Self.encode(Self.linear(top) * alpha + Self.linear(bottom) * (1 - alpha))
        }
        return RGB(r: blend(r, background.r), g: blend(g, background.g), b: blend(b, background.b))
    }

    /// Perceptual distance in Oklab — the right space for "do these read as
    /// different colours", which sRGB euclidean distance answers badly.
    func oklabDistance(to other: RGB) -> Double {
        let a = oklab, b = other.oklab
        return sqrt(pow(a.0 - b.0, 2) + pow(a.1 - b.1, 2) + pow(a.2 - b.2, 2))
    }

    private var oklab: (Double, Double, Double) {
        let lr = Self.linear(r), lg = Self.linear(g), lb = Self.linear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        )
    }
}
