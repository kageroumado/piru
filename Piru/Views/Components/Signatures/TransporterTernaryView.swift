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
                TernaryPlot(triple: triple, accent: accent)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @Environment(\.layoutDirection) private var layoutDirection

    private static let height: CGFloat = 196
    private static let labelWidth: CGFloat = 92
    /// How many context dots get named. Four is what fits a ~300pt plot without
    /// labels colliding; the rest stay unnamed dots that still show the spread.
    private static let namedGhostLimit = 4

    /// The best-known context compounds, skipping any that would print on top of
    /// a peer or the focus — those already carry their own label.
    private var namedGhosts: [TransporterTernaryModel.Point] {
        let taken = Set(triple.peers.map(\.name) + [triple.focus.name])
        return triple.ghosts
            .filter { !taken.contains($0.name) && $0.popularity > 0 }
            .prefix(Self.namedGhostLimit)
            .map(\.self)
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

                ForEach(triple.ghosts) { ghost in
                    dot(ghost, box: box, radius: 3, filled: false)
                }
                // Name the best-known few. The context cloud only means something
                // if the reader recognizes what is in it — landmarks, not a count.
                // Kept to `namedGhostLimit` so labels stay legible; the plot is
                // ~300pt wide and every label is a 92pt box.
                ForEach(namedGhosts) { ghost in
                    label(ghost, box: box)
                }
                ForEach(triple.peers) { peer in
                    dot(peer, box: box, radius: 4.5, filled: true)
                    label(peer, box: box)
                }
                dot(triple.focus, box: box, radius: 8, filled: true)
                label(triple.focus, box: box)

                vertexLabel(SignatureTarget.dat.label, at: vertices(box).apex, box: box, anchor: .center, dy: -15)
                vertexLabel(SignatureTarget.net.label, at: vertices(box).leading, box: box, anchor: .leading, dy: 11)
                vertexLabel(SignatureTarget.sert.label, at: vertices(box).trailing, box: box, anchor: .trailing, dy: 11)
            }
            .frame(width: box.width, height: box.height)
            .signaturePlotPinnedToLTR()
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Transporter potency share", comment: "Accessibility label for the SERT/DAT/NET ternary plot"),
        )
        .accessibilityValue(Text(TransporterTernaryView.shareLine(triple.focus.shares)))
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
        let tint = point.isFocus ? accent : Theme.secondaryLabel
        return Circle()
            .fill(filled ? tint.opacity(point.isFocus ? 1 : 0.5) : Color.clear)
            .overlay(
                Circle().strokeBorder(
                    point.isFocus ? Color(.systemBackground) : tint.opacity(filled ? 0 : 0.35),
                    lineWidth: point.isFocus ? 2.5 : 1,
                ),
            )
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: center.x - radius, y: center.y - radius)
    }

    private func label(_ point: TransporterTernaryModel.Point, box: CGSize) -> some View {
        let center = position(point.shares, box: box)
        // Near the DAT apex the label goes underneath the dot; elsewhere above it.
        let above = center.y >= box.height * 0.45
        let clamped = min(max(center.x, Self.labelWidth / 2), box.width - Self.labelWidth / 2)
        return Text(point.name)
            .font(.system(size: 9.5, weight: point.isFocus ? .bold : .medium))
            // Context names sit a step back from the gated peers so the triangle
            // still reads focus → same-study peers → landmarks, not one flat list.
            .foregroundStyle(point.isFocus ? accent : Theme.secondaryLabel.opacity(point.isGated ? 1 : 0.65))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: Self.labelWidth)
            .offset(x: clamped - Self.labelWidth / 2, y: center.y + (above ? -18 : 12))
    }

    private func vertexLabel(
        _ text: String,
        at point: CGPoint,
        box: CGSize,
        anchor: Alignment,
        dy: CGFloat,
    ) -> some View {
        let width: CGFloat = 56
        let dx: CGFloat = switch anchor {
        case .leading: 0
        case .trailing: -width
        default: -width / 2
        }
        let clamped = min(max(point.x + dx, 0), box.width - width)
        return Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: anchor == .center ? .center : (anchor == .leading ? .leading : .trailing))
            .offset(x: clamped, y: point.y + dy)
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
