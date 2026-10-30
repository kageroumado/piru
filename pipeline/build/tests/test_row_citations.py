"""Row citations stay attached to the rows they were checked against, and the
number of sourceless rows only goes down.

Two things are pinned here:

1. **Every entry in `data/curated/row-citations.json` still names exactly one
   row**, and that row cites what the entry says. An entry that matches nothing
   (the substance was renamed, the row was dropped), matches several, or whose
   row's prose changed (the `claim_sha1` no longer agrees) is stale: its
   citation was checked against a row that no longer exists in that form.
2. **The uncited ratchet.** Rows of the two sources that are not an outside
   publication — `piru-curated` and `peer-review-primary` — are sourced only
   by a citation. Their uncited count per table is committed in
   `uncited-baseline.json`, and a count above it fails. A count below it passes
   and asks for the baseline to be lowered, so the number never drifts back up.

    python3 pipeline/build/tests/test_row_citations.py
    python3 pipeline/build/tests/test_row_citations.py --write-baseline   # after a count drops
"""

from __future__ import annotations

import json
import sqlite3
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1]))

import row_citations  # noqa: E402
from sqlite import is_identifier_citation, parse_reference  # noqa: E402

REPO = HERE.parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
BASELINE = HERE / "uncited-baseline.json"
#: The sources whose rows are attributed to nobody outside Piru, so a missing
#: citation means a missing source. Every other source is an outside
#: publication that is itself the attribution.
SOURCELESS_SLUGS = ("piru-curated", "peer-review-primary")


def uncited_counts(conn: sqlite3.Connection) -> dict[str, int]:
    """`"<table> · <slug>"` → uncited row count, for every table that has both a
    `source_id` and a `citation_id`."""
    out: dict[str, int] = {}
    tables = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        ).fetchall()
    ]
    marks = ",".join("?" for _ in SOURCELESS_SLUGS)
    for table in tables:
        columns = row_citations.table_columns(conn, table)
        if not {"source_id", "citation_id"} <= columns:
            continue
        for slug, count in conn.execute(
            f'SELECT src.slug, COUNT(*) FROM "{table}" t JOIN sources src ON src.id = t.source_id '
            f"WHERE t.citation_id IS NULL AND src.slug IN ({marks}) GROUP BY src.slug",
            SOURCELESS_SLUGS,
        ):
            out[f"{table} · {slug}"] = count
    return dict(sorted(out.items()))


class TestEntriesAreWellFormed(unittest.TestCase):
    """File-only checks: these hold whether or not a DB has been built."""

    def setUp(self) -> None:
        self.entries = row_citations.load()

    def test_every_entry_has_its_fields(self) -> None:
        bad = [
            f"{e.get('table')} · {e.get('substance')}: {'; '.join(p)}"
            for e in self.entries
            if (p := row_citations.problems(e))
        ]
        self.assertEqual(bad, [], "\n".join(bad))

    def test_every_ref_is_a_citation_the_build_keeps(self) -> None:
        bad = []
        for entry in self.entries:
            doi, pmid, url, title = parse_reference(row_citations.cite_string(entry))
            if (doi, pmid, url) == (None, None, None) or is_identifier_citation(
                doi, pmid, url, title
            ):
                bad.append(f"{entry['table']} · {entry['substance']}: {entry['ref']}")
        self.assertEqual(bad, [], "identifier or unparseable refs:\n" + "\n".join(bad))

    def test_no_two_entries_name_one_row(self) -> None:
        seen: dict[tuple, int] = {}
        for entry in self.entries:
            seen[row_citations.entry_key(entry)] = seen.get(row_citations.entry_key(entry), 0) + 1
        dupes = [str(key) for key, n in seen.items() if n > 1]
        self.assertEqual(dupes, [], "\n".join(dupes))


@unittest.skipUnless(DB.exists(), f"{DB} not built — run pipeline/build.sh fast")
class TestEntriesMatchTheBuiltDatabase(unittest.TestCase):
    def setUp(self) -> None:
        self.conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

    def tearDown(self) -> None:
        self.conn.close()

    def test_every_entry_names_exactly_one_row_and_that_row_cites_it(self) -> None:
        stale = []
        for entry in row_citations.load():
            label = f"{entry['table']} · {entry['substance']} · {entry.get('match') or {}}"
            issues = row_citations.problems(entry, self.conn)
            if issues:
                stale.append(f"{label}: {'; '.join(issues)}")
                continue
            rows = row_citations.find_rows(self.conn, entry)
            if len(rows) != 1:
                stale.append(f"{label}: matches {len(rows)} rows")
                continue
            _, citation_id = rows[0]
            doi, pmid, url, _ = parse_reference(row_citations.cite_string(entry))
            cited = self.conn.execute(
                "SELECT doi, pmid, url FROM citations WHERE id = ?", (citation_id,)
            ).fetchone()
            if cited is None or not (
                (doi and cited[0] == doi)
                or (pmid and cited[1] == pmid)
                or (url and cited[2] == url)
            ):
                stale.append(f"{label}: row cites {cited}, entry says {entry['ref']}")
        self.assertEqual(stale, [], "stale row citations:\n" + "\n".join(stale))

    def test_uncited_counts_never_rise(self) -> None:
        baseline = json.loads(BASELINE.read_text())["counts"]
        current = uncited_counts(self.conn)
        risen = [
            f"{key}: {count} uncited, baseline {baseline.get(key, 0)}"
            for key, count in current.items()
            if count > baseline.get(key, 0)
        ]
        self.assertEqual(
            risen,
            [],
            "rows without a source were added. Cite them (data/curated/row-citations.json "
            "or the row's own input) rather than raising the baseline:\n" + "\n".join(risen),
        )
        dropped = [k for k, v in baseline.items() if current.get(k, 0) < v]
        if dropped:
            print(
                f"\nuncited counts fell for {len(dropped)} table(s); lower the baseline with "
                "`python3 pipeline/build/tests/test_row_citations.py --write-baseline`",
                file=sys.stderr,
            )


def write_baseline() -> None:
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    counts = uncited_counts(conn)
    conn.close()
    data = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    data["counts"] = counts
    BASELINE.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(
        f"{BASELINE}: {sum(counts.values())} uncited rows across {len(counts)} table·source pairs"
    )


if __name__ == "__main__":
    if "--write-baseline" in sys.argv:
        write_baseline()
    else:
        unittest.main()
