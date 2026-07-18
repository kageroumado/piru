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
import subprocess
import tempfile
from pathlib import Path

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
    xs = [a[1] for a in atoms]
    ys = [a[2] for a in atoms]
    cx = sum(xs) / n
    cy = sum(ys) / n
    # Principal-axis angle from the coordinate covariance matrix.
    sxx = sum((x - cx) ** 2 for x in xs)
    syy = sum((y - cy) ** 2 for y in ys)
    sxy = sum((xs[i] - cx) * (ys[i] - cy) for i in range(n))
    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ct, st = math.cos(-theta), math.sin(-theta)
    rot = [(el, (x - cx) * ct - (y - cy) * st, (x - cx) * st + (y - cy) * ct) for el, x, y in atoms]
    ring = _ring_atoms(n, bonds)
    if ring:
        ring_mx = sum(rot[i][1] for i in ring) / len(ring)
        others = [i for i in range(n) if i not in ring]
        other_mx = sum(rot[i][1] for i in others) / len(others) if others else ring_mx
        # Ring belongs on the left (smaller x): flip horizontally if it isn't.
        if ring_mx > other_mx:
            rot = [(el, -x, y) for el, x, y in rot]

    # Vertical polarity (independent of the ring-left flip, which only touches x):
    # PCA leaves the up/down direction arbitrary. Prefer the textbook reading —
    # a carbonyl (C=O) points up (how cathinones, ketones, amides are drawn);
    # with no carbonyl, nudge heteroatoms (N/O) toward the top. Here y is still
    # math-orientation (up = larger y); _normalize flips to screen space after.
    carbonyl = {
        i for a, b, order in bonds if order == 2 for i in (a, b) if 0 <= i < n and rot[i][0] == "O"
    }
    mean_y = sum(p[2] for p in rot) / n
    ref_indices = carbonyl or {i for i in range(n) if rot[i][0] in ("O", "N")}
    if ref_indices:
        ref_y = sum(rot[i][2] for i in ref_indices) / len(ref_indices)
        if ref_y < mean_y:  # reference group sits below center → flip it up
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
    """Generate normalized 2D shapes for every ``(key, smiles)`` pair.

    ``key`` is an opaque, whitespace-free identifier (the substance id as a
    string) round-tripped through OpenBabel as the SDF title so output rows
    can be matched back to their input even across the retry-on-bad-line
    splits below.

    Returns ``(shapes_by_key, failed_keys)``. Assumes the caller already
    checked ``chem_ids.obabel_available()`` — if obabel truly cannot run,
    every key comes back failed rather than raising.
    """
    shapes: dict[str, dict] = {}
    failed: list[str] = []
    # Defensive: drop blank SMILES up front rather than feeding them to obabel.
    remaining = [(k, s) for k, s in pairs if s and s.strip()]
    failed.extend(k for k, s in pairs if not (s and s.strip()))

    with tempfile.TemporaryDirectory() as tmp_dir:
        batch_path = Path(tmp_dir) / "batch.smi"
        while remaining:
            batch_path.write_text("\n".join(f"{smiles} {key}" for key, smiles in remaining) + "\n")
            try:
                proc = subprocess.run(
                    ["obabel", str(batch_path), "-osdf", "--gen2d"],
                    capture_output=True,
                    text=True,
                    timeout=_OBABEL_TIMEOUT_S,
                )
                stdout = proc.stdout
            except Exception:
                # obabel itself is unusable (missing, crashed, timed out) —
                # nothing in this batch can be recovered.
                failed.extend(key for key, _ in remaining)
                break

            records = _parse_sdf_records(stdout)
            if not records:
                # The very first item in the batch is the one obabel choked
                # on (it aborts before emitting anything). Drop it and retry
                # the rest.
                failed.append(remaining[0][0])
                remaining = remaining[1:]
                continue

            # Match by TITLE, not position: a molecule that fails 2D/stereo
            # generation (kekulization, "no available bond" stereo errors —
            # both seen in practice) still lets obabel continue to the next
            # line, so it just leaves a hole *inside* the record stream rather
            # than truncating it. Walking records positionally against
            # `remaining` would misinterpret that hole as every subsequent
            # substance being unmatched too. A genuinely invalid SMILES (bad
            # syntax) is the only thing that truncates the read entirely —
            # everything from that point on is simply absent from `by_title`.
            by_title = {r["title"]: r for r in records}

            # The last position (in `remaining`'s order) that DID produce a
            # record. Everything up to and including it was reached by
            # obabel's reader, so any gaps in that span are confirmed
            # per-molecule failures (not read-truncation) and can be recorded
            # directly without a retry.
            last_reached = -1
            for i, (key, _) in enumerate(remaining):
                if key in by_title:
                    last_reached = i

            for key, _ in remaining[: last_reached + 1]:
                record = by_title.get(key)
                if record is None:
                    # obabel reached past this position, so it did attempt
                    # this molecule and produced no usable record for it.
                    failed.append(key)
                    continue
                oriented = _orient(record["atoms"], record["bonds"])
                shape = _normalize(oriented, record["bonds"], box=box, margin=margin)
                if shape is None:
                    failed.append(key)
                else:
                    shapes[key] = shape

            # Whatever's left (nothing after `last_reached` was ever
            # produced) is retried as a fresh batch. If the read truncated
            # right at its first item, the next pass's "no records at all"
            # branch above drops that one item and makes forward progress.
            remaining = remaining[last_reached + 1 :]

    return shapes, failed
