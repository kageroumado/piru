#!/usr/bin/env python3
"""Structurally survey the hand-curated substance overlay.

The overlay (``data/curated/substances/*.json``) is ingested as the highest-
priority source ``piru-curated``, so every field it sets overrides whatever the
scraped sources independently provide. Over the years it has accreted three very
different kinds of content, tangled together:

  1. Genuine curation      — data no upstream source has (real NPS, hand-authored
                             pharmacology, corrected identifiers).
  2. Stale bug-patches     — an override written to work around a since-fixed
                             pipeline bug that now merely re-states upstream.
  3. Wrong-compound copies — a dose/duration block pasted from an unrelated
                             substance (e.g. 2-FDCK carrying ketamine-shaped
                             numbers, or a ladder shared with Lithium orotate).

This script does NOT modify anything. It reads each curated file, compares every
overriding field against the *non-curated* sources in the built SQLite DB, and
emits a structural inventory. Per curated field the override is classified:

  ABSENT   — no non-curated source provides the field; curated is the sole
             provider (cannot be redundant — real data).
  MATCH    — curated equals a non-curated source; the override is redundant.
  DIVERGE  — curated differs from every non-curated source that has the field;
             real curation or a wrong-compound copy — needs eyeballing.

It also (a) fingerprints every curated dose/duration block and clusters identical
blocks shared across substances, flagging the CROSS-FAMILY ones as copy-paste
suspects, and (b) reports exact-InChIKey duplicate substance rows (merge failures
or identifier corruption — the connectivity-block stereoisomer families are left
alone).

Run from the repo root:

    python3 pipeline/audit/survey_curated_overlay.py              # human summary
    python3 pipeline/audit/survey_curated_overlay.py --json OUT   # full dump
    python3 pipeline/audit/survey_curated_overlay.py --clones     # clone clusters
    python3 pipeline/audit/survey_curated_overlay.py --dups       # InChIKey dup rows
    python3 pipeline/audit/survey_curated_overlay.py --redundant  # redundant filenames
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import overlay_lib as L  # noqa: E402


def build_survey(db: dict) -> dict:
    results = []
    dose_fps: dict = defaultdict(list)
    dur_fps: dict = defaultdict(list)

    sub_category: dict = {}
    for fp, entry in L.load_curated_files():
        if entry is None:
            results.append({"file": fp.name, "error": "parse failed"})
            continue
        name = entry.get("name") or fp.stem
        rec = L.resolve(db, name, entry.get("aliases"))
        sub_category[name] = L.resolved_category(entry, rec)
        analysis = L.analyze_file(entry, rec)
        for key, route in analysis["dose_fingerprints"]:
            dose_fps[key].append((name, route))
        for key, route in analysis["dur_fingerprints"]:
            dur_fps[key].append((name, route))

        upstream_backed = bool(rec and (rec["sources"] - {L.CURATED_SOURCE}))
        roll_up = _roll_up(entry, analysis, upstream_backed, rec is not None)
        results.append(
            {
                "file": fp.name,
                "name": name,
                "matched_db": rec is not None,
                "canonical": rec["name"] if rec else None,
                "upstream_backed": upstream_backed,
                "keys_present": _top_keys(entry),
                "fields": analysis["fields"],
                "verdict_counts": analysis["verdict_counts"],
                "roll_up": roll_up,
            }
        )

    clones = {
        "doses": _clone_clusters(dose_fps, sub_category),
        "durations": _clone_clusters(dur_fps, sub_category),
    }
    return {
        "files": results,
        "clones": clones,
        "inchikey_dups": L.inchikey_duplicates(db),
        "pubchem_cid_dups": L.pubchem_cid_duplicates(db),
        "isomer_families": L.isomer_families(db),
    }


def _clone_clusters(fps: dict, sub_category: dict) -> list:
    out = []
    for key, members in fps.items():
        subs = sorted({s for s, _ in members})
        if len(subs) >= 2:
            cats = sorted({sub_category.get(s) for s in subs if sub_category.get(s)})
            out.append(
                {
                    "block": key,
                    "substances": subs,
                    "categories": cats,
                    "cross_category": len(cats) >= 2,
                    "cross_family": L.cross_family(subs),
                }
            )
    # Cross-category first (near-certain copy bugs), then wider clusters.
    return sorted(out, key=lambda c: (not c["cross_category"], -len(c["substances"])))


def _top_keys(entry: dict) -> list:
    interesting = [
        "category",
        "routes",
        "effects",
        "tags",
        "halfLifeMinutes",
        "mechanismOfAction",
        "sources",
        "displayName",
        "popularity",
        "cas",
        "inchikey",
        "formula",
        "pubchemCID",
        "molarMass",
        "peptideProfile",
        "subjectiveEffects",
        "toleranceInfo",
        "extraCategories",
    ]
    return [k for k in interesting if entry.get(k) not in (None, [], {}, "")]


def _roll_up(entry, analysis, upstream_backed, matched) -> str:
    if not matched:
        return "UNMATCHED — not found in built DB"
    v = analysis["verdict_counts"]
    total = sum(v.values())
    if total == 0:
        return "NO_OVERRIDES — sets only identity/presentation fields"
    if not upstream_backed:
        return "NPS_ONLY — no upstream source; overlay is the sole data"
    n_match, n_div, n_abs = v.get("MATCH", 0), v.get("DIVERGE", 0), v.get("ABSENT", 0)
    if n_div == 0 and n_abs == 0 and n_match > 0:
        return f"FULLY_REDUNDANT — all {n_match} override(s) re-state upstream"
    if n_div == 0 and n_match > 0:
        return f"REDUNDANT+ADDITIVE — {n_match} redundant, {n_abs} sole-source"
    if n_div > 0:
        return f"DIVERGENT — {n_div} contradict upstream; {n_match} redundant, {n_abs} sole-source"
    return f"ADDITIVE — {n_abs} sole-source field(s)"


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
def print_summary(out: dict) -> None:
    files = out["files"]
    matched = [f for f in files if f.get("matched_db")]
    unmatched = [f for f in files if not f.get("matched_db") and "error" not in f]
    errors = [f for f in files if "error" in f]

    buckets = defaultdict(list)
    for f in matched:
        buckets[f["roll_up"].split(" ")[0]].append(f)
    total_v = defaultdict(int)
    for f in matched:
        for k, n in f["verdict_counts"].items():
            total_v[k] += n

    print("=" * 74)
    print("CURATED OVERLAY STRUCTURAL SURVEY")
    print("=" * 74)
    print(f"Curated files:            {len(files)}")
    print(f"  matched in DB:          {len(matched)}")
    print(f"  UNMATCHED:              {len(unmatched)}")
    print(f"  parse errors:           {len(errors)}")
    print()
    print("Per-FILE roll-up:")
    for tag in (
        "FULLY_REDUNDANT",
        "DIVERGENT",
        "REDUNDANT+ADDITIVE",
        "ADDITIVE",
        "NPS_ONLY",
        "NO_OVERRIDES",
    ):
        fs = buckets.get(tag, [])
        if fs:
            print(f"  {tag:20s} {len(fs):4d}")
    print()
    print("Per-FIELD override verdicts:")
    print(f"  MATCH   (redundant): {total_v.get('MATCH', 0)}")
    print(f"  DIVERGE (conflict):  {total_v.get('DIVERGE', 0)}")
    print(f"  ABSENT  (sole data): {total_v.get('ABSENT', 0)}")
    print()

    dose_c = out["clones"]["doses"]
    dur_c = out["clones"]["durations"]
    dose_x = [c for c in dose_c if c["cross_category"]]
    dur_x = [c for c in dur_c if c["cross_category"]]
    print("CLONE CLUSTERS (identical block shared across ≥2 substances):")
    print(f"  dose ladders: {len(dose_c)} total, {len(dose_x)} CROSS-CATEGORY (copy suspects)")
    print(f"  durations:    {len(dur_c)} total, {len(dur_x)} CROSS-CATEGORY")
    print()
    print(f"EXACT-InChIKey duplicate rows (merge/corruption bugs): {len(out['inchikey_dups'])}")
    print(f"Duplicate PubChem CID rows:                           {len(out['pubchem_cid_dups'])}")
    print(f"Stereoisomer-family fold candidates:                  {len(out['isomer_families'])}")
    print()

    if unmatched:
        print(f"-- UNMATCHED files ({len(unmatched)}) --")
        for f in unmatched:
            print(f"   {f['name']}  ({f['file']})")
        print()
    if dose_x or dur_x:
        print("-- CROSS-CATEGORY clone clusters (strongest copy-paste signal) --")
        for c in dose_x:
            print(
                f"   [dose {c['block'][0]}] {' / '.join(c['categories'])}: {', '.join(c['substances'])}"
            )
        for c in dur_x:
            print(
                f"   [dur {c['block'][0]}] {' / '.join(c['categories'])}: {', '.join(c['substances'])}"
            )
        print()
    if out["inchikey_dups"]:
        print("-- EXACT-InChIKey duplicate substance rows (merge/corruption) --")
        for g in out["inchikey_dups"]:
            print(f"   {g['inchikey']}: {', '.join(g['substances'])}")
        print()
    if out["isomer_families"]:
        print(
            f"-- STEREOISOMER fold candidates ({len(out['isomer_families'])}) — parent ← variants(code) --"
        )
        for fam in out["isomer_families"]:
            vs = ", ".join(f"{v['name']}({v['isomer'] or '?'})" for v in fam["variants"])
            print(f"   {fam['parent']} ← {vs}")
        print()


def print_clones(out: dict) -> None:
    for kind in ("doses", "durations"):
        clusters = out["clones"][kind]
        print(f"=== {kind.upper()} clone clusters ({len(clusters)}; cross-family first) ===")
        for c in clusters:
            flag = "  ⚠ CROSS-FAMILY" if c["cross_family"] else ""
            print(f"\n  block {json.dumps(c['block'], default=list)}{flag}")
            print(f"    {len(c['substances'])} substances: {', '.join(c['substances'])}")
        print()


def print_dups(out: dict) -> None:
    print(f"=== Exact-InChIKey duplicate rows ({len(out['inchikey_dups'])}) ===")
    for g in out["inchikey_dups"]:
        print(f"  {g['inchikey']}: {', '.join(g['substances'])}")
    print(f"\n=== Duplicate PubChem CID rows ({len(out['pubchem_cid_dups'])}) ===")
    for g in out["pubchem_cid_dups"]:
        print(f"  CID {g['cid']}: {', '.join(g['substances'])}")


def print_redundant(out: dict) -> None:
    fr = [
        f
        for f in out["files"]
        if f.get("matched_db") and f["roll_up"].startswith("FULLY_REDUNDANT")
    ]
    print(f"# {len(fr)} fully-redundant curated files\n")
    for f in sorted(fr, key=lambda x: x["name"]):
        print(f["file"])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", metavar="PATH", help="write full structured survey to PATH")
    ap.add_argument("--clones", action="store_true", help="print clone clusters")
    ap.add_argument("--dups", action="store_true", help="print InChIKey/CID duplicate rows")
    ap.add_argument("--redundant", action="store_true", help="print fully-redundant filenames")
    ap.add_argument("--db", default=str(L.DB), help="path to built SQLite DB")
    args = ap.parse_args()

    if not Path(args.db).exists():
        print(f"error: DB not found at {args.db}; run pipeline/build.sh first", file=sys.stderr)
        return 2

    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    db = L.load_db(con)
    con.close()
    out = build_survey(db)

    if args.json:
        Path(args.json).write_text(json.dumps(out, indent=2, default=list))
        print(f"wrote {args.json}", file=sys.stderr)
    if args.clones:
        print_clones(out)
    elif args.dups:
        print_dups(out)
    elif args.redundant:
        print_redundant(out)
    else:
        print_summary(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
