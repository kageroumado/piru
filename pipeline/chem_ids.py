"""Shared chemical-identifier utilities for the whole pipeline — the fetch
brushers *and* the build/audit layer.

Kept stdlib-only and side-effect-free on import so both `pipeline/build/` and
`pipeline/fetch/brushers/` can import it (via a `sys.path` insert of the
`pipeline/` dir) without pulling in build state.

Two concerns live here:

* ``obabel_inchikey`` — the project's structural-identity oracle: recompute an
  InChIKey from a SMILES via OpenBabel. Previously copied verbatim in three
  places (the reconciler, the enrichment key-fixer, the CI integrity check);
  a single copy keeps a flag/invocation change from silently diverging.
* InChIKey layer accessors — ``inchikey_block1`` (the 14-char connectivity
  skeleton, the dedup/fold key) and ``inchikey_block2`` (the stereo/isotope
  layer, whose sentinel ``UHFFFAOYSA`` marks "no stereo specified"). These make
  skeleton-vs-stereo comparisons explicit instead of ad-hoc ``key[:14]`` slices.
"""

from __future__ import annotations

import shutil
import subprocess

# InChIKey block 2 for an empty stereo layer — i.e. racemic / unspecified
# stereochemistry. Every non-stereo InChIKey carries it; a resolved enantiomer
# carries a distinct block 2 instead.
UNSPECIFIED_STEREO_BLOCK = "UHFFFAOYSA"

_OBABEL_CACHE: dict[str, str | None] = {}


def obabel_available() -> bool:
    """True when the ``obabel`` CLI is on PATH."""
    return shutil.which("obabel") is not None


def obabel_inchikey(smiles: str | None) -> str | None:
    """InChIKey computed from ``smiles`` via OpenBabel, or ``None`` when
    ``smiles`` is empty, obabel is missing, or the conversion fails. Cached per
    SMILES for the process lifetime."""
    if not smiles:
        return None
    if smiles in _OBABEL_CACHE:
        return _OBABEL_CACHE[smiles]
    try:
        p = subprocess.run(
            ["obabel", f"-:{smiles}", "-oinchikey"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        out = [ln.strip() for ln in p.stdout.splitlines() if ln.strip() and ln.strip() != "*"]
        key = out[0] if out else None
    except Exception:
        key = None
    _OBABEL_CACHE[smiles] = key
    return key


def inchikey_block1(key: str | None) -> str | None:
    """The 14-char connectivity/skeleton block (InChIKey block 1), or ``None``
    when ``key`` is missing/too short. Substances sharing block 1 share a
    molecular skeleton (enantiomers, tautomers)."""
    if not key or len(key) < 14:
        return None
    return key[:14]


def inchikey_block2(key: str | None) -> str | None:
    """The 10-char stereo/isotope block (InChIKey block 2), or ``None``. Equals
    :data:`UNSPECIFIED_STEREO_BLOCK` when no stereochemistry is specified."""
    if not key or len(key) < 25:
        return None
    return key[15:25]


def same_skeleton(a: str | None, b: str | None) -> bool:
    """True when two InChIKeys share their connectivity block (block 1)."""
    block = inchikey_block1(a)
    return block is not None and block == inchikey_block1(b)
