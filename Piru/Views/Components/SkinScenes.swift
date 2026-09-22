import SwiftUI
import Synchronization

// Five scenes for the second batch of skins — a paper garden (Origami +
// Kaze), fireflies and an aurora (Hotaru), snow (Yuki), a neon arcade (Hebi)
// and a living sky (Kumo). Each is a pure
// function of `(size, time, tilt, clock)` from `SeededRNG`, drawn by
// `SceneRenderer` on the one clock; every number was read from the source
// app named in the comment above it.

nonisolated extension SceneRenderer {
    // MARK: - Paper garden

    /// Origami's washi ground with its grain, Kaze's raked sand bending around
    /// stones, sakura petals on Kaze's fall, and fireflies after dark.
    func drawPaperGarden(_ garden: SkinPaperGarden, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x5A0D &+ UInt64(size.width))
        let light = !dark
        if let grain = textures.grain {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .tiledImage(grain, scale: 1 / 3))
        }
        // The sand: the lower 55%, a gradient between Kaze's two sands.
        let sandTop = size.height * 0.45
        context.fill(
            Path(CGRect(x: 0, y: sandTop, width: size.width, height: size.height - sandTop)),
            with: .linearGradient(
                Gradient(colors: [garden.sand1.opacity(0), garden.sand1.opacity(light ? 0.55 : 0.5), garden.sand2.opacity(light ? 0.7 : 0.6)]),
                startPoint: CGPoint(x: 0, y: sandTop), endPoint: CGPoint(x: 0, y: size.height),
            ),
        )
        // Two stones, with their moss, that the rake bends around.
        struct Stone { let c: CGPoint; let w: CGFloat; let h: CGFloat }
        let stones = [
            Stone(c: CGPoint(x: size.width * (0.28 + rng.unit() * 0.1), y: sandTop + size.height * 0.18), w: 50, h: 40),
            Stone(c: CGPoint(x: size.width * (0.7 + rng.unit() * 0.1), y: sandTop + size.height * 0.38), w: 70, h: 55),
        ]
        let shift = parallax(0.5)
        // Grooves: Kaze's fine rake, one every 9pt, bending around the stones.
        for row in stride(from: sandTop + 14, to: size.height, by: 9) {
            var groove = Path()
            var x: CGFloat = -4
            var first = true
            while x <= size.width + 4 {
                var y = row + 1.5 * sin(x / 60 + row / 40)
                for s in stones {
                    let dx = x - s.c.x, dy = row - s.c.y
                    let r = max(s.w, s.h) * 0.8
                    let d2 = (dx * dx) / (r * r * 1.6) + (dy * dy) / (r * r)
                    y += (dy < 0 ? -1 : 1) * 9 * exp(-d2 * 2.2)
                }
                let p = CGPoint(x: x + shift.width, y: y + shift.height)
                if first { groove.move(to: p); first = false } else { groove.addLine(to: p) }
                x += 8
            }
            context.stroke(groove, with: .color(Color.white.opacity(light ? 0.4 : 0.08)), lineWidth: 1)
            context.stroke(groove.offsetBy(dx: 0, dy: 1.2), with: .color(garden.groove.opacity(light ? 0.16 : 0.35)), lineWidth: 1)
        }
        for s in stones {
            // Rings, then the stone with Kaze's gradient and hairline, then moss.
            for i in 1 ... 5 {
                let rr = CGFloat(i) * 9
                let ring = Path(ellipseIn: CGRect(x: s.c.x - s.w / 2 - rr + shift.width, y: s.c.y - s.h / 2 - rr * 0.8 + shift.height, width: s.w + rr * 2, height: s.h + rr * 1.6))
                context.stroke(ring, with: .color(garden.groove.opacity((light ? 0.14 : 0.3) * (1 - Double(i) / 6))), lineWidth: 1)
            }
            let rect = CGRect(x: s.c.x - s.w / 2 + shift.width, y: s.c.y - s.h / 2 + shift.height, width: s.w, height: s.h)
            context.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [garden.stone.mix(with: .white, by: 0.15), garden.stone.mix(with: .black, by: 0.2)]), startPoint: rect.origin, endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            context.stroke(Path(ellipseIn: rect), with: .color(garden.stone.mix(with: .black, by: 0.3).opacity(0.5)), lineWidth: 1)
            for (dx, dy, mw) in [(-0.3, 0.25, 0.4), (0.25, 0.3, 0.3)] {
                let m = CGRect(x: rect.minX + rect.width * (0.5 + dx) - rect.width * mw / 2, y: rect.minY + rect.height * (0.5 + dy) - 4, width: rect.width * mw, height: 8)
                context.fill(Path(ellipseIn: m), with: .color(garden.moss.opacity(0.75)))
            }
        }
        // Petals on Kaze's fall: 60±30 pt/s at −0.3±0.5 rad, xAccel 10, yAccel −15 (SpriteKit y-up).
        var prng = SeededRNG(seed: 0x9E7A1)
        let span = size.height + 120
        for _ in 0 ..< 22 {
            let start = prng.unit() * 30
            let t = (time + start).truncatingRemainder(dividingBy: 14)
            let angle = -0.3 + (prng.unit() - 0.5)
            let speed = 60 + (prng.unit() - 0.5) * 60
            let vx = cos(angle) * speed * 0.35, vy = -sin(angle) * speed * 0.35 + 25
            let x0 = -40 + prng.unit() * size.width * 0.8
            let x = x0 + vx * t + 5 * t * t * 0.3 + parallax(0.3 + prng.unit() * 0.5).width
            let y = (vy * t + 7.5 * t * t * 0.3).truncatingRemainder(dividingBy: span) - 60
            let rot = 1.5 * t + prng.unit() * 6.28
            let alpha = max(0.2, 0.8 - 0.05 * t)
            let scale = 0.3 + prng.unit() * 0.3
            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(rot))
                layer.scaleBy(x: scale * 2.4, y: scale * 2.4)
                layer.fill(Path(ellipseIn: CGRect(x: -5, y: -4, width: 10, height: 8)), with: .color(garden.petal.opacity(alpha)))
            }
        }
        // Fireflies over the garden at night — Kaze's, with its blink keyframes.
        if dark {
            var frng = SeededRNG(seed: 0xF1E)
            for i in 0 ..< 12 {
                let life = 6 + frng.unit() * 6
                let u = ((time / life) + frng.unit()).truncatingRemainder(dividingBy: 1)
                let a = u < 0.2 ? u / 0.2 * 0.8 : (u < 0.8 ? 0.8 : (1 - u) / 0.2 * 0.8)
                let x = size.width * (0.1 + 0.8 * frng.unit()) + 12 * sin(time / 3 + Double(i)) + parallax(0.6).width
                let y = size.height * (0.2 + 0.6 * frng.unit()) + 8 * sin(time / 2.3 + Double(i) * 1.7) + parallax(0.6).height
                bloom(garden.firefly, at: CGPoint(x: x, y: y), radius: 8, alpha: a * 0.7, in: &context)
                context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(garden.firefly.opacity(a)))
            }
        }
        // Kaze's vignette, floored at .5.
        let reach = max(size.width, size.height) * 0.7
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(Gradient(colors: [garden.groove.opacity(0), garden.groove.opacity(light ? 0.12 : 0.3)]), center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: reach * 0.5, endRadius: reach),
        )
    }

    // MARK: - Hotaru: fireflies and an aurora

    /// Hotaru's `Fireflies.metal` and `Aurora.metal`: ground, tree line, fog,
    /// 120 fireflies with the shader's blink, size and two-term glow; three
    /// aurora ribbons on its wave, cycling green → cyan → purple → pink.
    func drawFireflies(_ night: SkinFireflies, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x407A)
        // Aurora, top 30%, additive. Light mode: none.
        if dark {
            context.blendMode = .plusLighter
            for i in 0 ..< 3 {
                let layerOffset = Double(i) * 0.3
                let layerSpeed = 1 + Double(i) * 0.2
                let baseY = size.height * (0.10 + Double(i) * 0.06) + parallax(0.1).height
                let intensity = (1 - Double(i) * 0.15) * 0.4
                let t3 = time * 0.3
                for (c, color) in night.aurora.enumerated() {
                    var ribbon = Path()
                    var x: CGFloat = -10
                    var first = true
                    // Sampled finely and drawn as a smooth curve, so the
                    // ribbon is a curtain, not a chain of segments.
                    var prev: CGPoint?
                    while x <= size.width + 10 {
                        let flowX = Double(x) / Double(size.width) * 3 + t3 * 0.2 * layerSpeed + layerOffset
                        let wave = sin(flowX * 2) * 0.1 + sin(flowX * 4 + t3 * 0.5) * 0.05 + sin(flowX * 7 + t3 * 0.3) * 0.015
                        let y = baseY + wave * size.height * 0.35
                        let p = CGPoint(x: x, y: y)
                        if first { ribbon.move(to: p); first = false }
                        else if let q = prev { ribbon.addQuadCurve(to: CGPoint(x: (q.x + p.x) / 2, y: (q.y + p.y) / 2), control: q) }
                        prev = p
                        x += 6
                    }
                    // Each colour owns a quarter of the width, drifting: a
                    // horizontal alpha gradient selects it.
                    let phase = ((t3 * 0.1 + layerOffset * 0.5) * 0.5).truncatingRemainder(dividingBy: 1)
                    let start = (Double(c) / 4 + phase).truncatingRemainder(dividingBy: 1)
                    let sx = start * Double(size.width)
                    let ex = sx + Double(size.width) / 4
                    context.stroke(
                        ribbon,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: color.opacity(0), location: 0),
                                .init(color: color.opacity(intensity), location: 0.5),
                                .init(color: color.opacity(0), location: 1),
                            ]),
                            startPoint: CGPoint(x: sx - size.width / 8, y: 0), endPoint: CGPoint(x: ex + size.width / 8, y: 0),
                        ),
                        style: StrokeStyle(lineWidth: 34, lineCap: .round),
                    )
                    // A wider, fainter pass under it softens the edge.
                    context.stroke(
                        ribbon,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: color.opacity(0), location: 0),
                                .init(color: color.opacity(intensity * 0.35), location: 0.5),
                                .init(color: color.opacity(0), location: 1),
                            ]),
                            startPoint: CGPoint(x: sx - size.width / 8, y: 0), endPoint: CGPoint(x: ex + size.width / 8, y: 0),
                        ),
                        style: StrokeStyle(lineWidth: 70, lineCap: .round),
                    )
                }
            }
            context.blendMode = .normal
            drawStars(SkinNightSky(starColor: night.core, haloColor: night.glow, density: 0.4, moon: false, glows: []), in: &context)
        } else {
            // Morning mist over a dawn meadow.
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.5)), with: .linearGradient(Gradient(colors: [night.core.opacity(0.35), night.core.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.5)))
        }
        // Fog at the bottom third: three wide ellipses, sliding.
        for i in 0 ..< 3 {
            let w = size.width * 1.2
            let x = -size.width * 0.1 + sin(time * 0.02 * 6.28 + Double(i) * 2) * 30
            let y = size.height * (0.78 + Double(i) * 0.06)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: 90)), with: .radialGradient(Gradient(colors: [night.fog.opacity(0.15), night.fog.opacity(0)]), center: CGPoint(x: x + w / 2, y: y + 45), startRadius: 0, endRadius: w / 2))
        }
        // Tree line: `h·(.3 + fbm·.4)` over the bottom 140pt.
        var trees = Path()
        trees.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        while x <= size.width {
            let u = Double(x) / Double(size.width)
            let f = 0.5 + 0.5 * (sin(u * 7.1) * 0.5 + sin(u * 17.3 + 1) * 0.3 + sin(u * 41 + 2) * 0.2)
            trees.addLine(to: CGPoint(x: x, y: size.height - 140 * (0.3 + f * 0.7) + parallax(0.2).height))
            x += 6
        }
        trees.addLine(to: CGPoint(x: size.width, y: size.height))
        trees.closeSubpath()
        context.fill(trees, with: .color(night.tree.opacity(dark ? 1 : 0.9)))
        // Fireflies. Light mode: pollen motes, no glow.
        if dark { context.blendMode = .plusLighter }
        for _ in 0 ..< (dark ? 120 : 60) {
            let phase = rng.unit()
            let depth = 0.3 + rng.unit() * 0.7
            let bx = rng.unit() * size.width, by = size.height * (0.15 + 0.75 * rng.unit())
            let particleTime = time + phase * 100
            let x = bx + sin(particleTime * 0.11 + phase * 6) * 26 * depth + sin(particleTime * 0.037 + phase) * 40 * depth + parallax(depth).width
            let y = by + cos(particleTime * 0.09 + phase * 4) * 20 * depth + sin(particleTime * 0.05 + phase * 2) * 30 * depth + parallax(depth).height
            let pulseFreq = 0.5 + rng.unit()
            let pulse = sin(particleTime * pulseFreq * 6.28318) * 0.5 + 0.5
            let flickerHash = (floor(particleTime * 3) + phase * 97).truncatingRemainder(dividingBy: 1)
            let flicker = flickerHash > 0.95 ? 0.0 : 1.0
            let brightness = (dark ? pulse * pulse * flicker : 0.5 + 0.2 * pulse) * (sin(particleTime * 0.1 + phase * 6.28318) * 0.3 + 0.7)
            guard brightness > 0.02 else { continue }
            let sz = (8 + depth * 12) * (0.5 + brightness * 0.5) * (dark ? 0.5 : 0.25)
            let center = CGPoint(x: x, y: y)
            context.fill(
                Path(ellipseIn: CGRect(x: x - sz, y: y - sz, width: sz * 2, height: sz * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: night.core.opacity(brightness * (dark ? 0.95 : 0.5)), location: 0),
                        .init(color: night.glow.opacity(brightness * (dark ? 0.5 : 0.15)), location: 0.35),
                        .init(color: night.glow.opacity(0), location: 1),
                    ]),
                    center: center, startRadius: 0, endRadius: sz,
                ),
            )
        }
        context.blendMode = .normal
    }

    // MARK: - Yuki: snow

    /// Yuki's `SnowfallView` in closed form, frost blooms and crystals at the
    /// top corners, and a drift of settled snow along the top edge.
    func drawSnow(_ snow: SkinSnow, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x5000)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0)] {
            bloom(snow.frost, at: corner, radius: 220, alpha: dark ? 0.12 : 0.25, in: &context)
        }
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 10)), with: .linearGradient(Gradient(colors: [snow.frost.opacity(0.5), snow.frost.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 10)))
        // Crystals: eight, fading on slow clocks.
        for i in 0 ..< 8 {
            let c = CGPoint(x: i < 4 ? 14 + rng.unit() * 90 : size.width - 14 - rng.unit() * 90, y: 20 + rng.unit() * 110)
            let r = 6 + rng.unit() * 6
            let a = 0.35 * (0.5 + 0.5 * sin(time / (4 + rng.unit() * 3) + rng.unit() * 6.28))
            var crystal = Path()
            for arm in 0 ..< 3 {
                let ang = Double(arm) * .pi / 3
                crystal.move(to: CGPoint(x: c.x - cos(ang) * r, y: c.y - sin(ang) * r))
                crystal.addLine(to: CGPoint(x: c.x + cos(ang) * r, y: c.y + sin(ang) * r))
            }
            context.stroke(crystal, with: .color(snow.frost.opacity(dark ? a : a * 0.8)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        // Flakes — Yuki's numbers.
        for _ in 0 ..< 60 {
            let speed = 15 + rng.unit() * 30
            let radius = 1 + rng.unit() * 2.5
            let opacity = 0.15 + rng.unit() * 0.35
            let driftAmp = 10 + rng.unit() * 20
            let driftFreq = 0.3 + rng.unit() * 0.7
            let driftPhase = rng.unit() * 6.28
            let x0 = rng.unit()
            let y0 = -200 + rng.unit() * 1_000
            let birth = rng.unit() * 20
            let age = time + birth
            let wrapped = (y0 + age * speed).truncatingRemainder(dividingBy: size.height + 20) - 10
            let y = (wrapped < -10 ? wrapped + size.height + 20 : wrapped)
            let depth = Double(radius) / 3.5
            let shift = parallax(0.2 + 0.7 * depth)
            let x = x0 * size.width + sin(age * driftFreq + driftPhase) * driftAmp + shift.width
            let fade = opacity * (1 - abs(y / size.height - 0.5) * 0.4)
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y + shift.height - radius, width: radius * 2, height: radius * 2)), with: .color(snow.flake.opacity(dark ? fade * 1.6 : fade * 1.3)))
        }
    }

    // MARK: - Hebi: Neon City

    /// A perspective grid floor scrolling toward the viewer, pixel stars, a
    /// snake walking a seeded path on an invisible grid, its food, scanlines.
    func drawArcade(_ arcade: SkinArcade, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x5E8A)
        let vp = size.height * 0.52 + parallax(0.1).height
        // Stars: 2×2 pixels, upper half.
        for _ in 0 ..< 60 {
            let depth = rng.unit()
            let x = rng.unit() * size.width + parallax(0.1 + depth * 0.4).width
            let y = rng.unit() * vp * 0.95
            let a = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * (1 + depth * 2) + depth * 20))
            context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: 2, height: 2)), with: .color(arcade.star.opacity(a * (dark ? 0.9 : 0.6))))
        }
        // The floor.
        if dark { context.blendMode = .plusLighter }
        var lines = Path()
        for k in 0 ..< 14 {
            let u = Double(k) / 13
            let xTop = size.width * (0.35 + u * 0.3)
            let xBottom = size.width * (-0.6 + u * 2.2)
            lines.move(to: CGPoint(x: xTop, y: vp))
            lines.addLine(to: CGPoint(x: xBottom, y: size.height))
        }
        for k in 0 ..< 12 {
            let z = ((Double(k) / 12) + time * 0.12).truncatingRemainder(dividingBy: 1)
            let y = vp + (size.height - vp) * z * z
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(lines, with: .color(arcade.wall.opacity(dark ? 0.45 : 0.35)), lineWidth: dark ? 1 : 1)
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: vp))
        horizon.addLine(to: CGPoint(x: size.width, y: vp))
        context.stroke(horizon, with: .color(arcade.border.opacity(0.7)), lineWidth: 1.5)
        bloom(arcade.border, at: CGPoint(x: size.width / 2, y: vp), radius: size.width * 0.5, alpha: dark ? 0.18 : 0.08, in: &context)
        context.blendMode = .normal
        // The snake: a real game on a 12pt grid in the upper half, one step
        // every .16 s. It steers toward the food, never reverses, never
        // crosses its own body, grows when it eats, and when it traps itself
        // the round ends and a new snake starts. Deterministic from the seed,
        // so the frame at any time is the same on every device.
        let cell: CGFloat = 12
        let cols = Int(size.width / cell), rows = Int(vp * 0.9 / cell)
        let game = SnakeGame(cols: cols, rows: rows, seed: 0x5AAE)
        let state = game.state(atStep: Int(time / 0.16) % SnakeGame.tapeLength)
        let shift = parallax(0.6)
        for (k, (cx, cy)) in state.body.enumerated() {
            let rect = CGRect(x: CGFloat(cx) * cell + 1 + shift.width, y: CGFloat(cy) * cell + 1 + shift.height, width: cell - 2, height: cell - 2)
            let head = k == 0
            let color = head ? arcade.snake : arcade.snakeBody
            if dark, k < 12 { bloom(color, at: CGPoint(x: rect.midX, y: rect.midY), radius: head ? 14 : 8, alpha: head ? 0.5 : 0.25, in: &context) }
            let fade = max(0.35, 0.85 - Double(k) * 0.03)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(head ? 1 : fade)))
            if head {
                for ex in [0.3, 0.7] {
                    context.fill(Path(CGRect(x: rect.minX + rect.width * ex - 1, y: rect.minY + 3, width: 2, height: 2)), with: .color(.black.opacity(0.8)))
                }
            }
        }
        let (fx, fy) = state.food
        let food = CGRect(x: CGFloat(fx) * cell + 2 + shift.width, y: CGFloat(fy) * cell + 2 + shift.height, width: cell - 4, height: cell - 4)
        let blink = 0.6 + 0.4 * (sin(time * 2 * 6.28) > 0 ? 1 : 0)
        bloom(arcade.food, at: CGPoint(x: food.midX, y: food.midY), radius: 12, alpha: 0.3 * blink, in: &context)
        context.fill(Path(roundedRect: food, cornerRadius: 2), with: .color(arcade.food.opacity(blink)))
        // Scanlines and a vignette.
        if let scan = textures.scanlines {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .tiledImage(scan, scale: 1 / 3))
        }
        let reach = max(size.width, size.height) * 0.72
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(dark ? 0.45 : 0.1)]), center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: reach * 0.5, endRadius: reach))
    }

    // MARK: - Kumo: a living sky

    /// Kumo's sky by the real clock and season: its gradients lerped through
    /// dawn and dusk, sun or moon on an arc, its stars, three cloud layers on
    /// their own speeds, rain or snow by month, the night aurora band.
    func drawSky(_ sky: SkinSky, in context: inout GraphicsContext) {
        let f = clock.dayFraction
        // Light mode keeps a day family; dark keeps a night family.
        let hour = f * 24
        let dawn = max(0, min(1, (hour - 5) / 2)), dusk = max(0, min(1, (hour - 17) / 3))
        let dayness: Double = if hour < 5 { 0 } else if hour < 7 { dawn } else if hour < 17 { 1 } else if hour < 20 { 1 - dusk } else { 0 }
        let sunset: Double = if hour >= 5 && hour < 7 { sin(dawn * .pi) } else if hour >= 17 && hour < 20 { sin(dusk * .pi) } else { 0 }
        let mode = dark ? min(dayness, 0.25) : max(dayness, 0.55)
        func mixColor(_ n: Color, _ d: Color, _ s: Color) -> Color {
            n.mix(with: d, by: mode).mix(with: s, by: sunset * 0.7)
        }
        let top = mixColor(sky.night.0, sky.day.0, sky.sunset.0)
        let bottom = mixColor(sky.night.1, sky.day.1, sky.sunset.1)
        let wobble = sin(time * 0.1) * 0.05
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: size.width * (0.3 + wobble), y: 0), endPoint: CGPoint(x: size.width * (0.7 - wobble), y: size.height)),
        )
        // Sun or moon on an arc.
        let isNight = mode < 0.4
        let arcT = isNight ? ((f + 0.5).truncatingRemainder(dividingBy: 1) - 0.25) / 0.5 : (f - 0.25) / 0.5
        let angle = .pi * max(0.05, min(0.95, arcT))
        let orb = CGPoint(x: size.width * (0.5 - cos(angle) * 0.42) + parallax(0.05).width, y: size.height * 0.3 - sin(angle) * size.height * 0.2 + parallax(0.05).height)
        if isNight {
            bloom(sky.moon, at: orb, radius: 70, alpha: 0.35, in: &context)
            context.fill(Path(ellipseIn: CGRect(x: orb.x - 16, y: orb.y - 16, width: 32, height: 32)), with: .color(sky.moon.opacity(0.95)))
            context.fill(Path(ellipseIn: CGRect(x: orb.x - 10, y: orb.y - 22, width: 32, height: 32)), with: .color(top.opacity(0.98)))
            for _ in 0 ..< 1 {
                var rng = SeededRNG(seed: 0x5A7)
                for _ in 0 ..< 80 {
                    let x = rng.unit() * size.width, y = rng.unit() * size.height * 0.6
                    let sz = 1 + rng.unit() * 2, speed = 0.5 + rng.unit() * 2.5, phase = rng.unit() * 6.28, b = 0.5 + rng.unit() * 0.5
                    let tw = (sin(time * speed + phase) + 1) / 2
                    let a = b * (0.4 + tw * 0.6), cs = sz * (0.8 + tw * 0.2)
                    context.fill(Path(ellipseIn: CGRect(x: x - cs * 2, y: y - cs * 2, width: cs * 4, height: cs * 4)), with: .color(sky.star.opacity(a * 0.12)))
                    context.fill(Path(ellipseIn: CGRect(x: x - cs, y: y - cs, width: cs * 2, height: cs * 2)), with: .color(sky.star.opacity(a)))
                }
            }
            let auroraY = size.height * 0.15 + sin(time * 0.2) * 20
            context.fill(Path(CGRect(x: 0, y: auroraY - 60, width: size.width, height: 120)), with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: sky.auroraPurple.opacity(0.06), location: 0.4), .init(color: sky.auroraCyan.opacity(0.04), location: 0.6), .init(color: .clear, location: 1)]), startPoint: CGPoint(x: 0, y: auroraY - 60), endPoint: CGPoint(x: 0, y: auroraY + 60)))
        } else {
            bloom(sky.sun, at: orb, radius: 120, alpha: 0.45, in: &context)
            context.fill(Path(ellipseIn: CGRect(x: orb.x - 20, y: orb.y - 20, width: 40, height: 40)), with: .color(sky.sun.opacity(0.95)))
        }
        // Clouds: Kumo's three layers.
        for (speed, yPos, scale, alpha) in [(8.0, 0.12, 1.2, 0.15), (15.0, 0.22, 1.0, 0.2), (22.0, 0.08, 0.8, 0.12)] {
            let shift = parallax(speed / 22 * 0.6)
            let xOffset = (time * speed).truncatingRemainder(dividingBy: Double(size.width) * 2)
            for i in 0 ..< 3 {
                let baseX = Double(i) * Double(size.width) * 0.7 - xOffset
                let x = (baseX < -260 ? baseX + Double(size.width) * 2 : baseX) + shift.width
                let y = size.height * yPos + sin(time * 0.3 + Double(i)) * 10 + shift.height
                let w = 200 * scale, h = 60 * scale
                var cloud = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: h / 2)
                cloud.addRoundedRect(in: CGRect(x: x + w * 0.2, y: y - h * 0.3, width: w * 0.6, height: h * 0.8), cornerSize: CGSize(width: h * 0.4, height: h * 0.4))
                context.fill(cloud, with: .color(sky.cloud.opacity(alpha * (isNight ? 0.7 : 1.4))))
            }
        }
        // Weather by season.
        var wrng = SeededRNG(seed: 0x8A1)
        let m = clock.month
        if m == 12 || m <= 2 {
            for _ in 0 ..< 60 {
                let x0 = wrng.unit() * size.width, vx = -20 + wrng.unit() * 40, vy = 40 + wrng.unit() * 80
                let scale = 0.3 + wrng.unit() * 0.7, phase = wrng.unit() * 6.28, start = wrng.unit() * 12
                let t = (time + start).truncatingRemainder(dividingBy: 12)
                let x = x0 + vx * t + sin((phase + t) * 2) * 15 + parallax(0.5).width
                let y = (-20 + vy * t).truncatingRemainder(dividingBy: size.height + 40)
                context.fill(Path(ellipseIn: CGRect(x: x - 3 * scale, y: y - 3 * scale, width: 6 * scale, height: 6 * scale)), with: .color(sky.cloud.opacity((0.4 + wrng.unit() * 0.5) * (1 - t / 12 * 0.3))))
            }
        } else if m == 3 || m == 4 || m == 10 || m == 11 {
            for _ in 0 ..< 90 {
                let x0 = -20 + wrng.unit() * (size.width + 40), vx = -15 + wrng.unit() * 20, vy = 600 + wrng.unit() * 400
                let scale = 0.5 + wrng.unit() * 0.5, alpha = 0.2 + wrng.unit() * 0.3, start = wrng.unit() * 2
                let t = (time + start).truncatingRemainder(dividingBy: 2)
                let x = x0 + vx * t + parallax(0.3).width, y = (-100 + vy * t).truncatingRemainder(dividingBy: size.height + 120) - 20
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: 1.5 * scale, height: 18 * scale * 0.7), cornerRadius: 1), with: .color(sky.rain.opacity(0.6 * alpha * 0.7)))
            }
        }
    }

    // MARK: - dose.wiki

    /// dose.wiki's home page: its four page halos breathing slowly, its
    /// molecule ring large and faint behind the right half of the screen, and
    /// one node pulse walking the ring's six outer vertices.
    func drawMolecule(_ molecule: SkinMolecule, in context: inout GraphicsContext) {
        // Halos: the site's `--theme-page-halo-*`, each breathing ±20% on its
        // own phase. Their light page is near-white with barely a tint.
        let mode = dark ? 1.0 : 0.15
        let breathing = molecule.halos.enumerated().map { i, halo in
            SkinGlow(halo.color, at: halo.center, opacity: halo.opacity * mode * (0.8 + 0.2 * sin(time / 8 + Double(i) * 1.7)))
        }
        drawGlows(breathing, in: &context)

        // The ring: their logo as a template, tinted with the skin's ink.
        let shift = parallax(0.5)
        let width = size.width * 1.05
        let center = CGPoint(x: size.width * 0.66 + shift.width, y: size.height * 0.40 + sin(time / 9) * 8 + shift.height)
        var image = context.resolve(Image(molecule.image))
        image.shading = .color(molecule.ink)
        let height = width * image.size.height / image.size.width
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        context.drawLayer { layer in
            layer.opacity = dark ? 0.045 : 0.03
            layer.draw(image, in: rect)
        }

        // One pulse walking the mark's three outer nodes (right, bottom-left,
        // top-left), one node every 2.4 s.
        let radius = width * 0.43
        let step = time / 2.4
        let index = Int(step.rounded(.down)) % 3
        let fraction = step - step.rounded(.down)
        let angle = Double(index) * 2 * Double.pi / 3
        let node = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        let envelope = sin(fraction * .pi)
        context.drawLayer { layer in
            if dark { layer.blendMode = .plusLighter }
            bloom(molecule.ink, at: node, radius: 28, alpha: (dark ? 0.08 : 0.05) * envelope, in: &layer)
        }
    }
}

private nonisolated extension Path {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        applying(CGAffineTransform(translationX: dx, y: dy))
    }
}

// MARK: - Snake

/// Hebi's game, replayed for the backdrop: a snake on a grid that chases the
/// food with the three turns the real game allows, growing as it eats. It is a
/// pure function of (grid, seed, step). The whole tape is simulated once per
/// grid and kept — `tapeLength` states of at most `maxLength` cells — so a
/// frame is one array read rather than a replay of every step before it.
nonisolated struct SnakeGame {
    struct State {
        /// Head first.
        var body: [(Int, Int)]
        var food: (Int, Int)
    }

    /// Steps before the replay loops.
    static let tapeLength = 900
    static let startLength = 6
    static let maxLength = 32

    let cols: Int, rows: Int, seed: UInt64

    private struct TapeKey: Hashable {
        let cols: Int, rows: Int, seed: UInt64
    }

    /// One tape per grid: the canvas draws every frame, and a frame that
    /// replayed the game from step 0 walked up to 900 steps each time.
    private static let tapes = Mutex<[TapeKey: [State]]>([:])

    func state(atStep target: Int) -> State {
        let key = TapeKey(cols: cols, rows: rows, seed: seed)
        let step = max(0, min(target, Self.tapeLength - 1))
        if let tape = Self.tapes.withLock({ $0[key] }) { return tape[step] }
        let tape = simulateTape()
        Self.tapes.withLock { $0[key] = tape }
        return tape[step]
    }

    /// Every state from step 0 through `tapeLength - 1`, in order.
    func simulateTape() -> [State] {
        var rng = SeededRNG(seed: seed)
        var body = Self.freshSnake(cols: cols, rows: rows)
        var dir = (1, 0)
        var food = Self.placeFood(avoiding: body, cols: cols, rows: rows, rng: &rng)
        var tape: [State] = []
        tape.reserveCapacity(Self.tapeLength)
        tape.append(State(body: body, food: food))
        var step = 0
        while tape.count < Self.tapeLength {
            step += 1
            let head = body[0]
            // The three legal moves, forward first; the tail cell frees up
            // unless this step eats, so it is not an obstacle.
            let candidates = [dir, (-dir.1, dir.0), (dir.1, -dir.0)]
            var best: ((Int, Int), Int)? = nil
            for d in candidates {
                let next = (head.0 + d.0, head.1 + d.1)
                guard next.0 >= 0, next.0 < cols, next.1 >= 0, next.1 < rows else { continue }
                let eats = next == food
                let obstacle = body.dropLast(eats ? 0 : 1).contains { $0 == next }
                if obstacle { continue }
                let distance = abs(next.0 - food.0) + abs(next.1 - food.1)
                // A little waver so the path reads as play, not a ruler.
                let score = distance + (rng.unit() < 0.15 ? 2 : 0)
                if best == nil || score < best!.1 { best = (d, score) }
            }
            guard let move = best?.0 else {
                // Trapped: the round ends and a new snake starts in the middle.
                body = Self.freshSnake(cols: cols, rows: rows)
                dir = (1, 0)
                food = Self.placeFood(avoiding: body, cols: cols, rows: rows, rng: &rng)
                tape.append(State(body: body, food: food))
                continue
            }
            dir = move
            let next = (head.0 + dir.0, head.1 + dir.1)
            body.insert(next, at: 0)
            if next == food {
                if body.count > Self.maxLength { body.removeLast() }
                food = Self.placeFood(avoiding: body, cols: cols, rows: rows, rng: &rng)
            } else {
                body.removeLast()
            }
            tape.append(State(body: body, food: food))
        }
        return tape
    }

    private static func freshSnake(cols: Int, rows: Int) -> [(Int, Int)] {
        let y = rows / 2, x = cols / 2
        return (0 ..< startLength).map { (x - $0, y) }
    }

    private static func placeFood(avoiding body: [(Int, Int)], cols: Int, rows: Int, rng: inout SeededRNG) -> (Int, Int) {
        for _ in 0 ..< 64 {
            let cell = (Int(rng.next() % UInt64(max(cols, 1))), Int(rng.next() % UInt64(max(rows, 1))))
            if !body.contains(where: { $0 == cell }) { return cell }
        }
        return (0, 0)
    }
}

nonisolated extension SceneRenderer {
    // MARK: - Hanabi: the festival night

    /// The game's menu behind its `FireworkScene`: a static star field, a
    /// thin drift of sparks, and rockets that rise on a fading trail and
    /// burst in the five card suits.
    ///
    /// Four rocket slots, each on its own period. Everything about one flight
    /// — where it launches, which suit, which of the three burst shapes — is
    /// drawn from an RNG seeded on `(slot, cycle)`, so a flight is a pure
    /// function of the clock with no history kept between frames. The `.sks`
    /// scene it comes from emits particles; this cannot, so the burst is the
    /// closed form of one: radius grows as `sqrt`, gravity pulls the tail
    /// down, alpha falls off a cube.
    func drawFireworks(_ fw: SkinFireworks, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x8A0B)
        let suits = fw.suits.isEmpty ? [fw.spark] : fw.suits
        // The menu's 50 stars, white at 0.06–0.30. Night only.
        if dark {
            for _ in 0 ..< 50 {
                let depth = rng.unit()
                let shift = parallax(0.1 + depth * 0.3)
                let x = rng.unit() * size.width + shift.width
                let y = rng.unit() * size.height * 0.8 + shift.height
                let r = 0.7 + depth * 1.1
                let a = (0.06 + rng.unit() * 0.24) * (0.7 + 0.3 * sin(time * (0.5 + depth) + depth * 12))
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(fw.star.opacity(a)))
            }
        }
        // The menu's drifting sparks, thinned: the site runs 80, but they sit
        // behind copy here. Suit-coloured rather than the menu's random hue —
        // a skin never invents a colour that is not in its palette.
        if dark { context.blendMode = .plusLighter }
        for i in 0 ..< 26 {
            let phase = rng.unit()
            let depth = 0.3 + rng.unit() * 0.7
            let speed = 14 + rng.unit() * 22
            let x0 = rng.unit()
            let colour = suits[i % suits.count]
            let travel = (time * speed + phase * size.height).truncatingRemainder(dividingBy: size.height + 40)
            let y = size.height + 20 - travel
            let shift = parallax(depth * 0.6)
            let x = x0 * size.width + sin(time * 0.3 + phase * 6.28) * 16 * depth + shift.width
            let r = 0.9 + depth * 1.4
            let a = (dark ? 0.5 : 0.35) * (1 - travel / (size.height + 40)) * (0.5 + 0.5 * sin(time * 2 + phase * 6.28))
            if a < 0.02 { continue }
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y + shift.height - r, width: r * 2, height: r * 2)), with: .color(colour.opacity(a)))
        }
        // Four flights, staggered so they rarely burst together.
        for slot in 0 ..< 4 {
            let period = 5.2 + Double(slot) * 1.7
            let offset = Double(slot) * 2.3
            let t = (time + offset) / period
            let cycle = floor(t)
            let p = t - cycle
            var flight = SeededRNG(seed: 0x8A0B &+ UInt64(slot) &* 0x9E37 &+ UInt64(bitPattern: Int64(cycle)) &* 0x85EB)
            let launchX = (0.12 + flight.unit() * 0.76) * size.width
            let apexY = size.height * (0.12 + flight.unit() * 0.26)
            let colour = suits[Int(flight.unit() * Double(suits.count)) % suits.count]
            let kind = Int(flight.unit() * 3)
            let count = 58
            let riseEnd = 0.34
            let shift = parallax(0.35 + flight.unit() * 0.3)
            if p < riseEnd {
                // The rocket and its eight-node fading trail.
                let rise = p / riseEnd
                let eased = 1 - pow(1 - rise, 1.7)
                let y = size.height + 12 - (size.height + 12 - apexY) * eased
                for node in 0 ..< 8 {
                    let back = Double(node) * 0.055
                    let nodeRise = max(0, rise - back)
                    let ny = size.height + 12 - (size.height + 12 - apexY) * (1 - pow(1 - nodeRise, 1.7))
                    let a = (1 - Double(node) / 8) * 0.5 * (dark ? 1 : 0.55)
                    let r = 2.0 - Double(node) * 0.18
                    context.fill(Path(ellipseIn: CGRect(x: launchX + shift.width - r, y: ny + shift.height - r, width: r * 2, height: r * 2)), with: .color(colour.opacity(a)))
                }
                context.fill(Path(ellipseIn: CGRect(x: launchX + shift.width - 2.4, y: y + shift.height - 2.4, width: 4.8, height: 4.8)), with: .color(fw.spark.opacity(dark ? 0.9 : 0.5)))
            } else {
                // The burst. Three shapes, the way `FireworkScene` picks them:
                // a circle, a star on eight arms, and a double ring.
                let b = (p - riseEnd) / (1 - riseEnd)
                let fade = pow(1 - b, 3)
                if fade > 0.02 {
                    // Opens fast, then coasts: the shell's own easing.
                    let spread = 150.0 * (1 - pow(1 - b, 2.2))
                    let centre = CGPoint(x: launchX + shift.width, y: apexY + shift.height)
                    // The white core, brightest at the moment it opens.
                    if dark, b < 0.35 {
                        bloom(fw.spark, at: centre, radius: 38 * (1 - b / 0.35), alpha: 0.55 * (1 - b / 0.35), in: &context)
                    }
                    let a = fade * (dark ? 0.7 : 0.4)
                    if a >= 0.02 {
                        // Each spark is a short radial streak, not a dot — a ring
                        // of dots reads as a dotted circle, which is what this
                        // was before the first look at it on a device.
                        for n in 0 ..< count {
                            let angle = Double(n) / Double(count) * 6.283185
                            let reach: Double = switch kind {
                            case 0: 0.78 + (Double((n * 7) % 5) / 5) * 0.22       // circle, a little ragged
                            case 1: n % 7 == 0 ? 1.0 : 0.5                        // star: long arms
                            default: n % 2 == 0 ? 1.0 : 0.66                      // double ring
                            }
                            let dist = spread * reach
                            let gravity = 58 * b * b
                            let tail = max(6.0, dist * 0.22) * (1 - b * 0.6)
                            let inner = max(0, dist - tail)
                            let dx = cos(angle), dy = sin(angle)
                            var streak = Path()
                            streak.move(to: CGPoint(x: centre.x + dx * inner, y: centre.y + dy * inner + gravity * 0.7))
                            streak.addLine(to: CGPoint(x: centre.x + dx * dist, y: centre.y + dy * dist + gravity))
                            context.stroke(
                                streak,
                                with: .color(colour.opacity(a)),
                                style: StrokeStyle(lineWidth: (2.1 - b * 1.1) * (dark ? 1 : 0.85), lineCap: .round),
                            )
                        }
                    }
                }
            }
        }
        context.blendMode = .normal
    }
}

nonisolated extension SceneRenderer {
    // MARK: - Selenia: the engraved wheel

    /// `ChartWheel.swift` as a backdrop: concentric rules, twelve sign sectors
    /// with their ticks, the aspect chords across the middle, and the faint
    /// dome `CelestialSphereView` turns. One revolution every twelve minutes —
    /// slow enough that it reads as still, which is what an instrument should.
    func drawEphemeris(_ e: SkinEphemeris, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x5E1E)
        // The dome: a thin field of stars, no twinkle — engraved, not alive.
        for _ in 0 ..< 70 {
            let depth = rng.unit()
            let shift = parallax(0.1 + depth * 0.25)
            let x = rng.unit() * size.width + shift.width
            let y = rng.unit() * size.height + shift.height
            let r = 0.6 + depth * 0.9
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(e.star.opacity((dark ? 0.30 : 0.22) * (0.4 + depth * 0.6))),
            )
        }
        let centre = CGPoint(
            x: size.width * 0.5 + parallax(0.3).width,
            y: size.height * 0.44 + parallax(0.3).height,
        )
        let outer = min(size.width, size.height) * 0.74
        let spin = time * (2 * .pi / 720)
        let inkA = dark ? 0.28 : 0.32
        let ringA = dark ? 0.22 : 0.28

        // The plate is lit from its middle, so the wheel reads as an object
        // rather than as lines lying on the background.
        bloom(e.ring, at: centre, radius: outer * 0.95, alpha: dark ? 0.10 : 0.07, in: &context)

        // Six concentric rules: the degree ring, the zodiac band, the house
        // band, the aspect circle and the hub.
        for (i, f) in [1.0, 0.93, 0.80, 0.66, 0.44, 0.13].enumerated() {
            context.stroke(
                Path(ellipseIn: CGRect(x: centre.x - outer * f, y: centre.y - outer * f, width: outer * f * 2, height: outer * f * 2)),
                with: .color(e.ring.opacity(ringA * (i == 0 || i == 1 ? 1.25 : 0.75))),
                lineWidth: i == 0 || i == 1 ? 1.3 : 0.9,
            )
        }

        // A full 360° of degree marks, every one of them, in a single path:
        // 360 subpaths cost one stroke call, and a wheel that stops short of
        // the whole circle stops being an instrument.
        var degrees = Path()
        var fives = Path()
        for d in 0 ..< 360 {
            let a = spin + Double(d) * (.pi / 180)
            let c = cos(a), sn = sin(a)
            let long = d % 5 == 0
            let inner = outer * (long ? 0.945 : 0.962)
            let from = CGPoint(x: centre.x + c * inner, y: centre.y + sn * inner)
            let to = CGPoint(x: centre.x + c * outer, y: centre.y + sn * outer)
            if long {
                fives.move(to: from)
                fives.addLine(to: to)
            } else {
                degrees.move(to: from)
                degrees.addLine(to: to)
            }
        }
        context.stroke(degrees, with: .color(e.ring.opacity(ringA * 0.5)), lineWidth: 0.6)
        context.stroke(fives, with: .color(e.ring.opacity(ringA * 0.95)), lineWidth: 0.9)

        // Twelve sign sectors: a spoke across the bands, the sign's own glyph
        // set on the zodiac band, and its element's tick beside it.
        let signBand = outer * 0.865
        for sign in 0 ..< 12 {
            let angle = spin + Double(sign) * (.pi / 6)
            let c = cos(angle), sn = sin(angle)
            var spoke = Path()
            spoke.move(to: CGPoint(x: centre.x + c * outer * 0.66, y: centre.y + sn * outer * 0.66))
            spoke.addLine(to: CGPoint(x: centre.x + c * outer * 0.93, y: centre.y + sn * outer * 0.93))
            context.stroke(spoke, with: .color(e.ring.opacity(ringA)), lineWidth: 0.9)

            // The glyph sits at the middle of its sector, not on the spoke.
            let mid = angle + .pi / 12
            let at = CGPoint(x: centre.x + cos(mid) * signBand, y: centre.y + sin(mid) * signBand)
            if wheel.indices.contains(sign) {
                context.opacity = dark ? 0.55 : 0.5
                context.draw(wheel[sign], at: at)
                context.opacity = 1
            }
            // The element repeats fire, earth, air, water around the wheel.
            let element = e.elements.isEmpty ? e.ink : e.elements[sign % e.elements.count]
            var tick = Path()
            let tc = cos(mid), ts = sin(mid)
            tick.move(to: CGPoint(x: centre.x + tc * outer * 0.795, y: centre.y + ts * outer * 0.795))
            tick.addLine(to: CGPoint(x: centre.x + tc * outer * 0.822, y: centre.y + ts * outer * 0.822))
            context.stroke(tick, with: .color(element.opacity(dark ? 0.5 : 0.45)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }

        // The seven classical planets, each at its own longitude, with the
        // mark on the house band that a chart would draw to place it.
        var placed = SeededRNG(seed: 0x5E1E_0B17)
        for planet in 0 ..< 7 {
            let longitude = placed.unit() * 2 * .pi
            // Each drifts on its own period — the slowest barely at all.
            let a = spin + longitude + time * (2 * .pi / (900 + Double(planet) * 420))
            let c = cos(a), sn = sin(a)
            let at = CGPoint(x: centre.x + c * outer * 0.565, y: centre.y + sn * outer * 0.565)
            var stem = Path()
            stem.move(to: CGPoint(x: centre.x + c * outer * 0.645, y: centre.y + sn * outer * 0.645))
            stem.addLine(to: CGPoint(x: centre.x + c * outer * 0.665, y: centre.y + sn * outer * 0.665))
            context.stroke(stem, with: .color(e.ink.opacity(inkA)), lineWidth: 1)
            let index = WheelAtlasIndex.planets + planet
            if wheel.indices.contains(index) {
                context.opacity = dark ? 0.62 : 0.56
                context.draw(wheel[index], at: at)
                context.opacity = 1
            }
        }

        // The aspect chords across the inner circle, breathing on long phases
        // so the wheel is never quite static.
        for (i, step) in [4, 3, 6].enumerated() {
            let a = 0.5 + 0.5 * sin(time / (18 + Double(i) * 7) + Double(i) * 2)
            var chord = Path()
            for k in 0 ..< 12 where k % step == 0 {
                let a1 = spin + Double(k) * (.pi / 6)
                let a2 = spin + Double(k + step) * (.pi / 6)
                chord.move(to: CGPoint(x: centre.x + cos(a1) * outer * 0.44, y: centre.y + sin(a1) * outer * 0.44))
                chord.addLine(to: CGPoint(x: centre.x + cos(a2) * outer * 0.44, y: centre.y + sin(a2) * outer * 0.44))
            }
            context.stroke(chord, with: .color(e.ink.opacity(inkA * (0.35 + a * 0.55))), lineWidth: 0.9)
        }
    }

    // MARK: - Astrelia: the deep sky

    /// What `GalaxyShaders.metal` and `GalaxyLensing.metal` draw, in closed
    /// form: the baked emission nebulae as blooms, the dusty band across the
    /// middle, a dense fine star field, and Sgr A* — a photon ring around a
    /// dark shadow, its disc brighter on the approaching side.
    func drawDeepSky(_ sky: SkinDeepSky, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0xA57E)
        if dark { context.blendMode = .plusLighter }
        // Two nebulae, breathing on long phases.
        for (i, colour) in [sky.nebula1, sky.nebula2].enumerated() {
            let phase = time / (40 + Double(i) * 17) + Double(i) * 2.2
            let at = CGPoint(
                x: size.width * (i == 0 ? 0.24 : 0.78) + parallax(0.18).width,
                y: size.height * (i == 0 ? 0.26 : 0.66) + parallax(0.18).height,
            )
            let alpha = (dark ? 0.26 : 0.16) * (0.72 + 0.28 * sin(phase))
            bloom(colour, at: at, radius: min(size.width, size.height) * 0.62, alpha: alpha, in: &context)
        }
        context.blendMode = .normal
        // The dusty band, across its width rather than as a flat wedge: a
        // solid fill gives it two straight edges, and dust has no edges.
        let bandY = size.height * 0.54 + parallax(0.12).height
        var band = Path()
        band.move(to: CGPoint(x: -40, y: bandY + 70))
        band.addLine(to: CGPoint(x: size.width + 40, y: bandY - 110))
        band.addLine(to: CGPoint(x: size.width + 40, y: bandY - 40))
        band.addLine(to: CGPoint(x: -40, y: bandY + 140))
        band.closeSubpath()
        let dustA = dark ? 0.34 : 0.18
        context.fill(
            band,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: sky.dust.opacity(0), location: 0),
                    .init(color: sky.dust.opacity(dustA), location: 0.45),
                    .init(color: sky.dust.opacity(dustA * 0.8), location: 0.6),
                    .init(color: sky.dust.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: size.width / 2, y: bandY - 40),
                endPoint: CGPoint(x: size.width / 2, y: bandY + 80),
            ),
        )
        if dark { context.blendMode = .plusLighter }
        // The star field: dense and fine, the way an instrument plots it —
        // magnitude sets the radius, and nothing twinkles hard.
        for _ in 0 ..< 150 {
            let depth = rng.unit()
            let shift = parallax(0.08 + depth * 0.35)
            let x = rng.unit() * size.width + shift.width
            let y = rng.unit() * size.height + shift.height
            let r = 0.45 + pow(depth, 2.4) * 1.5
            let a = (0.22 + depth * 0.55) * (0.85 + 0.15 * sin(time * (0.4 + depth) + depth * 18))
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(sky.star.opacity(dark ? a : a * 0.7)),
            )
        }
        // Sgr A*: a photon ring seen near edge-on, turning once a minute.
        let hole = CGPoint(x: size.width * 0.66 + parallax(0.45).width, y: size.height * 0.3 + parallax(0.45).height)
        let rx = min(size.width, size.height) * 0.19
        let ry = rx * 0.34
        let turn = time * (2 * .pi / 60)
        // Additive over the shader's sky, so the disc reads as emitting.
        if dark { context.blendMode = .plusLighter }
        // The disc, drawn as arcs whose alpha rises on the approaching side.
        for seg in 0 ..< 48 {
            let a0 = Double(seg) / 48 * 2 * .pi
            let a1 = Double(seg + 1) / 48 * 2 * .pi
            let doppler = 0.35 + 0.65 * (0.5 + 0.5 * cos(a0 - turn))
            var arc = Path()
            arc.move(to: CGPoint(x: hole.x + cos(a0) * rx, y: hole.y + sin(a0) * ry))
            arc.addLine(to: CGPoint(x: hole.x + cos(a1) * rx, y: hole.y + sin(a1) * ry))
            context.stroke(arc, with: .color(sky.disc.opacity((dark ? 0.5 : 0.3) * doppler)), lineWidth: 3.2)
            var inner = Path()
            inner.move(to: CGPoint(x: hole.x + cos(a0) * rx * 0.88, y: hole.y + sin(a0) * ry * 0.88))
            inner.addLine(to: CGPoint(x: hole.x + cos(a1) * rx * 0.88, y: hole.y + sin(a1) * ry * 0.88))
            context.stroke(inner, with: .color(sky.disc.opacity((dark ? 0.75 : 0.4) * doppler)), lineWidth: 1.2)
        }
        context.blendMode = .normal
        // The shadow: the one place in any scene that takes light away.
        context.fill(
            Path(ellipseIn: CGRect(x: hole.x - rx * 0.42, y: hole.y - rx * 0.42, width: rx * 0.84, height: rx * 0.84)),
            with: .radialGradient(
                Gradient(colors: [.black.opacity(dark ? 0.92 : 0.5), .black.opacity(0)]),
                center: hole, startRadius: 0, endRadius: rx * 0.46,
            ),
        )
    }
}
