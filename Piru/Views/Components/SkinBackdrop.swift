import SwiftUI

extension View {
    /// The skin's ground behind a screen: the background colour, and — for a
    /// decorated skin with decorations on — the chaos layer over it. Replaces
    /// `.background(Theme.background)` at every screen root; graph code that
    /// *fills* with `Theme.background` (dot rings, fades) keeps the plain colour.
    func skinBackdrop() -> some View {
        background { SkinBackdrop().ignoresSafeArea() }
    }
}

/// Starfield, a warm glow at the top, drifting glyph stickers, and a few of the
/// site's blinkies — all at low opacity, all behind the content, all seeded so
/// a screen looks the same every time it appears. Motion stops under Reduce
/// Motion, and the whole layer is a plain colour when the toggle is off.
struct SkinBackdrop: View {
    @State private var skins = SkinStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background
            if let decor = skins.current.decorations, skins.decorationsEnabled {
                glow
                Starfield()
                GeometryReader { geo in
                    let places = placements(in: geo.size, decor: decor)
                    // One clock drives every glyph's drift — nineteen
                    // `repeatForever` animations per screen was enough to
                    // stall the main thread on a device.
                    TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 1 / 12)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                            sticker(place, decor: decor)
                                .position(x: place.x, y: place.y + drift(place, at: t, animate: !reduceMotion))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    /// The site's `radial-gradient(115% 70% at 50% -6%, pink 0.12)`.
    private var glow: some View {
        RadialGradient(
            colors: [skins.current.accentMark.opacity(0.14), .clear],
            center: UnitPoint(x: 0.5, y: -0.06),
            startRadius: 0,
            endRadius: 520,
        )
    }

    /// The site's `drift`: a slow ±5pt bob on each sticker's own phase.
    private func drift(_ place: Placement, at t: TimeInterval, animate: Bool) -> CGFloat {
        guard animate, case .glyph = place.kind else { return 0 }
        let period = 5 + place.phase * 4
        return 5 * sin((t / period + place.phase) * 2 * .pi)
    }

    @ViewBuilder
    private func sticker(_ place: Placement, decor: SkinDecorations) -> some View {
        switch place.kind {
        case let .glyph(index):
            let glyph = decor.glyphs[index % decor.glyphs.count]
            Text(verbatim: glyph.symbol)
                .font(.system(size: place.size))
                .foregroundStyle(glyph.color)
                .shadow(color: glyph.color.opacity(0.7), radius: 6)
                .opacity(place.opacity)
        case let .slogan(index):
            // Blinky colours cycle the token colours only (gold, accent, wine);
            // white is a sparkle colour, not a text colour on the pink ground.
            let tinted = decor.glyphs.filter { $0.color != .white }
            Blinky(text: decor.slogans[index % decor.slogans.count], color: tinted[(index * 3) % max(tinted.count, 1)].color)
                .opacity(place.opacity)
        }
    }

    // MARK: - Layout

    struct Placement {
        enum Kind { case glyph(Int), slogan(Int) }
        let kind: Kind
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let phase: Double
    }

    /// Sixteen glyphs and three blinkies, seeded by the screen's size so the
    /// same screen is stable across appearances but two screens differ. Kept
    /// toward the edges: the middle is where cards and rows live, and a glyph
    /// under text is chaos, not charm.
    private func placements(in size: CGSize, decor: SkinDecorations) -> [Placement] {
        guard size.width > 0, size.height > 0 else { return [] }
        var rng = SeededRNG(seed: UInt64(size.width) &* 7919 &+ UInt64(size.height) &* 104_729)
        var out: [Placement] = []
        for i in 0 ..< 16 {
            // Edge bias: pull x toward the margins, y anywhere below the title.
            // Left cluster starts past the timeline's 58pt hour rail; right
            // cluster hugs the trailing margin.
            let raw = rng.unit()
            let x = raw < 0.5 ? 90 + raw * 2 * size.width * 0.18 : size.width - 8 - (1 - raw) * 2 * size.width * 0.20
            let y = 90 + rng.unit() * (size.height - 220)
            out.append(Placement(
                kind: .glyph(i),
                x: x, y: y,
                size: 13 + rng.unit() * 16,
                opacity: 0.28 + rng.unit() * 0.32,
                phase: rng.unit(),
            ))
        }
        // Blinkies keep to the trailing margin, clear of the hour rail and the
        // leading edge where rows start their text.
        for i in 0 ..< min(3, decor.slogans.count) {
            let x = size.width - 84 - rng.unit() * 30
            let y = size.height * (0.28 + Double(i) * 0.24) + rng.unit() * 30
            out.append(Placement(kind: .slogan(i), x: x, y: y, size: 0, opacity: 0.45, phase: rng.unit()))
        }
        return out
    }
}

// MARK: - Pieces

/// One of the site's blinkies: a bordered pixel-face slogan with a soft glow.
private struct Blinky: View {
    let text: LocalizedStringResource
    let color: Color

    var body: some View {
        Text(text)
            .font(.piruLabel(.caption2))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Theme.inputBackground)
            .overlay(Rectangle().strokeBorder(color, lineWidth: 2))
            .shadow(color: color.opacity(0.5), radius: 6)
            .fixedSize()
    }
}

/// Faint dots, like the site's starfield ground. Drawn once per size.
private struct Starfield: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: 0xE1A5)
            for _ in 0 ..< 90 {
                let x = rng.unit() * size.width
                let y = rng.unit() * size.height
                let r = 0.6 + rng.unit() * 1.1
                let alpha = 0.05 + rng.unit() * 0.08
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// SplitMix64 — deterministic, so a screen's decoration is the same every time.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
