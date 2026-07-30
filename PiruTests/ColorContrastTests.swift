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
    static let roaFillAlpha = 0.10

    // MARK: - Route tints (light) — FIXED, gated

    /// Both appearances now — the dark-mode gap this used to pin is closed.
    ///
    /// It was never fixable by retuning hue: at the 0.16 fill alpha the pill
    /// used, a colour on a tint of itself asymptotes around 4.5:1 whatever its
    /// lightness, so all 11 routes failed in dark. The fill is now 0.10, and the
    /// label takes a gated `text` variant separate from the `accent` fill.
    @Test
    func `Every route pill is legible as ~11pt text on its own fill`() {
        for route in RouteOfAdministration.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let surface = style == .light ? Self.cardLight : Self.cardDark
                let text = RGB(route.tintTextColor, style: style)
                let accent = RGB(route.tintColor, style: style)
                let fill = accent.composited(alpha: Self.roaFillAlpha, over: surface)
                #expect(
                    text.contrastRatio(against: fill) >= Self.textGate,
                    """
                    Route \(route.rawValue) \(style == .light ? "light" : "dark") label \(text.hex) is \
                    \(text.contrastRatio(against: fill).to2dp):1 on its own \
                    \(Int(Self.roaFillAlpha * 100))% fill — below \(Self.textGate). Regenerate the \
                    `route` scale with design-system/color/build_l2_scales.py rather than hand-tuning.
                    """,
                )
                #expect(
                    accent.contrastRatio(against: surface) >= 3.0,
                    "Route \(route.rawValue) \(style == .light ? "light" : "dark") mark \(accent.hex) is below the 3:1 non-text floor",
                )
            }
        }
    }

    // MARK: - Semantic label colours — FIXED, gated

    @Test
    func `The caution tiers that carry a darkened text variant are legible`() {
        // `InteractionSeverity.labelColor` and `DoseLevel.labelColor` swap in a
        // darkened amber for `.caution` / `.common`. Raw `.color` / `.swiftUIColor`
        // are *fill* values and measure 1.39:1 as text — reaching for those at a
        // text call site is the exact bug this catches.
        // `.caution` and `.dangerous` now resolve to the design system's
        // semantic tokens; both are gated in both appearances.
        for severity in [InteractionSeverity.caution, .dangerous] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let surface = style == .light ? Self.cardLight : Self.cardDark
                let resolved = RGB(severity.labelColor, style: style)
                #expect(
                    resolved.contrastRatio(against: surface) >= Self.textGate,
                    "InteractionSeverity.\(severity) labelColor \(resolved.hex) regressed to a fill value",
                )
            }
        }

        let level = RGB(DoseLevel.common.labelColor, style: .light)
        #expect(
            level.contrastRatio(against: Self.cardLight) >= Self.textGate,
            "DoseLevel.common labelColor \(level.hex) regressed to a fill value",
        )
    }

    // MARK: - Generated P3 catalog tokens

    /// The `semantic/*` colorsets resolve **and** clear their gates at the
    /// precision they actually ship at.
    ///
    /// Resolution is the load-bearing half: `Color("some/missing/name")` does
    /// not throw — it silently yields a fallback — so a typo in a namespace
    /// path or a missing `provides-namespace` marker would go unnoticed until
    /// someone saw the wrong colour on screen. Asserting a real, non-fallback
    /// value catches that at build time.
    ///
    /// Values are Display-P3 and mostly outside the sRGB gamut, which is why
    /// `RGB.linear` is sign-preserving — see its note.
    @Test
    func `Generated semantic tokens resolve from the catalog and clear their gates`() {
        // Xcode's own asset-symbol extensions, not a hand-written accessor file:
        // these are compile-time checked, so a renamed or missing colorset is a
        // build error rather than a silent runtime fallback.
        let tokens: [(String, Color, Color)] = [
            ("danger", .Semantic.Danger.text, .Semantic.Danger.accent),
            ("caution", .Semantic.Caution.text, .Semantic.Caution.accent),
            ("success", .Semantic.Success.text, .Semantic.Success.accent),
            ("info", .Semantic.Info.text, .Semantic.Info.accent),
        ]
        for (name, textColor, accentColor) in tokens {
            // Proof the *appearance-aware* lookup works: a failed lookup yields
            // one flat fallback for every appearance, so light and dark would be
            // identical. Every token's text value genuinely differs across modes.
            //
            // Deliberately not comparing text against accent — in dark mode
            // `caution` and `success` legitimately resolve to the *same* value,
            // because against near-black the max-chroma colour clearing the 3:1
            // accent gate also clears the 4.5:1 text gate, so both converge.
            #expect(
                RGB(textColor, style: .light).oklabDistance(to: RGB(textColor, style: .dark)) > 0.01,
                "semantic/\(name)/text resolved identically in light and dark — the catalog lookup probably failed",
            )

            for style in [UIUserInterfaceStyle.light, .dark] {
                let surface = style == .light ? Self.cardLight : Self.cardDark
                let text = RGB(textColor, style: style)
                let accent = RGB(accentColor, style: style)
                let fill = accent.composited(alpha: 0.10, over: surface)
                #expect(
                    text.contrastRatio(against: fill) >= Self.textGate,
                    "semantic/\(name)/text \(text.hex) is \(text.contrastRatio(against: fill).to2dp):1 on its own fill (\(style == .light ? "light" : "dark"))",
                )
                #expect(
                    text.contrastRatio(against: surface) >= Self.textGate,
                    "semantic/\(name)/text \(text.hex) is \(text.contrastRatio(against: surface).to2dp):1 on the card",
                )
                #expect(
                    accent.contrastRatio(against: surface) >= 3.0,
                    "semantic/\(name)/accent \(accent.hex) is \(accent.contrastRatio(against: surface).to2dp):1 on the card",
                )
            }
        }
    }

    // MARK: - L2 encoding scales

    /// The experience-phase scale, gated like the semantic tokens.
    ///
    /// It renders its colour as `.caption` text on a capsule filled with that
    /// same colour at 18% (`DosePhaseProgressBar`), which is the self-tint
    /// pattern — the old hex ramp measured 1.73–2.71:1 in light mode.
    ///
    /// This scale also used to exist **twice** with unrelated values, so editing
    /// a dose and then reading it flipped "peak" from orange to green. One ramp
    /// now, hues preserved from the surviving one.
    @Test
    func `Experience-phase scale is legible as text and visible as a mark`() {
        let phases: [(String, Color, Color)] = [
            ("onset", .Phase.Onset.text, .Phase.Onset.accent),
            ("comeup", .Phase.Comeup.text, .Phase.Comeup.accent),
            ("peak", .Phase.Peak.text, .Phase.Peak.accent),
            ("offset", .Phase.Offset.text, .Phase.Offset.accent),
            ("afterglow", .Phase.Afterglow.text, .Phase.Afterglow.accent),
        ]
        for (name, textColor, accentColor) in phases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let surface = style == .light ? Self.cardLight : Self.cardDark
                let text = RGB(textColor, style: style)
                let accent = RGB(accentColor, style: style)
                let fill = accent.composited(alpha: 0.10, over: surface)
                #expect(
                    text.contrastRatio(against: fill) >= Self.textGate,
                    "phase/\(name)/text \(text.hex) is \(text.contrastRatio(against: fill).to2dp):1 on its own fill",
                )
                #expect(
                    text.contrastRatio(against: surface) >= Self.textGate,
                    "phase/\(name)/text \(text.hex) is \(text.contrastRatio(against: surface).to2dp):1 on the card",
                )
                #expect(
                    accent.contrastRatio(against: surface) >= 3.0,
                    "phase/\(name)/accent \(accent.hex) is \(accent.contrastRatio(against: surface).to2dp):1 on the card",
                )
            }
        }
    }

    // MARK: - Known gaps, pinned so they can only improve

    /// Severity and dose tiers *other* than caution/common still render raw
    /// system orange and red as text, which fail on the light card (2.04–3.27).
    ///
    /// Unlike caution, these have no darkened variant yet — that arrives with
    /// the `semantic/*` tokens in migration Phase 3.
    @Test
    func `Non-caution status tiers are a known gap that must not worsen`() {
        // `.dangerous` graduated out of this list in migration phase 3 — it now
        // resolves to `semantic/danger/text` and is gated above. `.unsafe` sits
        // between caution and danger, and the four-level ladder has no middle
        // tier, so it waits for the severity *scale* to be designed as an
        // ordered L2 encoding rather than being flattened into danger.
        let subjects: [(String, Color)] = [
            ("InteractionSeverity.unsafe", InteractionSeverity.unsafe.labelColor),
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

    /// `Theme.secondaryLabel` — graduated from known gap to real gate in
    /// migration phase 3.
    ///
    /// It measured **3.89:1** on the real card in light mode, a WCAG AA failure
    /// across ~566 call sites. The original audit reported 4.25 and thought it
    /// passed, because it computed against pure white — the exact mistake this
    /// suite's surface constants exist to prevent.
    ///
    /// Now `#6E6E73` light (4.65:1) and the system's `#BCBCC4` dark (9.97:1),
    /// resolved from `text/secondary` in the catalog.
    @Test
    func `Theme.secondaryLabel is legible in both appearances`() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let surface = style == .light ? Self.cardLight : Self.cardDark
            let resolved = RGB(Theme.secondaryLabel, style: style)
            let ratio = resolved.contrastRatio(against: surface)
            #expect(
                ratio >= Self.textGate,
                "Theme.secondaryLabel \(resolved.hex) is \(ratio.to2dp):1 on the \(style == .light ? "light" : "dark") card",
            )
        }
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

    /// Encoded -> linear light, **sign-preserving**.
    ///
    /// `UIColor.getRed` reports *extended* sRGB for a Display-P3 asset: same
    /// primaries, but components outside `[0, 1]` to reach the wider gamut. A
    /// naive `pow` on a negative component returns NaN and silently poisons
    /// every ratio downstream. Mirroring the magnitude and restoring the sign
    /// keeps luminance correct for both plain and wide-gamut colours, because
    /// extended sRGB shares sRGB's primaries — the luminance coefficients still
    /// apply.
    private static func linear(_ channel: Double) -> Double {
        let sign: Double = channel < 0 ? -1 : 1
        let magnitude = abs(channel)
        return sign * (magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4))
    }

    private static func encode(_ channel: Double) -> Double {
        let sign: Double = channel < 0 ? -1 : 1
        let magnitude = abs(channel)
        return sign * (magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055)
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
