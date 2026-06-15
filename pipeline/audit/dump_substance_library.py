"""Dump the bundled SQLite library to human-readable text files for review.

Writes one `.txt` file per resolved category to the chosen output directory,
an `_INDEX.md` summary, and a `_FLAGS.md` of automatically-detected data-quality
red flags (all-caps names, raw-IUPAC display names, likely duplicates, category
conflicts across sources, stubs surfacing in browse categories).

The "resolved" category is computed the way the app resolves it: among the
**default-enabled** sources, the one with the lowest `default_priority` wins.
Each substance line also shows the full per-source category set so a reviewer
can see *why* a substance landed where it did.

Usage:
    python3 pipeline/audit/dump_substance_library.py [output_dir]

Defaults to `data/snapshots/by-category/` (the by-category companion to
`data/snapshots/substances.{json,csv}`).
"""

from __future__ import annotations

import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"

# Known acronyms/abbreviations that are legitimately all-caps or mixed — do NOT
# flag these as casing errors. Lowercased for comparison.
ACRONYM_ALLOWLIST = {
    "dmt",
    "lsd",
    "mdma",
    "mda",
    "mde",
    "ghb",
    "gbl",
    "bdo",
    "pcp",
    "dxm",
    "dph",
    "thc",
    "cbd",
    "cbn",
    "cbg",
    "dom",
    "doc",
    "dob",
    "doi",
    "dmxe",
    "5-meo-dmt",
    "5-meo-mipt",
    "5-ho-dmt",
    "2c-b",
    "2c-i",
    "2c-e",
    "2c-t-7",
    "2c-c",
    "2c-p",
    "2c-d",
    "4-aco-dmt",
    "4-ho-met",
    "4-ho-mipt",
    "mxe",
    "mdpv",
    "a-pvp",
    "3-mmc",
    "4-mmc",
    "2-mmc",
    "3-cmc",
    "4-cmc",
    "2-fdck",
    "pma",
    "pmma",
    "tma",
    "ald-52",
    "1p-lsd",
    "1cp-lsd",
    "eth-lad",
    "al-lad",
    "nbome",
    "25i-nbome",
    "25c-nbome",
    "25b-nbome",
    "dipt",
    "mipt",
    "det",
    "amt",
    "aet",
    "5-apb",
    "6-apb",
    "mdai",
    "bk-mdma",
    "u-47700",
    "ghrp",
    "hgh",
    "igf-1",
    "bpc-157",
    "tb-500",
    "nad",
    "nadh",
    "5-htp",
    "gaba",
    "sam-e",
    "msm",
    "dhea",
    "dhm",
    "ksm-66",
    "epa",
    "dha",
    "coq10",
    "alcar",
    "nac",
    "nsi-189",
    "phenibut",
    "f-phenibut",
    "dpa",
    "4f-mph",
    "ipph",
}


def looks_like_iupac(name: str) -> bool:
    """Heuristic: a long, chemical-prefixed name better off behind a display_name."""
    if len(name) < 26:
        return False
    # Lots of hyphens, parentheses, digits, or systematic prefixes.
    chem = sum(name.count(c) for c in "()-,[]")
    digits = sum(ch.isdigit() for ch in name)
    has_systematic = bool(
        re.search(
            r"(methyl|ethyl|phenyl|piperidin|pyrrolidin|methoxy|hydroxy|chloro|fluoro|amino|benzyl|carboxyl)",
            name,
            re.I,
        )
    )
    return (chem + digits >= 4) and has_systematic


def is_bad_caps(name: str) -> bool:
    """All-caps (or all-caps multiword) name that isn't a known acronym."""
    letters = [c for c in name if c.isalpha()]
    if len(letters) < 4:
        return False
    if name.lower() in ACRONYM_ALLOWLIST:
        return False
    # Strip a trailing salt/form word for the acronym check.
    head = name.split()[0].lower()
    if head in ACRONYM_ALLOWLIST:
        return False
    return name == name.upper() and any(c.isalpha() for c in name)


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "data/snapshots/by-category"
    out_dir.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    priority = {}
    enabled = {}
    for r in db.execute("select slug, default_priority, default_enabled from sources"):
        priority[r["slug"]] = r["default_priority"]
        enabled[r["slug"]] = bool(r["default_enabled"])

    subs = list(
        db.execute("""
        select s.id, s.canonical_name, s.display_name, s.normalized_name,
               s.inchikey, s.display_class, s.regulatory_status, s.popularity,
               s.is_stub,
               (select group_concat(a.alias, '|')
                  from (select distinct alias from aliases where substance_id=s.id) a) as aliases
        from substances s
        order by s.canonical_name collate nocase
    """)
    )

    cats_by_sub: dict[int, list[tuple[int, str, str, bool]]] = defaultdict(list)
    for r in db.execute(
        "select c.substance_id, src.slug, c.category "
        "from categories c join sources src on src.id=c.source_id"
    ):
        slug = r["slug"]
        cats_by_sub[r["substance_id"]].append(
            (priority.get(slug, 999), slug, r["category"], enabled.get(slug, False))
        )

    tags_by_sub: dict[int, set[str]] = defaultdict(set)
    for r in db.execute("select substance_id, tag from tags"):
        tags_by_sub[r["substance_id"]].add(r["tag"])

    # One-line dose summary: default-route ladder, lowest-priority-source wins.
    dose_by_sub: dict[int, str] = {}
    for r in db.execute("""
        select substance_id, route, unit, light_lower, common_lower, common_upper,
               strong_upper, heavy
          from dose_ranges
         order by substance_id, route
    """):
        sid = r["substance_id"]
        if sid in dose_by_sub:
            continue
        parts = []
        if r["common_lower"] is not None:
            hi = r["heavy"] or r["strong_upper"] or r["common_upper"]
            parts.append(f"common {r['common_lower']:g}-{r['common_upper']:g}")
            if hi:
                parts.append(f"heavy {hi:g}")
        if parts:
            dose_by_sub[sid] = f"{r['route']} {r['unit']}: " + ", ".join(parts)

    flags: dict[str, list[str]] = defaultdict(list)
    by_cat: dict[str, list[dict]] = defaultdict(list)
    inchi_groups: dict[str, list[str]] = defaultdict(list)
    norm_groups: dict[str, list[str]] = defaultdict(list)

    for s in subs:
        sid = s["id"]
        pairs = cats_by_sub.get(sid, [])

        # Resolution mirrors the app (SubstanceStore.resolvedCategory): a
        # non-informative "Other" from a non-curated source sinks below any
        # specific category, then default-priority decides. A curated "Other" is
        # authoritative and stays at its priority. Key: (sink_other, priority).
        def _key(p):
            return (p[2] == "Other" and p[1] != "piru-curated", p[0])

        enabled_pairs = sorted((p for p in pairs if p[3]), key=_key)
        all_pairs = sorted(pairs, key=_key)
        if enabled_pairs:
            winning_cat = enabled_pairs[0][2]
        elif all_pairs:
            winning_cat = all_pairs[0][2]
        else:
            winning_cat = "(no category)"

        name = s["canonical_name"]
        display = s["display_name"]
        tags = sorted(tags_by_sub.get(sid, set()))
        distinct_cats = sorted({p[2] for p in pairs})

        by_cat[winning_cat].append(
            {
                "name": name,
                "display": display,
                "aliases": s["aliases"] or "",
                "tags": tags,
                "src_cats": [(p[1], p[2]) for p in all_pairs],
                "distinct_cats": distinct_cats,
                "is_stub": bool(s["is_stub"]),
                "display_class": s["display_class"] or "",
                "popularity": s["popularity"] or 0.0,
                "dose": dose_by_sub.get(sid, ""),
            }
        )

        # ---- automated flags ----
        shown = display or name
        if is_bad_caps(shown):
            flags["all_caps_name"].append(f"{name}  (display={display!r})")
        if not display and looks_like_iupac(name):
            flags["raw_iupac_no_display"].append(f"[{winning_cat}] {name}")
        if len(distinct_cats) >= 3:
            flags["category_conflict_3plus"].append(
                f"{name}: " + ", ".join(f"{c}@{sl}" for sl, c in [(p[1], p[2]) for p in all_pairs])
            )
        if s["inchikey"]:
            inchi_groups[s["inchikey"][:14]].append(name)
        norm_groups[s["normalized_name"]].append(name)

    # Duplicate detection
    for block, names in inchi_groups.items():
        if len(set(names)) > 1:
            flags["dup_same_inchikey_block"].append(f"{block}: " + " | ".join(sorted(set(names))))
    for norm, names in norm_groups.items():
        uniq = sorted(set(names))
        if len(uniq) > 1:
            flags["dup_same_normalized"].append(f"{norm}: " + " | ".join(uniq))

    # Per-category files
    for cat, items in sorted(by_cat.items()):
        safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in cat)[:60]
        items.sort(key=lambda d: (-d["popularity"], d["name"].lower()))
        with (out_dir / f"{safe}.txt").open("w") as f:
            f.write(f"# {cat} — {len(items)} substances (sorted by popularity)\n")
            f.write(
                "# fields: NAME [display] {aliases} <display_class> dose | #tags | also-categorized\n\n"
            )
            for d in items:
                line = f"  {d['name']}"
                if d["display"]:
                    line += f"  [{d['display']}]"
                if d["is_stub"]:
                    line += "  (STUB)"
                if d["display_class"]:
                    line += f"  <{d['display_class']}>"
                if d["dose"]:
                    line += f"  — {d['dose']}"
                f.write(line + "\n")
                if d["aliases"]:
                    f.write(f"      aka: {d['aliases']}\n")
                if d["tags"]:
                    f.write("      #" + "  #".join(d["tags"][:12]) + "\n")
                other = [c for c in d["distinct_cats"] if c != cat]
                if other:
                    f.write(f"      also: {', '.join(other)}\n")

    # Index
    total = sum(len(v) for v in by_cat.values())
    with (out_dir / "_INDEX.md").open("w") as f:
        f.write(f"# Resolved category breakdown — {total} substances\n\n")
        f.write("| Category | Count | File |\n|---|---:|---|\n")
        for cat, items in sorted(by_cat.items(), key=lambda x: -len(x[1])):
            safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in cat)[:60]
            f.write(f"| {cat} | {len(items)} | [{safe}.txt]({safe}.txt) |\n")

    # Flags
    with (out_dir / "_FLAGS.md").open("w") as f:
        f.write("# Automated data-quality flags\n\n")
        f.write("Heuristic — review before acting. Sections:\n\n")
        descriptions = {
            "all_caps_name": "All-caps names not on the acronym allow-list (casing bug, e.g. IBOGAINE).",
            "raw_iupac_no_display": "Long raw-IUPAC canonical names with no display_name (need a friendly name).",
            "category_conflict_3plus": "Substances categorized 3+ different ways across sources.",
            "dup_same_inchikey_block": "Different names sharing an InChIKey connectivity block (likely dupes).",
            "dup_same_normalized": "Different names sharing a normalized_name (likely dupes).",
        }
        for key, desc in descriptions.items():
            entries = flags.get(key, [])
            f.write(f"\n## {key} ({len(entries)}) — {desc}\n\n")
            for e in sorted(entries):
                f.write(f"- {e}\n")

    print(f"Wrote {len(by_cat)} category files + _INDEX.md + _FLAGS.md to {out_dir}")
    for key in (
        "all_caps_name",
        "raw_iupac_no_display",
        "category_conflict_3plus",
        "dup_same_inchikey_block",
        "dup_same_normalized",
    ):
        print(f"  {key}: {len(flags.get(key, []))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
