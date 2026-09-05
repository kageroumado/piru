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

// MARK: - Flourishes

extension View {
    /// The skin's corner glyphs on a large card — ✧ hanging off the top-right
    /// edge, ♡ off the bottom-left — for a decorated skin with decorations on.
    /// Glance cards only: on a dense row the pair would collide with its text.
    func skinFrameCorners() -> some View {
        modifier(SkinFrameCorners())
    }

    /// The site's cursor trail: a glyph floats up and fades from every tap.
    /// Attached once at the root; a simultaneous gesture, so buttons and
    /// scrolling are untouched.
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
}

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

/// One ♡ from a tap: rises, shrinks, turns and fades over 0.8 s — the site's
/// `@keyframes tr` — then removes itself.
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
    /// The skin's outlined hero title on a SwiftUI-drawn title (the substance
    /// name): the same fill, outline and hard drop the navigation bar's large
    /// title gets from ``SkinNavigationTitles``. SwiftUI cannot stroke text,
    /// so the outline is eight zero-radius shadows — the site's own trick.
    func skinHeroTitle() -> some View {
        modifier(SkinHeroTitle())
    }
}

private struct SkinHeroTitle: ViewModifier {
    @State private var skins = SkinStore.shared

    func body(content: Content) -> some View {
        if let outline = skins.current.titleOutline {
            let s = outline.stroke
            content
                .foregroundStyle(outline.fill)
                .shadow(color: s, radius: 0, x: -2, y: -2)
                .shadow(color: s, radius: 0, x: 2, y: -2)
                .shadow(color: s, radius: 0, x: -2, y: 2)
                .shadow(color: s, radius: 0, x: 2, y: 2)
                .shadow(color: s, radius: 0, x: -2, y: 0)
                .shadow(color: s, radius: 0, x: 2, y: 0)
                .shadow(color: s, radius: 0, x: 0, y: -2)
                .shadow(color: s, radius: 0, x: 0, y: 2)
                .shadow(color: outline.shadow, radius: 0, x: outline.shadowOffset.width, y: outline.shadowOffset.height)
        } else {
            content
        }
    }
}
