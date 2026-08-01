#!/usr/bin/env python3
"""Find substance rows that are the SAME molecule under two names.

Every merge pass in `pipeline/build/sqlite.py` keys on *text* — a canonical
name, an alias, a `duplicate-of-` tag, or a curated registry. That leaves a
class untouched: two rows with the same structure whose names look nothing
alike and whose identifiers don't line up, because one side has no InChIKey at
all or is stored as the salt. The 2026-08-01 cleanup found six such pairs, two
of them mass-casualty cathinones (N-Ethylpentylone/Ephylone,
Dimethylpentylone/Dipentylone). A compound split across two rows carries its
dose ladder on one and its interaction class on the other.

## Why this reports instead of merging

The first version of this check merged automatically. It was wrong, in two ways
that are worth writing down because both are invisible until you read the
output:

1. **A structural collision is ambiguous.** It means *either* two rows are the
   same compound *or* one of them has a wrong SMILES. Those have opposite
   fixes — merge vs. correct the structure — and nothing in the key tells you
   which. Auto-merging silently resolves every wrong-SMILES bug by destroying a
   real compound.
2. **A key can degrade silently.** `5-BR-DMT`'s main fragment
   (`CN(C)CCc1cnc2ccc(Br)cc12`) does not sanitize in RDKit, so "largest parseable
   fragment" falls through to its fumarate counterion and the row keys as a
   generic dianion — colliding with anything else whose real structure failed to
   parse. That is a data bug the report should *surface*, not act on.

So: this finds candidates, and `data/curated/structural-duplicates.json` records
the ones a human verified. The build merges only from that file.

## The key

The full InChIKey of the largest parseable fragment, with two deliberate
properties:

- Dropping the counterion folds a hydrochloride onto its freebase. Salt rows are
  stored `[Cl-].<molecule>.[H+]`, which yields a completely different InChIKey
  from the freebase — precisely why these pairs survived every text-keyed pass.
- Keeping the **full** key (not the block-1 connectivity prefix) preserves
  stereochemistry, so enantiomers never collapse: Ketamine is
  `YQEZLKZALYSWHR-UHFFFAOYSA-N`, Esketamine `YQEZLKZALYSWHR-CYBMUJFWSA-N`.
  Block-1 matching would fuse them, which is why the identifier-integrity test
  deliberately does not flag connectivity matches.

CAS is deliberately not used as a secondary key: the catalog has nine known
pairs of *distinct* molecules sharing one CAS (2026-08-01 data audit), so CAS
cannot currently be merged on.

Usage:
    python3 pipeline/audit/structural_dupes.py            # report
    python3 pipeline/audit/structural_dupes.py --gate     # exit 1 on an
                                                          # unadjudicated pair
    python3 pipeline/audit/structural_dupes.py --json out.json
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
VERIFIED = REPO / "data/curated/structural-duplicates.json"


def structural_key(smiles: str) -> tuple[str | None, list[str]]:
    """(full InChIKey of the largest parseable fragment, unparseable fragments).

    The second element is not diagnostic noise — a row whose *main* fragment
    failed to parse produces a key for its counterion, which is worse than no
    key at all. Callers must treat a non-empty list as a data defect.
    """
    from rdkit import Chem, RDLogger

    RDLogger.DisableLog("rdApp.*")
    best = None
    failed: list[str] = []
    for frag in smiles.split("."):
        mol = Chem.MolFromSmiles(frag)
        if mol is None:
            failed.append(frag)
            continue
        if mol.GetNumHeavyAtoms() == 0:
            continue
        if best is None or mol.GetNumHeavyAtoms() > best.GetNumHeavyAtoms():
            best = mol
    if best is None or best.GetNumHeavyAtoms() < 3:
        return None, failed
    try:
        key = Chem.MolToInchiKey(best)
    except Exception:  # noqa: BLE001 - rdkit raises bare exceptions here
        return None, failed
    return (key or None), failed


def load_verified() -> set[frozenset[str]]:
    """Every pair somebody has already ruled on, as frozensets of lowercased names.

    Both halves of the file count as adjudicated. `duplicates` are pairs judged
    to be one compound and merged at build time; `notMerged` are pairs judged
    NOT to be — a wrong SMILES, or a combination product with no single
    structure — and deliberately left colliding. The gate exists to catch a
    collision nobody has looked at, so a documented decision either way clears
    it.
    """
    if not VERIFIED.is_file():
        return set()
    payload = json.loads(VERIFIED.read_text())
    pairs = {
        frozenset({entry["keep"].lower(), entry["merge"].lower()})
        for entry in payload.get("duplicates", [])
    }
    pairs |= {
        frozenset(n.lower() for n in entry["names"])
        for entry in payload.get("notMerged", [])
        if len(entry.get("names", [])) == 2
    }
    return pairs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB)
    parser.add_argument(
        "--gate", action="store_true", help="exit 1 on a collision nobody has adjudicated"
    )
    parser.add_argument("--json", type=Path, help="write the full result here")
    args = parser.parse_args()

    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    cur = con.cursor()
    groups: dict[str, list[tuple[int, str]]] = defaultdict(list)
    unparseable: list[tuple[str, list[str]]] = []
    for sid, name, smiles in cur.execute(
        "SELECT id, canonical_name, smiles FROM substances "
        "WHERE smiles IS NOT NULL AND smiles != ''"
    ):
        key, failed = structural_key(smiles)
        if failed:
            unparseable.append((name, failed))
        if key:
            groups[key].append((sid, name))

    verified = load_verified()
    collisions = []
    for key, members in sorted(groups.items()):
        if len(members) < 2:
            continue
        names = sorted(n for _, n in members)
        pair = frozenset(n.lower() for n in names)
        collisions.append(
            {
                "key": key,
                "names": names,
                "adjudicated": len(names) == 2 and pair in verified,
            }
        )

    print(f"structural-dupes: {args.db.name}")
    print(f"  {len(groups)} structural keys over parseable rows")
    print(f"  {len(collisions)} key(s) shared by >1 substance")
    open_items = [c for c in collisions if not c["adjudicated"]]
    for c in collisions:
        mark = "ok " if c["adjudicated"] else "NEW"
        print(f"  [{mark}] {c['key']}  {c['names']}")
    if unparseable:
        print(f"\n  {len(unparseable)} row(s) have an unparseable SMILES fragment — these key")
        print("  off their counterion and will collide spuriously:")
        for name, frags in unparseable[:20]:
            print(f"    {name}: {frags}")

    if args.json:
        args.json.write_text(
            json.dumps(
                {"collisions": collisions, "unparseable": unparseable}, indent=1, ensure_ascii=False
            )
            + "\n"
        )
        print(f"\nfull result → {args.json}")

    if args.gate and open_items:
        print(
            f"\nstructural-dupes: FAILED — {len(open_items)} structural collision(s) nobody "
            f"has adjudicated:",
            file=sys.stderr,
        )
        for c in open_items:
            print(f"  {c['names']} share {c['key']}", file=sys.stderr)
        print(
            "\nEach is EITHER a genuine duplicate OR a wrong SMILES — decide which, then "
            f"record it in {VERIFIED.relative_to(REPO)} (to merge) or fix the structure.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
