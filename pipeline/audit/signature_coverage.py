#!/usr/bin/env python3
"""How much of the library can actually draw a class signature.

A signature is a *comparison*: the ternary, the efficacy ladder and the
5-HT2A↔5-HT1A arc all plot one substance against the peers measured beside it.
So a binding row on the right target is not enough — the row has to sit in a
group (a curated `comparable_set`, or failing that its `citation_id`) that holds
at least one *other* substance. A lone Kᵢ from a paper nobody else appears in
renders nothing.

That makes coverage two numbers per family, and only the second one matters:

    substances  have any binding on a signature target — the ceiling
    plottable   are in a group with ≥2 distinct substances — what draws

The families and their target predicates mirror `ClassSignature.targetPredicate`
on the Swift side; when one changes, both change.

    python3 pipeline/audit/signature_coverage.py            # report
    python3 pipeline/audit/signature_coverage.py --write    # + save the snapshot
    python3 pipeline/audit/signature_coverage.py --gate     # exit 1 if plottable dropped
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru" / "Data" / "piru-substances.sqlite"
SNAPSHOT = REPO / "data" / "snapshots" / "signature-coverage.json"

FAMILIES: dict[str, str] = {
    "transporters": "b.target IN ('SERT', 'DAT', 'NET', '5-HTT')",
    "serotonin": "(b.target LIKE '5-HT2A%' OR b.target LIKE '5-HT1A%')",
    "muOpioid": (
        "(b.target LIKE 'MOR%' OR b.target LIKE 'μ-opioid%' OR b.target LIKE 'mu-opioid%')"
    ),
    "cannabinoid1": "b.target LIKE 'CB1%'",
    "nmda": "b.target LIKE 'NMDA%'",
}


def measure(db: sqlite3.Connection, predicate: str) -> dict[str, int]:
    rows = db.execute(
        f"""
        SELECT b.substance_id, COALESCE(b.comparable_set, 'c:' || b.citation_id) AS grp
          FROM bindings b
         WHERE {predicate}
        """
    ).fetchall()

    groups: dict[str, set[int]] = {}
    for substance_id, group in rows:
        # A row with neither a panel nor a citation was never established as part
        # of any experiment, which is not the same as comparable to everything.
        if group is None or "not-comparable" in group:
            continue
        groups.setdefault(group, set()).add(substance_id)

    plottable = {s for members in groups.values() if len(members) >= 2 for s in members}
    return {
        "substances": len({substance_id for substance_id, _ in rows}),
        "plottable": len(plottable),
    }


def survey() -> dict[str, dict[str, int]]:
    if not DB.exists():
        print(
            f"signature-coverage: {DB.relative_to(REPO)} is missing — run pipeline/fetch-db.sh",
            file=sys.stderr,
        )
        raise SystemExit(2)
    with sqlite3.connect(f"file:{DB}?mode=ro", uri=True) as db:
        return {family: measure(db, pred) for family, pred in FAMILIES.items()}


def report(current: dict[str, dict[str, int]], baseline: dict[str, dict[str, int]] | None) -> None:
    width = max(len(f) for f in current)
    header = f"{'family':<{width}}  substances  plottable       %"
    if baseline:
        header += "   delta"
    print(header)
    print("-" * len(header))
    for family, counts in current.items():
        total, plottable = counts["substances"], counts["plottable"]
        pct = 100 * plottable / total if total else 0
        line = f"{family:<{width}}  {total:>10}  {plottable:>9}  {pct:>5.1f}%"
        if baseline:
            delta = plottable - baseline.get(family, {}).get("plottable", 0)
            line += f"  {delta:>+6}"
        print(line)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="save the snapshot")
    parser.add_argument("--gate", action="store_true", help="exit 1 if any family regressed")
    args = parser.parse_args()

    current = survey()
    baseline = json.loads(SNAPSHOT.read_text()) if SNAPSHOT.exists() else None
    report(current, baseline if args.gate else None)
    sys.stdout.flush()

    if args.write:
        SNAPSHOT.write_text(json.dumps(current, indent=2) + "\n")
        print(f"\nwrote {SNAPSHOT.relative_to(REPO)}")

    if args.gate:
        if baseline is None:
            print(
                f"\nsignature-coverage: no snapshot at {SNAPSHOT.relative_to(REPO)} — "
                "run with --write first.",
                file=sys.stderr,
            )
            return 1
        regressed = {
            family: (baseline[family]["plottable"], counts["plottable"])
            for family, counts in current.items()
            if family in baseline and counts["plottable"] < baseline[family]["plottable"]
        }
        if regressed:
            print(
                "\nsignature-coverage: FAILED — plottable coverage dropped:",
                file=sys.stderr,
            )
            for family, (was, now) in regressed.items():
                print(f"  {family}: {was} → {now}", file=sys.stderr)
            print(
                "\nA binding row lost its comparable_set or citation, or a group fell below two "
                "substances. Restore the grouping, or re-baseline with --write if the drop is "
                "intended.",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
