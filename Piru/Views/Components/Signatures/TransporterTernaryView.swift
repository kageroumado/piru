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
        VStack(alignment: .leading, spacing: 9) {
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
                // rather than on lines of their own. The basis has to stay visible — a
                // release EC₅₀ and a blocker's IC₅₀ are different axes, and that is
                // the whole reason this view has a basis switch — but it is a label
                // on the picture, not a sentence about it.
                //
                // Per-transporter percentages are deliberately absent. The triangle's
                // point is the *position*: which corner a compound leans to and how
                // far it sits from its neighbours. "DAT 33% · NET 66% · SERT 1%"
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
                                CitationLink(url: url, size: 10)
                            }
                            Text(Self.captionBasis(triple))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .padding(.trailing, 2)
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
                    .stroke(Theme.secondaryLabel.opacity(0.10), lineWidth: 1)

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
                    dot(ghost, box: box, radius: 3, filled: false)
                }
                // Name the best-known few. The context cloud only means something
                // if the reader recognizes what is in it — landmarks, not a count.
                // Kept to `namedGhostLimit` so labels stay legible; the plot is
                // ~300pt wide and every label is a 92pt box.
                ForEach(namedGhosts) { ghost in
                    if ghost.id != selectedID {
                        label(ghost, box: box)
                    }
                }
                ForEach(triple.peers) { peer in
                    dot(peer, box: box, radius: 4.5, filled: true)
                    if peer.id != selectedID {
                        label(peer, box: box)
                    }
                }
                dot(triple.focus, box: box, radius: 8, filled: true)
                label(triple.focus, box: box)

                if let selected {
                    selectedLabel(selected, box: box)
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
            Color(.systemBackground)
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

    private func label(_ point: TransporterTernaryModel.Point, box: CGSize) -> some View {
        let frame = labelFrame(point, box: box)
        return Text(point.name)
            .font(.system(size: 9.5, weight: point.isFocus ? .bold : .medium))
            // Context names sit a step back from the gated peers so the triangle
            // still reads focus → same-study peers → landmarks, not one flat list.
            .foregroundStyle(point.isFocus ? accent : Theme.secondaryLabel.opacity(point.isGated ? 1 : 0.65))
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
    private func selectedLabel(_ point: TransporterTernaryModel.Point, box: CGSize) -> some View {
        let placement = selectedPlacement(point, box: box)
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

    /// The label's 92pt frame in its default slot: above the dot, or underneath
    /// it near the DAT apex, kept inside the plot horizontally.
    private func labelFrame(_ point: TransporterTernaryModel.Point, box: CGSize) -> CGRect {
        let center = position(point.shares, box: box)
        return labelFrame(around: center, dx: 0, dy: defaultLabelDY(center, box: box), box: box)
    }

    private func defaultLabelDY(_ center: CGPoint, box: CGSize) -> CGFloat {
        center.y >= box.height * 0.45 ? -18 : 12
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
    /// showing, the focus dot, and the three vertex names.
    private func obstacles(box: CGSize) -> [CGRect] {
        var rects = ([triple.focus] + triple.peers + namedGhosts)
            .filter { $0.id != selectedID }
            .map { textBounds($0.name, in: labelFrame($0, box: box)) }
        let focus = position(triple.focus.shares, box: box)
        rects.append(CGRect(x: focus.x - 8, y: focus.y - 8, width: 16, height: 16))
        let v = vertices(box)
        rects.append(vertexLabelFrame(at: v.apex, box: box, anchor: .center, dy: -15))
        rects.append(vertexLabelFrame(at: v.leading, box: box, anchor: .leading, dy: 11))
        rects.append(vertexLabelFrame(at: v.trailing, box: box, anchor: .trailing, dy: 11))
        return rects
    }

    private func selectedPlacement(_ point: TransporterTernaryModel.Point, box: CGSize) -> Placement {
        let center = position(point.shares, box: box)
        let defaultDY = defaultLabelDY(center, box: box)
        // Default slot first, then the opposite side, then one step further out,
        // then beside the dot, then two steps out.
        let slots: [(dx: CGFloat, dy: CGFloat)] = [
            (0, defaultDY), (0, defaultDY < 0 ? 12 : -18),
            (0, -36), (0, 30),
            (56, -6), (-56, -6),
            (0, -54), (0, 48),
        ]
        let blocked = obstacles(box: box)
        let frames = slots.map { labelFrame(around: center, dx: $0.dx, dy: $0.dy, box: box) }
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

    private struct TriangleShape: Shape {
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
    private struct GridLines: Shape {
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
        VStack(alignment: .leading, spacing: 7) {
            row(SignatureTarget.dat.label, share: triple.focus.shares.dat, value: triple.focus.values.dat)
            row(SignatureTarget.net.label, share: triple.focus.shares.net, value: triple.focus.values.net)
            row(SignatureTarget.sert.label, share: triple.focus.shares.sert, value: triple.focus.values.sert)
        }
    }

    private func row(_ label: String, share: Double, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
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
