"""Generate 2D skeletal-diagram coordinates for substances, offline and
deterministic given a committed SMILES.

Piru's Chemistry card draws a labeled skeletal structure (bonds as sticks,
double/triple bonds as parallel lines, heteroatoms labeled) for every
substance that has a SMILES. RDKit's CoordGen depiction produces the 2D
layout; this module reorients it and turns it into the flat, normalized rows
``pipeline/build/sqlite.py`` stores in the ``molecule_shapes`` table.
"""

from __future__ import annotations

import math

# Target coordinate box (square) each molecule is normalized into. Aspect
# ratio is preserved — a long, thin molecule fills one axis and is centered on
# the other, never stretched.
DEFAULT_BOX = 100.0
# Wider than the decorative hero molecules' 8/116 ratio (~6.9%) because this
# renderer draws element-symbol labels at the atom positions — a label needs
# more edge headroom than a bare dot to avoid clipping near the canvas border.
DEFAULT_MARGIN = 9.0


def _ring_atoms(n: int, bonds: list[tuple[int, int, int]]) -> set[int]:
    """Indices of atoms that lie in a ring (the graph's 2-core), found by
    iteratively pruning terminal (degree ≤ 1) atoms until only cycles remain."""
    adj: dict[int, set[int]] = {i: set() for i in range(n)}
    for a, b, _ in bonds:
        if a != b:
            adj[a].add(b)
            adj[b].add(a)
    alive = set(range(n))
    changed = True
    while changed:
        changed = False
        for i in list(alive):
            if sum(1 for j in adj[i] if j in alive) <= 1:
                alive.discard(i)
                changed = True
    return alive


def _orient(
    atoms: list[tuple[str, float, float]],
    bonds: list[tuple[int, int, int]],
) -> list[tuple[str, float, float]]:
    """Rotate a molecule into the textbook reading orientation: its long
    (principal) axis horizontal, and — when it has a ring system — the ring on
    the LEFT with the chain/substituent tail trailing to the RIGHT. This matches
    how chemists draw amines (ring left, N tail right) and keeps every card's
    molecule reading consistently instead of at the depiction's arbitrary angle.
    """
    n = len(atoms)
    if n < 3:
        return atoms
    cx = sum(a[1] for a in atoms) / n
    cy = sum(a[2] for a in atoms) / n
    ring = _ring_atoms(n, bonds)

    # Orientation angle. For a ring molecule, align the main exocyclic bond
    # (ring → substituent chain) horizontal — this reproduces the canonical
    # textbook ring pose (attachment at the ring's right vertex, flat top/bottom)
    # far better than a whole-molecule principal-axis fit, which tilts the ring.
    # Ringless molecules fall back to the principal axis.
    theta: float | None = None
    has_para = False
    aryl_ketone = False
    if ring:
        adj: dict[int, list[int]] = {i: [] for i in range(n)}
        for a, b, _ in bonds:
            if a != b:
                adj[a].append(b)
                adj[b].append(a)
        # exocyclic bonds, oriented ring-atom (r) → chain-atom (s)
        exo = [(a, b) if a in ring else (b, a) for a, b, _ in bonds if (a in ring) != (b in ring)]
        if exo:

            def _fragment_size(s: int) -> int:
                seen = {s}
                stack = [s]
                while stack:
                    u = stack.pop()
                    for v in adj[u]:
                        if v not in seen and v not in ring:
                            seen.add(v)
                            stack.append(v)
                return len(seen)

            r, s = max(exo, key=lambda rs: _fragment_size(rs[1]))
            exo_angle = math.atan2(atoms[s][2] - atoms[r][2], atoms[s][1] - atoms[r][1])
            # The exocyclic bond is radial to the ring, so its final direction
            # fixes the ring's rotation. Two textbook poses:
            #  • +30° (up-right) → ring on the LEFT, chain trailing up-right. The
            #    canonical amine pose (amphetamine, methamphetamine).
            #  • 0° (horizontal) → ring on the LEFT reading left-to-right. The
            #    canonical cathinone pose (methcathinone/mephedrone: aryl ketone
            #    up, chain to the right; any para substituent points straight LEFT
            #    opposite the chain). At +30° a para group swings out to the
            #    lower-left and the whole molecule reads as a tilted, diagonal ring.
            # Horizontal is chosen for aryl ketones (cathinones) and for any ring
            # with a para substituent.
            s_is_carbonyl = any(
                order == 2 and s in (u, v) and (atoms[u][0] == "O" or atoms[v][0] == "O")
                for u, v, order in bonds
            )
            aryl_ketone = s_is_carbonyl
            # Detect the para case: another substituent on the ring roughly
            # opposite (≈180° around the ring centroid) the chain's ipso atom.
            rcx = sum(atoms[i][1] for i in ring) / len(ring)
            rcy = sum(atoms[i][2] for i in ring) / len(ring)
            ipso_angle = math.atan2(atoms[r][2] - rcy, atoms[r][1] - rcx)
            for r2, _s2 in exo:
                if r2 == r:
                    continue
                a2 = math.atan2(atoms[r2][2] - rcy, atoms[r2][1] - rcx)
                delta = abs((a2 - ipso_angle + math.pi) % (2 * math.pi) - math.pi)
                if delta > math.radians(150):
                    has_para = True
                    break
            theta = exo_angle - math.radians(0 if (has_para or aryl_ketone) else 30)
    if theta is None:
        sxx = sum((a[1] - cx) ** 2 for a in atoms)
        syy = sum((a[2] - cy) ** 2 for a in atoms)
        sxy = sum((a[1] - cx) * (a[2] - cy) for a in atoms)
        theta = 0.5 * math.atan2(2 * sxy, sxx - syy)

    ct, st = math.cos(-theta), math.sin(-theta)
    rot = [(el, (x - cx) * ct - (y - cy) * st, (x - cx) * st + (y - cy) * ct) for el, x, y in atoms]
    # For the +30° amine pose, geometry already puts the ring on the left with
    # the chain trailing up-right (a phenethylamine), so no vertical flip — an
    # explicit "heteroatom up" flip would invert the chain back down.
    #
    # For the horizontal (cathinone) pose, RDKit's zig-zag may land the carbonyl
    # below the chain axis. Textbooks draw the aryl ketone pointing UP, so flip
    # vertically when it doesn't. _normalize folds math-Y (up) to screen-Y (down),
    # so "renders on top" == larger rot-Y; flip when the carbonyl O sits below the
    # ring.
    if has_para or aryl_ketone:
        carbonyl_o = [i for (u, v, o) in bonds if o == 2 for i in (u, v) if atoms[i][0] == "O"]
        if carbonyl_o:
            oy = sum(rot[i][2] for i in carbonyl_o) / len(carbonyl_o)
            ring_y = sum(rot[i][2] for i in ring) / len(ring)
            if oy < ring_y:
                rot = [(el, x, -y) for el, x, y in rot]
    return rot


def _normalize(
    atoms: list[tuple[str, float, float]],
    bonds: list[tuple[int, int, int]],
    *,
    box: float,
    margin: float,
) -> dict | None:
    """Fit ``atoms`` into a ``0...box`` square (aspect-ratio preserved, atoms
    centered, an ``margin``-unit border on every side) and flip Y so it reads
    upright in screen space (Y grows downward), returning the JSON-ready shape
    dict, or ``None`` for a degenerate (empty) atom list.
    """
    if not atoms:
        return None
    xs = [a[1] for a in atoms]
    ys = [a[2] for a in atoms]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    # Guard a single atom / perfectly collinear molecule (zero span).
    span = max(max_x - min_x, max_y - min_y, 1e-6)
    usable = box - 2 * margin
    scale = usable / span
    drawn_w = (max_x - min_x) * scale
    drawn_h = (max_y - min_y) * scale
    off_x = margin + (usable - drawn_w) / 2
    off_y = margin + (usable - drawn_h) / 2

    out_atoms = []
    for element, x, y in atoms:
        nx = off_x + (x - min_x) * scale
        # (x, y) is math-orientation (Y up); fold to a box-relative Y-up value
        # first, then flip to screen space (Y down) in one step.
        y_up = off_y + (y - min_y) * scale
        ny = box - y_up
        out_atoms.append({"el": element, "x": round(nx, 2), "y": round(ny, 2)})

    out_bonds = [{"a": a, "b": b, "order": order} for a, b, order in bonds]
    return {"atoms": out_atoms, "bonds": out_bonds}


def generate_molecule_shapes(
    pairs: list[tuple[str, str]],
    *,
    box: float = DEFAULT_BOX,
    margin: float = DEFAULT_MARGIN,
) -> tuple[dict[str, dict], list[str]]:
    """Generate normalized 2D skeletal shapes for every ``(key, smiles)`` pair
    via RDKit's canonical depiction (proper 120-degree angles, standard bond
    lengths, ring templates — a textbook layout), then a light rigid
    reorientation (:func:`_orient`) for a consistent reading direction across
    the app. Offline and deterministic.

    Returns ``(shapes_by_key, failed_keys)``. If RDKit is unavailable every key
    comes back failed rather than raising.
    """
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import rdDepictor
    except ImportError:
        return {}, [k for k, _ in pairs]
    RDLogger.DisableLog("rdApp.*")  # silence per-molecule parse noise
    rdDepictor.SetPreferCoordGen(True)  # CoordGen: cleaner, template-based layout

    shapes: dict[str, dict] = {}
    failed: list[str] = []
    for key, smiles in pairs:
        if not smiles or not smiles.strip():
            failed.append(key)
            continue
        try:
            mol = Chem.MolFromSmiles(smiles)
            if mol is None:
                failed.append(key)
                continue
            Chem.Kekulize(mol, clearAromaticFlags=True)
            rdDepictor.Compute2DCoords(mol)
            conf = mol.GetConformer()
            atoms = [
                (atom.GetSymbol(), conf.GetAtomPosition(i).x, conf.GetAtomPosition(i).y)
                for i, atom in enumerate(mol.GetAtoms())
            ]
            bonds = [
                (b.GetBeginAtomIdx(), b.GetEndAtomIdx(), int(round(b.GetBondTypeAsDouble())))
                for b in mol.GetBonds()
            ]
            shape = _normalize(_orient(atoms, bonds), bonds, box=box, margin=margin)
            if shape is None:
                failed.append(key)
            else:
                shapes[key] = shape
        except Exception:  # noqa: BLE001 - one bad molecule must not sink the batch
            failed.append(key)
    return shapes, failed
