import SwiftUI

// The cast that swims behind the Jellyfish skin: rocuronium's five mascots —
// Remi, Bitjelly, Koko, Aurora and Sparkler — ported with permission from
// `~/Developer/rocuronium/Rocuronium/Presence/`, and Piru's own jelly. Every
// creature is a pure function of `(time, motion)` drawn into a `GraphicsContext`
// in its own local units; `SkinBackdrop` places, scales and tilts them. All of
// it is `nonisolated`: the canvas renders off the main thread on hardware.
//
// The mascots' colours are their own, ported verbatim from that project's
// palette (it tunes them by eye in its HTML prototypes), which is why they are
// hex literals rather than catalog tokens: they are art, not UI colour roles.

// MARK: - Motion

/// A swimmer's whole-body motion as a pure function of time, so a lagging part
/// evaluates it in the past instead of carrying a history buffer — exact under
/// a dropped frame. Offsets are in *local units* of the creature.
nonisolated struct JellyMotion {
    /// Bell pulse.
    let period: Double
    let amp: Double
    /// Idle sway, in local units.
    let sway: Double
    let swayPeriod: Double
    /// Upward travel, in local units per second.
    let rise: Double
    let phase: Double

    var contraction: (Double) -> Double {
        JellyKit.contraction
    }

    /// Where the body is at `t`, relative to its lane.
    func offset(at t: TimeInterval) -> CGPoint {
        let c = JellyKit.contraction(((t / period + phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1))
        let surge = 8 * max(0, c) * (amp / 0.3)
        return CGPoint(x: sway * sin(t * 2 * .pi / swayPeriod + phase * 6.28), y: -rise * t - surge)
    }

    /// Where the body was `age` seconds ago, relative to now.
    func lag(at t: TimeInterval, age: Double) -> CGPoint {
        let now = offset(at: t), then = offset(at: t - age)
        return CGPoint(x: then.x - now.x, y: then.y - now.y)
    }

    /// How hard the bell squeezes right now, 0 … amp.
    func squeeze(at t: TimeInterval) -> Double {
        let u = ((t / period + phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        return max(0, JellyKit.contraction(u) * amp)
    }
}

// MARK: - JellyKit

/// rocuronium's shared machinery: one contraction curve, a tapered ribbon, a
/// trail that lags behind the body, one face, and blooms that are gradients.
nonisolated enum JellyKit {
    /// A fast squeeze and a long glide back; the dip below zero at the end is
    /// the refill overshoot.
    static func contraction(_ u: Double) -> Double {
        let up = 0.26
        if u < up {
            let f = u / up
            return 1 - pow(1 - f, 3)
        }
        let v = (u - up) / (1 - up)
        let smoother = v * v * v * (v * (v * 6 - 15) + 10)
        return (1 - smoother) - 0.17 * sin(.pi * pow(v, 0.72))
    }

    /// Piecewise-smoothstep between keyframes.
    static func keyframed(_ t: Double, _ keys: [(Double, Double)]) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 1 ..< keys.count where t <= keys[i].0 {
            let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
            let f = (t - t0) / max(1e-6, t1 - t0)
            let s = f * f * (3 - 2 * f)
            return v0 + (v1 - v0) * s
        }
        return last.1
    }

    /// Trailing points that remember where the body was, so a strand lags
    /// instead of steering. Sway is zero at the root — the attachment never
    /// wobbles away from the hem.
    static func trail(
        time: TimeInterval, motion: JellyMotion, from origin: CGPoint,
        length: Double, segments: Int, sway: Double, period: Double, offset: Double,
    ) -> [CGPoint] {
        (0 ... segments).map { k in
            let t = Double(k) / Double(segments)
            let l = motion.lag(at: time, age: Double(k) * 0.045)
            let s = sin(time * 2 * .pi / period - Double(k) * 0.5 + offset) * sway * (0.03 + t * 1.1)
            return CGPoint(x: origin.x + s + l.x * 0.9, y: origin.y + t * length + l.y * 0.9)
        }
    }

    /// A tapered ribbon as a filled outline, so the tip actually vanishes.
    static func ribbon(_ points: [CGPoint], _ w0: Double, _ w1: Double) -> Path {
        guard points.count > 1 else { return Path() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in points.indices {
            let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let m = max(hypot(dx, dy), 1e-6)
            dx /= m; dy /= m
            let w = (w0 + (w1 - w0) * Double(i) / Double(points.count - 1)) / 2
            left.append(CGPoint(x: points[i].x - dy * w, y: points[i].y + dx * w))
            right.append(CGPoint(x: points[i].x + dy * w, y: points[i].y - dx * w))
        }
        var path = Path()
        path.move(to: left[0])
        for p in left.dropFirst() {
            path.addLine(to: p)
        }
        for p in right.reversed() {
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    /// A point on a cubic — so a hem that was drawn can also be walked, and a
    /// root lands exactly on it.
    static func bez3(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ s: Double) -> CGPoint {
        let m = 1 - s
        let a = m * m * m, b = 3 * m * m * s, c = 3 * m * s * s, d = s * s * s
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// A radial bloom that reaches zero at its own edge — every soft glow in
    /// the cast, because a gradient reads as light and a disc reads as a disc.
    static func bloom(in ctx: inout GraphicsContext, at c: CGPoint, rx: Double, ry: Double, color: Color, opacity: Double) {
        guard opacity > 0.004 else { return }
        ctx.fill(
            ellipse(c.x, c.y, rx, ry),
            with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]), center: c, startRadius: 0, endRadius: max(rx, ry)),
        )
    }

    /// One face across the cast: two lit eyes with a wandering glint, a slow
    /// blink, a blush behind them.
    static func face(in ctx: inout GraphicsContext, time: TimeInterval, at p: CGPoint, spread: Double, r: Double, ink: Color, glint: Color?, blush: Color?) {
        let blink = (time / 3.9).truncatingRemainder(dividingBy: 1) < 0.05
        let hh = max(r * (blink ? 0.12 : 1), 0.05)
        let gaze = CGPoint(x: 0.22 * r * sin(time * 2 * .pi / 3.1), y: 0.14 * r * sin(time * 2 * .pi / 4.3))
        if let blush {
            for side in [-1.0, 1.0] {
                ctx.fill(ellipse(p.x + side * (spread + r * 1.05), p.y + r * 1.05, r * 0.68, r * 0.46), with: .color(blush))
            }
        }
        for side in [-1.0, 1.0] {
            let ex = p.x + side * spread
            ctx.fill(ellipse(ex, p.y, r, hh), with: .color(ink))
            if !blink, let glint {
                ctx.fill(ellipse(ex + gaze.x + r * 0.26, p.y + gaze.y - r * 0.3, r * 0.3, r * 0.3), with: .color(glint))
            }
        }
    }

    /// The ambient light level: a slow breath, brighter than the mascot's idle
    /// because down here the creature is the lamp.
    static func light(_ time: TimeInterval) -> Double {
        0.5 + 0.2 * sin(time * 2 * .pi / 3.2)
    }
}

private nonisolated extension Color {
    /// `0xRRGGBB`, so a colour tuned by eye in rocuronium's prototypes is
    /// verbatim the same colour here.
    init(jelly hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Species

/// Who can be in the water. Each draws in its own local units; `bellWidth` is
/// how wide its bell is in those units, so a placer can size it.
nonisolated enum JellySpecies: CaseIterable, Sendable {
    /// Remi — the smooth original: soft bell, five lagging tentacles.
    case remi
    /// The 14×18 sprite, four frames.
    case bitjelly
    /// Koko — a pearl sheet with a hem that never holds still.
    case koko
    /// A clear bell with a curtain of aurora standing up inside it.
    case aurora
    /// The flower hat jelly: pinstripes, beads of light running down the legs.
    case sparkler
    /// Piru's own: a dome with a scalloped hem, ribbons, oral arms, sleepy eyes.
    case piru

    var bellWidth: Double {
        switch self {
        case .remi: 49
        case .bitjelly: 54.6
        case .koko: 16.5
        case .aurora: 15.8
        case .sparkler: 12.2
        case .piru: 36
        }
    }

    /// The pulse each creature was tuned to.
    var beat: (period: Double, amp: Double) {
        switch self {
        case .remi: (1.6, 0.3)
        case .bitjelly: (2.4, 0.6)
        case .koko: (4.0, 0.28)
        case .aurora: (3.0, 0.46)
        case .sparkler: (3.2, 0.44)
        case .piru: (1.5, 0.3)
        }
    }

    /// Draws the creature with its bell centred near the origin. `bell` is the
    /// colour the placer cycles through; species with their own palette use it
    /// only as a tint.
    func draw(in ctx: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, bell: Color, dark: Bool, showFace: Bool) {
        switch self {
        case .remi: Remi.draw(in: &ctx, time: time, motion: motion, dark: dark, showFace: showFace)
        case .bitjelly: Bitjelly.draw(in: &ctx, time: time, motion: motion, dark: dark, showFace: showFace)
        case .koko: Koko.draw(in: &ctx, time: time, motion: motion, dark: dark, showFace: showFace)
        case .aurora: Aurora.draw(in: &ctx, time: time, motion: motion, dark: dark, showFace: showFace)
        case .sparkler: Sparkler.draw(in: &ctx, time: time, motion: motion, dark: dark, showFace: showFace)
        case .piru: PiruJelly.draw(in: &ctx, time: time, motion: motion, bell: bell, dark: dark, showFace: showFace)
        }
    }
}

// MARK: - Remi (classic)

private nonisolated enum Remi {
    nonisolated enum P {
        static let bellTop = Color(jelly: 0xEDEFFF)
        static let bellMid = Color(jelly: 0x8B88FF)
        static let bellRim = Color(jelly: 0x58E0F5)
        static let pink = Color(jelly: 0xFF9BDD)
        static let eye = Color(jelly: 0x262664)
        static let glow = Color(jelly: 0x789BFF)
    }

    struct Tentacle {
        let start: CGPoint
        let curves: [(c1: CGPoint, c2: CGPoint, to: CGPoint)]
        var path: Path {
            var path = Path()
            path.move(to: start)
            for curve in curves {
                path.addCurve(to: curve.to, control1: curve.c1, control2: curve.c2)
            }
            return path
        }
    }

    static let tentacles: [Tentacle] = [
        .init(start: .init(x: 17, y: 43), curves: [
            (.init(x: 15.5, y: 52), .init(x: 19, y: 59), .init(x: 15.5, y: 68)),
            (.init(x: 14, y: 72.5), .init(x: 16, y: 77), .init(x: 14.5, y: 80)),
        ]),
        .init(start: .init(x: 24.5, y: 44.5), curves: [
            (.init(x: 24, y: 54), .init(x: 21.5, y: 60), .init(x: 24.5, y: 69)),
            (.init(x: 25.8, y: 73), .init(x: 24, y: 77.5), .init(x: 25, y: 81)),
        ]),
        .init(start: .init(x: 32, y: 45), curves: [
            (.init(x: 32.5, y: 55), .init(x: 30, y: 62), .init(x: 33, y: 71)),
            (.init(x: 34, y: 74.5), .init(x: 32.5, y: 79), .init(x: 33.5, y: 82)),
        ]),
        .init(start: .init(x: 39.5, y: 44.5), curves: [
            (.init(x: 40.5, y: 54), .init(x: 38, y: 60), .init(x: 41, y: 68)),
            (.init(x: 42.3, y: 72), .init(x: 40.5, y: 76.5), .init(x: 41.5, y: 80)),
        ]),
        .init(start: .init(x: 47, y: 43), curves: [
            (.init(x: 48.5, y: 52), .init(x: 45.5, y: 59), .init(x: 48.5, y: 67)),
            (.init(x: 50, y: 71), .init(x: 48.5, y: 75.5), .init(x: 49.5, y: 79)),
        ]),
    ]

    static let bellPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 32, y: 7))
        path.addCurve(to: CGPoint(x: 7.5, y: 31), control1: CGPoint(x: 16, y: 7), control2: CGPoint(x: 7.5, y: 20))
        path.addCurve(to: CGPoint(x: 17, y: 41), control1: CGPoint(x: 7.5, y: 37), control2: CGPoint(x: 12, y: 40.5))
        path.addCurve(to: CGPoint(x: 32, y: 42), control1: CGPoint(x: 22, y: 41.5), control2: CGPoint(x: 26.5, y: 42))
        path.addCurve(to: CGPoint(x: 47, y: 41), control1: CGPoint(x: 37.5, y: 42), control2: CGPoint(x: 42, y: 41.5))
        path.addCurve(to: CGPoint(x: 56.5, y: 31), control1: CGPoint(x: 52, y: 40.5), control2: CGPoint(x: 56.5, y: 37))
        path.addCurve(to: CGPoint(x: 32, y: 7), control1: CGPoint(x: 56.5, y: 20), control2: CGPoint(x: 48, y: 7))
        path.closeSubpath()
        return path
    }()

    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, dark: Bool, showFace: Bool) {
        // The 64×84 design box, bell centred at (32, 25).
        var body = context
        body.translateBy(x: -32, y: -25)
        let t = ((time / 1.25 + motion.phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)

        // Halo.
        if dark { body.blendMode = .plusLighter }
        JellyKit.bloom(in: &body, at: CGPoint(x: 32, y: 26), rx: 34 + 4 * (0.5 + 0.5 * sin(time * 2 * .pi / 1.6)), ry: 34, color: P.glow, opacity: (dark ? 0.5 : 0.22) * 0.55)
        body.blendMode = .normal

        // Tentacles first, behind the bell, each on its own period; the swing
        // is a rotation about the root, so the root never leaves the hem.
        let periods = [3.1, 3.5, 2.9, 3.4, 3.2]
        let offsets = [0.0, 0.35, 0.6, 0.2, 0.5]
        let gradient = Gradient(colors: [P.bellRim, P.bellMid, P.pink])
        for (index, tentacle) in tentacles.enumerated() {
            let period = periods[index] * 0.6
            let sway = 3.5 * sin((time + offsets[index] + motion.phase) * 2 * .pi / period)
            var tctx = body
            tctx.translateBy(x: tentacle.start.x, y: tentacle.start.y)
            tctx.rotate(by: .degrees(sway))
            tctx.translateBy(x: -tentacle.start.x, y: -tentacle.start.y)
            tctx.stroke(
                tentacle.path,
                with: .linearGradient(gradient, startPoint: CGPoint(x: tentacle.start.x, y: 43), endPoint: CGPoint(x: tentacle.start.x, y: 82)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round),
            )
        }

        // The bell, squashing and stretching on the beat.
        var bell = body
        let sx = JellyKit.keyframed(t, [(0, 1), (0.16, 1.14), (0.42, 0.93), (0.7, 1.02), (1, 1)])
        let sy = JellyKit.keyframed(t, [(0, 1), (0.16, 0.8), (0.42, 1.09), (0.7, 0.98), (1, 1)])
        bell.translateBy(x: 32, y: 21)
        bell.scaleBy(x: sx, y: sy)
        bell.translateBy(x: -32, y: -21)
        bell.fill(
            bellPath,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: P.bellTop.opacity(0.92), location: 0),
                    .init(color: P.bellMid.opacity(0.92), location: 0.46),
                    .init(color: P.bellRim.opacity(0.92), location: 0.88),
                ]),
                center: CGPoint(x: 32, y: 16), startRadius: 0, endRadius: 40,
            ),
        )
        bell.fill(Path(ellipseIn: CGRect(x: 17, y: 13, width: 30, height: 22)), with: .color(.white.opacity(0.22)))

        guard showFace else { return }
        let blinkPhase = (time / 4.4 + motion.phase).truncatingRemainder(dividingBy: 1)
        let blink = blinkPhase < 0.055 ? sin(blinkPhase / 0.055 * .pi) : 0
        let gazeX = 0.6 * sin(time * 2 * .pi / 3.1), gazeY = 0.4 * sin(time * 2 * .pi / 4.3)
        let eyeRadius = 2.6
        let eyeHeight = eyeRadius * (1 - 0.85 * blink)
        for eyeX in [26.0, 38.0] {
            bell.fill(Path(ellipseIn: CGRect(x: eyeX - eyeRadius, y: 32.5 - eyeHeight, width: eyeRadius * 2, height: eyeHeight * 2)), with: .color(P.eye))
            if blink < 0.5 {
                bell.fill(Path(ellipseIn: CGRect(x: eyeX + 0.05 + gazeX, y: 30.75 + gazeY * 0.8, width: 1.7, height: 1.7)), with: .color(.white))
            }
        }
        for cheekX in [20.5, 43.5] {
            bell.fill(Path(ellipseIn: CGRect(x: cheekX - 1.5, y: 34.5, width: 3, height: 3)), with: .color(P.pink.opacity(0.7)))
        }
    }
}

// MARK: - Bitjelly

private nonisolated enum Bitjelly {
    static let gridW = 14
    static let cell = 3.9
    static let originX = 32.0 - Double(gridW) * cell / 2
    static let originY = 6.0

    /// `1` bell, `2` a light pixel on the bell, `.` open water. Row 8 is the hem.
    static let frames: [[String]] = [
        ["..1111111111..", ".111111111111.", "11111111111111", "12111111111121", "11111111111111", "11111111111111", "11211111111211", "11111111111111", ".1.11.11.11.1.", ".............."],
        ["...11111111...", "..1111111111..", ".111111111111.", "11211111111211", "11111111111111", "11111111111111", "11211111111211", ".111111111111.", "...11.11.11...", ".............."],
        ["....111111....", "...11111111...", "..1111111111..", ".112111111211.", ".111111111111.", ".111111111111.", ".112111111211.", "..1111111111..", "....1.11.1....", ".............."],
        [".111111111111.", "11111111111111", "11111111111111", "12111111111121", "11111111111111", "11111111111111", "11211111111211", "11111111111111", ".1.11.11.11.1.", ".............."],
    ]
    static let glyphCore: [(r: Int, q: Int)] = [(1, 6), (1, 7), (2, 6), (2, 7)]
    static let glyphRing: [(r: Int, q: Int)] = [(0, 6), (0, 7), (1, 5), (1, 8), (2, 5), (2, 8), (3, 6), (3, 7)]
    static let strandCols = [1, 4, 6, 7, 9, 12]
    static let eyeRow = 4
    static let eyeCols = [4, 9]

    static func rect(_ q: Int, _ r: Int, rows: Int = 1) -> CGRect {
        CGRect(x: originX + Double(q) * cell, y: originY + Double(r) * cell, width: cell, height: cell * Double(rows))
    }

    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, dark: Bool, showFace: Bool) {
        var ctx = context
        ctx.translateBy(x: -32, y: -25)
        let period = 2.4, amp = 0.6
        let u = ((time / period + motion.phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let raw = JellyKit.contraction(u) * amp
        let c = max(0, raw)
        let frameIndex = c > 0.43 ? 2 : (c > 0.2 ? 1 : (u > 0.88 ? 3 : 0))
        let grid = frames[frameIndex].map(Array.init)
        let light = Remi.P.bellRim
        // The glyph ripples outward on a slow clock.
        let w = ((time / 3.4).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        func bump(_ off: Double) -> Double {
            max(0, 1 - ((w - off + 1).truncatingRemainder(dividingBy: 1)) * 3.4)
        }
        let levels = (core: max(0.35, bump(0)), ring: max(0.1, bump(0.16)), edge: max(0.1, bump(0.32)))

        if dark { ctx.blendMode = .plusLighter }
        JellyKit.bloom(in: &ctx, at: CGPoint(x: 32, y: 26), rx: 36, ry: 36, color: Remi.P.glow, opacity: (dark ? 0.45 : 0.2) * 0.55)
        ctx.blendMode = .normal

        var bell = Path(), edgeLights = Path()
        for r in grid.indices {
            for q in grid[r].indices {
                let ch = grid[r][q]
                guard ch != "." else { continue }
                bell.addRect(rect(q, r))
                if ch == "2" { edgeLights.addRect(rect(q, r)) }
            }
        }
        ctx.fill(bell, with: .color(Remi.P.bellMid.opacity(0.94)))
        ctx.fill(edgeLights, with: .color(light.opacity(0.20 + 0.75 * levels.edge)))
        for (cells, level) in [(glyphRing, levels.ring), (glyphCore, levels.core)] {
            var path = Path()
            for spot in cells where spot.r < grid.count && grid[spot.r][spot.q] != "." {
                path.addRect(rect(spot.q, spot.r))
            }
            ctx.fill(path, with: .color(light.opacity(0.12 + 0.83 * level)))
        }
        if showFace {
            let blink = (time / 3.6 + motion.phase).truncatingRemainder(dividingBy: 1) < 0.05
            var eyes = Path()
            for q in eyeCols {
                eyes.addRect(rect(q, blink ? eyeRow + 1 : eyeRow, rows: blink ? 1 : 2))
            }
            ctx.fill(eyes, with: .color(Remi.P.eye.opacity(0.95)))
        }

        // Strands hang from the hem's real cells, one column of travel per link.
        let hem = grid[8]
        let hemCells = hem.indices.filter { hem[$0] != "." }
        guard let hemMin = hemCells.first, let hemMax = hemCells.last else { return }
        let hemCentre = Double(hemMin + hemMax) / 2
        let hemHalf = max(0.5, Double(hemMax - hemMin) / 2)
        let restCentre = 6.5, restHalf = 5.5
        for k in 0 ..< 7 {
            var path = Path()
            let l = motion.lag(at: time, age: Double(k + 1) * 0.049)
            let alpha = max(0.12, 0.85 - Double(k) * 0.09)
            for (i, restCol) in strandCols.enumerated() {
                if (k + i) % 4 == 3 { continue }
                let wanted = hemCentre + (Double(restCol) - restCentre) * (hemHalf / restHalf)
                var root = hemCells[0]
                for q in hemCells where abs(Double(q) - wanted) < abs(Double(root) - wanted) {
                    root = q
                }
                var col = root
                for step in 0 ... k {
                    let sway = sin(time * 2 * .pi * 0.6 / (2.4 + Double(i) * 0.3) - Double(step) * 0.7)
                    let want = Double(root) + sway * 1.5 + l.x * 0.35
                    if want > Double(col) + 0.5 { col += 1 } else if want < Double(col) - 0.5 { col -= 1 }
                    col = min(max(col, 0), gridW - 1)
                }
                var cellRect = rect(col, 9 + k)
                cellRect.origin.y += l.y * 0.3
                path.addRect(cellRect)
            }
            ctx.fill(path, with: .color(Remi.P.bellRim.opacity(alpha)))
        }
    }
}

// MARK: - Koko (ghost)

private nonisolated enum Koko {
    nonisolated enum P {
        static let veil = Color(jelly: 0xF1EDFF)
        static let core = Color(jelly: 0xFFFFFF)
        static let deep = Color(jelly: 0xA9A2DC)
        static let eye = Color(jelly: 0x2B2450)
        static let blush = Color(jelly: 0xFF96BE, opacity: 0.36)
    }

    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, dark: Bool, showFace: Bool) {
        var ctx = context
        let c = motion.squeeze(at: time)
        let lev = JellyKit.light(time)
        let tint = P.veil
        let w = 7.8 * (1 - 0.10 * c)
        let h = 6.6 * (1 + 0.13 * c)
        let s = 11.5 * (1 - 0.10 * c)
        let lag = motion.lag(at: time, age: 0.07)
        let waist = s * 0.38, wb = w * 1.06
        let dx = lag.x * 0.35, dy = lag.y * 0.40
        let lobes = 5
        let rest = waist + (s - waist) * 0.52
        func wave(_ off: Double) -> Double {
            sin(time * 2 * .pi / 3.0 - off + motion.phase * 6.28)
        }
        let tilt = wave(0) * 0.058

        // Wisps, drawn where the body used to be.
        for layer in [1, 0] {
            let l = motion.lag(at: time, age: 0.16 + Double(layer) * 0.13)
            let k = 1.10 + Double(layer) * 0.22
            JellyKit.bloom(in: &ctx, at: CGPoint(x: l.x, y: -h * 0.3 + l.y + s * 0.25), rx: w * k * 1.5, ry: (h + s * 0.5) * k, color: tint, opacity: (dark ? 0.10 : 0.06) - Double(layer) * 0.03)
        }
        ctx.translateBy(x: 0, y: waist)
        ctx.rotate(by: .radians(tilt))
        ctx.translateBy(x: 0, y: -waist)

        let shoulderL = wave(0.75) * 0.80, shoulderR = wave(-0.75) * 0.80
        let crown = wave(0.25) * 0.70
        let apexY = -h * 1.58 + crown * 0.8
        var body = Path()
        body.move(to: CGPoint(x: -wb + dx, y: waist + dy))
        body.addCurve(to: CGPoint(x: crown * 1.3, y: apexY), control1: CGPoint(x: -wb * 1.03, y: -h * 0.90 + shoulderL), control2: CGPoint(x: -w * 0.60, y: apexY))
        body.addCurve(to: CGPoint(x: wb + dx, y: waist + dy), control1: CGPoint(x: w * 0.60, y: apexY), control2: CGPoint(x: wb * 1.03, y: -h * 0.90 + shoulderR))
        for lobe in 0 ..< lobes {
            let x0 = JellyKit.lerp(wb, -wb, Double(lobe) / Double(lobes))
            let x1 = JellyKit.lerp(wb, -wb, Double(lobe + 1) / Double(lobes))
            let span = x0 - x1
            let swell = wave(1.7 + Double(lobe) * 0.52) * 1.5
            let tip = (lobe.isMultiple(of: 2) ? s * 0.84 : s) + swell
            let last = lobe == lobes - 1
            let nx = last ? -wb : x1
            let ny = last ? waist : rest + wave(2.0 + Double(lobe) * 0.52) * 0.9
            body.addCurve(
                to: CGPoint(x: nx + dx, y: ny + dy),
                control1: CGPoint(x: x0 - span * 0.50 + lag.x * 0.8, y: tip + lag.y * 0.9),
                control2: CGPoint(x: nx + span * 0.50 + lag.x * 0.8, y: tip + lag.y * 0.9),
            )
        }
        body.closeSubpath()
        ctx.fill(
            body,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: P.core.opacity(0.74 + 0.24 * lev), location: 0),
                    .init(color: tint.opacity(0.58 + 0.20 * lev), location: 0.32),
                    .init(color: tint.opacity(0.36), location: 0.60),
                    .init(color: P.deep.opacity(0.17), location: 0.84),
                    .init(color: P.deep.opacity(0.01), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: -h * 1.58), endPoint: CGPoint(x: 0, y: s * 1.04),
            ),
        )
        if dark { ctx.blendMode = .plusLighter }
        JellyKit.bloom(in: &ctx, at: CGPoint(x: 0, y: -h * 0.40), rx: w * 2.3, ry: h * 2.3, color: tint, opacity: (dark ? 0.26 : 0.12) * lev)
        ctx.blendMode = .normal
        JellyKit.bloom(in: &ctx, at: CGPoint(x: crown * 1.1, y: -h * 0.88 + crown * 0.7), rx: w * 0.80, ry: h * 0.56, color: P.core, opacity: 0.30 + 0.18 * lev)
        if showFace {
            JellyKit.face(in: &ctx, time: time + motion.phase * 3, at: CGPoint(x: crown * 0.5, y: -h * 0.44 + crown * 0.3), spread: w * 0.32, r: 1.30, ink: P.eye.opacity(0.90), glint: Color.white.opacity(0.95), blush: P.blush)
        }
    }
}

// MARK: - Aurora

private nonisolated enum Aurora {
    nonisolated enum P {
        static let glass = Color(jelly: 0x7FCDE8)
        static let rim = Color(jelly: 0xEAFBFF)
        static let fringe = Color(jelly: 0xFF3DC4)
        static let green = Color(jelly: 0x22FF9B)
        static let teal = Color(jelly: 0x2FE3FF)
        static let crown = Color(jelly: 0xB44BFF)
        static let tent = Color(jelly: 0xCFF3FF)
        static let ink = Color(jelly: 0x0E2430)
        static let blush = Color(jelly: 0x5ADCBE, opacity: 0.30)
    }

    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, dark: Bool, showFace: Bool) {
        var ctx = context
        let c = motion.squeeze(at: time)
        let lev = JellyKit.light(time)
        let spd = 0.6
        let w = 8.4 * (1 - 0.12 * c)
        let h = 7.6 * (1 + 0.15 * c)
        let sagY = h * 0.24 * 1.15
        let rimX = w * 0.94
        let hem = [CGPoint(x: rimX, y: 0), CGPoint(x: w * 0.58, y: sagY), CGPoint(x: -w * 0.58, y: sagY), CGPoint(x: -rimX, y: 0)]
        func rootAt(_ u: Double) -> CGPoint {
            JellyKit.bez3(hem[0], hem[1], hem[2], hem[3], u)
        }
        var bell = Path()
        bell.move(to: CGPoint(x: -rimX, y: 0))
        bell.addCurve(to: CGPoint(x: 0, y: -h * 1.30), control1: CGPoint(x: -w * 1.08, y: -h * 0.44), control2: CGPoint(x: -w * 0.78, y: -h * 1.30))
        bell.addCurve(to: CGPoint(x: rimX, y: 0), control1: CGPoint(x: w * 0.78, y: -h * 1.30), control2: CGPoint(x: w * 1.08, y: -h * 0.44))
        bell.addCurve(to: hem[3], control1: hem[1], control2: hem[2])
        bell.closeSubpath()

        // Tendrils first; the bell lands on their roots and the join disappears.
        let legs = 9
        for n in 0 ..< legs {
            let u = 0.07 + Double(n) * (0.86 / Double(legs - 1))
            let root = rootAt(u)
            let l = 13.0 * (0.54 + 0.46 * sin(u * .pi)) * (0.86 + 0.28 * Double((n * 7) % 5) / 5)
            let pts = JellyKit.trail(time: time, motion: motion, from: CGPoint(x: root.x, y: root.y - 0.6), length: l, segments: 24, sway: 1.5 + 0.9 * sin(u * .pi), period: 2.4 + Double(n) * 0.31, offset: Double(n) * 0.77 + motion.phase)
            ctx.fill(JellyKit.ribbon(pts, 0.78, 0.02), with: .color(P.tent.opacity(0.26)))
            let hue: Color = u < 0.40 ? P.green : (u > 0.60 ? P.crown : P.teal)
            for pass in 0 ..< 3 {
                let cut = Int((Double(pts.count) * (0.46 - Double(pass) * 0.13)).rounded(.up))
                ctx.fill(JellyKit.ribbon(Array(pts.prefix(max(2, cut))), 0.52, 0.05), with: .color(hue.opacity(0.09 + 0.18 * lev)))
            }
        }

        var inside = ctx
        inside.clip(to: bell)
        inside.fill(bell, with: .linearGradient(Gradient(colors: [P.rim.opacity(0.34), P.glass.opacity(0.14)]), startPoint: CGPoint(x: 0, y: -h * 1.30), endPoint: CGPoint(x: 0, y: h * 0.3)))
        var curtain = inside
        if dark { curtain.blendMode = .plusLighter }
        let bands = 16
        let floor = sagY * 0.72
        let span = w * 1.88
        for b in 0 ..< bands {
            let t = Double(b) / Double(bands - 1)
            let x = JellyKit.lerp(-w * 0.92, w * 0.92, t)
            let bw = span / Double(bands) * 1.25
            let ph = time * spd * 1.05 + t * 4.0 + motion.phase * 6.28
            let tall = (0.82 + 0.18 * pow(max(0, sin(ph)), 1.3)) * h * 1.56
            let intensity = (0.34 + 0.66 * lev) * (0.42 + 0.58 * pow(max(0, sin(ph + 0.6)), 1.1)) * (dark ? 1 : 0.75)
            curtain.fill(
                Path(CGRect(x: x - bw / 2, y: floor - tall, width: bw, height: tall)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: P.fringe.opacity(0.30 * intensity), location: 0),
                        .init(color: P.fringe.opacity(0.95 * intensity), location: 0.06),
                        .init(color: P.green.opacity(1.00 * intensity), location: 0.20),
                        .init(color: P.green.opacity(0.88 * intensity), location: 0.46),
                        .init(color: P.teal.opacity(0.60 * intensity), location: 0.66),
                        .init(color: P.crown.opacity(0.34 * intensity), location: 0.86),
                        .init(color: P.crown.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: floor), endPoint: CGPoint(x: 0, y: floor - tall),
                ),
            )
        }
        JellyKit.bloom(in: &inside, at: CGPoint(x: -w * 0.22, y: -h * 1.00), rx: w * 0.92, ry: w * 0.92, color: P.rim, opacity: 0.32)
        ctx.stroke(bell, with: .color(P.rim.opacity(0.50)), lineWidth: 0.42)
        if showFace {
            JellyKit.face(in: &ctx, time: time + motion.phase * 3, at: CGPoint(x: 0, y: -h * 0.40), spread: w * 0.28, r: 1.16, ink: P.ink.opacity(0.88), glint: Color(jelly: 0xF0FFFF, opacity: 0.95), blush: P.blush)
        }
    }
}

// MARK: - Sparkler

private nonisolated enum Sparkler {
    nonisolated enum P {
        static let hi = Color(jelly: 0xFFE9F4)
        static let bell = Color(jelly: 0xF79ACB)
        static let deep = Color(jelly: 0xB8478F)
        static let tent = Color(jelly: 0xF9C2DF)
        static let bead = Color(jelly: 0xFFFAFD)
        static let beadGlow = Color(jelly: 0xFF9FD8)
        static let ink = Color(jelly: 0x3D0F2C)
        static let blush = Color(jelly: 0xE2488C, opacity: 0.30)
    }

    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, dark: Bool, showFace: Bool) {
        var ctx = context
        let c = motion.squeeze(at: time)
        let lev = JellyKit.light(time)
        let spd = 0.7
        let w = 6.9 * (1 - 0.11 * c)
        let h = 6.0 * (1 + 0.16 * c)
        let sagY = h * 0.19 * 1.30
        let rimX = w * 0.88
        let hem = [CGPoint(x: rimX, y: 0), CGPoint(x: w * 0.55, y: sagY), CGPoint(x: -w * 0.55, y: sagY), CGPoint(x: -rimX, y: 0)]
        func rootAt(_ u: Double) -> CGPoint {
            JellyKit.bez3(hem[0], hem[1], hem[2], hem[3], u)
        }
        var bell = Path()
        bell.move(to: CGPoint(x: -rimX, y: 0))
        bell.addCurve(to: CGPoint(x: 0, y: -h * 1.34), control1: CGPoint(x: -w * 1.06, y: -h * 0.52), control2: CGPoint(x: -w * 0.86, y: -h * 1.34))
        bell.addCurve(to: CGPoint(x: rimX, y: 0), control1: CGPoint(x: w * 0.86, y: -h * 1.34), control2: CGPoint(x: w * 1.06, y: -h * 0.52))
        bell.addCurve(to: hem[3], control1: hem[1], control2: hem[2])
        bell.closeSubpath()

        let legs = 9, beads = 3
        for n in 0 ..< legs {
            let u = 0.07 + Double(n) * (0.86 / Double(legs - 1))
            let root = rootAt(u)
            let l = 12.5 * (0.60 + 0.40 * sin(u * .pi))
            let pts = JellyKit.trail(time: time, motion: motion, from: CGPoint(x: root.x, y: root.y - 0.4), length: l, segments: 22, sway: 1.5, period: 2.6 + Double(n) * 0.27, offset: Double(n) * 0.8 + motion.phase)
            ctx.fill(JellyKit.ribbon(pts, 0.55, 0.02), with: .color(P.tent.opacity(0.40)))
            for b in 0 ..< beads {
                let f = ((time * spd * 0.42 - Double(b) / Double(beads) - Double(n) * 0.11 + motion.phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                let idx = f * Double(pts.count - 1)
                let i0 = min(pts.count - 1, max(0, Int(idx)))
                let fr = idx - Double(i0)
                let p0 = pts[i0], p1 = pts[min(pts.count - 1, i0 + 1)]
                let at = CGPoint(x: JellyKit.lerp(p0.x, p1.x, fr), y: JellyKit.lerp(p0.y, p1.y, fr))
                let env = sin(f * .pi)
                let a = (0.42 + 0.58 * lev) * env
                guard a > 0.04 else { continue }
                let r = 0.28 + 0.36 * env
                if dark { ctx.blendMode = .plusLighter }
                JellyKit.bloom(in: &ctx, at: at, rx: r * 4.2, ry: r * 4.2, color: P.beadGlow, opacity: 0.55 * a)
                ctx.blendMode = .normal
                ctx.fill(JellyKit.ellipse(at.x, at.y, r, r), with: .color(P.bead.opacity(min(1, a))))
            }
            if let tip = pts.last {
                let ta = 0.30 + 0.45 * lev
                JellyKit.bloom(in: &ctx, at: tip, rx: 1.5, ry: 1.5, color: P.beadGlow, opacity: 0.55 * ta)
                ctx.fill(JellyKit.ellipse(tip.x, tip.y, 0.26, 0.26), with: .color(P.bead.opacity(ta)))
            }
        }

        var inside = ctx
        inside.clip(to: bell)
        inside.fill(
            bell,
            with: .radialGradient(
                Gradient(stops: [.init(color: P.hi.opacity(0.97), location: 0), .init(color: P.bell.opacity(0.94), location: 0.46), .init(color: P.deep.opacity(0.92), location: 1)]),
                center: CGPoint(x: -w * 0.26, y: -h * 1.10), startRadius: 0.4, endRadius: w * 1.8,
            ),
        )
        inside.fill(bell, with: .linearGradient(Gradient(colors: [P.beadGlow.opacity(0.50 * lev), P.beadGlow.opacity(0)]), startPoint: CGPoint(x: 0, y: sagY), endPoint: CGPoint(x: 0, y: -h * 0.55)))
        for k in 0 ..< 15 {
            let t = Double(k) / 14 * 2 - 1
            var stripe = Path()
            stripe.move(to: CGPoint(x: t * w * 0.05, y: -h * 1.30))
            stripe.addQuadCurve(to: CGPoint(x: t * rimX * 1.03, y: 0.3), control: CGPoint(x: t * w * 0.66, y: -h * 0.80))
            inside.stroke(stripe, with: .color(P.deep.opacity(0.30)), lineWidth: 0.32)
        }
        ctx.stroke(bell, with: .color(P.hi.opacity(0.52)), lineWidth: 0.45)
        if showFace {
            JellyKit.face(in: &ctx, time: time + motion.phase * 3, at: CGPoint(x: 0, y: -h * 0.44), spread: w * 0.30, r: 1.14, ink: P.ink.opacity(0.90), glint: Color(jelly: 0xFFF7FB, opacity: 0.95), blush: P.blush)
        }
    }
}

// MARK: - Piru's own

/// The jelly the skin shipped with: a dome with a scalloped hem, five tapered
/// ribbons and two frilly oral arms hanging from the hem the bell is drawing
/// this frame, a rim highlight, sleepy eyes. Bell colour comes from the water.
private nonisolated enum PiruJelly {
    static func draw(in context: inout GraphicsContext, time: TimeInterval, motion: JellyMotion, bell color: Color, dark: Bool, showFace: Bool) {
        var ctx = context
        let c = motion.squeeze(at: time) / max(0.001, motion.amp)
        let w = 18 * (1 - 0.14 * c)
        let h = 15 * (1 + 0.16 * c)
        let sagY = h * 0.32 * (1 + 0.5 * c)
        let scallops = 4
        /// A point on the scalloped hem, u from the right rim to the left.
        func hemAt(_ u: Double) -> CGPoint {
            let lobe = min(scallops - 1, Int(u * Double(scallops)))
            let tt = u * Double(scallops) - Double(lobe)
            let x0 = w - (2 * w) * Double(lobe) / Double(scallops)
            let x1 = w - (2 * w) * Double(lobe + 1) / Double(scallops)
            return CGPoint(x: x0 + (x1 - x0) * tt, y: 2 * (1 - tt) * tt * sagY)
        }

        let alpha = dark ? 1.0 : 0.85
        if dark { ctx.blendMode = .plusLighter }
        JellyKit.bloom(in: &ctx, at: .zero, rx: w * (dark ? 2.8 : 2.2), ry: w * (dark ? 2.8 : 2.2), color: color, opacity: (dark ? 0.4 : 0.16) * (0.8 + 0.2 * c))
        ctx.blendMode = .normal

        // Ribbons from the live hem, tucked a hair under it.
        let periods: [Double] = [3.1, 3.5, 2.9, 3.4, 3.2]
        let offsets: [Double] = [0, 0.35, 0.6, 0.2, 0.5]
        for k in 0 ..< 5 {
            let hp = hemAt(0.1 + 0.2 * Double(k))
            let root = CGPoint(x: hp.x * 0.97, y: hp.y - h * 0.06)
            let length = h * (2.6 + 0.6 * Double(k % 2))
            let pts = JellyKit.trail(time: time, motion: motion, from: root, length: length, segments: 12, sway: 7 * 0.6, period: periods[k], offset: offsets[k] * 6.28 + motion.phase * 6.28)
            ctx.fill(
                JellyKit.ribbon(pts, 2.2, 0.05),
                with: .linearGradient(Gradient(colors: [color.opacity(0.75 * alpha), color.opacity(0)]), startPoint: root, endPoint: CGPoint(x: root.x, y: root.y + length)),
            )
        }
        // Two frilly oral arms from under the centre.
        let pink = Color(jelly: 0xFF9BDD)
        for k in 0 ..< 2 {
            let hp = hemAt(0.42 + 0.16 * Double(k))
            let root = CGPoint(x: hp.x, y: hp.y - h * 0.04), length = h * 1.7
            var arm = Path()
            arm.move(to: root)
            for s in stride(from: 0.0, through: 1.0, by: 0.1) {
                let wave = sin(time * 3 + s * 9 + Double(k) * 2 + motion.phase * 6.28) * 3 * s
                arm.addLine(to: CGPoint(x: root.x + wave, y: root.y + length * s))
            }
            ctx.stroke(arm, with: .color(pink.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 2.4 * (1 - 0.3 * c), lineCap: .round))
        }

        // The bell: a dome with a scalloped hem, lit from the top.
        var bell = Path()
        bell.move(to: CGPoint(x: -w, y: 0))
        bell.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: -2.3 * h))
        for n in 0 ..< scallops {
            let x0 = w - (2 * w) * Double(n) / Double(scallops)
            let x1 = w - (2 * w) * Double(n + 1) / Double(scallops)
            bell.addQuadCurve(to: CGPoint(x: x1, y: 0), control: CGPoint(x: (x0 + x1) / 2, y: sagY))
        }
        bell.closeSubpath()
        ctx.fill(
            bell,
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.92 * alpha), color.opacity(0.8 * alpha), color.opacity(0.45 * alpha)]),
                center: CGPoint(x: 0, y: -h * 0.9), startRadius: 0, endRadius: w * 1.5,
            ),
        )
        ctx.stroke(bell, with: .color(color.opacity(0.55 * alpha)), lineWidth: 0.8)
        // The hem lip the ribbons hang from.
        var lip = Path()
        for i in 0 ... 24 {
            let hp = hemAt(Double(i) / 24)
            if i == 0 { lip.move(to: hp) } else { lip.addLine(to: hp) }
        }
        ctx.stroke(lip, with: .color(color.opacity(0.75 * alpha)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        var rim = Path()
        rim.move(to: CGPoint(x: -w * 0.55, y: -h * 0.95))
        rim.addQuadCurve(to: CGPoint(x: w * 0.35, y: -h * 1.15), control: CGPoint(x: -w * 0.1, y: -h * 1.55))
        ctx.stroke(rim, with: .color(Color.white.opacity(0.55 * alpha)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        if showFace {
            let ink = Color.black.opacity(0.55 * alpha)
            for ex in [-0.3, 0.3] {
                let e = CGPoint(x: ex * w, y: -h * 0.35)
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - 1.3, y: e.y - 1.3, width: 2.6, height: 2.6)), with: .color(ink))
            }
        }
    }
}
