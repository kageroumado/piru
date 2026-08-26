#!/usr/bin/env python3
"""Ask whether a substance's two half-life columns can both be true at once.

The DB carries elimination twice: `half_lives.half_life_minutes` (the value the
detail card and every fallback chain resolve) and `pk_routes.half_life_min`
(the per-route study row the PK engine assembles parameters from). Nothing
compares them — so fentanyl can honestly say 219 min on one path (IV study)
and 1020 min on the other (transdermal), and Methylone can say 90 and 384 for
no reason at all. The first kind is route pharmacology; the second is a data
bug wearing the same clothes.

This cross-checks each substance that carries both columns:

    ROUTE-EXPLAINED   the substance's own pk_routes rows span >=2x across
                      routes, so a route-level disagreement with the single
                      half_lives number is expected (transdermal depots, oral
                      vs smoked THC). Reported, never gated.
    UNEXPLAINED       the pk_routes rows agree with each other, and still
                      disagree >2x with half_lives. One of the two columns is
                      wrong. Gated.

Only human and unstated-species pk_routes rows are compared — an animal row's
half-life is scaled downstream and would flag as a disagreement it isn't.

Known-but-unfixed contradictions are waived in WAIVERS below, each naming its
reason; fix the data (in `data/curated/`, then `pipeline/build.sh fast`),
remove the waiver, and the gate holds it fixed.

    python3 pipeline/audit/pk_sanity.py                # ranked report
    python3 pipeline/audit/pk_sanity.py --gate         # exit 1 on unexplained
    python3 pipeline/audit/pk_sanity.py --ratio 3.0    # loosen the threshold

Offline and deterministic — it reads only the built SQLite.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"

#: Substances whose unexplained contradiction is known, logged, and awaiting a
#: sourced fix (Specs/found-defects.md). A waiver only suppresses the gate; the
#: report still prints the row. Remove the entry when the data is corrected.
WAIVERS: dict[str, str] = {}


def load(db_path: Path):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    half_lives: dict[str, list[float]] = defaultdict(list)
    for name, minutes in con.execute(
        """SELECT s.canonical_name, h.half_life_minutes
             FROM half_lives h JOIN substances s ON s.id = h.substance_id
            WHERE h.half_life_minutes > 0"""
    ):
        half_lives[name].append(minutes)
    pk_routes: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for name, route, minutes in con.execute(
        """SELECT s.canonical_name, p.route, p.half_life_min
             FROM pk_routes p JOIN substances s ON s.id = p.substance_id
            WHERE p.half_life_min > 0
              AND (p.species IS NULL OR p.species = 'human')"""
    ):
        pk_routes[name].append((route, minutes))
    con.close()
    return half_lives, pk_routes


def findings(half_lives, pk_routes, ratio_gate: float):
    rows = []
    for name in sorted(set(half_lives) & set(pk_routes)):
        hl_values = half_lives[name]
        pk_values = [m for _, m in pk_routes[name]]
        # Most charitable cross-pair: the closest (half_lives, pk_routes)
        # combination. A finding means NO pairing of the two columns agrees.
        best = min(
            (max(a, b) / min(a, b) for a in hl_values for b in pk_values),
        )
        if best <= ratio_gate:
            continue
        pk_spread = max(pk_values) / min(pk_values)
        rows.append(
            {
                "name": name,
                "ratio": best,
                "half_lives": sorted(hl_values),
                "pk_routes": sorted(pk_routes[name], key=lambda rm: rm[1]),
                "route_explained": pk_spread >= 2.0,
                "waived": name in WAIVERS,
            }
        )
    rows.sort(key=lambda r: r["ratio"], reverse=True)
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--ratio", type=float, default=2.0, help="disagreement threshold (default 2.0)")
    ap.add_argument("--gate", action="store_true", help="exit 1 on unexplained, unwaived findings")
    args = ap.parse_args()

    if not args.db.exists():
        print(
            f"pk_sanity: DB not found at {args.db} — run pipeline/fetch-db.sh first",
            file=sys.stderr,
        )
        return 2

    half_lives, pk_routes = load(args.db)
    rows = findings(half_lives, pk_routes, args.ratio)

    stale_waivers = sorted(set(WAIVERS) - {r["name"] for r in rows})
    unexplained = [r for r in rows if not r["route_explained"] and not r["waived"]]

    def fmt(r) -> str:
        routes = ", ".join(f"{route} {minutes:g}" for route, minutes in r["pk_routes"])
        hl = "/".join(f"{v:g}" for v in r["half_lives"])
        mark = " [waived]" if r["waived"] else ""
        return (
            f"  {r['ratio']:6.2f}x  {r['name']:<20} half_lives {hl} min · pk_routes {routes}{mark}"
        )

    explained = [r for r in rows if r["route_explained"]]
    if explained:
        print(
            f"ROUTE-EXPLAINED ({len(explained)}) — the substance's own pk_routes span >=2x across routes:"
        )
        for r in explained:
            print(fmt(r))
    waived_rows = [r for r in rows if not r["route_explained"] and r["waived"]]
    if waived_rows:
        print(f"\nWAIVED ({len(waived_rows)}) — known contradictions awaiting a sourced fix:")
        for r in waived_rows:
            print(fmt(r))
            print(f"          note: {WAIVERS[r['name']]}")
    if unexplained:
        print(
            f"\nUNEXPLAINED ({len(unexplained)}) — no pairing agrees and the routes agree with each other:"
        )
        for r in unexplained:
            print(fmt(r))
    if stale_waivers:
        print(
            f"\nSTALE WAIVERS — no longer tripping, delete from WAIVERS: {', '.join(stale_waivers)}"
        )
    if not rows and not stale_waivers:
        print("pk_sanity: no half_lives vs pk_routes disagreement above the threshold.")

    if args.gate and (unexplained or stale_waivers):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
