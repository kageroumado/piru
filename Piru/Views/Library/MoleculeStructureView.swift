import SwiftUI

/// A labeled 2D skeletal-structure diagram for a substance's Chemistry card:
/// bonds drawn as sticks (double/triple bonds as inner-offset skeletal lines),
/// heteroatoms labeled with their element symbol, carbons left implicit (bare
/// vertices — the standard skeletal-formula convention). Monochrome, matching
/// the app's restraint — not the rainbow CPK coloring a full chemistry tool
/// would use.
///
/// The view sizes itself to the molecule's own aspect ratio and scales to the
/// atoms' actual bounds (not a padded square), so a wide molecule renders in a
/// short frame instead of floating in vertical whitespace. Coordinates come
/// from ``MoleculeStructure`` (`pipeline/build/molecule_shapes.py`).
///
/// Bond lines stop short of a labeled endpoint rather than being drawn full
/// length and painted over with an opaque knockout — the Chemistry card sits on
/// translucent material, so a flat rectangle can't match it. Stopping short is
/// the same technique real cheminformatics renderers use.
struct MoleculeStructureView: View {
    let structure: MoleculeStructure
    /// Read into the VoiceOver summary alongside the atom count — pass the
    /// substance's formula for a meaningful value ("C17H21NO4").
    var formula: String?
    var color: Color = .primary
    var lineWidth: CGFloat = 1.6

    /// Point padding reserved inside the canvas so element-symbol glyphs and the
    /// bond ends near them never clip against the frame edge.
    private nonisolated static let edgePadding: CGFloat = 14
    /// How far (points) a bond stops short of a labeled atom's center.
    private nonisolated static let labelInset: CGFloat = 9
    /// Perpendicular spacing (points) for the inner line of a double/triple bond.
    private nonisolated static let bondGap: CGFloat = 3.6

    private var bounds: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let xs = structure.atoms.map { CGFloat($0.x) }
        let ys = structure.atoms.map { CGFloat($0.y) }
        return (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
    }

    /// Width-to-height ratio of the molecule, clamped so a near-linear molecule
    /// doesn't collapse to a sliver and a tall one doesn't dominate the card.
    private var aspect: CGFloat {
        let b = bounds
        let w = max(b.maxX - b.minX, 0.001)
        let h = max(b.maxY - b.minY, 0.001)
        return min(max(w / h, 0.85), 3.0)
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .chartSummaryAccessibility(
            label: Text("Molecular structure"),
            value: formula.map { Text($0) } ?? Text("\(structure.atoms.count) atoms"),
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard !structure.atoms.isEmpty else { return }
        let b = bounds
        let w = max(b.maxX - b.minX, 0.001)
        let h = max(b.maxY - b.minY, 0.001)
        let pad = Self.edgePadding
        let scale = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h)
        let drawnW = w * scale
        let drawnH = h * scale
        let offX = (size.width - drawnW) / 2
        let offY = (size.height - drawnH) / 2

        func point(_ index: Int) -> CGPoint? {
            guard structure.atoms.indices.contains(index) else { return nil }
            let atom = structure.atoms[index]
            return CGPoint(
                x: offX + (CGFloat(atom.x) - b.minX) * scale,
                y: offY + (CGFloat(atom.y) - b.minY) * scale,
            )
        }
        func isHeteroatom(_ index: Int) -> Bool {
            structure.atoms.indices.contains(index) && structure.atoms[index].element != "C"
        }

        func centroid(of points: [CGPoint]) -> CGPoint {
            CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(max(points.count, 1)),
                y: points.map(\.y).reduce(0, +) / CGFloat(max(points.count, 1)),
            )
        }
        let moleculeCentroid = centroid(of: structure.atoms.indices.compactMap(point))
        // A ring double bond's inner line must be offset toward the ring's own
        // center, not the whole molecule's — a long substituent chain pulls the
        // molecule centroid off to one side, which would push an inner line
        // *outside* the ring.
        let ringAtoms = ringAtomIndices()
        let ringCentroid = ringAtoms.isEmpty
            ? moleculeCentroid
            : centroid(of: ringAtoms.compactMap(point))

        var sticks = Path()
        for bond in structure.bonds {
            guard let a = point(bond.a), let b2 = point(bond.b) else { continue }
            let start = isHeteroatom(bond.a) ? Self.inset(a, towards: b2, by: Self.labelInset) : a
            let end = isHeteroatom(bond.b) ? Self.inset(b2, towards: a, by: Self.labelInset) : b2
            let towards = (ringAtoms.contains(bond.a) && ringAtoms.contains(bond.b)) ? ringCentroid : moleculeCentroid
            Self.appendBondLines(&sticks, from: start, to: end, order: bond.order, gap: Self.bondGap, centroid: towards)
        }
        context.stroke(
            sticks,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
        )

        for (index, atom) in structure.atoms.enumerated() where atom.element != "C" {
            guard let p = point(index) else { continue }
            context.draw(
                Text(heteroatomLabel(index)).font(.caption2.weight(.bold)).foregroundStyle(color),
                at: p,
            )
        }
    }

    /// Indices of ring atoms (the bond graph's 2-core), by iteratively pruning
    /// terminal atoms — matches the pipeline's `_ring_atoms`.
    private func ringAtomIndices() -> Set<Int> {
        var adjacency: [Int: Set<Int>] = [:]
        for bond in structure.bonds where bond.a != bond.b {
            adjacency[bond.a, default: []].insert(bond.b)
            adjacency[bond.b, default: []].insert(bond.a)
        }
        var alive = Set(structure.atoms.indices)
        var changed = true
        while changed {
            changed = false
            for i in alive where (adjacency[i] ?? []).count(where: { alive.contains($0) }) <= 1 {
                alive.remove(i)
                changed = true
            }
        }
        return alive
    }

    /// A heteroatom's label with its implicit hydrogens spelled out the way a
    /// textbook does — "NH₂", "OH", "N" — computed from standard valence minus
    /// the atom's bond orders. Carbons stay implicit and aren't labeled.
    private func heteroatomLabel(_ index: Int) -> String {
        let element = structure.atoms[index].element
        let valence: Int? = switch element {
        case "N": 3
        case "O", "S": 2
        case "P": 3
        case "F", "Cl", "Br", "I": 1
        default: nil
        }
        guard let valence else { return element }
        let bondOrderSum = structure.bonds.reduce(0) { sum, bond in
            (bond.a == index || bond.b == index) ? sum + bond.order : sum
        }
        let hydrogens = max(0, valence - bondOrderSum)
        switch hydrogens {
        case 0: return element
        case 1: return "\(element)H"
        default:
            let subscripts = "₀₁₂₃₄₅₆₇₈₉"
            let digit = subscripts[subscripts.index(subscripts.startIndex, offsetBy: min(hydrogens, 9))]
            return "\(element)H\(digit)"
        }
    }

    /// Moves `point` towards `other` by `amount` points, capped at 40% of the
    /// segment so a very short bond never collapses to nothing.
    private static func inset(_ point: CGPoint, towards other: CGPoint, by amount: CGFloat) -> CGPoint {
        let dx = other.x - point.x
        let dy = other.y - point.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return point }
        let t = min(amount / length, 0.4)
        return CGPoint(x: point.x + dx * t, y: point.y + dy * t)
    }

    /// Appends the line(s) for a bond. A double bond is a full line on the axis
    /// plus a shorter inner line offset toward the molecule interior (the
    /// textbook skeletal look); a triple bond is three parallel lines.
    private static func appendBondLines(_ path: inout Path, from start: CGPoint, to end: CGPoint, order: Int, gap: CGFloat, centroid: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return }
        let perpX = -dy / length
        let perpY = dx / length

        func full(offset: CGFloat) {
            path.move(to: CGPoint(x: start.x + perpX * offset, y: start.y + perpY * offset))
            path.addLine(to: CGPoint(x: end.x + perpX * offset, y: end.y + perpY * offset))
        }

        switch order {
        case 2:
            full(offset: 0)
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
