#!/usr/bin/env python3
"""Compare the resolved DB values against PsychonautWiki for substances
present in PW. PW is our high-trust reference; divergence on popular
substances suggests a curation problem (our override is wrong, or a
non-piru-curated higher-priority source displaced PW with worse data).

Outputs a markdown table sorted by popularity, flagging:
  - dose tier upper bound: ratio outside [0.5, 2.0]
  - duration phase max:    ratio outside [0.5, 2.0]
  - half-life:             ratio outside [0.5, 2.0]
  - unit mismatch (e.g. PW says µg, resolver says mg with no conversion)

Run from the repo root:
    python3 pipeline/audit/compare_to_pw.py > docs/audit/pw-divergence.md
"""

from __future__ import annotations

import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"

# Source priority order (lower wins). Mirrors the resolver's default.
PRIORITY = {
    "piru-curated": 1,
    "peer-review-primary": 2,
    "psychonautwiki": 3,
    "tripsit": 4,
    "drug.community": 5,
    "dailymed": 6,
    "erowid-pihkal": 7,
    "erowid-tihkal": 8,
    "pdsp": 9,
    "pubchem": 10,
    "wikidata": 11,
    "dea-orange-book": 12,
}

# Significant divergence thresholds. ≥2× either direction is the bar:
# values within 0.5×–2× are considered "broadly consistent" given the
# wide between-individual variation in psychoactive dosing.
RATIO_LO = 0.5
RATIO_HI = 2.0


def unit_to_mg_factor(unit: str | None) -> float | None:
    """Same idea as the build script's helper — convert mass units to mg,
    return None for things we can't validate."""
    if unit is None:
        return 1.0
    u = unit.lower().strip()
    if not u:
        return 1.0
    if "/kg" in u or "/day" in u or "/24h" in u:
        return None
    if u in ("mg", "mgs"):
        return 1.0
    if u in ("g", "gram", "grams"):
        return 1000.0
    if u in ("µg", "ug", "mcg", "μg", "micrograms"):
        return 0.001
    if u in ("µg/hr", "ug/hr", "mcg/hr", "mcg/hour", "mcg/hr (patch)"):
        return 0.001
    return None


def ratio_significant(pw: float | None, resolved: float | None) -> bool:
    if pw is None or resolved is None or pw <= 0 or resolved <= 0:
        return False
    r = resolved / pw
    return r < RATIO_LO or r > RATIO_HI


def fmt_ratio(pw: float, resolved: float) -> str:
    r = resolved / pw
    if r >= 1:
        return f"{r:.1f}× higher"
    return f"{1 / r:.1f}× lower"


def fmt_dose(t, ll, lu, cl, cu, sl, su, h, unit: str) -> str:
    """Render a dose row compactly."""
    parts = []
    if t is not None:
        parts.append(f"thresh {t}")
    if ll is not None or lu is not None:
        parts.append(f"light {ll or '?'}–{lu or '?'}")
    if cl is not None or cu is not None:
        parts.append(f"common {cl or '?'}–{cu or '?'}")
    if sl is not None or su is not None:
        parts.append(f"strong {sl or '?'}–{su or '?'}")
    if h is not None:
        parts.append(f"heavy {h}")
    return f"{' / '.join(parts)} {unit}" if parts else f"(empty) {unit}"


def fmt_dur(phases: dict) -> str:
    """Render a duration profile compactly. phases keyed by phase name."""
    parts = []
    for k in ("onset", "comeup", "peak", "offset", "total"):
        if k not in phases:
            continue
        mn, mx = phases[k]
        if mx >= 60:
            parts.append(f"{k} {mn / 60:.1f}–{mx / 60:.1f}h")
        else:
            parts.append(f"{k} {int(mn)}–{int(mx)}m")
    return " / ".join(parts) if parts else "(empty)"


db = sqlite3.connect(str(DB))
db.row_factory = sqlite3.Row

# ── Popularity score per substance ────────────────────────────────────────
# Heuristic: aliases (well-known compounds have many street names),
# source count (popular = in many DBs), and the `common` tag (subset
# curated as broadly recognised).
popularity = {}
for r in db.execute("""
    SELECT s.id AS sid, s.canonical_name AS name,
           (SELECT COUNT(*) FROM aliases  WHERE substance_id=s.id)                       AS aliases,
           (SELECT COUNT(DISTINCT source_id) FROM dose_ranges WHERE substance_id=s.id)   AS sources_with_doses,
           (SELECT 1 FROM tags WHERE substance_id=s.id AND tag='common' LIMIT 1)         AS is_common
    FROM substances s
""").fetchall():
    score = (
        (r["aliases"] or 0) * 0.5
        + (r["sources_with_doses"] or 0) * 2
        + (8 if r["is_common"] else 0)
    )
    popularity[r["sid"]] = (r["name"], score)

# ── PW substances ────────────────────────────────────────────────────────
pw_substance_ids = {
    r["substance_id"]
    for r in db.execute("""
        SELECT DISTINCT substance_id FROM dose_ranges
        WHERE source_id=(SELECT id FROM sources WHERE slug='psychonautwiki')
        UNION
        SELECT DISTINCT substance_id FROM durations
        WHERE source_id=(SELECT id FROM sources WHERE slug='psychonautwiki')
        UNION
        SELECT DISTINCT substance_id FROM half_lives
        WHERE source_id=(SELECT id FROM sources WHERE slug='psychonautwiki')
    """).fetchall()
}


# ── For each PW substance, compare resolved vs PW value ──────────────────
def resolve_row(rows: list[sqlite3.Row], field_key="source_slug") -> sqlite3.Row | None:
    """Pick the highest-priority row (lowest priority number)."""
    best = None
    best_p = 999
    for row in rows:
        p = PRIORITY.get(row[field_key], 999)
        if p < best_p:
            best, best_p = row, p
    return best


findings = []

for sid in sorted(pw_substance_ids):
    name, score = popularity.get(sid, (None, 0))
    if name is None:
        continue

    # ── Dose comparison per (substance, route) ──────────────────────────
    # Group rows by route, then compare PW vs resolver pick.
    by_route_dose: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for r in db.execute(
        """
        SELECT dr.*, src.slug AS source_slug
          FROM dose_ranges dr
          JOIN sources src ON src.id=dr.source_id
         WHERE dr.substance_id=?
    """,
        (sid,),
    ).fetchall():
        by_route_dose[r["route"]].append(r)

    for route, rows in by_route_dose.items():
        pw_row = next((r for r in rows if r["source_slug"] == "psychonautwiki"), None)
        if pw_row is None:
            continue
        resolved = resolve_row(rows)
        if resolved is None or resolved["source_slug"] == "psychonautwiki":
            continue  # resolver picks PW already — no divergence

        # Pick the common-upper bound (best representative value).
        # Fall back to strong upper or heavy if common isn't populated.
        def representative(row):
            return (
                row["common_upper"]
                or row["common_lower"]
                or row["strong_upper"]
                or row["light_upper"]
                or row["heavy"]
            )

        pw_val = representative(pw_row)
        rs_val = representative(resolved)

        pw_factor = unit_to_mg_factor(pw_row["unit"])
        rs_factor = unit_to_mg_factor(resolved["unit"])

        unit_mismatch = (
            pw_factor is not None
            and rs_factor is not None
            and pw_factor != rs_factor
            and (pw_row["unit"] or "").strip().lower() != (resolved["unit"] or "").strip().lower()
        )

        if pw_factor is not None and rs_factor is not None and pw_val and rs_val:
            pw_mg = pw_val * pw_factor
            rs_mg = rs_val * rs_factor
            if ratio_significant(pw_mg, rs_mg) or unit_mismatch:
                findings.append(
                    {
                        "name": name,
                        "score": score,
                        "type": "dose",
                        "route": route,
                        "pw": fmt_dose(
                            pw_row["threshold"],
                            pw_row["light_lower"],
                            pw_row["light_upper"],
                            pw_row["common_lower"],
                            pw_row["common_upper"],
                            pw_row["strong_lower"],
                            pw_row["strong_upper"],
                            pw_row["heavy"],
                            pw_row["unit"],
                        ),
                        "resolved": fmt_dose(
                            resolved["threshold"],
                            resolved["light_lower"],
                            resolved["light_upper"],
                            resolved["common_lower"],
                            resolved["common_upper"],
                            resolved["strong_lower"],
                            resolved["strong_upper"],
                            resolved["heavy"],
                            resolved["unit"],
                        ),
                        "winner": resolved["source_slug"],
                        "ratio_note": fmt_ratio(pw_mg, rs_mg)
                        if not unit_mismatch
                        else f"unit mismatch ({pw_row['unit']} vs {resolved['unit']})",
                    }
                )

    # ── Duration comparison per (substance, route) ──────────────────────
    by_route_dur: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for r in db.execute(
        """
        SELECT du.route, du.phase, du.min_minutes, du.max_minutes, src.slug AS source_slug
          FROM durations du
          JOIN sources src ON src.id=du.source_id
         WHERE du.substance_id=?
    """,
        (sid,),
    ).fetchall():
        by_route_dur[r["route"]][r["source_slug"]].append(
            (r["phase"], r["min_minutes"], r["max_minutes"])
        )

    for route, by_source in by_route_dur.items():
        if "psychonautwiki" not in by_source:
            continue
        # Resolver picks highest-priority source whose rows we'll consume.
        winner_slug = min(by_source, key=lambda s: PRIORITY.get(s, 999))
        if winner_slug == "psychonautwiki":
            continue
        pw_phases = {ph: (mn, mx) for ph, mn, mx in by_source["psychonautwiki"]}
        rs_phases = {ph: (mn, mx) for ph, mn, mx in by_source[winner_slug]}

        # Compare on `total` (most useful single field) or `peak` if no total.
        ph_check = (
            "total"
            if "total" in pw_phases and "total" in rs_phases
            else ("peak" if "peak" in pw_phases and "peak" in rs_phases else None)
        )
        if ph_check is None:
            continue
        pw_max = pw_phases[ph_check][1]
        rs_max = rs_phases[ph_check][1]
        if ratio_significant(pw_max, rs_max):
            findings.append(
                {
                    "name": name,
                    "score": score,
                    "type": "duration",
                    "route": route,
                    "pw": fmt_dur(pw_phases),
                    "resolved": fmt_dur(rs_phases),
                    "winner": winner_slug,
                    "ratio_note": f"{ph_check}: " + fmt_ratio(pw_max, rs_max),
                }
            )

    # ── Half-life comparison ────────────────────────────────────────────
    hl_rows = db.execute(
        """
        SELECT h.half_life_minutes, src.slug AS source_slug
          FROM half_lives h JOIN sources src ON src.id=h.source_id
         WHERE h.substance_id=?
    """,
        (sid,),
    ).fetchall()
    pw_hl = next((r for r in hl_rows if r["source_slug"] == "psychonautwiki"), None)
    if pw_hl is not None:
        resolved_hl = resolve_row(hl_rows)
        if resolved_hl is not None and resolved_hl["source_slug"] != "psychonautwiki":
            if ratio_significant(pw_hl["half_life_minutes"], resolved_hl["half_life_minutes"]):
                findings.append(
                    {
                        "name": name,
                        "score": score,
                        "type": "half-life",
                        "route": "",
                        "pw": f"{pw_hl['half_life_minutes'] / 60:.1f}h",
                        "resolved": f"{resolved_hl['half_life_minutes'] / 60:.1f}h",
                        "winner": resolved_hl["source_slug"],
                        "ratio_note": fmt_ratio(
                            pw_hl["half_life_minutes"], resolved_hl["half_life_minutes"]
                        ),
                    }
                )


# ── Sort by popularity desc and print ────────────────────────────────────
findings.sort(key=lambda f: (-f["score"], f["name"], f["type"], f["route"]))

print(f"# PsychonautWiki divergence audit\n")
print(
    f"Out of {len(pw_substance_ids)} substances with PW data, "
    f"{len({f['name'] for f in findings})} have at least one significant divergence "
    f"({len(findings)} total findings).\n"
)
print(
    "Significant = field value differs by ≥2× from PW after unit conversion. "
    "Sorted by popularity (alias count + source breadth + `common` tag).\n"
)

print("| Pop. score | Substance | Type | Route | Winner | PW | Resolved | Ratio |")
print("|---:|---|---|---|---|---|---|---|")
for f in findings:
    name = f["name"]
    if len(name) > 28:
        name = name[:25] + "…"
    pw = f["pw"][:60]
    rs = f["resolved"][:60]
    print(
        f"| {f['score']:.0f} | {name} | {f['type']} | {f['route']} | {f['winner']} | {pw} | {rs} | {f['ratio_note']} |"
    )
