import SwiftUI

/// A labeled 2D skeletal-structure diagram for a substance's Chemistry card:
/// bonds drawn as sticks (double/triple bonds as parallel lines), heteroatoms
/// labeled with their element symbol, carbons left implicit (bare vertices —
/// the standard skeletal-formula convention). Monochrome, matching the app's
/// restraint — not the rainbow CPK coloring a full chemistry tool would use.
///
/// Coordinates come from ``MoleculeStructure``, already normalized into a
/// `0...100` box with margin baked in (`pipeline/build/molecule_shapes.py`);
/// this view just scales that box to fit its frame.
///
/// Bond lines are shortened near a labeled endpoint rather than drawn full
/// length and painted over with an opaque "knockout" rectangle — the
/// Chemistry card's background is a translucent material (`CardBackground`,
/// `.ultraThinMaterial` in light mode), so a flat rectangle can't reliably
/// match it. Stopping the line short of the glyph is the same technique real
/// cheminformatics renderers (RDKit, ChemDraw) use, and it's correct
/// regardless of what's behind the canvas.
struct MoleculeStructureView: View {
    let structure: MoleculeStructure
    /// Read into the VoiceOver summary alongside the atom count — pass the
    /// substance's formula for a meaningful value ("C17H21NO4").
    var formula: String?
    var color: Color = .primary
    var lineWidth: CGFloat = 1.6

    /// The coordinate space every atom position already lives in.
    private nonisolated static let box: CGFloat = 100
    /// How far (in box units) a bond stops short of a labeled atom's center,
    /// so the stroke never runs under the element-symbol glyph.
    private nonisolated static let labelInset: CGFloat = 6.5
    /// Perpendicular spacing (in box units) between the parallel lines of a
    /// double/triple bond.
    private nonisolated static let multiBondGap: CGFloat = 3.2

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityElement(children: .ignore)
        .chartSummaryAccessibility(
            label: Text("Molecular structure"),
            value: formula.map { Text($0) } ?? Text("\(structure.atoms.count) atoms"),
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard !structure.atoms.isEmpty else { return }
        let scale = min(size.width, size.height) / Self.box
        let offsetX = (size.width - Self.box * scale) / 2
        let offsetY = (size.height - Self.box * scale) / 2

        func point(_ index: Int) -> CGPoint? {
            guard structure.atoms.indices.contains(index) else { return nil }
            let atom = structure.atoms[index]
            return CGPoint(x: atom.x * scale + offsetX, y: atom.y * scale + offsetY)
        }
        func isHeteroatom(_ index: Int) -> Bool {
            structure.atoms.indices.contains(index) && structure.atoms[index].element != "C"
        }

        // Molecule centroid — the inner line of a double bond is drawn on the
        // side facing it, which reads as the textbook skeletal convention
        // (inner line inside a ring, not a symmetric railroad track).
        let centerPoints = structure.atoms.indices.compactMap(point)
        let centroid = CGPoint(
            x: centerPoints.map(\.x).reduce(0, +) / CGFloat(max(centerPoints.count, 1)),
            y: centerPoints.map(\.y).reduce(0, +) / CGFloat(max(centerPoints.count, 1)),
        )

        var sticks = Path()
        for bond in structure.bonds {
            guard let a = point(bond.a), let b = point(bond.b) else { continue }
            let start = isHeteroatom(bond.a) ? Self.inset(a, towards: b, by: Self.labelInset * scale) : a
            let end = isHeteroatom(bond.b) ? Self.inset(b, towards: a, by: Self.labelInset * scale) : b
            Self.appendBondLines(
                &sticks, from: start, to: end, order: bond.order,
                gap: Self.multiBondGap * scale, centroid: centroid,
            )
        }
        context.stroke(
            sticks,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
        )

        for (index, atom) in structure.atoms.enumerated() where atom.element != "C" {
            guard let p = point(index) else { continue }
            context.draw(
                Text(atom.element).font(.caption2.weight(.bold)).foregroundStyle(color),
                at: p,
            )
        }
    }

    /// Moves `point` a fixed distance towards `other`, capped at 40% of the
    /// segment so a very short bond (common in fused rings) never collapses
    /// to nothing.
    private static func inset(_ point: CGPoint, towards other: CGPoint, by amount: CGFloat) -> CGPoint {
        let dx = other.x - point.x
        let dy = other.y - point.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return point }
        let t = min(amount / length, 0.4)
        return CGPoint(x: point.x + dx * t, y: point.y + dy * t)
    }

    /// Appends one, two, or three parallel line segments between `start` and
    /// `end` depending on bond `order` (double/triple bonds fan out
    /// perpendicular to the bond axis). Any order outside 1...3 (e.g. a raw
    /// aromatic bond type that slipped through) falls back to a single line
    /// rather than drawing nothing.
    private static func appendBondLines(_ path: inout Path, from start: CGPoint, to end: CGPoint, order: Int, gap: CGFloat, centroid: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return }
        let perpX = -dy / length
        let perpY = dx / length

        /// The main bond always sits on the axis, full length.
        func full(offset: CGFloat) {
            path.move(to: CGPoint(x: start.x + perpX * offset, y: start.y + perpY * offset))
            path.addLine(to: CGPoint(x: end.x + perpX * offset, y: end.y + perpY * offset))
        }

        switch order {
        case 2:
            full(offset: 0)
            // Second line offset toward the molecule interior, inset from both
            // ends — the standard skeletal double-bond look.
            let midX = (start.x + end.x) / 2
            let midY = (start.y + end.y) / 2
            let side: CGFloat = ((centroid.x - midX) * perpX + (centroid.y - midY) * perpY) >= 0 ? 1 : -1
            let t: CGFloat = 0.16
            path.move(to: CGPoint(x: start.x + dx * t + perpX * gap * side, y: start.y + dy * t + perpY * gap * side))
            path.addLine(to: CGPoint(x: end.x - dx * t + perpX * gap * side, y: end.y - dy * t + perpY * gap * side))
        case 3:
            full(offset: -gap)
            full(offset: 0)
            full(offset: gap)
        default:
            full(offset: 0)
        }
    }
}
