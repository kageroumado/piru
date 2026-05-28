#!/usr/bin/env python3
"""Build human-readable snapshots of every substance Piru ships with.

These snapshots are the GitHub-friendly mirror of the bundled SQLite — anyone
reading the repo can browse them to see exactly what data the app contains,
without needing sqlite tooling.

Merges:
  - data/intermediate/substances-bundled.json  (curated overlay, Substance schema)
  - data/sources/drug-community.json           (drug.community dump, their schema)

Outputs to data/snapshots/:
  - substances.csv  (one row per compound, semicolon-delimited multi-value cells)
  - substances.json (same data, structured)
  - gaps.csv        (only rows with data gaps — PR target list for crawlers)

Run from the repo root:
    python3 pipeline/build/snapshots.py
"""

import csv
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CURATED = REPO / "data/intermediate/substances-bundled.json"
DRUG_COMMUNITY = REPO / "data/sources/drug-community.json"
OUT_DIR = REPO / "data/snapshots"
OUT_CSV = OUT_DIR / "substances.csv"
OUT_JSON = OUT_DIR / "substances.json"
OUT_GAPS_CSV = OUT_DIR / "gaps.csv"


def normalize(name: str) -> str:
    """Lowercase + strip stereo prefixes / salts for dedup."""
    s = unicodedata.normalize("NFKD", name).lower().strip()
    s = re.sub(r"^\(\s*[+\-±rs]\s*\)\s*-?\s*", "", s)
    s = re.sub(r"\s*[·.]?\s*(hcl|hydrochloride|sulfate|sulphate|fumarate|tartrate|maleate|mesylate|citrate)\s*$", "", s)
    s = re.sub(r"\s+", " ", s)
    return s


def parse_curated(path: Path) -> list[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out = []
    for s in data:
        routes_with_data = [
            r["route"] for r in (s.get("routes") or [])
            if any(r.get("doses", {}).get(k) for k in ("threshold", "light", "common", "strong", "heavy"))
        ]
        all_routes = [r["route"] for r in (s.get("routes") or [])]
        has_duration = any(r.get("duration") for r in (s.get("routes") or []))
        out.append({
            "source": "curated",
            "name": s["name"],
            "aliases": s.get("aliases") or [],
            "category": s.get("category", ""),
            "tags": s.get("tags") or [],
            "chemical_class": "",
            "psychoactive_class": "",
            "default_route": s.get("defaultRoute", ""),
            "all_routes": all_routes,
            "routes_with_dose": routes_with_data,
            "has_dose_data": bool(routes_with_data),
            "has_duration_data": has_duration,
            "half_life_minutes": s.get("halfLifeMinutes"),
            "mechanism_summary": (s.get("mechanismOfAction") or {}).get("summary", "") if isinstance(s.get("mechanismOfAction"), dict) else "",
            "sources": s.get("sources") or [],
            "effects": s.get("effects") or [],
            "subjective_effects": [
                e.get("name") if isinstance(e, dict) else e
                for e in (s.get("subjectiveEffects") or [])
            ],
        })
    return out


def parse_drug_community(path: Path) -> list[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out = []
    for s in data:
        name = s.get("drug_name", "")
        if "(" in name and name.endswith(")"):
            base, parens = name.split("(", 1)
            name = base.strip()
            inner = parens.rstrip(")").strip()
            paren_aliases = [a.strip() for a in inner.split(",") if a.strip()]
        else:
            paren_aliases = []
        alt_names = s.get("alternative_names") or []
        aliases = list({a for a in (paren_aliases + alt_names) if a.lower() != name.lower()})

        dosages = s.get("dosages") or {}
        route_entries = dosages.get("routes_of_administration") or []
        routes_with_dose = []
        all_routes = []
        for r in route_entries:
            route_name = r.get("route", "")
            all_routes.append(route_name)
            dr = r.get("dose_ranges") or {}
            if any(dr.get(k) for k in ("threshold", "light", "common", "strong", "heavy")):
                routes_with_dose.append(route_name)

        duration_curves = s.get("duration_curves") or []
        has_duration = any((dc.get("duration_curve") or {}) for dc in duration_curves)

        out.append({
            "source": "drug.community",
            "name": name,
            "aliases": aliases,
            "category": s.get("psychoactive_class") or (s.get("categories") or [""])[0],
            "tags": [],
            "chemical_class": s.get("chemical_class") or "",
            "psychoactive_class": s.get("psychoactive_class") or "",
            "default_route": route_entries[0]["route"] if route_entries else "",
            "all_routes": all_routes,
            "routes_with_dose": routes_with_dose,
            "has_dose_data": bool(routes_with_dose),
            "has_duration_data": has_duration,
            "half_life_minutes": None,
            "mechanism_summary": "",
            "sources": ["drug.community"],
            "effects": [],
            "subjective_effects": s.get("subjective_effects") or [],
            "half_life_raw": s.get("half_life") or "",
        })
    return out


def merge(curated: list[dict], drug_community: list[dict]) -> list[dict]:
    """Curated wins on conflict (it's hand-vetted); drug.community fills gaps."""
    by_key: dict[str, dict] = {}
    for entry in curated:
        key = normalize(entry["name"])
        for alias in entry["aliases"]:
            by_key.setdefault(normalize(alias), entry)
        by_key[key] = entry

    out = list(curated)
    for entry in drug_community:
        key = normalize(entry["name"])
        if key in by_key:
            # Merge into curated entry — only fill blanks
            target = by_key[key]
            if not target.get("chemical_class"):
                target["chemical_class"] = entry["chemical_class"]
            if not target.get("psychoactive_class"):
                target["psychoactive_class"] = entry["psychoactive_class"]
            # Union aliases
            existing_aliases_lower = {a.lower() for a in target["aliases"]}
            for alias in entry["aliases"]:
                if alias.lower() not in existing_aliases_lower and alias.lower() != target["name"].lower():
                    target["aliases"].append(alias)
            # Union sources
            for src in entry["sources"]:
                if src not in target["sources"]:
                    target["sources"].append(src)
            # Note presence in drug.community
            target.setdefault("present_in", []).append("drug.community")
        else:
            entry.setdefault("present_in", ["drug.community"])
            by_key[key] = entry
            for alias in entry["aliases"]:
                by_key.setdefault(normalize(alias), entry)
            out.append(entry)

    for entry in curated:
        entry.setdefault("present_in", ["curated"])

    return out


def gaps_for(entry: dict) -> list[str]:
    gaps = []
    if not entry.get("has_dose_data"):
        gaps.append("dose_ranges_by_route")
    if not entry.get("has_duration_data"):
        gaps.append("duration_by_route")
    if not entry.get("half_life_minutes"):
        gaps.append("half_life_minutes")
    if not entry.get("mechanism_summary"):
        gaps.append("mechanism_of_action")
    if not entry.get("subjective_effects"):
        gaps.append("subjective_effects")
    if not entry.get("chemical_class"):
        gaps.append("chemical_class")
    if not entry.get("sources"):
        gaps.append("references")
    return gaps


def to_csv_row(entry: dict) -> dict:
    return {
        "name": entry["name"],
        "aliases": " | ".join(entry["aliases"]),
        "category": entry["category"],
        "tags": " | ".join(entry["tags"]),
        "chemical_class": entry.get("chemical_class") or "",
        "psychoactive_class": entry.get("psychoactive_class") or "",
        "default_route": entry.get("default_route") or "",
        "all_routes": " | ".join(entry.get("all_routes") or []),
        "routes_with_dose": " | ".join(entry.get("routes_with_dose") or []),
        "has_dose_data": "yes" if entry.get("has_dose_data") else "no",
        "has_duration_data": "yes" if entry.get("has_duration_data") else "no",
        "half_life_minutes": "" if entry.get("half_life_minutes") is None else str(entry["half_life_minutes"]),
        "mechanism_summary": entry.get("mechanism_summary") or "",
        "effects": " | ".join(entry.get("effects") or []),
        "subjective_effects": " | ".join(entry.get("subjective_effects") or []),
        "sources": " | ".join(entry.get("sources") or []),
        "present_in": " | ".join(entry.get("present_in") or []),
        "data_gaps": ", ".join(gaps_for(entry)),
    }


def main() -> int:
    OUT_DIR.mkdir(exist_ok=True)
    curated = parse_curated(CURATED)
    dc = parse_drug_community(DRUG_COMMUNITY)
    merged = merge(curated, dc)
    merged.sort(key=lambda e: e["name"].lower())

    fieldnames = list(to_csv_row(merged[0] if merged else {"name": ""}).keys())

    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for entry in merged:
            w.writerow(to_csv_row(entry))

    gaps_rows = [to_csv_row(e) for e in merged if gaps_for(e)]
    with OUT_GAPS_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(gaps_rows)

    json_rows = [{**e, "data_gaps": gaps_for(e)} for e in merged]
    OUT_JSON.write_text(json.dumps(json_rows, indent=2, ensure_ascii=False))

    # Stats to stderr
    counts = defaultdict(int)
    for e in merged:
        counts[e["category"] or "unknown"] += 1
    print(f"Wrote {len(merged)} substances", file=sys.stderr)
    print(f"  curated only:        {sum(1 for e in merged if e.get('present_in') == ['curated'])}", file=sys.stderr)
    print(f"  drug.community only: {sum(1 for e in merged if e.get('present_in') == ['drug.community'])}", file=sys.stderr)
    print(f"  in both:             {sum(1 for e in merged if set(e.get('present_in') or []) >= {'curated', 'drug.community'})}", file=sys.stderr)
    print(f"  with dose data:      {sum(1 for e in merged if e.get('has_dose_data'))}", file=sys.stderr)
    print(f"  with gaps:           {len(gaps_rows)}", file=sys.stderr)
    print(f"  by category:", file=sys.stderr)
    for cat, n in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"    {cat:32s} {n}", file=sys.stderr)
    print(f"\nOutputs:", file=sys.stderr)
    print(f"  {OUT_CSV}", file=sys.stderr)
    print(f"  {OUT_JSON}", file=sys.stderr)
    print(f"  {OUT_GAPS_CSV}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
