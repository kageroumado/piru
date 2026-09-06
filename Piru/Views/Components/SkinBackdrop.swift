import SwiftUI

extension View {
    /// The skin's ground behind a screen: the background colour, and — for a
    /// decorated skin with decorations on — the scene over it. Replaces
    /// `.background(Theme.background)` at every screen root; graph code that
    /// *fills* with `Theme.background` (dot rings, fades) keeps the plain colour.
    /// Screen roots only: a component that paints this multiplies the layer.
    func skinBackdrop() -> some View {
        background { SkinBackdrop().ignoresSafeArea() }
    }
}

/// The decoration layer. One `Canvas` on one `TimelineView` clock draws the
/// skin's scene (stickers over a dotted ground, a night sky, or deep water)
/// and the glyph stickers on top of it — every screen root gets exactly one
/// of these, so the cost is one draw pass per frame however many stickers,
/// stars or jellyfish it holds. Everything is a pure function of `(size,
/// time)` from a seeded RNG, so a screen looks the same every time it appears
/// and nothing needs a history buffer. Motion stops under Reduce Motion, and
/// the whole layer is a plain colour when the toggle is off.
///
/// Drawing lessons carried over from rocuronium's jellyfish: no `.blur` or
/// `.shadow` filters in the hot path — a glow is a radial gradient that
/// reaches zero alpha at its own edge — and glows over dark water composite
/// additively, or a colour only reads as paler, not as emitting.
struct SkinBackdrop: View {
    @State private var skins = SkinStore.shared
    /// The screen this backs is on screen. Every tab root and every pushed
    /// screen keeps its backdrop alive; only the visible one may tick.
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Theme.background
            if let decor = skins.current.decorations, skins.decorationsEnabled {
                if case .stickers = decor.scene {
                    stickerGlow
                }
                // Resolved outside the canvas: reads inside the renderer
                // closure are not tracked by Observation.
                let dark = colorScheme == .dark
                let animate = !reduceMotion && visible
                let interval: Double = if case .stickers = decor.scene { 1 / 20 } else { 1 / 30 }
                let atlas = GlyphAtlas.images(for: skins.current, decor: decor, dark: dark, scale: displayScale)
                TimelineView(.animation(minimumInterval: interval, paused: !animate)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    // Polled, not observed — see `SkinMotion.tilt`.
                    let tilt = reduceMotion ? .zero : SkinMotion.shared.tilt
                    // `@Sendable`: a closure formed in this main-actor body
                    // would otherwise inherit main-actor isolation, and the
                    // asynchronous renderer calls it off the main thread on
                    // hardware. Everything it captures is a `Sendable` value.
                    Canvas(rendersAsynchronously: true) { @Sendable context, size in
                        SceneRenderer(decor: decor, atlas: atlas, size: size, time: t, dark: dark, tilt: tilt).draw(in: &context)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    visible = true
                    if !reduceMotion { SkinMotion.shared.retain() }
                }
                .onDisappear {
                    visible = false
                    if !reduceMotion { SkinMotion.shared.release() }
                }
            }
        }
    }

    /// The site's `radial-gradient(115% 70% at 50% -6%, pink 0.12)`.
    private var stickerGlow: some View {
        RadialGradient(
            colors: [skins.current.accentMark.opacity(0.14), .clear],
            center: UnitPoint(x: 0.5, y: -0.06),
            startRadius: 0,
            endRadius: 520,
        )
    }
}

// MARK: - Renderer

/// Draws one frame of a scene. A value, rebuilt per frame; every random
/// choice comes from `SeededRNG` re-seeded the same way, so the frame is a
/// pure function of size and time.
///
/// `nonisolated`: `Canvas(rendersAsynchronously: true)` draws on a
/// background thread on hardware (the simulator draws on main), and under
/// the project's `MainActor` default isolation an implicitly main-actor
/// renderer traps on its first off-main call — a launch crash the simulator
/// never showed. Everything it reads is a `Sendable` value.
private nonisolated struct SceneRenderer {
    let decor: SkinDecorations
    /// Every glyph at every size bucket, rendered once — see ``GlyphAtlas``.
    let atlas: [Image]
    let size: CGSize
    let time: TimeInterval
    let dark: Bool
    /// Device tilt, -1 … 1 per axis. Zero on the simulator and at rest.
    let tilt: CGPoint

    /// The window into the aquarium: a layer at `depth` (0 far, 1 at the
    /// glass) slides opposite the tilt, farther layers less.
    private func parallax(_ depth: Double) -> CGSize {
        CGSize(width: -tilt.x * 34 * depth, height: tilt.y * 26 * depth)
    }

    /// Sticker sizes are bucketed so each glyph is rendered a handful of
    /// times into the atlas instead of laid out once per sticker per frame.
    static let glyphSizes: [CGFloat] = [12, 16, 20, 26, 34]

    static func atlasIndex(glyph: Int, bucket: Int) -> Int {
        glyph * glyphSizes.count + bucket
    }

    func draw(in context: inout GraphicsContext) {
        switch decor.scene {
        case .stickers:
            drawDots(in: &context, count: 110, alpha: 0.05 ... 0.13, color: .white)
            drawGlyphs(in: &context, share: 1.0)
        case let .nightSky(sky):
            drawGlows(sky.glows, in: &context)
            drawStars(sky, in: &context)
            if sky.moon { drawMoon(sky, in: &context) }
            drawGlyphs(in: &context, share: 0.45)
        case let .underwater(water):
            drawWater(water, in: &context)
            drawGlyphs(in: &context, share: 0.3)
        }
    }

    // MARK: Shared pieces

    /// Faint dots — the sticker skin's ground, the plankton in deep water.
    private func drawDots(in context: inout GraphicsContext, count: Int, alpha: ClosedRange<Double>, color: Color, twinkle: Bool = false) {
        var rng = SeededRNG(seed: 0xE1A5)
        for _ in 0 ..< count {
            let x = rng.unit() * size.width
            let y = rng.unit() * size.height
            let r = 0.6 + rng.unit() * 1.1
            var a = alpha.lowerBound + rng.unit() * (alpha.upperBound - alpha.lowerBound)
            if twinkle { a *= 0.6 + 0.4 * sin(time / (1.5 + rng.unit() * 2) + rng.unit() * 6.28) }
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(a)))
        }
    }

    private func drawGlows(_ glows: [SkinGlow], in context: inout GraphicsContext) {
        let reach = max(size.width, size.height) * 0.75
        for glow in glows {
            let center = CGPoint(x: glow.center.x * size.width, y: glow.center.y * size.height)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [glow.color.opacity(glow.opacity), glow.color.opacity(0)]),
                    center: center, startRadius: 0, endRadius: reach,
                ),
            )
        }
    }

    /// A soft bloom: a radial gradient to zero alpha, never a blur.
    private func bloom(_ color: Color, at center: CGPoint, radius: CGFloat, alpha: Double, in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.35), color.opacity(0)]),
                center: center, startRadius: 0, endRadius: radius,
            ),
        )
    }

    // MARK: Glyph stickers

    /// One sticker per cell of a jittered grid, so the field is spread rather
    /// than clumped, a little bigger and brighter toward the edges. `share`
    /// thins the field for scenes that carry their own life.
    private func drawGlyphs(in context: inout GraphicsContext, share: Double) {
        let glyphs = decor.glyphs
        guard size.width > 0, size.height > 0, !glyphs.isEmpty else { return }
        var rng = SeededRNG(seed: UInt64(size.width) &* 7919 &+ UInt64(size.height) &* 104_729)
        let columns = 4
        let rows = max(6, Int(size.height / 110))
        let cellW = size.width / CGFloat(columns)
        let cellH = (size.height - 80) / CGFloat(rows)
        for row in 0 ..< rows {
            for col in 0 ..< columns {
                // Leave cells empty so it reads as scattered, not tiled.
                let skip = rng.unit()
                let x = CGFloat(col) * cellW + 12 + rng.unit() * (cellW - 24)
                let y = 80 + CGFloat(row) * cellH + 8 + rng.unit() * (cellH - 16)
                let edge = min(x, size.width - x) / (size.width / 2) // 0 at the edge, 1 at centre
                let glyphIndex = Int(rng.next() % UInt64(glyphs.count))
                let glyph = glyphs[glyphIndex]
                let fontSize = 12 + rng.unit() * 14 + (1 - edge) * 8
                let opacity = 0.22 + rng.unit() * 0.3 + (1 - edge) * 0.12
                let phase = rng.unit()
                if skip > share * 0.82 { continue }

                let spins = ["✦", "✧", "✿", "✗", "✚", "⋆", "✩"].contains(glyph.symbol)
                let twinkles = ["✦", "✧", "☆", "⋆", "✩"].contains(glyph.symbol)
                // The site's `drift` (a slow bob), `.bob` sway, `.spin` (8–12s)
                // and the ✦ twinkle, each on this sticker's own phase.
                let bob = 4 + phase * 4
                let sway = 5 + (1 - phase) * 5
                let dy = 8 * sin((time / bob + phase) * 2 * .pi)
                let dx = 4 * sin((time / sway + phase * 3) * 2 * .pi)
                let spin = spins ? (time / (8 + phase * 4)) * 360 * (phase < 0.5 ? 1 : -1) : 0
                let brightness = twinkles ? 0.55 + 0.45 * (0.5 + 0.5 * sin((time / 1.6 + phase) * 2 * .pi)) : 1

                let shift = parallax(0.35 + 0.5 * (1 - edge))
                let center = CGPoint(x: x + dx + shift.width, y: y + dy + shift.height)
                if twinkles {
                    bloom(glyph.color, at: center, radius: fontSize * 0.9, alpha: 0.35 * opacity * brightness, in: &context)
                }
                let bucket = Self.glyphSizes.indices.min { abs(Self.glyphSizes[$0] - fontSize) < abs(Self.glyphSizes[$1] - fontSize) } ?? 0
                let index = Self.atlasIndex(glyph: glyphIndex, bucket: bucket)
                guard atlas.indices.contains(index) else { continue }
                let image = context.resolve(atlas[index])
                context.drawLayer { layer in
                    layer.opacity = opacity * brightness
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .degrees(spin))
                    layer.draw(image, at: .zero, anchor: .center)
                }
            }
        }
    }

    // MARK: Night sky

    /// Tsuki's `FloatingStarsView`: each star has its own twinkle speed, a
    /// sine drift, and a halo behind a bright core — the halo a gradient, so
    /// it costs one fill.
    private func drawStars(_ sky: SkinNightSky, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x57A2 &+ UInt64(size.height))
        let count = Int(170 * sky.density * Double(size.height) / 900)
        if dark { context.blendMode = .plusLighter }
        for i in 0 ..< count {
            let baseX = rng.unit() * size.width
            let baseY = rng.unit() * size.height
            let tier = rng.unit()
            let r: CGFloat = tier > 0.9 ? 1.9 + rng.unit() : tier > 0.6 ? 1.1 + rng.unit() * 0.6 : 0.5 + rng.unit() * 0.5
            let period = 1.4 + rng.unit() * 3.2
            let phase = rng.unit() * 2 * .pi
            let drift = 2 + rng.unit() * 3
            let shift = parallax(0.15 + 0.6 * tier)
            let y = baseY + drift * sin(time / (5 + Double(i % 5)) + phase) + shift.height
            let x = baseX + shift.width
            let twinkle = 0.5 + 0.5 * sin(time * 2 * .pi / period + phase)
            let brightness = 0.35 + 0.65 * twinkle
            let center = CGPoint(x: x, y: y)
            if tier > 0.6 {
                bloom(sky.haloColor, at: center, radius: r * 4.5, alpha: (dark ? 0.55 : 0.35) * brightness, in: &context)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(sky.starColor.opacity((dark ? 0.95 : 0.8) * brightness)),
            )
            // The brightest stars get four points.
            if tier > 0.9 {
                var cross = Path()
                let arm = r * (3 + twinkle * 1.5)
                cross.move(to: CGPoint(x: x - arm, y: y)); cross.addLine(to: CGPoint(x: x + arm, y: y))
                cross.move(to: CGPoint(x: x, y: y - arm)); cross.addLine(to: CGPoint(x: x, y: y + arm))
                context.stroke(cross, with: .color(sky.starColor.opacity(0.5 * brightness)), lineWidth: 0.8)
            }
        }
        context.blendMode = .normal
    }

    /// Tsuki's sleeping moon: a crescent in the top-right with a breathing
    /// glow, closed eyes and a small smile.
    private func drawMoon(_ sky: SkinNightSky, in context: inout GraphicsContext) {
        // Proportions measured off Tsuki's app icon (moon r ≈ 300 px there):
        // the bite opens to the right, and the face is small and clustered on
        // the thick left body, a little below centre.
        let r: CGFloat = 38
        let shift = parallax(0.9)
        let center = CGPoint(x: size.width - 74 + shift.width, y: size.height * 0.42 + shift.height)
        let breathe = 0.5 + 0.5 * sin(time * 2 * .pi / 3)
        bloom(sky.haloColor, at: center, radius: r * 2.4 + 6 * breathe, alpha: (dark ? 0.5 : 0.3) * (0.7 + 0.3 * breathe), in: &context)
        context.drawLayer { layer in
            layer.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(sky.starColor.opacity(dark ? 0.95 : 0.9)))
            layer.blendMode = .destinationOut
            let bite = CGPoint(x: center.x + r * 0.50, y: center.y - r * 0.05)
            let br = r * 0.92
            layer.fill(Path(ellipseIn: CGRect(x: bite.x - br, y: bite.y - br, width: br * 2, height: br * 2)), with: .color(.black))
        }
        let ink = sky.moonInk.opacity(0.85)
        let stroke = StrokeStyle(lineWidth: max(1.2, r * 0.035), lineCap: .round)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * r, y: center.y + y * r) }
        // Happy closed eyes: "∩" arcs.
        var eyes = Path()
        for eye in [at(-0.75, 0.18), at(-0.60, 0.15)] {
            let half = r * 0.07
            eyes.move(to: CGPoint(x: eye.x - half, y: eye.y))
            eyes.addQuadCurve(to: CGPoint(x: eye.x + half, y: eye.y), control: CGPoint(x: eye.x, y: eye.y - r * 0.09))
        }
        var smile = Path()
        let m = at(-0.67, 0.29)
        smile.move(to: CGPoint(x: m.x - r * 0.06, y: m.y))
        smile.addQuadCurve(to: CGPoint(x: m.x + r * 0.06, y: m.y), control: CGPoint(x: m.x, y: m.y + r * 0.07))
        context.stroke(eyes, with: .color(ink), style: stroke)
        context.stroke(smile, with: .color(ink), style: stroke)
        for blush in [at(-0.84, 0.28), at(-0.50, 0.24)] {
            context.fill(
                Path(ellipseIn: CGRect(x: blush.x - r * 0.05, y: blush.y - r * 0.035, width: r * 0.10, height: r * 0.07)),
                with: .color(sky.moonBlush.opacity(0.4)),
            )
        }
    }

    // MARK: Underwater

    private func drawWater(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        // The water column: shallow at the top, deep below.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [water.shallow, water.deep]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height),
            ),
        )
        // Night dive in the dark; sunlit deep in the light.
        drawRays(water, in: &context)
        drawCaustics(water, in: &context)
        drawSurface(water, in: &context)
        drawDots(in: &context, count: 50, alpha: 0.08 ... 0.3, color: water.bubble, twinkle: true)
        drawFog(water, in: &context)
        drawJellyfish(water, in: &context)
        drawBubbles(water, in: &context)
        // The glass: a vignette so the edges read as a window frame.
        let reach = max(size.width, size.height) * 0.72
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [water.deep.opacity(0), water.deep.opacity(dark ? 0.6 : 0.25)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: reach * 0.45, endRadius: reach,
            ),
        )
    }

    /// Caustics: slow sine ripples near the surface, two speeds so they
    /// interfere, fading with depth.
    private func drawCaustics(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0xCA05)
        if dark { context.blendMode = .plusLighter }
        let band = size.height * 0.28
        let shift = parallax(0.18)
        for i in 0 ..< 6 {
            let y0 = 24 + band * Double(i) / 6 + shift.height
            let amp = 4 + rng.unit() * 6
            let wavelength = 70 + rng.unit() * 60
            let phase = rng.unit() * 6.28
            let speed1 = 0.5 + rng.unit() * 0.4
            let speed2 = 0.25 + rng.unit() * 0.2
            let fade = 1 - Double(i) / 6
            let alpha = (dark ? 0.07 : 0.15) * fade
            var ripple = Path()
            var x: CGFloat = -20
            var first = true
            while x <= size.width + 20 {
                let y = y0 + amp * sin(x / wavelength + time * speed1 + phase) + amp * 0.5 * sin(x / (wavelength * 0.55) - time * speed2)
                if first { ripple.move(to: CGPoint(x: x + shift.width, y: y)); first = false } else { ripple.addLine(to: CGPoint(x: x + shift.width, y: y)) }
                x += 12
            }
            context.stroke(ripple, with: .color(water.ray.opacity(alpha)), style: StrokeStyle(lineWidth: 1.5 + rng.unit() * 1.5, lineCap: .round))
        }
        context.blendMode = .normal
    }

    /// The surface: a bright band at the top in the light; a faint wavering
    /// line in the dark.
    private func drawSurface(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        if dark {
            var line = Path()
            var x: CGFloat = 0
            line.move(to: CGPoint(x: 0, y: 6))
            while x <= size.width {
                line.addLine(to: CGPoint(x: x, y: 6 + 2 * sin(x / 40 + time * 0.8)))
                x += 10
            }
            context.blendMode = .plusLighter
            context.stroke(line, with: .color(water.ray.opacity(0.06)), lineWidth: 1)
            context.blendMode = .normal
        } else {
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: 110)),
                with: .linearGradient(
                    Gradient(colors: [water.ray.opacity(0.45), water.ray.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: 110),
                ),
            )
        }
    }

    /// Depth fog over the bottom of the column, drawn before the jellies so
    /// the far ones sink into it.
    private func drawFog(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        context.fill(
            Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)),
            with: .linearGradient(
                Gradient(colors: [water.deep.opacity(0), water.deep.opacity(dark ? 0.4 : 0.15)]),
                startPoint: CGPoint(x: 0, y: size.height * 0.55), endPoint: CGPoint(x: 0, y: size.height),
            ),
        )
    }

    /// Light from the surface: translucent wedges swaying slowly, each drawn
    /// as three nested wedges so its edges fade across. Faint moon rays at
    /// night; sun in the light.
    private func drawRays(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0xA7)
        if dark { context.blendMode = .plusLighter }
        let shift = parallax(0.12)
        let count = dark ? 5 : 8
        let reach = size.height * (dark ? 0.6 : 0.9)
        for i in 0 ..< count {
            let x = size.width * (0.05 + 0.9 * rng.unit()) + shift.width
            let width = 14 + rng.unit() * 30
            let phase = rng.unit() * 6.28
            let sway = (6 + rng.unit() * 8) * sin(time * 2 * .pi / (9 + Double(i)) + phase)
            let alpha = (dark ? 0.05 : 0.18) * (0.7 + 0.3 * sin(time / 3 + phase)) / 3
            for spread in [1.0, 0.66, 0.33] as [CGFloat] {
                var ray = Path()
                ray.move(to: CGPoint(x: x - width * 0.3 * spread, y: -20))
                ray.addLine(to: CGPoint(x: x + width * 0.3 * spread, y: -20))
                ray.addLine(to: CGPoint(x: x + width * 1.3 * spread + sway * 6, y: size.height))
                ray.addLine(to: CGPoint(x: x - width * 1.3 * spread + sway * 6, y: size.height))
                ray.closeSubpath()
                context.fill(
                    ray,
                    with: .linearGradient(
                        Gradient(colors: [water.ray.opacity(alpha), water.ray.opacity(0)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: reach),
                    ),
                )
            }
        }
        context.blendMode = .normal
    }

    private func drawBubbles(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0xB0B)
        let span = size.height + 60
        for _ in 0 ..< 26 {
            let x0 = rng.unit() * size.width
            let r = 1.5 + rng.unit() * 3.5
            let speed = 14 + rng.unit() * 22
            let phase = rng.unit() * 6.28
            let start = rng.unit() * span
            // Rise, wobble, wrap.
            let shift = parallax(0.3 + Double(r) / 5 * 0.7)
            let y = size.height + 30 - (start + speed * time).truncatingRemainder(dividingBy: span) + shift.height
            let x = x0 + 6 * sin(time / 1.7 + phase) + shift.width
            let alpha = dark ? 0.45 : 0.6
            context.stroke(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(water.bubble.opacity(alpha)), lineWidth: 0.9,
            )
            // The highlight that makes a ring read as a sphere — sunlight only.
            if !dark {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.5, height: r * 0.4)),
                    with: .color(water.bubble.opacity(alpha * 0.9)),
                )
            }
        }
    }

    /// rocuronium's bell: a fast squeeze over the first quarter of the cycle,
    /// then a smoother glide back with a small refill overshoot. 0 at rest.
    private func contraction(_ u: Double) -> Double {
        let f = u.truncatingRemainder(dividingBy: 1)
        if f < 0.26 {
            let p = f / 0.26
            return 1 - pow(1 - p, 3)
        }
        let v = (f - 0.26) / 0.74
        let glide = 1 - (v * v * v * (v * (v * 6 - 15) + 10))
        return glide - 0.17 * sin(.pi * pow(v, 0.72)) * (1 - glide)
    }

    /// Jellyfish swimming up. Each is a pure function of `(lane, time)`: it
    /// rises at its own speed, sways, pulses its bell on the contraction
    /// curve, and its tentacles lag behind the bell's own motion rather than
    /// being steered — no history buffer, exact under dropped frames.
    private func drawJellyfish(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        guard !water.bells.isEmpty else { return }
        var rng = SeededRNG(seed: 0x1E11 &+ UInt64(size.width))
        let count = max(3, Int(size.height / 190))
        let span = size.height + 320
        for i in 0 ..< count {
            let laneX = size.width * (0.12 + 0.76 * rng.unit())
            let scale = 0.55 + rng.unit() * 0.7
            let speed = 9 + rng.unit() * 9
            let phase = rng.unit() * 6.28
            let period = 1.15 + rng.unit() * 0.6
            let start = rng.unit() * span
            let bellColor = water.bells[i % water.bells.count]
            let c = contraction(time / period + phase)
            // Depth from size: the small ones are far, behind more water.
            let depth = (scale - 0.55) / 0.7
            let shift = parallax(0.25 + 0.75 * depth)
            // Pulse-and-glide: the surge follows the squeeze.
            let surge = 10 * c * scale
            let y = size.height + 160 - (start + speed * (0.7 + 0.3 * depth) * time).truncatingRemainder(dividingBy: span) - surge + shift.height
            let x = laneX + 14 * scale * sin(time * 2 * .pi / (7 + Double(i)) + phase) + shift.width
            let tiltDeg = 3.5 * sin(time * 2 * .pi / 9 + phase)
            let w = 18 * scale * (1 - 0.14 * c)
            let h = 15 * scale * (1 + 0.16 * c)
            let alpha = (dark ? 1.0 : 0.85) * (0.55 + 0.45 * depth)
            // Light lost with distance: far jellies sink toward the water.
            let color = depth < 0.5 ? bellColor.mix(with: water.deep, by: (0.5 - depth) * 0.8) : bellColor

            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .degrees(tiltDeg))
                if dark { layer.blendMode = .plusLighter }
                // Bloom under the bell: at night the jelly is the light.
                bloom(color, at: .zero, radius: w * (dark ? 2.8 : 2.2), alpha: (dark ? 0.4 : 0.16) * (0.8 + 0.2 * c), in: &layer)
                layer.blendMode = .normal

                // Tentacles first, so the bell sits over their roots. Five
                // strands from the hem, each a tapered ribbon that lags.
                let periods: [Double] = [3.1, 3.5, 2.9, 3.4, 3.2]
                let offsets: [Double] = [0, 0.35, 0.6, 0.2, 0.5]
                for k in 0 ..< 5 {
                    let root = CGPoint(x: w * (-0.72 + 0.36 * CGFloat(k)), y: h * 0.28)
                    let length = h * (2.6 + 0.6 * Double(k % 2))
                    let width: CGFloat = 2.2 * scale
                    var left: [CGPoint] = []
                    var right: [CGPoint] = []
                    for s in stride(from: 0.0, through: 1.0, by: 0.1) {
                        let sway = sin(time * 2 * .pi / periods[k] - 2.4 * s + offsets[k] * 6.28 + phase) * 7 * scale * (0.2 + s)
                        let p = CGPoint(x: root.x + sway, y: root.y + length * s)
                        let half = width * (1 - s)
                        left.append(CGPoint(x: p.x - half, y: p.y))
                        right.append(CGPoint(x: p.x + half, y: p.y))
                    }
                    var ribbon = Path()
                    ribbon.move(to: left[0])
                    for p in left.dropFirst() { ribbon.addLine(to: p) }
                    for p in right.reversed() { ribbon.addLine(to: p) }
                    ribbon.closeSubpath()
                    layer.fill(
                        ribbon,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.75 * alpha), color.opacity(0)]),
                            startPoint: root, endPoint: CGPoint(x: root.x, y: root.y + length),
                        ),
                    )
                }
                // Two frilly oral arms in the middle, in the pink.
                let pink = water.bells[water.bells.count - 1]
                for k in 0 ..< 2 {
                    let root = CGPoint(x: w * (-0.18 + 0.36 * CGFloat(k)), y: h * 0.25)
                    let length = h * 1.7
                    var arm = Path()
                    arm.move(to: root)
                    for s in stride(from: 0.0, through: 1.0, by: 0.1) {
                        let wave = sin(time * 3 + s * 9 + Double(k) * 2 + phase) * 3 * scale * s
                        arm.addLine(to: CGPoint(x: root.x + wave, y: root.y + length * s))
                    }
                    layer.stroke(arm, with: .color(pink.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 2.4 * scale * (1 - 0.3 * c), lineCap: .round))
                }

                // The bell: a dome with a scalloped hem, lit from the top.
                var bell = Path()
                bell.move(to: CGPoint(x: -w, y: 0))
                bell.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: -2.3 * h))
                let scallops = 4
                for n in 0 ..< scallops {
                    let x0 = w - (2 * w) * CGFloat(n) / CGFloat(scallops)
                    let x1 = w - (2 * w) * CGFloat(n + 1) / CGFloat(scallops)
                    bell.addQuadCurve(to: CGPoint(x: x1, y: 0), control: CGPoint(x: (x0 + x1) / 2, y: h * 0.32 * (1 + 0.5 * c)))
                }
                bell.closeSubpath()
                layer.fill(
                    bell,
                    with: .radialGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.92 * alpha), color.opacity(0.78 * alpha), color.opacity(0.22 * alpha),
                        ]),
                        center: CGPoint(x: 0, y: -h * 0.9), startRadius: 0, endRadius: w * 1.5,
                    ),
                )
                layer.stroke(bell, with: .color(color.opacity(0.55 * alpha)), lineWidth: 0.8)
                // A rim highlight and two sleepy eyes.
                var rim = Path()
                rim.move(to: CGPoint(x: -w * 0.55, y: -h * 0.95))
                rim.addQuadCurve(to: CGPoint(x: w * 0.35, y: -h * 1.15), control: CGPoint(x: -w * 0.1, y: -h * 1.55))
                layer.stroke(rim, with: .color(Color.white.opacity(0.55 * alpha)), style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
                let ink = Color.black.opacity(0.55 * alpha)
                for ex in [-0.3, 0.3] as [CGFloat] {
                    let e = CGPoint(x: ex * w, y: -h * 0.35)
                    layer.fill(Path(ellipseIn: CGRect(x: e.x - 1.3 * scale, y: e.y - 1.3 * scale, width: 2.6 * scale, height: 2.6 * scale)), with: .color(ink))
                }
            }
        }
    }
}

// MARK: - Pieces

/// The glyph stickers as bitmaps: every glyph of a skin at every size bucket,
/// rendered once per skin and appearance and kept. Text layout is the
/// expensive part of a sticker; at 20 fps across every live backdrop it was
/// enough to hang the phone. A bitmap blit is not.
private enum GlyphAtlas {
    private static var cache: [String: [Image]] = [:]

    @MainActor
    static func images(for skin: Skin, decor: SkinDecorations, dark: Bool, scale: CGFloat) -> [Image] {
        let key = "\(skin.rawValue)|\(dark)|\(scale)"
        if let cached = cache[key] { return cached }
        var images: [Image] = []
        for glyph in decor.glyphs {
            for size in SceneRenderer.glyphSizes {
                let renderer = ImageRenderer(content:
                    Text(verbatim: glyph.symbol)
                        .font(.system(size: size))
                        .foregroundStyle(glyph.color)
                        .padding(4)
                        .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = scale
                renderer.isOpaque = false
                if let cg = renderer.cgImage {
                    images.append(Image(decorative: cg, scale: scale))
                } else {
                    images.append(Image(systemName: "circle.fill"))
                }
            }
        }
        cache[key] = images
        return images
    }
}

/// SplitMix64 — deterministic, so a screen's decoration is the same every time.
private nonisolated struct SeededRNG {
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

// MARK: - Flourishes

extension View {
    /// The skin's corner glyphs on a large card — ✧ hanging off the top-right
    /// edge, ♡ off the bottom-left — for a decorated skin with decorations on.
    /// Glance cards only: on a dense row the pair would collide with its text.
    func skinFrameCorners() -> some View {
        modifier(SkinFrameCorners())
    }

    /// The site's cursor trail: a glyph floats up and fades from every tap.
    /// Attached once at the root.
    func tapTrail() -> some View {
        modifier(TapTrail())
    }
}

private struct SkinFrameCorners: ViewModifier {
    @State private var skins = SkinStore.shared

    func body(content: Content) -> some View {
        if let corners = skins.current.decorations?.frameCorners, skins.decorationsEnabled {
            content
                .overlay(alignment: .topTrailing) { glyph(corners.0).offset(x: 6, y: -11) }
                .overlay(alignment: .bottomLeading) { glyph(corners.1).offset(x: -6, y: 9) }
        } else {
            content
        }
    }

    private func glyph(_ glyph: SkinGlyph) -> some View {
        Text(verbatim: glyph.symbol)
            .font(.system(size: 18))
            .foregroundStyle(glyph.color)
            .shadow(color: glyph.color.opacity(0.8), radius: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TapTrail: ViewModifier {
    @State private var skins = SkinStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var puffs: [Puff] = []

    struct Puff: Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    func body(content: Content) -> some View {
        #if canImport(UIKit)
            trail(content)
        #else
            content
        #endif
    }

    #if canImport(UIKit)
    @ViewBuilder
    private func trail(_ content: Content) -> some View {
        if let glyph = skins.current.decorations?.tapGlyph, skins.decorationsEnabled, !reduceMotion {
            content
                // Not a SwiftUI gesture: a `simultaneousGesture` tap on an
                // ancestor cancels `List` row selection, so NavigationLinks
                // in the Library stopped opening. A window-level recognizer
                // that only *observes* (and always fails) never competes.
                .background {
                    TouchObserver { point in
                        puffs.append(Puff(point: point))
                        if puffs.count > 12 { puffs.removeFirst() }
                    }
                }
                .overlay {
                    ForEach(puffs) { puff in
                        TapPuff(glyph: glyph, at: puff.point) {
                            puffs.removeAll { $0.id == puff.id }
                        }
                    }
                    .allowsHitTesting(false)
                    // Touch points come in window coordinates.
                    .ignoresSafeArea()
                }
        } else {
            content
        }
    }
    #endif
}

#if canImport(UIKit)
/// Reports every touch-down in the window, in window coordinates, without
/// taking part in gesture resolution: the recognizer fails as soon as a touch
/// begins, and cancels nothing, so every control underneath sees the touch
/// exactly as it would without it.
private struct TouchObserver: UIViewRepresentable {
    let onTouch: (CGPoint) -> Void

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.onTouch = onTouch
    }

    final class HostView: UIView {
        var onTouch: ((CGPoint) -> Void)?
        private let spy = TouchSpy()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            spy.view?.removeGestureRecognizer(spy)
            guard let window else { return }
            spy.onTouch = { [weak self] point in self?.onTouch?(point) }
            window.addGestureRecognizer(spy)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    final class TouchSpy: UIGestureRecognizer {
        var onTouch: ((CGPoint) -> Void)?

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first, let view {
                onTouch?(touch.location(in: view))
            }
            state = .failed
        }
    }
}
#endif

/// One glyph from a tap: rises, shrinks, turns and fades over 0.8 s — the
/// site's `@keyframes tr` — then removes itself.
private struct TapPuff: View {
    let glyph: SkinGlyph
    let point: CGPoint
    let finished: () -> Void
    @State private var flown = false

    init(glyph: SkinGlyph, at point: CGPoint, finished: @escaping () -> Void) {
        self.glyph = glyph
        self.point = point
        self.finished = finished
    }

    var body: some View {
        Text(verbatim: glyph.symbol)
            .font(.system(size: 22))
            .foregroundStyle(glyph.color)
            .shadow(color: .white.opacity(0.9), radius: 4)
            .scaleEffect(flown ? 0.2 : 1)
            .rotationEffect(.degrees(flown ? 40 : 0))
            .opacity(flown ? 0 : 1)
            .position(x: point.x, y: point.y - (flown ? 28 : 0))
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { flown = true }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(850))
                finished()
            }
    }
}

// MARK: - Hero title

extension View {
    /// The skin's treated hero title on a SwiftUI-drawn title (the substance
    /// name): the fill and drop the navigation bar's large title gets from
    /// ``SkinNavigationTitles``, plus the outline an edged skin asks for.
    /// SwiftUI cannot stroke text, so the outline is eight zero-radius
    /// shadows of the composite fill — the site's own trick, and seam-free
    /// where UIKit's `strokeWidth` is not.
    func skinHeroTitle() -> some View {
        modifier(SkinHeroTitle())
    }
}

private struct SkinHeroTitle: ViewModifier {
    @State private var skins = SkinStore.shared

    func body(content: Content) -> some View {
        if let outline = skins.current.titleOutline {
            let s = outline.stroke ?? .clear
            content
                .foregroundStyle(outline.fill.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .shadow(color: s, radius: 0, x: -2, y: -2)
                .shadow(color: s, radius: 0, x: 2, y: -2)
                .shadow(color: s, radius: 0, x: -2, y: 2)
                .shadow(color: s, radius: 0, x: 2, y: 2)
                .shadow(color: s, radius: 0, x: -2, y: 0)
                .shadow(color: s, radius: 0, x: 2, y: 0)
                .shadow(color: s, radius: 0, x: 0, y: -2)
                .shadow(color: s, radius: 0, x: 0, y: 2)
                .shadow(color: outline.shadow, radius: outline.shadowBlur, x: outline.shadowOffset.width, y: outline.shadowOffset.height)
        } else {
            content
        }
    }
}
