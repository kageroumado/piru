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
    @State private var motion = SkinMotion.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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
                let tilt = reduceMotion ? .zero : motion.tilt
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    Canvas(rendersAsynchronously: true) { context, size in
                        SceneRenderer(decor: decor, size: size, time: t, dark: dark, tilt: tilt).draw(in: &context)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear { if !reduceMotion { motion.retain() } }
                .onDisappear { if !reduceMotion { motion.release() } }
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
private struct SceneRenderer {
    let decor: SkinDecorations
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
                let glyph = glyphs[Int(rng.next() % UInt64(glyphs.count))]
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
                let text = context.resolve(Text(verbatim: glyph.symbol).font(.system(size: fontSize)).foregroundStyle(glyph.color))
                context.drawLayer { layer in
                    layer.opacity = opacity * brightness
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .degrees(spin))
                    layer.draw(text, at: .zero, anchor: .center)
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
        let r: CGFloat = 34
        let shift = parallax(0.9)
        let center = CGPoint(x: size.width - 70 + shift.width, y: size.height * 0.42 + shift.height)
        let breathe = 0.5 + 0.5 * sin(time * 2 * .pi / 3)
        bloom(sky.haloColor, at: center, radius: r * 2.6 + 6 * breathe, alpha: (dark ? 0.5 : 0.3) * (0.7 + 0.3 * breathe), in: &context)
        context.drawLayer { layer in
            layer.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(sky.starColor.opacity(dark ? 0.95 : 0.9)))
            // Cut the crescent with a second circle offset up-right.
            layer.blendMode = .destinationOut
            let bite = CGPoint(x: center.x + r * 0.55, y: center.y - r * 0.35)
            layer.fill(Path(ellipseIn: CGRect(x: bite.x - r * 0.9, y: bite.y - r * 0.9, width: r * 1.8, height: r * 1.8)), with: .color(.black))
        }
        // Face on the thick side of the crescent.
        let ink = Color.Skin.Tsuki.Title.stroke.opacity(0.85)
        var eyes = Path()
        for ex in [-0.62, -0.28] as [CGFloat] {
            let e = CGPoint(x: center.x + ex * r, y: center.y + r * 0.18)
            eyes.move(to: CGPoint(x: e.x - 4, y: e.y))
            eyes.addQuadCurve(to: CGPoint(x: e.x + 4, y: e.y), control: CGPoint(x: e.x, y: e.y + 4))
        }
        var smile = Path()
        let m = CGPoint(x: center.x - r * 0.45, y: center.y + r * 0.5)
        smile.move(to: CGPoint(x: m.x - 3.5, y: m.y))
        smile.addQuadCurve(to: CGPoint(x: m.x + 3.5, y: m.y), control: CGPoint(x: m.x, y: m.y + 3.5))
        context.stroke(eyes, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        // Blush.
        for bx in [-0.8, -0.1] as [CGFloat] {
            let b = CGPoint(x: center.x + bx * r, y: center.y + r * 0.36)
            context.fill(Path(ellipseIn: CGRect(x: b.x - 4, y: b.y - 2.5, width: 8, height: 5)), with: .color(Color.Skin.Tsuki.Semantic.Danger.accent.opacity(0.35)))
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
        drawRays(water, in: &context)
        drawDots(in: &context, count: 50, alpha: 0.08 ... 0.3, color: water.bubble, twinkle: true)
        drawJellyfish(water, in: &context)
        drawBubbles(water, in: &context)
        // The glass: a faint vignette so the edges read as a window frame.
        let reach = max(size.width, size.height) * 0.72
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [water.deep.opacity(0), water.deep.opacity(dark ? 0.55 : 0.25)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: reach * 0.45, endRadius: reach,
            ),
        )
    }

    /// Light from the surface: a few translucent wedges swaying slowly.
    private func drawRays(_ water: SkinUnderwater, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0xA7)
        if dark { context.blendMode = .plusLighter }
        let shift = parallax(0.12)
        for i in 0 ..< 8 {
            let x = size.width * (0.05 + 0.9 * rng.unit()) + shift.width
            let width = 14 + rng.unit() * 30
            let phase = rng.unit() * 6.28
            let sway = (6 + rng.unit() * 8) * sin(time * 2 * .pi / (9 + Double(i)) + phase)
            let alpha = (dark ? 0.09 : 0.2) * (0.7 + 0.3 * sin(time / 3 + phase))
            var ray = Path()
            ray.move(to: CGPoint(x: x - width * 0.3, y: -20))
            ray.addLine(to: CGPoint(x: x + width * 0.3, y: -20))
            ray.addLine(to: CGPoint(x: x + width * 1.3 + sway * 6, y: size.height))
            ray.addLine(to: CGPoint(x: x - width * 1.3 + sway * 6, y: size.height))
            ray.closeSubpath()
            context.fill(
                ray,
                with: .linearGradient(
                    Gradient(colors: [water.ray.opacity(alpha), water.ray.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.85),
                ),
            )
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
            // The highlight that makes a ring read as a sphere.
            context.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.5, height: r * 0.4)),
                with: .color(water.bubble.opacity(alpha * 0.9)),
            )
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
            let color = water.bells[i % water.bells.count]
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

            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .degrees(tiltDeg))
                if dark { layer.blendMode = .plusLighter }
                // Bloom under the bell.
                bloom(color, at: .zero, radius: w * 2.4, alpha: (dark ? 0.32 : 0.2) * (0.8 + 0.2 * c), in: &layer)
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
