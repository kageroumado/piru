import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The drug.community intensity spectrum as a circular, draggable dose dial.
///
/// The dial reads as a dose slider bent into an arc: drag the thumb across the
/// dose bands (Threshold → Overdose) and the card updates to show what the
/// experience is like at that dose, the effects most reported there, and — on
/// the high bands — a caution/emergency callout. Dose ranges come from Piru's
/// own Dose & Duration data, so the dial extends the science card rather than
/// paralleling it.
struct DoseIntensityCard: View {
    let bands: [SpectrumBand]
    /// band index → localized dose-range text (e.g. "30–60 mg"), from Piru's
    /// dose ladder. Absent bands show the band name alone.
    let bandDoseText: [Int: String]
    let citationSlug: String
    let citationDeepLink: URL?
    /// The route the dose ranges belong to (e.g. "Oral") — shown in the eyebrow
    /// so it's clear which ROA the dial's dose bands refer to.
    var routeName: String?

    @State private var selected: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bandColors: [Color] = [
        Color(hex: "34C759"), Color(hex: "8ED04A"), Color(hex: "E0B93A"),
        Color(hex: "E8940C"), Color(hex: "E5613D"), Color(hex: "E5484D"),
    ]

    private var current: SpectrumBand {
        bands[min(selected, bands.count - 1)]
    }
    private func color(_ i: Int) -> Color {
        Self.bandColors[min(i, Self.bandColors.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let routeName {
                    Text("By dose · \(routeName)", comment: "Intensity dial eyebrow with route of administration")
                } else {
                    Text("By dose", comment: "Intensity dial eyebrow")
                }
            }
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            gauge
                .frame(height: 200)
                .overlay(centerReadout)
                .padding(.top, 2)
                .padding(.bottom, 10)

            // Reserve the height of the tallest band summary so the card doesn't
            // grow and shrink as the selector moves between doses. Hidden copies
            // of every summary size the ZStack (its frame is the union of its
            // children, so the tallest wins); the visible summary sits on top.
            ZStack {
                ForEach(bands) { band in
                    Text(band.summary)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .hidden()
                }
                Text(current.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)

            if !current.topEffects.isEmpty {
                mostReported
            }

            SourceAttributionRow(
                slug: citationSlug,
                label: "Intensity spectrum",
                deepLink: citationDeepLink,
            )
            .padding(.top, 6)
        }
        .padding(16)
        .themeCard()
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear { selected = defaultBand }
    }

    /// Open on the "Common" band when present, else the middle band.
    private var defaultBand: Int {
        bands.firstIndex { $0.bandKey == "Common" } ?? (bands.count / 2)
    }

    /// What VoiceOver speaks for the dial's current value: the band name plus its
    /// dose range (e.g. "Common, 75–150 mg"), so an adjust announces something
    /// meaningful rather than "band 3 of 6".
    private var accessibilityValueLabel: String {
        if let dose = bandDoseText[current.bandIndex] {
            return "\(current.localizedBandName), \(dose)"
        }
        return current.localizedBandName
    }

    // MARK: gauge

    private var gauge: some View {
        IntensityGauge(
            bandCount: bands.count,
            selected: selected,
            colors: bands.indices.map(color),
            valueLabel: accessibilityValueLabel,
        ) { newIndex in
            let clamped = max(0, min(bands.count - 1, newIndex))
            guard clamped != selected else { return }
            selected = clamped
        }
    }

    private var centerReadout: some View {
        VStack(spacing: 2) {
            Text(bandDoseText[current.bandIndex] ?? current.localizedBandName)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(current.isOverdose ? color(current.bandIndex) : .primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if bandDoseText[current.bandIndex] != nil {
                Text(current.localizedBandName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(current.bandIndex))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.localizedBandName)
        .accessibilityValue(bandDoseText[current.bandIndex].map { Text($0) } ?? Text(""))
        .offset(y: 10)
    }

    private var mostReported: some View {
        let maxFreq = max(current.topEffects.map(\.frequency).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("MOST REPORTED AT THIS DOSE", comment: "Intensity dial effects heading")
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.bottom, 2)
            ForEach(current.topEffects.prefix(3), id: \.name) { eff in
                HStack(spacing: 10) {
                    Text(eff.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    FrequencyBar(fraction: Double(eff.frequency) / Double(maxFreq))
                        .frame(width: 78)
                    Text("\(eff.frequency)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }
}

/// A thin capsule meter showing a 0…1 proportion. Matches the app's PotencyBars
/// idiom (track + accent fill).
struct FrequencyBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accent.opacity(0.14))
                Capsule().fill(Theme.accent)
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
    }
}

/// The circular arc gauge: one continuous faint spectrum line (green → red) with
/// rounded ends, and a raised Liquid Glass selector floating on top of it. Grab
/// the selector and drag it around the arc — it slides with a spring, recolors to
/// the band beneath it, and lifts on grab so the interaction is discoverable.
/// Selection state is owned by the parent.
private struct IntensityGauge: View {
    let bandCount: Int
    let selected: Int
    let colors: [Color]
    let valueLabel: String
    var onSelect: (Int) -> Void

    // Arc opens at the bottom: sweeps 240° clockwise from 150° (lower-left)
    // through the top to 30° (lower-right); the 120° gap sits at the bottom.
    private let startDeg = 150.0
    private let sweepDeg = 240.0
    private let lineWidth = 16.0
    /// The tap target covering the whole arc band, so a tap on any band jumps
    /// the selector to it.
    private var hitBand: Double {
        max(lineWidth + 6, 44)
    }
    private let coordSpace = "doseGauge"

    @State private var isGrabbed = false
    @Environment(\.colorScheme) private var scheme

    private func color(_ i: Int) -> Color {
        colors[min(max(i, 0), colors.count - 1)]
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.72)
            let radius = min(size.width / 2, size.height * 0.72) - lineWidth
            let seg = sweepDeg / Double(bandCount)
            let selStart = startDeg + Double(selected) * seg
            let handle = point(center: center, radius: radius, degrees: selStart + seg / 2)

            ZStack {
                Canvas { context, _ in
                    drawTrack(in: context, center: center, radius: radius, seg: seg)
                }

                glassSelector(center: center, radius: radius, startAngle: selStart, seg: seg, size: size)
                    .allowsHitTesting(false)

                // The grab handle: a generous invisible circle riding the
                // selected band. Only touches here start a drag, so the rest of
                // the card scrolls; once a drag begins the recognizer tracks the
                // finger anywhere on the arc, including the near-vertical ends.
                Circle()
                    .fill(.clear)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
                    .position(handle)
                    .gesture(
                        ArcPan(
                            coordSpace: coordSpace,
                            onGrab: { grabbed in
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                                    isGrabbed = grabbed
                                }
                            },
                            onMove: { onSelect(band(for: $0, center: center)) },
                        ),
                    )
            }
            .coordinateSpace(.named(coordSpace))
            // Tapping any band jumps the selector to it.
            .contentShape(
                ArcRing(center: center, radius: radius, thickness: hitBand, startDeg: startDeg, sweepDeg: sweepDeg),
            )
            .onTapGesture { onSelect(band(for: $0, center: center)) }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement()
        .accessibilityLabel(Text("Dose intensity", comment: "Dial accessibility label"))
        .accessibilityValue(Text(valueLabel))
        .accessibilityHint(Text("Swipe up or down to change the dose", comment: "Dial accessibility hint"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(bandCount - 1, selected + 1))
            case .decrement: onSelect(max(0, selected - 1))
            default: break
            }
        }
    }

    /// The base track: one continuous line, faintly tinted with the band colors
    /// as a smooth spectrum (green → red), round-capped so both ends of the
    /// semicircle are cleanly rounded. The glass selector rides on top of it; the
    /// line is not carved, so it reads as a single beautiful arc rather than a row
    /// of segments.
    private func drawTrack(in context: GraphicsContext, center: CGPoint, radius: Double, seg _: Double) {
        let faint = scheme == .dark ? 0.5 : 0.42
        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(startDeg), endAngle: .degrees(startDeg + sweepDeg), clockwise: false,
        )
        let shading: GraphicsContext.Shading
        if bandCount > 1 {
            // Place each band color along the arc's fraction of the full circle
            // (the conic gradient's angle spans 360°, the arc only `sweepDeg`).
            let span = sweepDeg / 360
            let stops = (0 ..< bandCount).map { i in
                Gradient.Stop(color: color(i).opacity(faint), location: Double(i) / Double(bandCount - 1) * span)
            }
            shading = .conicGradient(Gradient(stops: stops), center: center, angle: .degrees(startDeg))
        } else {
            shading = .color(color(0).opacity(faint))
        }
        // Butt cap here, not round: a round cap would extend past the arc ends
        // into angles where the conic gradient wraps (the start cap would sample
        // the *last* color). The rounded tips are drawn as explicit dots below,
        // each in its own end color.
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        for (deg, i) in [(startDeg, 0), (startDeg + sweepDeg, bandCount - 1)] {
            let tip = point(center: center, radius: radius, degrees: deg)
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - lineWidth / 2, y: tip.y - lineWidth / 2, width: lineWidth, height: lineWidth)),
                with: .color(color(i).opacity(faint)),
            )
        }
    }

    /// The floating Liquid Glass indicator over the selected band: a rounded pill
    /// (`ArcSegment` is a round-capped stroke) whose angle animates as `selected`
    /// changes, so it slides around the arc rather than jumping. Tinted the band
    /// color, raised (thicker + shadowed) more when grabbed, and carrying a
    /// grabber glyph that rotates to stay upright on the curve — the affordance
    /// that says "drag me," in place of the old text hint.
    private func glassSelector(
        center: CGPoint, radius: Double, startAngle: Double, seg: Double, size: CGSize,
    ) -> some View {
        let thickness = lineWidth + (isGrabbed ? 15 : 9)
        let midDeg = startAngle + seg / 2
        let handle = point(center: center, radius: radius, degrees: midDeg)
        let shape = ArcSegment(
            startDeg: startAngle, sweepDeg: seg, radius: radius, thickness: thickness, center: center,
        )
        // No GlassEffectContainer and no `.interactive()`: together they render a
        // soft glass *plate* around the pill (a lighter rounded halo). A bare
        // tinted glass over the filled pill gives the material without the plate;
        // the grab lift is driven manually below, so `.interactive()` isn't needed.
        return shape
            .fill(color(selected).gradient)
            .frame(width: size.width, height: size.height)
            .glassEffect(.regular.tint(color(selected)), in: shape)
            .overlay {
                GrabberGlyph(active: isGrabbed)
                    // The pill lies along the arc tangent (radial + 90°); align the
                    // grip ridges across it so they read as a grip at any position.
                    .rotationEffect(.degrees(midDeg + 90))
                    .position(handle)
            }
            // Neutral lift, not a colored glow — a tinted shadow reads as a halo.
            .shadow(color: .black.opacity(isGrabbed ? 0.22 : 0.14), radius: isGrabbed ? 9 : 5, y: 2)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: selected)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isGrabbed)
    }

    private func point(center: CGPoint, radius: Double, degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
    }

    /// Map a touch location to a band index. The bottom gap clamps to the nearest end.
    private func band(for location: CGPoint, center: CGPoint) -> Int {
        var deg = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        if deg < 0 { deg += 360 }
        var shifted = deg - startDeg
        if shifted < 0 { shifted += 360 }
        if shifted > sweepDeg {
            return shifted > (sweepDeg + (360 - sweepDeg) / 2) ? 0 : bandCount - 1
        }
        let seg = sweepDeg / Double(bandCount)
        return max(0, min(bandCount - 1, Int(shifted / seg)))
    }
}

/// One band of the ring as a rounded pill: the band's centerline arc stroked
/// with round caps, so its ends are fully rounded (a capsule bent along the
/// arc). A filled shape — not a live stroke — so it can carry a glass effect.
/// `startDeg` animates, which slides the selector between bands.
private struct ArcSegment: Shape {
    var startDeg: Double
    var sweepDeg: Double
    var radius: Double
    var thickness: Double
    var center: CGPoint

    /// Slide (startDeg) and lift (thickness) both animate.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startDeg, thickness) }
        set {
            startDeg = newValue.first
            thickness = newValue.second
        }
    }

    func path(in _: CGRect) -> Path {
        // The round caps reach thickness/2 past each end; pull the span in by
        // that much so the pill spans the band rather than overhanging it.
        let capDeg = (thickness / 2) / max(radius, 1) * 180 / .pi
        var arc = Path()
        arc.addArc(
            center: center, radius: radius,
            startAngle: .degrees(startDeg + capDeg),
            endAngle: .degrees(startDeg + sweepDeg - capDeg),
            clockwise: false,
        )
        return arc.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

/// The grip on the floating pill — a few short ridges that say "drag me,"
/// echoing the sheet grabber. Sits at the pill's center and is rotated by the
/// caller to track the pill around the arc; brightens and spreads slightly when
/// grabbed.
private struct GrabberGlyph: View {
    let active: Bool

    var body: some View {
        HStack(spacing: active ? 3.5 : 3) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Capsule()
                    .fill(.white.opacity(active ? 0.95 : 0.8))
                    .frame(width: 2, height: 11)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
    }
}

/// The dial's tap target: the swept band of the arc, not the box around it, so a
/// tap anywhere on the arc selects that band while the open bottom stays
/// scrollable.
private struct ArcRing: Shape {
    let center: CGPoint
    let radius: Double
    let thickness: Double
    let startDeg: Double
    let sweepDeg: Double

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(startDeg), endAngle: .degrees(startDeg + sweepDeg),
            clockwise: false,
        )
        return path.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}

/// The pan that drives the glass selector.
///
/// Attached to the small grab handle riding the selected band, so it only ever
/// receives touches that land on the handle — the rest of the card scrolls. It
/// fires `onGrab(true)` on touch-down for immediate lift feedback (a pan
/// otherwise waits for movement, and the grab should read the instant the finger
/// lands), and once dragging, the recognizer tracks the finger anywhere on the
/// arc — including the near-vertical ends that broke direction-based schemes.
private final class GrabPanRecognizer: UIPanGestureRecognizer {
    var onGrabChange: (Bool) -> Void = { _ in }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onGrabChange(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onGrabChange(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onGrabChange(false)
    }
}

private struct ArcPan: UIGestureRecognizerRepresentable {
    var coordSpace: String
    var onGrab: (Bool) -> Void
    var onMove: (CGPoint) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> GrabPanRecognizer {
        let recognizer = GrabPanRecognizer()
        recognizer.onGrabChange = onGrab
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: GrabPanRecognizer, context _: Context) {
        recognizer.onGrabChange = onGrab
    }

    func handleUIGestureRecognizerAction(_ recognizer: GrabPanRecognizer, context: Context) {
        // The handle is positioned away from the gauge origin, so read the touch
        // in the gauge's named space rather than the handle's local space.
        switch recognizer.state {
        case .began, .changed: onMove(context.converter.location(in: .named(coordSpace)))
        default: break
        }
    }

    /// Makes the enclosing scroll view wait for this recognizer to fail before it
    /// scrolls, so an on-handle drag wins even when it moves vertically (the arc's
    /// ends). Touches off the handle never reach this recognizer, so the rest of
    /// the card scrolls untouched.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer,
        ) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

extension SpectrumBand {
    /// Localized display name for the band key.
    var localizedBandName: String {
        switch bandKey {
        case "Threshold": String(localized: "Threshold", comment: "Dose band")
        case "Light": String(localized: "Light", comment: "Dose band")
        case "Common": String(localized: "Common", comment: "Dose band")
        case "Strong": String(localized: "Strong", comment: "Dose band")
        case "Heavy": String(localized: "Heavy", comment: "Dose band")
        case "Overdose": String(localized: "Overdose", comment: "Dose band")
        default: bandKey
        }
    }
}

#Preview("Dose intensity dial") {
    let names = ["Threshold", "Light", "Common", "Strong", "Heavy", "Overdose"]
    let bands = names.indices.map { i in
        SpectrumBand(
            bandIndex: i,
            bandKey: names[i],
            summary: "What the experience is like at the \(names[i].lowercased()) dose.",
            topEffects: [
                BandEffect(name: "euphoria", frequency: 1_200),
                BandEffect(name: "sociability", frequency: 800),
                BandEffect(name: "sensory enhancement", frequency: 300),
            ],
            warnings: [],
        )
    }
    // Wrapped in fillers so the segment seams and the scroll-past behavior are
    // both visible in the canvas.
    return ScrollView {
        VStack(spacing: 16) {
            Color.gray.opacity(0.12).frame(height: 200).overlay(Text("scroll above"))
            DoseIntensityCard(
                bands: bands,
                bandDoseText: [0: "30 mg", 1: "40–75 mg", 2: "75–125 mg", 3: "125–175 mg", 4: "175+ mg"],
                citationSlug: "drug.community",
                citationDeepLink: nil,
                routeName: "Oral",
            )
            Color.gray.opacity(0.12).frame(height: 400).overlay(Text("scroll below"))
        }
        .padding()
    }
}
