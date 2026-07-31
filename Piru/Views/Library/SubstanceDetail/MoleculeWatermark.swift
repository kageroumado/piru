import SwiftUI

/// The substance's own skeleton, drawn faint and oversized behind the detail
/// header — the same ball-and-stick idiom the Library family cards use
/// (``MoleculeView``): uniform sticks, uniform balls, monochrome, bond order
/// deliberately dropped so it reads as a calm hint rather than a diagram.
///
/// Distinct from ``MoleculeStructureView``, which is the *real* diagram on the
/// Chemistry card — labeled heteroatoms, double bonds, correct proportions.
/// This one is decoration: it bleeds off the trailing edge and is never the
/// thing being read, so it is `accessibilityHidden`.
struct MoleculeWatermark: View {
    let structure: MoleculeStructure
    var color: Color = .primary
    /// Stroke and ball weight at the reference 100-unit coordinate box.
    var lineWidth: CGFloat = 2.4
    var ballRadius: CGFloat = 3.0

    var body: some View {
        Canvas { context, size in
            guard !structure.atoms.isEmpty else { return }
            // Coordinates live in a 0…100 box; scale to the shorter edge so the
            // molecule keeps its aspect and simply overflows the frame.
            let scale = min(size.width, size.height) / 100

            func point(_ index: Int) -> CGPoint? {
                guard structure.atoms.indices.contains(index) else { return nil }
                let atom = structure.atoms[index]
                return CGPoint(x: CGFloat(atom.x) * scale, y: CGFloat(atom.y) * scale)
            }

            var sticks = Path()
            for bond in structure.bonds {
                guard let a = point(bond.a), let b = point(bond.b) else { continue }
                sticks.move(to: a)
                sticks.addLine(to: b)
            }
            context.stroke(
                sticks,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round),
            )

            let radius = ballRadius * scale
            for index in structure.atoms.indices {
                guard let p = point(index) else { continue }
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color),
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
