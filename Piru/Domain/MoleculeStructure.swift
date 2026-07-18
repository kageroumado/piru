import Foundation

/// A substance's 2D skeletal-structure diagram: atom positions and the bonds
/// between them, ready to draw. Generated offline at build time from the
/// substance's SMILES via OpenBabel (`pipeline/build/molecule_shapes.py`) and
/// stored in the bundled DB's `molecule_shapes` table — one row per substance,
/// keyed on `substance_id`.
///
/// Coordinates already live in a `0...100` box (a small margin baked in,
/// aspect ratio preserved) with Y in screen space (grows downward) — the
/// renderer draws them directly with no further transform.
struct MoleculeStructure: Hashable, Sendable {
    let atoms: [MoleculeAtom]
    let bonds: [MoleculeBond]
}

/// One heavy atom (hydrogens are stripped, matching how the diagram reads —
/// implicit hydrogens on carbon, explicit only via the label conventions the
/// renderer applies).
struct MoleculeAtom: Hashable, Sendable {
    /// Element symbol ("C", "N", "O", "Cl", …).
    let element: String
    /// Position in the `0...100` box.
    let x: Double
    let y: Double
}

/// A bond between two atom indices (0-based, into the owning
/// ``MoleculeStructure/atoms`` array).
struct MoleculeBond: Hashable, Sendable {
    let a: Int
    let b: Int
    /// 1 = single, 2 = double, 3 = triple.
    let order: Int
}
