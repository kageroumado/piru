import SwiftUI

extension View {
    /// The skin's ground behind a screen: the background colour, and — for a
    /// decorated skin with decorations on — the chaos layer over it. Replaces
    /// `.background(Theme.background)` at every screen root; graph code that
    /// *fills* with `Theme.background` (dot rings, fades) keeps the plain colour.
    /// Screen roots only: a component that paints this multiplies the layer.
    func skinBackdrop() -> some View {
        background { SkinBackdrop().ignoresSafeArea() }
    }
}

/// Starfield, a warm glow at the top, and a field of glyph stickers that bob,
/// sway, twinkle and turn — all at low opacity, all behind the content, all
/// seeded so a screen looks the same every time it appears. One clock drives
/// every sticker. Motion stops under Reduce Motion, and the whole layer is a
/// plain colour when the toggle is off.
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
                    TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 1 / 15)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                            let motion = place.motion(at: t, animate: !reduceMotion)
                            sticker(place, decor: decor)
                                .opacity(place.opacity * motion.brightness)
                                .rotationEffect(motion.spin)
                                .position(x: place.x + motion.dx, y: place.y + motion.dy)
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

    private func sticker(_ place: Placement, decor: SkinDecorations) -> some View {
        let glyph = decor.glyphs[place.glyph % decor.glyphs.count]
        return Text(verbatim: glyph.symbol)
            .font(.system(size: place.size))
            .foregroundStyle(glyph.color)
            .shadow(color: glyph.color.opacity(0.7), radius: 6)
    }

    // MARK: - Layout

    struct Placement {
        let glyph: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let phase: Double
        /// Sparkles, flowers and crosses turn; stars and hearts only drift.
        let spins: Bool
        /// Sparkles twinkle.
        let twinkles: Bool

        struct Motion {
            let dx: CGFloat
            let dy: CGFloat
            let spin: Angle
            let brightness: Double
        }

        /// The site's `drift` (a slow bob), `.bob` sway, `.spin` (8–12s) and
        /// the ✦ twinkle, each on this sticker's own phase.
        func motion(at t: TimeInterval, animate: Bool) -> Motion {
            guard animate else { return Motion(dx: 0, dy: 0, spin: .zero, brightness: 1) }
            let bob = 4 + phase * 4
            let sway = 5 + (1 - phase) * 5
            let dy = 8 * sin((t / bob + phase) * 2 * .pi)
            let dx = 4 * sin((t / sway + phase * 3) * 2 * .pi)
            let spin: Angle = spins ? .degrees((t / (8 + phase * 4)) * 360 * (phase < 0.5 ? 1 : -1)) : .zero
            let brightness = twinkles ? 0.55 + 0.45 * (0.5 + 0.5 * sin((t / 1.6 + phase) * 2 * .pi)) : 1
            return Motion(dx: dx, dy: dy, spin: spin, brightness: brightness)
        }
    }

    /// One sticker per cell of a jittered grid, so the field is spread rather
    /// than clumped, a little bigger and brighter toward the edges. Seeded by
    /// the screen size so a screen is stable across appearances.
    private func placements(in size: CGSize, decor: SkinDecorations) -> [Placement] {
        guard size.width > 0, size.height > 0, !decor.glyphs.isEmpty else { return [] }
        var rng = SeededRNG(seed: UInt64(size.width) &* 7919 &+ UInt64(size.height) &* 104_729)
        let columns = 4
        let rows = max(6, Int(size.height / 110))
        let cellW = size.width / CGFloat(columns)
        let cellH = (size.height - 80) / CGFloat(rows)
        var out: [Placement] = []
        for row in 0 ..< rows {
            for col in 0 ..< columns {
                // Leave a few cells empty so it reads as scattered, not tiled.
                if rng.unit() < 0.18 { continue }
                let x = CGFloat(col) * cellW + 12 + rng.unit() * (cellW - 24)
                let y = 80 + CGFloat(row) * cellH + 8 + rng.unit() * (cellH - 16)
                let edge = min(x, size.width - x) / (size.width / 2) // 0 at the edge, 1 at centre
                let glyph = Int(rng.next() % UInt64(decor.glyphs.count))
                let symbol = decor.glyphs[glyph].symbol
                out.append(Placement(
                    glyph: glyph,
                    x: x, y: y,
                    size: 12 + rng.unit() * 14 + (1 - edge) * 8,
                    opacity: 0.22 + rng.unit() * 0.3 + (1 - edge) * 0.12,
                    phase: rng.unit(),
                    spins: ["✦", "✧", "✿", "✗", "✚"].contains(symbol),
                    twinkles: ["✦", "✧", "☆"].contains(symbol),
                ))
            }
        }
        return out
    }
}

// MARK: - Pieces

/// Faint dots, like the site's starfield ground. Drawn once per size.
private struct Starfield: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: 0xE1A5)
            for _ in 0 ..< 110 {
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
