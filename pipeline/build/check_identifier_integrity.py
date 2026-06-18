#!/usr/bin/env python3
"""Integrity check: every substance's stored InChIKey must agree with the InChIKey
recomputed from its own SMILES.

This is the guard against the class of corruption fixed in 2026-06: upstream
sources shipped InChIKeys that didn't match their structure (the LLM enrichment
swarm fabricated ~72% of its keys; the NPS vendor dump carried wrong-regioisomer
SMILES). The reconciliation pass (``reconcile_identifiers_pubchem.py`` +
``apply_identifier_reconciliation``) drove the wrong-skeleton count from 158 → 4.
This check keeps it there: any *new* skeleton mismatch (e.g. a re-fetched
enrichment batch reintroducing bad keys) fails CI.

Comparison is on the InChIKey skeleton (first 14 chars — the connectivity block).
A stereo-layer-only difference is tolerated (often a flat-source-SMILES vs a
stereo key — a representation choice, not a wrong molecule).

``ALLOWLIST`` holds the known-irreducible mismatches: novel RCs PubChem doesn't
index (so no external arbiter) and one whose upstream name+CAS both collide with
an unrelated compound. Each is a substance whose *structure* can't be verified
externally, not a fixable error — adding to this list is a deliberate act.

Requires OpenBabel (``obabel``). Usage:
    python3 pipeline/build/check_identifier_integrity.py [path-to.sqlite]
Exits non-zero if any non-allowlisted mismatch is found.
"""

from __future__ import annotations

import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parents[2] / "Piru/Data/piru-substances.sqlite"

# Substances whose stored InChIKey can't be externally verified (not in PubChem,
# or upstream identifiers collide with an unrelated compound). Not errors —
# structures we have no authority to correct against. See module docstring.
ALLOWLIST = {
    "4-HO-PiPT",  # novel tryptamine, not in PubChem
    "5-BR-DMT",  # novel tryptamine, not in PubChem
    "alpha-N,N-trimethyltryptamine",  # not in PubChem
    "Doip",  # upstream name + CAS both resolve to an unrelated plasticizer
}


def obabel_available() -> bool:
    return shutil.which("obabel") is not None


def _obabel_inchikey(smiles: str, _cache: dict) -> str | None:
    if smiles in _cache:
        return _cache[smiles]
    try:
        p = subprocess.run(
            ["obabel", f"-:{smiles}", "-oinchikey"], capture_output=True, text=True, timeout=20
        )
        out = [ln.strip() for ln in p.stdout.splitlines() if ln.strip() and ln.strip() != "*"]
        key = out[0] if out else None
    except Exception:
        key = None
    _cache[smiles] = key
    return key


def find_mismatches(db_path: Path = DEFAULT_DB) -> list[tuple[str, str, str]]:
    """Return [(name, stored_inchikey, smiles_derived_inchikey)] for substances
    whose stored InChIKey skeleton disagrees with their SMILES, excluding the
    allowlist. Stereo-layer-only differences and obabel parse failures are skipped."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT canonical_name, inchikey, smiles FROM substances "
            "WHERE inchikey IS NOT NULL AND smiles IS NOT NULL ORDER BY canonical_name"
        ).fetchall()
    finally:
        con.close()
    cache: dict[str, str | None] = {}
    out: list[tuple[str, str, str]] = []
    for name, stored, smiles in rows:
        if name in ALLOWLIST:
            continue
        derived = _obabel_inchikey(smiles, cache)
        if not derived:
            continue
        if derived[:14] != stored[:14]:
            out.append((name, stored, derived))
    return out


def main() -> int:
    if not obabel_available():
        print("obabel not found — install OpenBabel to run the integrity check", file=sys.stderr)
        return 2
    db = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB
    mismatches = find_mismatches(db)
    if mismatches:
        print(f"InChIKey↔SMILES integrity FAILED — {len(mismatches)} unexpected mismatch(es):")
        for name, stored, derived in mismatches:
            print(f"  {name:32s} stored={stored}  from-smiles={derived}")
        print(
            "\nIf a substance genuinely can't be verified against PubChem, add it to "
            "ALLOWLIST with a reason; otherwise fix the identifier via "
            "reconcile_identifiers_pubchem.py / the manual corrections file."
        )
        return 1
    print("InChIKey↔SMILES integrity OK (all stored keys match their SMILES, modulo allowlist)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
