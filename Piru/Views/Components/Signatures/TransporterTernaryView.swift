import SwiftUI

/// The **SERT / DAT / NET triangle** — stimulants, empathogens, antidepressants.
///
/// Each point is a potency *share*: the normalized reciprocal of the half-max concentration, so a
/// compound sits nearest the transporter it is most potent at. DAT is the apex, NET the leading
/// vertex, SERT the trailing one.
///
/// A releaser's EC₅₀ and a blocker's Kᵢ/IC₅₀ are never plotted together — sertraline's triangle is
/// the blocker basis and says so on the axis line. MDMA legitimately has **two** passing triples
/// (Baumann's rat-synaptosome release EC₅₀ and Simmler's human uptake IC₅₀), which is why this is a
/// basis *switch* rather than one triangle: averaging them would be inventing a third number.
struct TransporterTernaryView: View {
    let model: TransporterTernaryModel
    let accent: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection = 0
    /// The comparison dot the reader tapped to name, by `Point.id`; `nil` when none.
    @State private var selectedPointID: String?
    /// Whether the reader has ever named a dot by tapping — the one-line hint under the plot
    /// shows until then.
    @AppStorage("ternaryTapHintSeen") private var tapHintSeen = false

    private var triple: TransporterTernaryModel.Triple {
        model.triples[min(selection, model.triples.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if model.triples.count > 1 {
                Picker(selection: $selection) {
                    ForEach(Array(model.triples.enumerated()), id: \.element.id) { index, item in
                        Text(Self.basisTitle(item)).tag(index)
                    }
                } label: {
                    Text("Measurement basis", comment: "Picker label for the transporter ternary basis switch")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(
                    Text("Measurement basis", comment: "Picker label for the transporter ternary basis switch"),
                )
            }

            if dynamicTypeSize.isAccessibilitySize {
                // The list is a VoiceOver / large-type reader's only access to the
                // plot, so it keeps the numbers the visual caption drops.
                TernaryShareList(triple: triple, accent: accent)
            } else {
                // Both pieces of provenance live in the plot's top-trailing corner
                // rather than on lines of their own: the study link, named as one,
                // and the basis. The basis has to stay visible — a release EC₅₀ and
                // a blocker's IC₅₀ are different axes — so it prints here only when
                // there is no basis switch above already saying it.
                //
                // Per-transporter percentages are deliberately absent. The triangle's
                // point is the *position*: which corner a compound leans to and how
                // far it sits from its neighbors. "DAT 33% · NET 66% · SERT 1%"
                // reads as a measured composition when it is a normalized reciprocal
                // of three half-max concentrations, and that much precision invites
                // arithmetic the numbers cannot support.
                TernaryPlot(triple: triple, accent: accent, selectedID: $selectedPointID)
                    // Both stack in the top-trailing corner. The bottom corners belong
                    // to the NET and SERT vertex labels, and a basis sitting there
                    // collided with SERT.
                    .overlay(alignment: .topTrailing) {
                        VStack(alignment: .trailing, spacing: 3) {
                            if let url = triple.provenance.citationURL {
                                Link(destination: url) {
                                    HStack(spacing: Spacing.xxs) {
                                        Text("Source")
                                        Image(systemName: "arrow.up.right")
                                            .accessibilityHidden(true)
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                }
                                // A bare Link claims its whole List row's taps.
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("View citation"))
                            }
                            if model.triples.count == 1 {
                                Text(Self.captionBasis(triple))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                        .padding(.trailing, Spacing.xxs)
                    }

                if !tapHintSeen {
                    Text("Tap a dot to name it", comment: "Hint under the transporter ternary plot")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedPointID) { _, selected in
            if selected != nil { tapHintSeen = true }
        }
        // Point ids are substance ids, so one can exist on both bases; a selection
        // still clears on a basis switch because the dot moves and the reader's
        // eye has lost it.
        .onChange(of: selection) { _, _ in
            selectedPointID = nil
        }
    }

    /// "Release EC₅₀" / "Reuptake IC₅₀" — the two things that must never share a triangle, so the
    /// switch between them is labeled with exactly that distinction.
    private static func basisTitle(_ triple: TransporterTernaryModel.Triple) -> String {
        switch (triple.provenance.basis, triple.action) {
        case (.ec50, .releasingAgent): String(localized: "Release EC₅₀", comment: "Ternary basis option")
        case (.ec50, _): String(localized: "Functional EC₅₀", comment: "Ternary basis option")
        case (.ic50, _): String(localized: "Reuptake IC₅₀", comment: "Ternary basis option")
        default: String(localized: "Binding Kᵢ", comment: "Ternary basis option")
        }
    }

    /// The same distinction as the switch, in caption case — a releaser's EC₅₀ is a *release* EC₅₀,
    /// and it is never the same axis as a blocker's IC₅₀.
    private static func captionBasis(_ triple: TransporterTernaryModel.Triple) -> String {
        switch (triple.provenance.basis, triple.action) {
        case (.ec50, .releasingAgent): String(localized: "release EC₅₀", comment: "Ternary axis basis")
        case (.ec50, _): String(localized: "functional EC₅₀", comment: "Ternary axis basis")
        case (.ic50, _): String(localized: "reuptake-inhibition IC₅₀", comment: "Ternary axis basis")
        default: String(localized: "binding Kᵢ", comment: "Ternary axis basis")
        }
    }

    static func shareLine(_ shares: TransporterTernaryModel.Shares) -> String {
        func percent(_ value: Double) -> String {
            (value * 100).formatted(.number.precision(.fractionLength(0 ... 0)))
        }
        return "DAT \(percent(shares.dat))% · NET \(percent(shares.net))% · SERT \(percent(shares.sert))%"
    }
}

// MARK: - The plot

private struct TernaryPlot: View {
    let triple: TransporterTernaryModel.Triple
    let accent: Color
    /// The tapped comparison dot, by `Point.id`. Tapping it again, or empty space, clears it.
    @Binding var selectedID: String?

    @Environment(\.layoutDirection) private var layoutDirection

    private static let height: CGFloat = 196
    private static let labelWidth: CGFloat = 92
    private static let labelHeight: CGFloat = 12
    /// How many context dots get named. Four is what fits a ~300pt plot without
    /// labels colliding; the rest stay unnamed dots that still show the spread.
    private static let namedGhostLimit = 4
    /// How far from a dot a tap still counts as hitting it. Dots cluster along
    /// the NET–SERT edge, so the nearest one within this radius wins.
    private static let tapRadius: CGFloat = 22
    private static let ghostRadius: CGFloat = 3
    private static let peerRadius: CGFloat = 4.5
    private static let focusRadius: CGFloat = 8

    /// The best-known context compounds, skipping any that would print on top of
    /// a peer or the focus — those already carry their own label.
    private var namedGhosts: [TransporterTernaryModel.Point] {
        let taken = Set(triple.peers.map(\.name) + [triple.focus.name])
        return triple.ghosts
            .filter { !taken.contains($0.name) && $0.popularity > 0 }
            .prefix(Self.namedGhostLimit)
            .map(\.self)
    }

    /// Every dot a tap can name: the context cloud and the same-study peers.
    private var selectable: [TransporterTernaryModel.Point] {
        triple.ghosts + triple.peers
    }

    private var selected: TransporterTernaryModel.Point? {
        selectable.first { $0.id == selectedID }
    }

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            ZStack(alignment: .topLeading) {
                TriangleShape(vertices: vertices(box))
                    .fill(accent.opacity(0.05))
                TriangleShape(vertices: vertices(box))
                    .stroke(Theme.secondaryLabel.opacity(0.22), lineWidth: 1.4)
                GridLines(vertices: vertices(box))
                    .stroke(Theme.secondaryLabel.opacity(Theme.Opacity.tint), lineWidth: 1)

                // One clear layer under the marks takes every tap, so a tap on
                // empty space clears the selection and a near miss on a dot still
                // lands on the nearest one.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        select(nearestTo: location, box: box)
                    }
                    .accessibilityHidden(true)

                ForEach(triple.ghosts) { ghost in
                    dot(ghost, box: box, radius: Self.ghostRadius, filled: false)
                }
                ForEach(triple.peers) { peer in
                    dot(peer, box: box, radius: Self.peerRadius, filled: true)
                }
                dot(triple.focus, box: box, radius: Self.focusRadius, filled: true)

                // Name the focus, the peers and the best-known few landmarks. The
                // context cloud only means something if the reader recognizes what
                // is in it — landmarks, not a count. Each label takes the first slot
                // around its dot that covers no dot and no label placed before it;
                // a landmark with no clear slot stays unnamed.
                let placed = placedLabels(box: box)
                ForEach(labeledPoints) { point in
                    if point.id != selectedID, let frame = placed[point.id] {
                        label(point, frame: frame)
                    }
                }

                if let selected {
                    selectedLabel(selected, box: box, placed: placed)
                }

                vertexLabel(SignatureTarget.dat.label, at: vertices(box).apex, box: box, anchor: .center, dy: -15)
                vertexLabel(SignatureTarget.net.label, at: vertices(box).leading, box: box, anchor: .leading, dy: 11)
                vertexLabel(SignatureTarget.sert.label, at: vertices(box).trailing, box: box, anchor: .trailing, dy: 11)
            }
            .frame(width: box.width, height: box.height)
            .signaturePlotPinnedToLTR()
        }
        .frame(height: Self.height)
        // The dots are the elements — each carries its substance name — so the
        // plot reads as a named group around them rather than one opaque picture.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text("Transporter potency share", comment: "Accessibility label for the SERT/DAT/NET ternary plot"),
        )
    }

    // MARK: selection

    private func select(nearestTo location: CGPoint, box: CGSize) {
        let hit = selectable
            .map { point in (point, distance(location, position(point.shares, box: box))) }
            .filter { $0.1 <= Self.tapRadius }
            .min { $0.1 < $1.1 }?
            .0
        toggle(hit)
    }

    private func toggle(_ point: TransporterTernaryModel.Point?) {
        withAnimation(.snappy(duration: 0.2)) {
            selectedID = point?.id == selectedID ? nil : point?.id
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: geometry

    private struct Vertices {
        let apex: CGPoint
        let leading: CGPoint
        let trailing: CGPoint
    }

    /// DAT at the apex, NET leading, SERT trailing. Under RTL the two base vertices swap so the
    /// triangle mirrors with the rest of the layout instead of reading backwards.
    private func vertices(_ box: CGSize) -> Vertices {
        let inset: CGFloat = 34
        let apex = CGPoint(x: box.width / 2, y: 24)
        let left = CGPoint(x: inset, y: box.height - 26)
        let right = CGPoint(x: box.width - inset, y: box.height - 26)
        return layoutDirection == .rightToLeft
            ? Vertices(apex: apex, leading: right, trailing: left)
            : Vertices(apex: apex, leading: left, trailing: right)
    }

    private func position(_ shares: TransporterTernaryModel.Shares, box: CGSize) -> CGPoint {
        let v = vertices(box)
        return CGPoint(
            x: shares.dat * v.apex.x + shares.net * v.leading.x + shares.sert * v.trailing.x,
            y: shares.dat * v.apex.y + shares.net * v.leading.y + shares.sert * v.trailing.y,
        )
    }

    // MARK: marks

    private func dot(
        _ point: TransporterTernaryModel.Point,
        box: CGSize,
        radius: CGFloat,
        filled: Bool,
    ) -> some View {
        let center = position(point.shares, box: box)
        let isSelected = point.id == selectedID
        // A selected dot grows to the peers' size and fills solid, ringed like the
        // focus so it lifts off the cloud it came from.
        let radius = isSelected ? max(radius, 5.5) : radius
        let filled = filled || isSelected
        let tint = point.isFocus ? accent : Theme.secondaryLabel
        let ring: Color = if point.isFocus || isSelected {
            Color.platformSystemBackground
        } else {
            tint.opacity(filled ? 0 : 0.35)
        }
        return Circle()
            .fill(filled ? tint.opacity(point.isFocus || isSelected ? 1 : 0.5) : Color.clear)
            .overlay(
                Circle().strokeBorder(ring, lineWidth: point.isFocus ? 2.5 : (isSelected ? 1.5 : 1)),
            )
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: center.x - radius, y: center.y - radius)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dotAccessibilityLabel(point))
            .accessibilityValue(Text(TransporterTernaryView.shareLine(point.shares)))
            // VoiceOver walks the focus first, then the same-study peers, then the cloud.
            .accessibilitySortPriority(point.isFocus ? 2 : (point.isGated ? 1 : 0))
            .accessibilityAddTraits(point.isFocus ? [] : (isSelected ? [.isButton, .isSelected] : .isButton))
            .accessibilityAction(named: Text("Name on plot", comment: "Accessibility action on a ternary plot dot")) {
                if !point.isFocus { toggle(point) }
            }
    }

    private func dotAccessibilityLabel(_ point: TransporterTernaryModel.Point) -> Text {
        if point.isFocus {
            Text("\(point.name), this substance", comment: "Accessibility label for the current substance's dot")
        } else if point.isGated {
            Text("\(point.name), measured in the same study", comment: "Accessibility label for a same-study peer dot")
        } else {
            Text(point.name)
        }
    }

    private func label(_ point: TransporterTernaryModel.Point, frame: CGRect) -> some View {
        Text(point.name)
            .font(.system(size: 9.5, weight: point.isFocus ? .bold : .medium))
            // Context names sit a step back from the gated peers so the triangle
            // still reads focus → same-study peers → landmarks, not one flat list.
            .foregroundStyle(point.isFocus ? AnyShapeStyle(accent) : AnyShapeStyle(Theme.secondaryLabel.legibleOpacity(point.isGated ? 1 : 0.65)))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: Self.labelWidth)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityHidden(true)
    }

    /// The tapped dot's name, in the primary label color so it stands apart from the
    /// muted landmarks. It takes the first slot around the dot that clears every
    /// other label; when that slot is anywhere but the default one, a leader line
    /// ties the name back to its dot.
    @ViewBuilder
    private func selectedLabel(
        _ point: TransporterTernaryModel.Point, box: CGSize, placed: [String: CGRect],
    ) -> some View {
        let placement = selectedPlacement(point, box: box, placed: placed)
        if let leader = placement.leader {
            Path { path in
                path.move(to: leader.from)
                path.addLine(to: leader.to)
            }
            .stroke(Theme.secondaryLabel.opacity(0.7), lineWidth: 1)
            .accessibilityHidden(true)
        }
        Text(point.name)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: Self.labelWidth)
            .offset(x: placement.frame.minX, y: placement.frame.minY)
            .accessibilityHidden(true)
    }

    // MARK: label placement

    private struct Placement {
        let frame: CGRect
        let leader: (from: CGPoint, to: CGPoint)?
    }

    /// The points that carry a name, in the order they claim space: the focus,
    /// then the same-study peers, then the landmarks.
    private var labeledPoints: [TransporterTernaryModel.Point] {
        [triple.focus] + triple.peers + namedGhosts
    }

    /// Every dot's disc, padded a point, so no label prints over a mark.
    private func dotBounds(box: CGSize) -> [CGRect] {
        func disc(_ point: TransporterTernaryModel.Point, _ radius: CGFloat) -> CGRect {
            let center = position(point.shares, box: box)
            let r = radius + 1
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
        return triple.ghosts.map { disc($0, Self.ghostRadius) }
            + triple.peers.map { disc($0, Self.peerRadius) }
            + [disc(triple.focus, Self.focusRadius)]
    }

    private func vertexLabelBounds(box: CGSize) -> [CGRect] {
        let v = vertices(box)
        return [
            vertexLabelFrame(at: v.apex, box: box, anchor: .center, dy: -15),
            vertexLabelFrame(at: v.leading, box: box, anchor: .leading, dy: 11),
            vertexLabelFrame(at: v.trailing, box: box, anchor: .trailing, dy: 11),
        ]
    }

    /// The slots tried around a dot: the default side, the opposite side, beside
    /// the dot on either hand, then one step further out.
    private func slots(defaultDY: CGFloat) -> [(dx: CGFloat, dy: CGFloat)] {
        [
            (0, defaultDY), (0, defaultDY < 0 ? 12 : -22),
            (56, -6), (-56, -6),
            (0, -36), (0, 30),
            (0, -54), (0, 48),
        ]
    }

    /// Each labeled point's frame, by `Point.id`. The focus and the peers always
    /// get a frame (their default slot when nothing is clear); a landmark with no
    /// clear slot gets none.
    private func placedLabels(box: CGSize) -> [String: CGRect] {
        var blocked = dotBounds(box: box) + vertexLabelBounds(box: box)
        var placed: [String: CGRect] = [:]
        for point in labeledPoints {
            let center = position(point.shares, box: box)
            let frames = slots(defaultDY: defaultLabelDY(center, box: box))
                .map { labelFrame(around: center, dx: $0.dx, dy: $0.dy, box: box) }
            let clear = frames.first { frame in
                let text = textBounds(point.name, in: frame)
                return !blocked.contains { $0.intersects(text) }
            }
            let isLandmark = !point.isFocus && !point.isGated
            guard let frame = clear ?? (isLandmark ? nil : frames.first) else { continue }
            placed[point.id] = frame
            blocked.append(textBounds(point.name, in: frame))
        }
        return placed
    }

    private func defaultLabelDY(_ center: CGPoint, box: CGSize) -> CGFloat {
        center.y >= box.height * 0.45 ? -22 : 12
    }

    private func labelFrame(around center: CGPoint, dx: CGFloat, dy: CGFloat, box: CGSize) -> CGRect {
        let x = min(max(center.x + dx - Self.labelWidth / 2, 0), box.width - Self.labelWidth)
        let y = min(max(center.y + dy, 0), box.height - Self.labelHeight)
        return CGRect(x: x, y: y, width: Self.labelWidth, height: Self.labelHeight)
    }

    /// The span the text itself covers inside a 92pt label frame — collisions are
    /// judged on this, since a frame is mostly empty around a short name.
    private func textBounds(_ name: String, in frame: CGRect) -> CGRect {
        let width = min(frame.width, CGFloat(name.count) * 5.6 + 6)
        return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
    }

    /// Everything a selected label must not print over: every label that is
    /// showing, every dot, and the three vertex names.
    private func obstacles(box: CGSize, placed: [String: CGRect]) -> [CGRect] {
        let labels = labeledPoints
            .filter { $0.id != selectedID }
            .compactMap { point in placed[point.id].map { textBounds(point.name, in: $0) } }
        return labels + dotBounds(box: box) + vertexLabelBounds(box: box)
    }

    private func selectedPlacement(
        _ point: TransporterTernaryModel.Point, box: CGSize, placed: [String: CGRect],
    ) -> Placement {
        let center = position(point.shares, box: box)
        let blocked = obstacles(box: box, placed: placed)
        let frames = slots(defaultDY: defaultLabelDY(center, box: box))
            .map { labelFrame(around: center, dx: $0.dx, dy: $0.dy, box: box) }
        let index = frames.firstIndex { frame in
            let text = textBounds(point.name, in: frame)
            return !blocked.contains { $0.intersects(text) }
        } ?? 0
        let frame = frames[index]
        guard index > 0 else { return Placement(frame: frame, leader: nil) }

        // The line runs from the dot's rim to the nearest edge of the text itself.
        let text = textBounds(point.name, in: frame)
        let to = CGPoint(
            x: min(max(center.x, text.minX), text.maxX),
            y: min(max(center.y, text.minY), text.maxY),
        )
        let length = max(distance(center, to), 1)
        let radius: CGFloat = 5.5
        let from = CGPoint(
            x: center.x + (to.x - center.x) / length * radius,
            y: center.y + (to.y - center.y) / length * radius,
        )
        return Placement(frame: frame, leader: (from, to))
    }

    private static let vertexLabelWidth: CGFloat = 56

    private func vertexLabelFrame(at point: CGPoint, box: CGSize, anchor: Alignment, dy: CGFloat) -> CGRect {
        let width = Self.vertexLabelWidth
        let dx: CGFloat = switch anchor {
        case .leading: 0
        case .trailing: -width
        default: -width / 2
        }
        let clamped = min(max(point.x + dx, 0), box.width - width)
        return CGRect(x: clamped, y: point.y + dy, width: width, height: Self.labelHeight)
    }

    private func vertexLabel(
        _ text: String,
        at point: CGPoint,
        box: CGSize,
        anchor: Alignment,
        dy: CGFloat,
    ) -> some View {
        let frame = vertexLabelFrame(at: point, box: box, anchor: anchor, dy: dy)
        return Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: frame.width, alignment: anchor == .center ? .center : (anchor == .leading ? .leading : .trailing))
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityHidden(true)
    }

    private nonisolated struct TriangleShape: Shape {
        let vertices: Vertices

        func path(in _: CGRect) -> Path {
            var path = Path()
            path.move(to: vertices.apex)
            path.addLine(to: vertices.trailing)
            path.addLine(to: vertices.leading)
            path.closeSubpath()
            return path
        }
    }

    /// Quarter-share guide lines, so the reader can eyeball "about a third DAT" instead of guessing.
    private nonisolated struct GridLines: Shape {
        let vertices: Vertices

        func path(in _: CGRect) -> Path {
            var path = Path()
            for fraction in [0.25, 0.5, 0.75] {
                let a = lerp(vertices.leading, vertices.apex, fraction)
                let b = lerp(vertices.trailing, vertices.apex, fraction)
                let c = CGPoint(x: lerp(vertices.leading, vertices.trailing, fraction).x, y: vertices.leading.y)
                path.move(to: a); path.addLine(to: b)
                path.move(to: a); path.addLine(to: c)
                path.move(to: b); path.addLine(to: c)
            }
            return path
        }

        private func lerp(_ from: CGPoint, _ to: CGPoint, _ fraction: Double) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
        }
    }
}

// MARK: - Degraded form

/// The triangle as three rows, for accessibility text sizes where the vertex labels cannot clear the
/// plot.
private struct TernaryShareList: View {
    let triple: TransporterTernaryModel.Triple
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            row(SignatureTarget.dat.label, share: triple.focus.shares.dat, value: triple.focus.values.dat)
            row(SignatureTarget.net.label, share: triple.focus.shares.net, value: triple.focus.values.net)
            row(SignatureTarget.sert.label, share: triple.focus.shares.sert, value: triple.focus.values.sert)
        }
    }

    private func row(_ label: String, share: Double, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Spacing.md) {
                Text(label).font(.subheadline.weight(.bold))
                Spacer(minLength: 6)
                Text(ClassSignature.shortNanomolar(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
                Text((share * 100).formatted(.number.precision(.fractionLength(0 ... 0))) + "%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.14)).frame(height: 6)
                    Capsule().fill(accent).frame(width: max(4, geo.size.width * share), height: 6)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}
