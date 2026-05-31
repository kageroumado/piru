#!/usr/bin/env python3
"""Human-readable snapshots of exactly what Piru ships — generated FROM the built
SQLite (`Piru/Data/piru-substances.sqlite`), not the upstream source feeds. So
the snapshots reflect the shipped, resolved data: curated overrides, per-fact
source priority, dedup, casing, references — everything the app sees.

Resolution mirrors the app: each field is taken from the highest-priority
(lowest `default_priority`) source that has a row for the substance.

Outputs to data/snapshots/:
  - substances.csv  (one row per compound, " | "-delimited multi-value cells)
  - substances.json (same data, structured)
  - gaps.csv        (only rows with data gaps — crawl/PR target list)

Run from the repo root (or via pipeline/build.sh):
    python3 pipeline/build/snapshots.py
"""

import csv
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_PATH = REPO / "Piru/Data/piru-substances.sqlite"
OUT_DIR = REPO / "data/snapshots"
OUT_CSV = OUT_DIR / "substances.csv"
OUT_JSON = OUT_DIR / "substances.json"
OUT_GAPS_CSV = OUT_DIR / "gaps.csv"

FIELDNAMES = [
    "name", "display_name", "aliases", "category", "display_class", "tags",
    "default_route", "all_routes", "routes_with_dose", "has_dose_data",
    "has_duration_data", "half_life_minutes", "mechanism_summary",
    "effects", "references", "data_gaps",
]


def _resolved(db, table, value_col, sid, priority):
    """Return value_col from the lowest-priority-number source with a row."""
    rows = db.execute(
        f"SELECT src.slug AS slug, t.{value_col} AS v FROM {table} t "
        f"JOIN sources src ON src.id = t.source_id WHERE t.substance_id = ?", (sid,)
    ).fetchall()
    best, best_pri = None, 1e9
    for r in rows:
        p = priority.get(r["slug"], 999)
        if r["v"] is not None and p < best_pri:
            best, best_pri = r["v"], p
    return best


def build_rows(db) -> list[dict]:
    db.row_factory = sqlite3.Row
    priority = {r["slug"]: r["default_priority"] for r in db.execute("SELECT slug, default_priority FROM sources")}
    rows = []
    for s in db.execute("SELECT * FROM substances ORDER BY canonical_name COLLATE NOCASE"):
        sid = s["id"]
        aliases = [r["alias"] for r in db.execute(
            "SELECT alias FROM aliases WHERE substance_id=? ORDER BY alias", (sid,))]
        tags = [r["tag"] for r in db.execute(
            "SELECT DISTINCT tag FROM tags WHERE substance_id=? ORDER BY tag", (sid,))]
        dose_routes = [r["route"] for r in db.execute(
            "SELECT DISTINCT route FROM dose_ranges WHERE substance_id=? AND "
            "(threshold IS NOT NULL OR light_lower IS NOT NULL OR common_lower IS NOT NULL "
            "OR strong_lower IS NOT NULL OR heavy IS NOT NULL)", (sid,))]
        all_routes = sorted({r["route"] for r in db.execute(
            "SELECT route FROM dose_ranges WHERE substance_id=:i "
            "UNION SELECT route FROM durations WHERE substance_id=:i "
            "UNION SELECT route FROM protocol_dosing WHERE substance_id=:i", {"i": sid})})
        has_duration = db.execute(
            "SELECT 1 FROM durations WHERE substance_id=? LIMIT 1", (sid,)).fetchone() is not None
        has_protocol = db.execute(
            "SELECT 1 FROM protocol_dosing WHERE substance_id=? LIMIT 1", (sid,)).fetchone() is not None
        category = _resolved(db, "categories", "category", sid, priority)
        half_life = _resolved(db, "half_lives", "half_life_minutes", sid, priority)
        mech = _resolved(db, "mechanisms_summary", "summary", sid, priority)
        effects = [r["text"] for r in db.execute(
            "SELECT DISTINCT text FROM effects WHERE substance_id=?", (sid,))]
        refs = [r["label"] for r in db.execute("""
            SELECT DISTINCT COALESCE(c.title, c.url, c.doi, 'PMID ' || c.pmid) AS label
            FROM citations c WHERE c.id IN (
                SELECT citation_id FROM substance_citations WHERE substance_id=:i
                UNION SELECT citation_id FROM dose_ranges WHERE substance_id=:i
                UNION SELECT citation_id FROM half_lives WHERE substance_id=:i
                UNION SELECT citation_id FROM mechanisms_summary WHERE substance_id=:i)
            """, {"i": sid}) if r["label"]]
        rows.append({
            "name": s["canonical_name"],
            "display_name": s["display_name"] or "",
            "aliases": aliases,
            "category": category or "",
            "display_class": s["display_class"] or "",
            "tags": tags,
            "default_route": dose_routes[0] if dose_routes else (all_routes[0] if all_routes else ""),
            "all_routes": all_routes,
            "routes_with_dose": sorted(dose_routes),
            "has_dose_data": bool(dose_routes),
            "has_duration_data": has_duration,
            "has_protocol_dosing": has_protocol,
            "half_life_minutes": half_life,
            "mechanism_summary": mech or "",
            "effects": effects,
            "references": refs,
        })
    return rows


def gaps_for(e: dict) -> list[str]:
    g = []
    # Protocol-dosed compounds (peptides/PEDs) legitimately have no dose ladder.
    if not e["has_dose_data"] and not e.get("has_protocol_dosing"):
        g.append("dose_ranges_by_route")
    if not e["has_duration_data"] and not e.get("has_protocol_dosing"):
        g.append("duration_by_route")
    if not e["half_life_minutes"]:
        g.append("half_life_minutes")
    if not e["mechanism_summary"]:
        g.append("mechanism_of_action")
    if not e["references"]:
        g.append("references")
    return g


def to_csv_row(e: dict) -> dict:
    return {
        "name": e["name"],
        "display_name": e["display_name"],
        "aliases": " | ".join(e["aliases"]),
        "category": e["category"],
        "display_class": e["display_class"],
        "tags": " | ".join(e["tags"]),
        "default_route": e["default_route"],
        "all_routes": " | ".join(e["all_routes"]),
        "routes_with_dose": " | ".join(e["routes_with_dose"]),
        "has_dose_data": "yes" if e["has_dose_data"] else "no",
        "has_duration_data": "yes" if e["has_duration_data"] else "no",
        "half_life_minutes": "" if e["half_life_minutes"] is None else str(e["half_life_minutes"]),
        "mechanism_summary": e["mechanism_summary"],
        "effects": " | ".join(e["effects"]),
        "references": " | ".join(e["references"]),
        "data_gaps": ", ".join(gaps_for(e)),
    }


def main() -> int:
    if not DB_PATH.exists():
        print(f"ERROR: {DB_PATH} not built — run pipeline/build/sqlite.py first", file=sys.stderr)
        return 1
    OUT_DIR.mkdir(exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    rows = build_rows(db)

    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDNAMES)
        w.writeheader()
        for e in rows:
            w.writerow(to_csv_row(e))

    gaps_rows = [to_csv_row(e) for e in rows if gaps_for(e)]
    with OUT_GAPS_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDNAMES)
        w.writeheader()
        w.writerows(gaps_rows)

    OUT_JSON.write_text(json.dumps(
        [{**e, "data_gaps": gaps_for(e)} for e in rows], indent=2, ensure_ascii=False) + "\n")

    counts = defaultdict(int)
    for e in rows:
        counts[e["category"] or "unknown"] += 1
    print(f"Wrote {len(rows)} substances (from built SQLite)", file=sys.stderr)
    print(f"  with dose data:    {sum(1 for e in rows if e['has_dose_data'])}", file=sys.stderr)
    print(f"  with protocol:     {sum(1 for e in rows if e.get('has_protocol_dosing'))}", file=sys.stderr)
    print(f"  with references:   {sum(1 for e in rows if e['references'])}", file=sys.stderr)
    print(f"  with gaps:         {len(gaps_rows)}", file=sys.stderr)
    print(f"Outputs: {OUT_CSV}, {OUT_JSON}, {OUT_GAPS_CSV}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
