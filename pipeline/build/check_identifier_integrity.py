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

Two comparisons run:

* **skeleton** — the InChIKey connectivity block (first 14 chars) must match. A
  mismatch here means a wrong 2D structure (the corruption fixed in 2026-06).
* **stereo** — when the skeleton matches AND *both* keys carry a specified stereo
  layer (block 2 != the ``UHFFFAOYSA`` sentinel), those layers must agree. A row
  whose SMILES encodes one enantiomer/diastereomer while its stored key claims
  another is a wrong-3D-structure error the skeleton-only check can't see (e.g.
  the swapped R/S-MDMA SMILES and the dextromethorphan-family stereo mixups). A
  flat-source SMILES (sentinel block 2) against a stereo key is still tolerated —
  that is a representation choice, not a wrong molecule.

``ALLOWLIST`` holds the known-irreducible mismatches: novel RCs PubChem doesn't
index (so no external arbiter) and one whose upstream name+CAS both collide with
an unrelated compound. Each is a substance whose *structure* can't be verified
externally, not a fixable error — adding to this list is a deliberate act.

Requires OpenBabel (``obabel``). Usage:
    python3 pipeline/build/check_identifier_integrity.py [path-to.sqlite]
Exits non-zero if any non-allowlisted mismatch is found.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # pipeline/ — for chem_ids
from chem_ids import (  # noqa: E402
    UNSPECIFIED_STEREO_BLOCK,
    inchikey_block1,
    inchikey_block2,
    obabel_available,
    obabel_inchikey,
)

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


def _stereo_specified(key: str | None) -> bool:
    """True when an InChIKey carries a specified (non-sentinel) stereo layer."""
    block = inchikey_block2(key)
    return bool(block) and block != UNSPECIFIED_STEREO_BLOCK


def find_mismatches(db_path: Path = DEFAULT_DB) -> list[tuple[str, str, str, str]]:
    """Return [(name, stored_inchikey, smiles_derived_inchikey, kind)] for
    substances whose stored InChIKey disagrees with their SMILES, excluding the
    allowlist. ``kind`` is "skeleton" (block-1 differs) or "stereo" (block-1 agrees
    but both keys specify a stereo layer and those disagree). Flat-vs-stereo
    differences and obabel parse failures are skipped."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT canonical_name, inchikey, smiles FROM substances "
            "WHERE inchikey IS NOT NULL AND smiles IS NOT NULL ORDER BY canonical_name"
        ).fetchall()
    finally:
        con.close()
    out: list[tuple[str, str, str, str]] = []
    for name, stored, smiles in rows:
        if name in ALLOWLIST:
            continue
        derived = obabel_inchikey(smiles)
        if not derived:
            continue
        if inchikey_block1(derived) != inchikey_block1(stored):
            out.append((name, stored, derived, "skeleton"))
        elif (
            _stereo_specified(stored)
            and _stereo_specified(derived)
            and inchikey_block2(stored) != inchikey_block2(derived)
        ):
            out.append((name, stored, derived, "stereo"))
    return out


def main() -> int:
    if not obabel_available():
        print("obabel not found — install OpenBabel to run the integrity check", file=sys.stderr)
        return 2
    db = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB
    mismatches = find_mismatches(db)
    if mismatches:
        print(f"InChIKey↔SMILES integrity FAILED — {len(mismatches)} unexpected mismatch(es):")
        for name, stored, derived, kind in mismatches:
            print(f"  [{kind:8s}] {name:32s} stored={stored}  from-smiles={derived}")
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
