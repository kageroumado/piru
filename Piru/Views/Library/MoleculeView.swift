import SwiftUI

/// A single hero molecule's 2D skeleton: atom coordinates in a `0...100` box
/// (y already in screen space) and the heavy-atom bonds between them.
///
/// Decoded from the bundled `MoleculeShapes.json`, which is built offline from
/// PubChem 2D structures — hydrogens stripped, then principal-axis-rotated to
/// the textbook "ring left / chain right" reading orientation. Bond *order* is
/// deliberately dropped: the card draws single sticks of uniform weight so the
/// molecule reads as a calm decorative hint, not a technical diagram.
struct MoleculeShape: Decodable {
    let atoms: [[Double]]
    let bonds: [[Int]]
}

/// Loads and caches the bundled hero-molecule shapes. One molecule per Library
/// family (plus a stylised peptide backbone — real peptides are far too large
/// to read at card scale).
enum MoleculeLibrary {
    static let shapes: [String: MoleculeShape] = {
        guard let url = Bundle.main.url(forResource: "MoleculeShapes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: MoleculeShape].self, from: data)
        else { return [:] }
        return decoded
    }()

    static func shape(_ key: String) -> MoleculeShape? {
        shapes[key]
    }
}

/// Ball-and-stick renderer for a hero molecule: single sticks, uniform balls,
/// monochrome. Drawn faint and oversized as a "hint" bleeding off the trailing
/// edge of a Library family card. Coordinates live in a `0...100` box with an
/// 8-unit margin (a 116-unit drawing space), matched to the design prototype.
struct MoleculeView: View {
    let key: String
    var color: Color = .white
    /// Stroke and ball weight at the reference 116-unit scale; scaled to the view.
    var lineWidth: CGFloat = 2.4
    var ballRadius: CGFloat = 3.0

    private nonisolated static let drawingBox: CGFloat = 116
    private nonisolated static let margin: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            guard let shape = MoleculeLibrary.shape(key), !shape.atoms.isEmpty else { return }
            let scale = min(size.width, size.height) / Self.drawingBox

            func point(_ index: Int) -> CGPoint? {
                guard shape.atoms.indices.contains(index) else { return nil }
                let a = shape.atoms[index]
                guard a.count >= 2 else { return nil }
                return CGPoint(
                    x: (CGFloat(a[0]) + Self.margin) * scale,
                    y: (CGFloat(a[1]) + Self.margin) * scale,
                )
            }

            var sticks = Path()
            for bond in shape.bonds where bond.count == 2 {
                guard let a = point(bond[0]), let b = point(bond[1]) else { continue }
                sticks.move(to: a)
                sticks.addLine(to: b)
            }
            context.stroke(
                sticks,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round),
            )

            let r = ballRadius * scale
            for index in shape.atoms.indices {
                guard let p = point(index) else { continue }
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(color),
                )
            }
        }
        .accessibilityHidden(true)
    }
}
