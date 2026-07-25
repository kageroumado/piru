#!/usr/bin/env python3
"""Check the built substance DB for duplicated values.

Every duplicate found so far reached the app as a card printed twice — cocaine
listing "Inhalation" with the same numbers under it, sertraline printing one
mechanism sentence as two paragraphs. Neither was visible anywhere in the
pipeline, so this makes them a build-time fact instead of a screenshot.

    python3 pipeline/audit/dedup_check.py              # report
    python3 pipeline/audit/dedup_check.py --gate       # exit 1 if anything removable remains
    python3 pipeline/audit/dedup_check.py --fix        # dedupe in place

`--gate` fails only on **mechanically removable** duplicates (exact row copies,
prose echoes). Value duplicates — rows agreeing on every number but carrying
different notes — are always reported and never fail: which note survives is an
editorial call. See `pipeline/build/dedupe.py`.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.dedupe import audit, dedupe_database  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to the built SQLite")
    parser.add_argument(
        "--gate", action="store_true", help="exit 1 when removable duplicates remain"
    )
    parser.add_argument("--fix", action="store_true", help="remove duplicates in place")
    args = parser.parse_args()

    if not args.db.exists():
        print(f"dedup-check: no database at {args.db}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(args.db)
    try:
        report = dedupe_database(conn) if args.fix else audit(conn)
    finally:
        conn.close()

    verb = "removed" if args.fix else "found"
    print(f"dedup-check: {args.db.relative_to(REPO) if args.db.is_relative_to(REPO) else args.db}")
    if report.total_removed or report.total_nulled:
        print(
            f"  {verb} {report.total_removed} exact duplicate row(s) and "
            f"{report.total_nulled} echoed prose column(s)"
        )
    if report.total_value_duplicates:
        print(f"  {report.total_value_duplicates} value duplicate(s) — reported only, see below")
    for line in report.summary_lines():
        print(line)
    if report.is_clean and not report.total_value_duplicates:
        print("  no duplicates")

    if args.gate and not args.fix and not report.is_clean:
        print(
            "dedup-check: FAILED — the build should have removed these; "
            "run `pipeline/build.sh fast` or `--fix`",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
