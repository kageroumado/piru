"""Generate 2D skeletal-diagram coordinates for substances, offline, via
OpenBabel — no network, fully deterministic given a committed SMILES.

Piru's Chemistry card draws a labeled skeletal structure (bonds as sticks,
double/triple bonds as parallel lines, heteroatoms labeled) for every
substance that has a SMILES. OpenBabel's ``--gen2d`` produces the 2D layout;
this module turns that into the flat, normalized rows
``pipeline/build/sqlite.py`` stores in the ``molecule_shapes`` table.

Batching, not one-process-per-molecule: with 1000+ substances, shelling out to
``obabel`` once per SMILES is far too slow. Instead every SMILES is written to
one ``.smi`` file (one molecule per line, titled with its substance id) and
``obabel`` is invoked ONCE with ``--gen2d``, which streams back one
``$$$$``-delimited SDF record per successfully-parsed molecule.

The catch: OpenBabel's line-oriented ``.smi`` reader aborts the *entire read*
at the first malformed SMILES — everything after it in the file is silently
dropped, not just the bad line (verified empirically; there is no "skip and
continue" flag). ``generate_molecule_shapes`` works around this by re-driving
the batch: whenever the output has fewer records than the input batch, the
next un-produced item is the culprit — it's marked failed and excluded, and
the remainder of the batch is retried. Each retry drops at least one bad
input, so the loop is guaranteed to terminate, and in the common case (few or
no bad SMILES) it costs a single subprocess call.
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

# Generous but bounded — a single obabel invocation over ~1000 SMILES
# completes in well under a minute locally; this just guards a hang.
_OBABEL_TIMEOUT_S = 600


def _fixed_int(text: str, start: int, width: int) -> int | None:
    """Parse an MDL-spec fixed-width integer field, or ``None`` if blank/short.

    The V2000 counts and bond lines are fixed-column, NOT whitespace-delimited
    (`"aaabbb...  "` — a 3-char atom count immediately followed by a 3-char
    bond count, no separator). Molecules with 100+ atoms/bonds — real for
    peptides — push those fields to their full 3 digits, so adjacent fields
    butt up against each other with zero whitespace between them
    (``"118123"`` = 118 atoms, 123 bonds). A naive ``.split()`` merges them
    into one bogus token and silently corrupts or drops the record.
    """
    field = text[start : start + width]
    if not field.strip():
        return None
    try:
        return int(field)
    except ValueError:
        return None


def _parse_sdf_records(sdf_text: str) -> list[dict]:
    """Split a multi-molecule SDF stream into per-molecule records.

    Each record: ``{"title": str, "atoms": [(element, x, y)], "bonds": [(a0,
    b0, order)]}`` — atom indices already converted to 0-based. Malformed
    records (short/garbled counts or atom lines) are silently dropped; the
    caller detects which input keys never got a record and treats those as
    failed (see ``generate_molecule_shapes``).
    """
    records: list[dict] = []
    for block in sdf_text.split("$$$$"):
        lines = block.strip("\n").split("\n")
        if len(lines) < 4:
            continue
        title = lines[0].strip()
        # Counts line is fixed-width (see _fixed_int) — NOT `.split()`.
        n_atoms = _fixed_int(lines[3], 0, 3)
        n_bonds = _fixed_int(lines[3], 3, 3)
        if n_atoms is None or n_bonds is None:
            continue
        atom_lines = lines[4 : 4 + n_atoms]
        bond_lines = lines[4 + n_atoms : 4 + n_atoms + n_bonds]
        if len(atom_lines) != n_atoms or len(bond_lines) != n_bonds:
            continue

        # Atom lines are also fixed-width in the spec, but each coordinate
        # field is 10 chars wide — obabel's 2D layouts never approach that
        # magnitude, so there's always real whitespace between fields in
        # practice and plain `.split()` is safe (and more forgiving of the
        # trailing property columns, whose exact widths we don't care about).
        atoms: list[tuple[str, float, float]] = []
        ok = True
        for al in atom_lines:
            parts = al.split()
            if len(parts) < 4:
                ok = False
                break
            try:
                x, y = float(parts[0]), float(parts[1])
            except ValueError:
                ok = False
                break
            atoms.append((parts[3], x, y))
        if not ok or not atoms:
            continue

        # Bond lines ARE fixed-width in practice for large molecules (atom
        # indices >= 100 collide with their neighbor field under `.split()`),
        # so use the same fixed-column parse as the counts line.
        bonds: list[tuple[int, int, int]] = []
        for bl in bond_lines:
            a = _fixed_int(bl, 0, 3)
            b = _fixed_int(bl, 3, 3)
            order = _fixed_int(bl, 6, 3)
            if a is None or b is None or order is None:
                continue
            bonds.append((a - 1, b - 1, order))

        records.append({"title": title, "atoms": atoms, "bonds": bonds})
    return records


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
    molecule reading consistently instead of at obabel's arbitrary angle.
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
            #  • +90° (straight up) → ring sits UPRIGHT below the chain, with a
            #    PARA substituent hanging straight down. The canonical cathinone
            #    pose (mephedrone: ketone up, ring-methyl down). Using +30° here
            #    would swing that para group out to the lower-left and read as a
            #    tilted, diagonal ring.
            # Detect the para case: another substituent on the ring roughly
            # opposite (≈180° around the ring centroid) the chain's ipso atom.
            rcx = sum(atoms[i][1] for i in ring) / len(ring)
            rcy = sum(atoms[i][2] for i in ring) / len(ring)
            ipso_angle = math.atan2(atoms[r][2] - rcy, atoms[r][1] - rcx)
            has_para = False
            for r2, _s2 in exo:
                if r2 == r:
                    continue
                a2 = math.atan2(atoms[r2][2] - rcy, atoms[r2][1] - rcx)
                delta = abs((a2 - ipso_angle + math.pi) % (2 * math.pi) - math.pi)
                if delta > math.radians(150):
                    has_para = True
                    break
            theta = exo_angle - math.radians(90 if has_para else 30)
    if theta is None:
        sxx = sum((a[1] - cx) ** 2 for a in atoms)
        syy = sum((a[2] - cy) ** 2 for a in atoms)
        sxy = sum((a[1] - cx) * (a[2] - cy) for a in atoms)
        theta = 0.5 * math.atan2(2 * sxy, sxx - syy)

    ct, st = math.cos(-theta), math.sin(-theta)
    rot = [(el, (x - cx) * ct - (y - cy) * st, (x - cx) * st + (y - cy) * ct) for el, x, y in atoms]
    # When the rotation was set from the exocyclic (ring→chain) bond pointing
    # up-right, geometry already guarantees the ring sits on the left with the
    # chain trailing up and to the right (the ring extends opposite the chain) —
    # the way every reference draws a phenethylamine. So no ring-left or vertical
    # flip: an explicit "heteroatom up" flip actively inverts the chain back down.
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
