#!/usr/bin/env python3
"""Every identifier the built database actually cites, most-cited first.

The Piru-specific half of paper research: *which* papers this project depends on.
Fetching and reading them is somebody else's job — this prints identifiers, one
per line, for whatever full-text fetcher you pipe it into.

    pipeline/audit/cited_identifiers.py             # every DOI/PMID cited
    pipeline/audit/cited_identifiers.py --limit 50  # the 50 most-cited

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
    args = parser.parse_args()

    if not args.db.exists():
        print(f"no database at {args.db} — run pipeline/build.sh first", file=sys.stderr)
        return 1
    for identifier in cited(args.db, args.limit):
        print(identifier)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
