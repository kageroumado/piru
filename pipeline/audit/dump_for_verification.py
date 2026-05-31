"""Dump the bundled SQLite substance library to human-readable text files for agent verification.

For each substance, emits the **resolved** dose ranges and durations per route
(the values the app actually shows the user, computed by mirroring
`SubstanceStore.resolvedDoseForRoute` — highest-priority enabled source wins).

When multiple sources disagree by more than ~2x on a common dose, the
disagreement is shown inline so reviewers can flag which value to trust.

Output is chunked by category (and split for large categories) into ~50
substances per file, suitable for parallel verification by multiple agents.

Usage:
    python3 pipeline/audit/dump_for_verification.py [output_dir]

Defaults to `docs/audit/verification-dump/` (gitignored — regenerate as needed).
"""

from __future__ import annotations

import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"

CHUNK_SIZE = 50
DISAGREEMENT_RATIO = 2.0


def fmt_range(lower, upper, unit):
    if lower is None and upper is None:
        return None
    if lower is None:
        return f"<{_num(upper)} {unit}"
    if upper is None or lower == upper:
        return f"{_num(lower)} {unit}"
    return f"{_num(lower)}–{_num(upper)} {unit}"


def _num(x):
    if x is None:
        return "?"
    if float(x).is_integer():
        return str(int(x))
    s = f"{x:g}"
    return s


def fmt_minutes(m):
    if m is None:
        return "?"
    if m < 1:
        return f"{_num(round(m * 60))}s"
    if m < 60:
        return f"{_num(m)}m"
    h = m / 60
    return f"{_num(h)}h"


def fmt_duration_range(lo, hi):
    if lo is None and hi is None:
        return None
    if lo == hi or hi is None:
        return fmt_minutes(lo)
    return f"{fmt_minutes(lo)}–{fmt_minutes(hi)}"


PHASE_ORDER = ["onset", "comeup", "peak", "offset", "total", "afterglow"]


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "docs/audit/verification-dump"
    out_dir.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    source_priority = {
        r["slug"]: r["default_priority"]
        for r in db.execute("SELECT slug, default_priority FROM sources WHERE default_enabled = 1")
    }

    substances = list(
        db.execute("""
        SELECT id, canonical_name FROM substances ORDER BY canonical_name COLLATE NOCASE
    """)
    )

    # Resolve category per substance (winning source by priority)
    cat_rows = list(
        db.execute("""
        SELECT c.substance_id, src.slug, src.default_priority, c.category
          FROM categories c JOIN sources src ON src.id = c.source_id
         WHERE src.default_enabled = 1
    """)
    )
    cat_winning: dict[int, str] = {}
    cat_candidates: dict[int, list] = defaultdict(list)
    for r in cat_rows:
        cat_candidates[r["substance_id"]].append((r["default_priority"], r["category"]))
    for sid, cands in cat_candidates.items():
        cands.sort()
        cat_winning[sid] = cands[0][1]

    # All dose-range rows
    dose_rows = list(
        db.execute("""
        SELECT d.substance_id, d.route, src.slug AS source, src.default_priority AS prio,
               d.unit, d.threshold,
               d.light_lower, d.light_upper, d.common_lower, d.common_upper,
               d.strong_lower, d.strong_upper, d.heavy
          FROM dose_ranges d JOIN sources src ON src.id = d.source_id
         WHERE src.default_enabled = 1
    """)
    )
    doses_by_sub: dict[int, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for r in dose_rows:
        doses_by_sub[r["substance_id"]][r["route"]].append(r)

    # All duration rows
    dur_rows = list(
        db.execute("""
        SELECT du.substance_id, du.route, src.slug AS source, src.default_priority AS prio,
               du.phase, du.min_minutes, du.max_minutes
          FROM durations du JOIN sources src ON src.id = du.source_id
         WHERE src.default_enabled = 1
    """)
    )
    dur_by_sub: dict[int, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for r in dur_rows:
        dur_by_sub[r["substance_id"]][r["route"]].append(r)

    # Half-lives
    hl_rows = list(
        db.execute("""
        SELECT h.substance_id, src.slug AS source, src.default_priority AS prio,
               h.half_life_minutes, h.notes
          FROM half_lives h JOIN sources src ON src.id = h.source_id
         WHERE src.default_enabled = 1
    """)
    )
    hl_by_sub: dict[int, list] = defaultdict(list)
    for r in hl_rows:
        hl_by_sub[r["substance_id"]].append(r)

    # Build per-substance text blocks
    by_cat: dict[str, list[tuple[str, str]]] = defaultdict(list)
    skipped = 0
    for s in substances:
        sid = s["id"]
        cat = cat_winning.get(sid, "Uncategorized")
        if sid not in doses_by_sub and sid not in dur_by_sub:
            skipped += 1
            continue
        block = render_substance(
            sid,
            s["canonical_name"],
            cat,
            doses_by_sub.get(sid, {}),
            dur_by_sub.get(sid, {}),
            hl_by_sub.get(sid, []),
            source_priority,
        )
        by_cat[cat].append((s["canonical_name"], block))

    # Chunk and write
    file_count = 0
    total_substances = 0
    for cat in sorted(by_cat.keys()):
        items = by_cat[cat]
        items.sort(key=lambda x: x[0].lower())
        chunks = [items[i : i + CHUNK_SIZE] for i in range(0, len(items), CHUNK_SIZE)]
        safe = "".join(c if c.isalnum() else "_" for c in cat)
        for idx, chunk in enumerate(chunks):
            suffix = f"_{idx + 1:02d}" if len(chunks) > 1 else ""
            fname = f"{safe}{suffix}.txt"
            with (out_dir / fname).open("w") as f:
                f.write(f"# {cat} — chunk {idx + 1}/{len(chunks)} — {len(chunk)} substances\n\n")
                f.write(_header_legend())
                for _name, block in chunk:
                    f.write(block)
                    f.write("\n")
            file_count += 1
            total_substances += len(chunk)

    # Index
    with (out_dir / "_INDEX.md").open("w") as f:
        f.write(
            f"# Substance verification dump — {total_substances} substances across {file_count} files\n\n"
        )
        f.write(f"Skipped {skipped} substances with no dose/duration data.\n\n")
        f.write(_header_legend())
        f.write("\n## Files\n\n")
        f.write("| Category | Substances | Files |\n|---|---:|---|\n")
        for cat in sorted(by_cat.keys()):
            items = by_cat[cat]
            chunks = (len(items) + CHUNK_SIZE - 1) // CHUNK_SIZE
            safe = "".join(c if c.isalnum() else "_" for c in cat)
            file_links = ", ".join(
                f"[{safe}{f'_{i + 1:02d}' if chunks > 1 else ''}.txt]({safe}{f'_{i + 1:02d}' if chunks > 1 else ''}.txt)"
                for i in range(chunks)
            )
            f.write(f"| {cat} | {len(items)} | {file_links} |\n")

    print(f"Wrote {file_count} files covering {total_substances} substances to {out_dir}")
    print(f"Skipped {skipped} substances with no dose/duration data.")
    return 0


def _header_legend() -> str:
    return (
        "Format: each route shows the resolved value the app displays (winning source in parens).\n"
        "When sources disagree on common dose by ≥2×, the disagreement is shown as `[also: …]`.\n"
        "Flag obvious errors: doses or durations that don't match clinical/community knowledge.\n\n"
    )


def render_substance(
    sid, name, category, doses_by_route, dur_by_route, hl_rows, source_priority
) -> str:
    lines = [f"## {name} ({category})"]

    routes = sorted(set(list(doses_by_route.keys()) + list(dur_by_route.keys())))
    if not routes:
        return "\n".join(lines) + "\n"

    for route in routes:
        line_parts = [f"  {route}:"]

        dose_candidates = sorted(doses_by_route.get(route, []), key=lambda r: r["prio"])
        if dose_candidates:
            winner = dose_candidates[0]
            unit = winner["unit"] or "mg"
            dose_str = _format_dose_resolved(winner)
            line_parts.append(dose_str)
            line_parts.append(f"({winner['source']})")
            disagreement = _format_dose_disagreement(dose_candidates, unit)
            if disagreement:
                line_parts.append(disagreement)
        else:
            line_parts.append("(no dose data)")

        dur_candidates = dur_by_route.get(route, [])
        if dur_candidates:
            dur_str = _format_duration_resolved(dur_candidates, source_priority)
            if dur_str:
                line_parts.append("|")
                line_parts.append(dur_str)

        lines.append(" ".join(line_parts))

    if hl_rows:
        hl_rows_sorted = sorted(hl_rows, key=lambda r: r["prio"])
        winner = hl_rows_sorted[0]
        hl_min = winner["half_life_minutes"]
        hl_str = fmt_minutes(hl_min) if hl_min else "?"
        lines.append(f"  half-life: {hl_str} ({winner['source']})")
        if len(hl_rows_sorted) > 1:
            others = [
                f"{fmt_minutes(r['half_life_minutes'])} ({r['source']})"
                for r in hl_rows_sorted[1:]
                if r["half_life_minutes"]
                and not _within_ratio(r["half_life_minutes"], hl_min, DISAGREEMENT_RATIO)
            ]
            if others:
                lines[-1] += f"  [also: {', '.join(others)}]"

    return "\n".join(lines) + "\n"


def _format_dose_resolved(row) -> str:
    unit = row["unit"] or "mg"
    tiers = []
    if row["threshold"] is not None:
        tiers.append(f"threshold {_num(row['threshold'])} {unit}")
    light = fmt_range(row["light_lower"], row["light_upper"], unit)
    if light:
        tiers.append(f"light {light}")
    common = fmt_range(row["common_lower"], row["common_upper"], unit)
    if common:
        tiers.append(f"common {common}")
    strong = fmt_range(row["strong_lower"], row["strong_upper"], unit)
    if strong:
        tiers.append(f"strong {strong}")
    if row["heavy"] is not None:
        tiers.append(f"heavy ≥{_num(row['heavy'])} {unit}")
    return ", ".join(tiers) if tiers else "(empty)"


def _format_dose_disagreement(candidates, unit) -> str | None:
    if len(candidates) < 2:
        return None
    winner = candidates[0]
    others = []
    for c in candidates[1:]:
        if _common_disagrees(winner, c, DISAGREEMENT_RATIO):
            common_str = fmt_range(c["common_lower"], c["common_upper"], c["unit"] or unit) or "—"
            others.append(f"{c['source']}: common {common_str}")
    if not others:
        return None
    return f"[also: {'; '.join(others)}]"


def _common_disagrees(a, b, ratio) -> bool:
    a_lo, a_hi = a["common_lower"], a["common_upper"]
    b_lo, b_hi = b["common_lower"], b["common_upper"]
    if None in (a_lo, b_lo):
        return False
    if (a["unit"] or "").lower() != (b["unit"] or "").lower():
        return True
    if not _within_ratio(a_lo, b_lo, ratio):
        return True
    return bool(a_hi and b_hi and not _within_ratio(a_hi, b_hi, ratio))


def _within_ratio(a, b, ratio) -> bool:
    if a == 0 or b == 0:
        return a == b
    r = a / b if a > b else b / a
    return r <= ratio


def _format_duration_resolved(candidates, source_priority) -> str:
    candidates_sorted = sorted(candidates, key=lambda r: r["prio"])
    winning_source = candidates_sorted[0]["source"]
    winning_phases = [c for c in candidates if c["source"] == winning_source]

    by_phase = {c["phase"]: c for c in winning_phases}
    parts = []
    for phase in PHASE_ORDER:
        if phase in by_phase:
            p = by_phase[phase]
            rng = fmt_duration_range(p["min_minutes"], p["max_minutes"])
            if rng:
                parts.append(f"{phase} {rng}")
    if not parts:
        return ""
    return f"duration ({winning_source}): " + ", ".join(parts)


if __name__ == "__main__":
    sys.exit(main())
