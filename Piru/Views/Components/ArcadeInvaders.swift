import SwiftUI

// Hebi's invaders: the sprites, the cast, and the rules the round's parts
// share. The round itself is `ArcadeGame`; the backdrop runs one on its own
// with the pilot flying, and tapping the ship hands it to you.

// MARK: - Sprites

/// Pixel art as rows of `X`. Original designs, drawn for this skin — the
/// arcade's invaders are an idea, not a sprite sheet to copy.
nonisolated enum ArcadeSprite {
    /// Three kinds, two frames each, 8 × 6.
    static let invaderRows: [[[String]]] = [
        [
            ["..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", ".X.XX.X.", "X......X"],
            ["..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", "..X..X..", ".X.XX.X."],
        ],
        [
            ["X......X", ".XXXXXX.", "XX.XX.XX", ".XXXXXX.", "..X..X..", ".X....X."],
            ["..X..X..", "XXXXXXXX", "XX.XX.XX", ".XXXXXX.", ".X.XX.X.", "X......X"],
        ],
        [
            ["...XX...", "..XXXX..", ".X.XX.X.", "XXXXXXXX", "..X..X..", ".X.XX.X."],
            ["...XX...", "..XXXX..", ".X.XX.X.", "XXXXXXXX", ".X.XX.X.", "X.X..X.X"],
        ],
    ]
    /// The red raiders — a little plane nosing down, 1942's formation.
    static let raiderRows = [".X.X.X.", "..XXX..", "XXXXXXX", "..XXX..", "...X..."]
    static let shipRows = ["....X....", "...XXX...", "...XXX...", ".X.XXX.X.", "XXXXXXXXX", "XXXXXXXXX", "X..XXX..X"]
    static let wingmanRows = ["..X..", ".XXX.", "XXXXX", "X.X.X"]
    /// One mark per power-up, drawn inside its capsule.
    static let powRows: [ArcadePower: [String]] = [
        .wide: ["X...X", ".X.X.", "..X..", "..X.."],
        .wingmen: ["..X..", "X.X.X", "XXXXX", "X...X"],
        .bomb: [".XXX.", "XXXXX", "XXXXX", ".XXX."],
        .loop: [".XXX.", "X...X", "X...X", ".XXX."],
        .laser: ["..X..", "..X..", "..X..", ".XXX."],
        .charm: [".X.X.", "XXXXX", ".XXX.", "..X.."],
        .shield: ["XXXXX", "X...X", ".X.X.", "..X.."],
    ]

    /// Play mode's extra aliens, from the second wave on.
    /// Armored: takes two hits, and shows the first as a crack.
    static let shieldedRows: [[String]] = [
        ["..XXXXXX..", ".XXXXXXXX.", "XX.XXXX.XX", "XXXXXXXXXX", "X.XX..XX.X", "X.X....X.X", "..XX..XX.."],
        ["..XXXXXX..", ".XXXXXXXX.", "XX.XXXX.XX", "XXXXXXXXXX", "X.XX..XX.X", "..X....X..", ".X......X."],
    ]
    /// Drawn dark over a shielded alien that has taken its first hit.
    static let crackRows = ["....X.....", ".....X....", "....X.....", "...X.X....", "..X...X...", "..........", ".........."]
    /// Two aliens holding hands: shot, it comes apart into two minis. Split
    /// down the seam so each half can take its own color.
    static let splitterRows: [[String]] = [
        [".XX...XX.", "XXXX.XXXX", "X.XX.XX.X", "XXXX.XXXX", ".X.X.X.X.", "X.......X"],
        [".XX...XX.", "XXXX.XXXX", "X.XX.XX.X", "XXXX.XXXX", ".X.X.X.X.", ".X.....X."],
    ]
    static let miniRows: [[String]] = [
        [".X.X.", "XXXXX", "X.X.X", ".X.X."],
        [".X.X.", "XXXXX", "X.X.X", "X...X"],
    ]
    /// The bonus ship across the top: points, and always a POW.
    static let mothershipRows = [
        ".....XXXXXX.....", "...XXXXXXXXXX...", "..XXXXXXXXXXXX..", ".XX.XX.XX.XX.XX.",
        "XXXXXXXXXXXXXXXX", "..XXX..XX..XXX..", "...X........X...",
    ]

    static let pixel: CGFloat = 2
    /// The mothership's portholes, the gaps in its fourth row.
    static let mothershipLights: [CGPoint] = [3, 6, 9, 12].map { CGPoint(x: (CGFloat($0) - 8 + 0.5) * pixel, y: 0) }
    static let invaders: [[Path]] = invaderRows.map { $0.map { path($0, pixel: pixel) } }
    static let raider = path(raiderRows, pixel: pixel)
    static let ship = path(shipRows, pixel: pixel)
    static let wingman = path(wingmanRows, pixel: pixel)
    static let pows: [ArcadePower: Path] = powRows.mapValues { path($0, pixel: 1.6) }
    static let shielded: [Path] = shieldedRows.map { path($0, pixel: pixel) }
    static let crack = path(crackRows, pixel: pixel)
    /// Left and right halves, per frame. Each half is padded back to the
    /// full width so both stay centered on the same point.
    static let splitter: [(left: Path, right: Path)] = splitterRows.map { rows in
        let left = rows.map { String($0.enumerated().map { $0.offset < 4 ? $0.element : "." }) }
        let right = rows.map { String($0.enumerated().map { $0.offset > 4 ? $0.element : "." }) }
        return (path(left, pixel: pixel), path(right, pixel: pixel))
    }
    static let mini: [Path] = miniRows.map { path($0, pixel: pixel) }
    static let mothership = path(mothershipRows, pixel: pixel)

    /// Invader footprint, for hits.
    static let invaderSize = CGSize(width: 16, height: 12)

    /// The lit pixels as one path, centered on the origin — one fill per sprite.
    static func path(_ rows: [String], pixel: CGFloat) -> Path {
        let w = CGFloat(rows.map(\.count).max() ?? 0) * pixel, h = CGFloat(rows.count) * pixel
        var p = Path()
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "X" {
                p.addRect(CGRect(x: CGFloat(x) * pixel - w / 2, y: CGFloat(y) * pixel - h / 2, width: pixel, height: pixel))
            }
        }
        return p
    }
}

/// Play mode's cast. The backdrop plays with `.plain` only.
nonisolated enum ArcadeAlien: Sendable {
    case plain
    case shielded
    case splitter
    case mini

    var hp: Int { self == .shielded ? 2 : 1 }
    /// How hard it sidesteps a bullet on a dive: armor is slow, minis quick.
    var agility: CGFloat {
        switch self {
        case .plain: 0.6
        case .shielded: 0.35
        case .splitter: 0.5
        case .mini: 0.8
        }
    }
    var points: Int {
        switch self {
        case .plain: 30
        case .shielded: 60
        case .splitter: 40
        case .mini: 25
        }
    }
}

nonisolated enum ArcadePower: CaseIterable, Sendable {
    case wide
    case wingmen
    /// A bubble on the ship that takes a hit for it, life and power-ups
    /// kept. Stacks to three, and shields the wingmen flying with it.
    case shield
    case bomb
    case loop
    /// Six seconds of a beam that pierces the whole column above the ship.
    case laser
    /// Ten seconds of the snake on your side. Rare, and it will not cycle.
    case charm

    /// What a shot turns a capsule into, in order. Charm stays out of it: it
    /// is rare, and shooting your way to it would make it common.
    static let cycle: [ArcadePower] = [.wide, .wingmen, .shield, .loop, .laser, .bomb]

    var next: ArcadePower {
        guard let i = Self.cycle.firstIndex(of: self) else { return self }
        return Self.cycle[(i + 1) % Self.cycle.count]
    }

    static func random(_ rng: inout SeededRNG) -> ArcadePower {
        rng.unit() < 0.08 ? .charm : cycle[Int(rng.next() % UInt64(cycle.count))]
    }
}

// MARK: - Rules

/// What the round's parts share: the formation's grid, the dive, the
/// pilot's numbers, and where home is.
nonisolated enum ArcadeRules {
    /// An invader out of its slot: it swoops, dives at the ship, and if it
    /// misses comes back in over the top to take its place again. A swarmer
    /// from the top edge has no slot (`col` -1) and is gone when it misses.
    struct Diver {
        var p: CGPoint
        var v: CGVector
        var col: Int, row: Int
        var age: Double
        /// Swings out left (-1) or right (1) before it dives.
        var side: CGFloat
        var returning = false
        var alien: ArcadeAlien = .plain
        var hp = 1
        /// Whether this one watches for bullets at all.
        var dodges = false
    }

    static let spacing = CGSize(width: 26, height: 20)
    static let shotSpeed: CGFloat = 520, bombSpeed: CGFloat = 150
    /// A new fruit cannot be burst for this long: it grows in first, so a
    /// stream of fire already on its spot does not set the snake on you.
    static let ripen = 0.8

    /// Home height: just over the horizon, the floor's own line. The pilot
    /// drifts around it rather than riding it.
    static func home(in size: CGSize) -> CGFloat {
        size.height * 0.52 - 16
    }

    /// One step of a dive toward `prey`. Returns false when the diver is back
    /// in its slot.
    static func steer(_ d: inout Diver, toward prey: CGPoint, slot: CGPoint, bottom: CGFloat, dt: Double, speed: CGFloat = 1) -> Bool {
        d.age += dt
        if d.returning {
            let dx = slot.x - d.p.x, dy = slot.y - d.p.y
            let dist = hypot(dx, dy)
            if dist < 4 { return false }
            let step = min(dist, 170 * speed * dt)
            d.v = CGVector(dx: dx / dist * 170 * speed, dy: dy / dist * 170 * speed)
            d.p.x += dx / dist * step
            d.p.y += dy / dist * step
            return true
        }
        if d.age < 0.7 {
            // The peel-off: a half loop out to the side, rising a little.
            let a = d.age / 0.7 * .pi
            d.v = CGVector(dx: d.side * 110 * speed * cos(a * 0.5), dy: (-60 * cos(a) + 40) * speed)
        } else {
            // The dive: down hard, bending toward the ship.
            let pull = max(-170, min(170, (prey.x - d.p.x) * 2.6)) * speed
            d.v = CGVector(dx: d.v.dx + (pull - d.v.dx) * min(1, 5 * dt), dy: 150 * speed)
        }
        d.p.x += d.v.dx * dt
        d.p.y += d.v.dy * dt
        if d.p.y > bottom {
            // Missed: round the back of the screen and in over the top.
            d.returning = true
            d.p = CGPoint(x: slot.x, y: -14)
        }
        return true
    }

    /// The idle pilot, the same one ely.pink/hebi flies. It thinks and moves
    /// separately: about twelve times a second it scores the spots around the
    /// ship (danger from everything projected to when it would get there, a
    /// led shot on its target, a falling POW, a home height that drifts, and
    /// not changing its mind too sharply) and picks the cheapest; then the
    /// ship steers there with capped speed and acceleration, so it curves
    /// rather than snapping. Something about to land is rolled through.
    enum Pilot {
        static let speed: CGFloat = 230, accel: CGFloat = 1_100
        static let offsets: [CGFloat] = [-130, -90, -55, -28, -10, 0, 10, 28, 55, 90, 130]
        static let lifts: [CGFloat] = [-70, -40, -18, 0, 18, 40, 70]

        static func home(_ base: CGFloat, at t: Double) -> CGFloat {
            base + 45 * CGFloat(sin(t * 0.31)) + 18 * CGFloat(sin(t * 0.77 + 1))
        }
    }
}

// MARK: - Drawing

/// The pieces both the backdrop and the cabinet draw, so a ship you pick up is
/// the same ship that was playing.
nonisolated enum ArcadeDraw {
    /// The dark edge round everything in play, so pink and purple still read
    /// against the pink sun. Invisible on the night sky, which is the point.
    static let outline = Color.black.opacity(0.7)
    /// Furious Bitjelly's red: its hue goes on at the jelly's own lightness,
    /// so the lights and shading stay, and `furyDepth` multiplies it deeper.
    static let fury = Color(.displayP3, red: 1, green: 0.18, blue: 0.14)
    static let furyDepth = Color(.displayP3, red: 1, green: 0.55, blue: 0.55)

    static func invaderTint(_ arcade: SkinArcade, row: Int) -> Color {
        [arcade.invader, arcade.wall, arcade.border][row % 3]
    }

    static func sprite(_ path: Path, at p: CGPoint, color: Color, glow: Bool, rotation: Angle = .zero, scale: CGFloat = 1, outlined: Bool = true, in context: inout GraphicsContext) {
        if glow {
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 14 * scale, y: p.y - 14 * scale, width: 28 * scale, height: 28 * scale)),
                with: .radialGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]), center: p, startRadius: 0, endRadius: 14 * scale),
            )
        }
        let t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rotation.radians).scaledBy(x: scale, y: scale)
        let placed = path.applying(t)
        // Stroked under the fill, so only the half outside the pixels shows.
        if outlined { context.stroke(placed, with: .color(outline), lineWidth: 2) }
        context.fill(placed, with: .color(color))
    }

    static func ship(at p: CGPoint, arcade: SkinArcade, time: Double, glow: Bool, rotation: Angle = .zero, scale: CGFloat = 1, in context: inout GraphicsContext) {
        // The engine: two pixels of the snake's cyan, flickering.
        let flame: CGFloat = sin(time * 40) > 0 ? 5 : 3
        context.fill(Path(CGRect(x: p.x - 1.5, y: p.y + 7, width: 3, height: flame)), with: .color(arcade.snake.opacity(0.9)))
        sprite(ArcadeSprite.ship, at: p, color: arcade.star, glow: glow, rotation: rotation, scale: scale, in: &context)
    }

    static func shot(at p: CGPoint, color: Color, in context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: p.x - 2, y: p.y - 5, width: 4, height: 10)), with: .color(outline))
        context.fill(Path(CGRect(x: p.x - 1, y: p.y - 4, width: 2, height: 8)), with: .color(color))
    }

    /// An invader's bomb: a zigzag, the arcade's own shorthand.
    static func bomb(at p: CGPoint, color: Color, time: Double, in context: inout GraphicsContext) {
        let flip: CGFloat = sin(time * 20 + p.y) > 0 ? 1 : -1
        var z = Path()
        z.move(to: CGPoint(x: p.x, y: p.y - 5))
        z.addLine(to: CGPoint(x: p.x + 2 * flip, y: p.y - 2))
        z.addLine(to: CGPoint(x: p.x - 2 * flip, y: p.y + 1))
        z.addLine(to: CGPoint(x: p.x, y: p.y + 4))
        context.stroke(z, with: .color(outline), lineWidth: 3.5)
        context.stroke(z, with: .color(color), lineWidth: 1.5)
    }

    /// Eight pixels thrown outward, fading over `life`.
    static func burst(at p: CGPoint, age: Double, life: Double = 0.4, color: Color, reach: CGFloat = 14, in context: inout GraphicsContext) {
        let u = age / life
        guard u < 1 else { return }
        let r = reach * CGFloat(0.3 + u)
        for k in 0 ..< 8 {
            let a = Double(k) / 8 * 2 * .pi
            let q = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r)
            context.fill(Path(CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)), with: .color(color.opacity(1 - u)))
        }
    }
}
