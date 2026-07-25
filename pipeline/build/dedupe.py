"""Schema-driven duplicate removal for the bundled substance DB.

Multi-source ingestion means the same fact arrives more than once: two sources
publish the same caffeine onset, one source is scraped twice under different
slugs, an importer writes a prose field into both `summary` and `description`.
None of that is visible in the pipeline — it surfaces in the app as a card
printed twice, which is how every instance of it has been found so far (cocaine
listing "Inhalation" twice, sertraline printing one mechanism sentence twice).

Three distinct shapes, deliberately treated differently:

**Exact duplicates** — two rows identical in every column but the surrogate
`id`. Nothing distinguishes them and nothing can; the second row is pure noise.
Removed, keeping the lowest id so the choice is stable across builds.

**Column echoes** — one row whose prose column merely repeats another
(`description` == `summary`). The reader renders both, so the user sees the
sentence twice. The echo is nulled, never the original.

**Value duplicates** — rows agreeing on every measured value but differing in
free text, e.g. cocaine's two inhalation PK rows with identical numbers and
different notes. These are **reported, never removed**: the numbers are
redundant but the prose is not, and choosing which note to keep is an editorial
call, not a mechanical one. The app collapses them for display instead (see
`SubstanceStore.displayRows(_:)`).

The pass is driven off `PRAGMA table_info` rather than a table list, so a table
added later is covered without touching this file.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field

#: Columns holding human prose rather than a measured value. Two rows that
#: differ *only* in these are value duplicates; a column that merely repeats
#: another of these within one row is an echo.
PROSE_COLUMNS = frozenset(
    {"notes", "note", "description", "summary", "narrative", "comment", "commentary"}
)

#: Surrogate keys, excluded from every comparison — they are what makes two
#: otherwise-identical rows distinct, which is precisely the thing being tested.
SURROGATE_COLUMNS = frozenset({"id", "rowid"})

#: Echo pairs to collapse, as (table, keep, redundant). Only pairs where the
#: reader treats the redundant column as optional belong here: `description`
#: decodes through `?? ""`, so nulling it renders one paragraph instead of two.
ECHO_PAIRS: tuple[tuple[str, str, str], ...] = (("mechanisms_summary", "summary", "description"),)


@dataclass
class DedupeReport:
    """What a dedupe pass changed, and what it deliberately left alone."""

    exact_removed: dict[str, int] = field(default_factory=dict)
    echoes_nulled: dict[str, int] = field(default_factory=dict)
    value_duplicates: dict[str, int] = field(default_factory=dict)

    @property
    def total_removed(self) -> int:
        return sum(self.exact_removed.values())

    @property
    def total_nulled(self) -> int:
        return sum(self.echoes_nulled.values())

    @property
    def total_value_duplicates(self) -> int:
        return sum(self.value_duplicates.values())

    @property
    def is_clean(self) -> bool:
        """True when nothing mechanically removable remains. Value duplicates
        don't count — they're a human's call, so they never fail a gate."""
        return self.total_removed == 0 and self.total_nulled == 0

    def summary_lines(self) -> list[str]:
        """Tense-neutral, because the same report is produced by an audit (which
        changes nothing) and by a dedupe pass (which changed exactly this)."""
        out: list[str] = []
        for table, n in sorted(self.exact_removed.items()):
            out.append(f"  {table}: {n} exact duplicate row(s)")
        for table, n in sorted(self.echoes_nulled.items()):
            out.append(f"  {table}: {n} echoed prose column(s)")
        for table, n in sorted(self.value_duplicates.items()):
            out.append(f"  {table}: {n} value duplicate(s) left in place (differ only in prose)")
        return out


def _tables(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_fts%' ORDER BY name"
    ).fetchall()
    return [r[0] for r in rows]


def _columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")').fetchall()]


def _quote(columns: list[str]) -> str:
    return ", ".join(f'"{c}"' for c in columns)


def find_exact_duplicates(conn: sqlite3.Connection, table: str) -> int:
    """Count the *excess* rows that are identical in every non-surrogate column."""
    columns = [c for c in _columns(conn, table) if c not in SURROGATE_COLUMNS]
    if not columns:
        return 0
    row = conn.execute(
        f"SELECT COALESCE(SUM(n - 1), 0) FROM "
        f'(SELECT COUNT(*) AS n FROM "{table}" GROUP BY {_quote(columns)} HAVING n > 1)'
    ).fetchone()
    return int(row[0])


def remove_exact_duplicates(conn: sqlite3.Connection, table: str) -> int:
    """Delete rows identical in every non-surrogate column, keeping the lowest
    `id` of each group (or the lowest `rowid` for id-less tables, so junction
    tables are covered too). Returns the number deleted."""
    all_columns = _columns(conn, table)
    columns = [c for c in all_columns if c not in SURROGATE_COLUMNS]
    if not columns:
        return 0
    key = "id" if "id" in all_columns else "rowid"
    before = conn.total_changes
    conn.execute(
        f'DELETE FROM "{table}" WHERE {key} NOT IN '
        f'(SELECT MIN({key}) FROM "{table}" GROUP BY {_quote(columns)})'
    )
    return conn.total_changes - before


def find_value_duplicates(conn: sqlite3.Connection, table: str) -> int:
    """Count excess rows that agree on every measured column but differ in prose.

    Reported, never removed — see the module docstring.
    """
    columns = [
        c for c in _columns(conn, table) if c not in SURROGATE_COLUMNS and c not in PROSE_COLUMNS
    ]
    if not columns:
        return 0
    row = conn.execute(
        f"SELECT COALESCE(SUM(n - 1), 0) FROM "
        f'(SELECT COUNT(*) AS n FROM "{table}" GROUP BY {_quote(columns)} HAVING n > 1)'
    ).fetchone()
    return int(row[0])


def find_echoes(conn: sqlite3.Connection, table: str, keep: str, redundant: str) -> int:
    """Count rows where `redundant` merely repeats `keep`."""
    columns = _columns(conn, table)
    if keep not in columns or redundant not in columns:
        return 0
    row = conn.execute(
        f'SELECT COUNT(*) FROM "{table}" '
        f'WHERE "{redundant}" IS NOT NULL AND "{redundant}" = "{keep}"'
    ).fetchone()
    return int(row[0])


def null_echoes(conn: sqlite3.Connection, table: str, keep: str, redundant: str) -> int:
    """Null `redundant` wherever it merely repeats `keep`. Returns rows changed."""
    columns = _columns(conn, table)
    if keep not in columns or redundant not in columns:
        return 0
    before = conn.total_changes
    conn.execute(
        f'UPDATE "{table}" SET "{redundant}" = NULL '
        f'WHERE "{redundant}" IS NOT NULL AND "{redundant}" = "{keep}"'
    )
    return conn.total_changes - before


def audit(conn: sqlite3.Connection) -> DedupeReport:
    """Report every duplicate class without changing anything."""
    report = DedupeReport()
    for table in _tables(conn):
        if n := find_exact_duplicates(conn, table):
            report.exact_removed[table] = n
        # Value duplicates are counted *after* exact ones would be removed, so a
        # table full of exact copies doesn't also report them as value dupes.
        if (n := find_value_duplicates(conn, table)) > report.exact_removed.get(table, 0):
            report.value_duplicates[table] = n - report.exact_removed.get(table, 0)
    for table, keep, redundant in ECHO_PAIRS:
        if n := find_echoes(conn, table, keep, redundant):
            report.echoes_nulled[table] = n
    return report


def dedupe_database(conn: sqlite3.Connection) -> DedupeReport:
    """Remove exact duplicates and prose echoes; report value duplicates.

    Safe to run more than once — a second pass finds nothing.
    """
    report = DedupeReport()
    for table in _tables(conn):
        if n := remove_exact_duplicates(conn, table):
            report.exact_removed[table] = n
    for table, keep, redundant in ECHO_PAIRS:
        if n := null_echoes(conn, table, keep, redundant):
            report.echoes_nulled[table] = n
    for table in _tables(conn):
        if n := find_value_duplicates(conn, table):
            report.value_duplicates[table] = n
    conn.commit()
    return report
