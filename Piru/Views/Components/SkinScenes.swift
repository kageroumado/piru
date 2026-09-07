import SwiftUI

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
            let y0 = -200 + rng.unit() * 1000
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
        // The snake: a seeded random walk on a 12pt grid in the upper half,
        // one step every .16 s, drawn as its last 12 cells.
        let cell: CGFloat = 12
        let cols = Int(size.width / cell), rows = Int(vp * 0.9 / cell)
        var walk = SeededRNG(seed: 0x5AAE)
        var path: [(Int, Int)] = []
        var pos = (cols / 2, rows / 2), dir = (1, 0)
        for _ in 0 ..< 600 {
            if walk.unit() < 0.18 { dir = walk.unit() < 0.5 ? (-dir.1, dir.0) : (dir.1, -dir.0) }
            var next = (pos.0 + dir.0, pos.1 + dir.1)
            if next.0 < 1 || next.0 >= cols - 1 || next.1 < 1 || next.1 >= rows - 1 { dir = (-dir.0, -dir.1); next = (pos.0 + dir.0, pos.1 + dir.1) }
            pos = next
            path.append(pos)
        }
        let step = Int(time / 0.16) % path.count
        let shift = parallax(0.6)
        for k in 0 ..< 12 {
            let idx = (step - k + path.count) % path.count
            let (cx, cy) = path[idx]
            let rect = CGRect(x: CGFloat(cx) * cell + 1 + shift.width, y: CGFloat(cy) * cell + 1 + shift.height, width: cell - 2, height: cell - 2)
            let head = k == 0
            let color = head ? arcade.snake : arcade.snakeBody
            if dark { bloom(color, at: CGPoint(x: rect.midX, y: rect.midY), radius: head ? 14 : 8, alpha: head ? 0.5 : 0.25, in: &context) }
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(head ? 1 : 0.85 - Double(k) * 0.04)))
            if head {
                for ex in [0.3, 0.7] {
                    context.fill(Path(CGRect(x: rect.minX + rect.width * ex - 1, y: rect.minY + 3, width: 2, height: 2)), with: .color(.black.opacity(0.8)))
                }
            }
        }
        let (fx, fy) = path[(step + 20) % path.count]
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
}

private nonisolated extension Path {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        applying(CGAffineTransform(translationX: dx, y: dy))
    }
}
