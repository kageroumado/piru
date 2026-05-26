"""Dump the bundled SQLite library to human-readable text files for review.

Writes one `.txt` file per resolved category to the chosen output directory
plus an `_INDEX.md` summary. Each substance line shows the canonical name,
the source whose category won under default priority, and the alias list.

Usage:
    python3 Exports/dump-substance-library.py [output_dir]

Defaults to `Exports/library-dump/`.
"""

from __future__ import annotations

import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DB = REPO / "Piru/Data/piru-substances.sqlite"


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "Exports/library-dump"
    out_dir.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    sources = {r["slug"]: r["default_priority"] for r in db.execute(
        "select slug, default_priority from sources"
    )}
    subs = list(db.execute("""
        select s.id, s.canonical_name,
               (select group_concat(a.alias, '|') from (select distinct alias from aliases where substance_id=s.id) a) as aliases
        from substances s
        order by s.canonical_name collate nocase
    """))

    cats_by_sub: dict[int, list[tuple[int, str, str]]] = defaultdict(list)
    for r in db.execute(
        "select c.substance_id, src.slug, c.category "
        "from categories c join sources src on src.id=c.source_id"
    ):
        cats_by_sub[r["substance_id"]].append(
            (sources.get(r["slug"], 999), r["slug"], r["category"])
        )

    tags_by_sub: dict[int, set[str]] = defaultdict(set)
    for r in db.execute("select substance_id, tag from tags"):
        tags_by_sub[r["substance_id"]].add(r["tag"])

    by_cat: dict[str, list[tuple[str, str, str, list[str]]]] = defaultdict(list)
    for s in subs:
        sid = s["id"]
        pairs = cats_by_sub.get(sid, [])
        if pairs:
            pairs.sort()
            winning_slug, winning_cat = pairs[0][1], pairs[0][2]
        else:
            winning_slug, winning_cat = "—", "(no category)"
        by_cat[winning_cat].append((
            s["canonical_name"],
            s["aliases"] or "",
            winning_slug,
            sorted(tags_by_sub.get(sid, set())),
        ))

    # Per-category files
    for cat, items in by_cat.items():
        safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in cat)[:60]
        with (out_dir / f"{safe}.txt").open("w") as f:
            f.write(f"# {cat} — {len(items)} substances\n\n")
            for name, aliases, slug, tags in items:
                line = f"  {name}"
                if aliases:
                    line += f"  [{aliases}]"
                line += f"  (source: {slug})"
                if tags:
                    line += f"  #" + "  #".join(tags[:8])
                    if len(tags) > 8:
                        line += f"  +{len(tags)-8}more"
                f.write(line + "\n")

    # Index
    total = sum(len(v) for v in by_cat.values())
    with (out_dir / "_INDEX.md").open("w") as f:
        f.write(f"# Resolved category breakdown — {total} substances\n\n")
        f.write("| Category | Count | File |\n|---|---:|---|\n")
        for cat, items in sorted(by_cat.items(), key=lambda x: -len(x[1])):
            safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in cat)[:60]
            f.write(f"| {cat} | {len(items)} | [{safe}.txt]({safe}.txt) |\n")

    print(f"Wrote {len(by_cat)} category files + _INDEX.md to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
