#!/usr/bin/env python3
"""Every identifier the built database actually cites, most-cited first.

The Piru-specific half of paper research: *which* papers this project depends on.
Fetching and reading them is somebody else's job — this prints identifiers, one
per line, for whatever full-text fetcher you pipe it into.

    pipeline/audit/cited_identifiers.py             # every DOI/PMID cited
    pipeline/audit/cited_identifiers.py --limit 50  # the 50 most-cited
    pipeline/audit/cited_identifiers.py --populate-papers   # fetch all into papers cache

Most-cited first, so a bounded run covers the papers the most rows depend on.
One paper can hold several `citations` rows — the same work cited by DOI in one
and by PMID in another — so exact-duplicate identifiers are dropped here. Two
rows citing one paper under *different* identifiers still emit twice; only
resolving them against a registry can collapse those, which is downstream work.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"


def cited(db: Path, limit: int | None = None) -> list[str]:
    connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = connection.execute(
        """
        SELECT c.doi, c.pmid, COUNT(sc.citation_id) AS uses
        FROM citations c
        LEFT JOIN substance_citations sc ON sc.citation_id = c.id
        WHERE c.doi IS NOT NULL OR c.pmid IS NOT NULL
        GROUP BY c.id
        ORDER BY uses DESC, c.id
        """
    ).fetchall()
    connection.close()

    seen: set[str] = set()
    identifiers: list[str] = []
    for doi, pmid, _ in rows:
        value = (doi or "").strip() or str(pmid)
        folded = value.lower()
        if folded in seen:
            continue
        seen.add(folded)
        identifiers.append(value)
    return identifiers[:limit] if limit else identifiers


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--limit", type=int)
    parser.add_argument(
        "--populate-papers",
        action="store_true",
        help="fetch all cited papers into the papers cache (needs `papers` CLI)",
    )
    args = parser.parse_args()

    if not args.db.exists():
        print(f"no database at {args.db} — run pipeline/build.sh first", file=sys.stderr)
        return 1

    identifiers = cited(args.db, args.limit)

    if args.populate_papers:
        from audit.papers import papers_cache  # noqa: E402

        pc = papers_cache()
        if not pc.available:
            print(
                "papers cache not found — install the `papers` CLI or set PAPERS_DIR",
                file=sys.stderr,
            )
            return 1

        uncached = [i for i in identifiers if not pc.has(i)]
        total = len(identifiers)
        cached = total - len(uncached)
        print(
            f"{total} cited identifiers, {cached} already cached, {len(uncached)} to fetch",
            file=sys.stderr,
        )

        if uncached:
            n = pc.populate(uncached)
            pc.reload()
            now_cached = sum(1 for i in identifiers if pc.has(i))
            print(f"submitted {n}, cache now holds {now_cached}/{total}", file=sys.stderr)
        return 0

    for identifier in identifiers:
        print(identifier)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
