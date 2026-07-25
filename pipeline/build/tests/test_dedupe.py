#!/usr/bin/env python3
"""Tests for the schema-driven dedupe pass (pipeline/build/dedupe.py)."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dedupe import (  # noqa: E402
    audit,
    dedupe_database,
    find_echoes,
    find_exact_duplicates,
    find_value_duplicates,
    remove_exact_duplicates,
)

FAILURES: list[str] = []


def check(condition: bool, label: str) -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label}")


def make_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.executescript(
        """
        CREATE TABLE pk_routes (
            id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT,
            half_life_min REAL, notes TEXT
        );
        CREATE TABLE mechanisms_summary (
            substance_id INTEGER, source_id INTEGER, summary TEXT, description TEXT
        );
        CREATE TABLE aliases (substance_id INTEGER, alias TEXT);
        """
    )
    return conn


def test_exact_duplicates_removed() -> None:
    print("exact duplicates")
    conn = make_db()
    conn.executemany(
        "INSERT INTO pk_routes (id, substance_id, route, half_life_min, notes) VALUES (?,?,?,?,?)",
        [
            (1, 10, "oral", 56.0, "smoked free-base"),
            (2, 10, "oral", 56.0, "smoked free-base"),  # exact copy of 1
            (3, 10, "oral", 56.0, "smoked free-base"),  # and another
            (4, 10, "insufflation", 75.0, None),
        ],
    )
    check(find_exact_duplicates(conn, "pk_routes") == 2, "counts the excess copies, not the group")
    removed = remove_exact_duplicates(conn, "pk_routes")
    check(removed == 2, "removes exactly the excess copies")
    ids = [r[0] for r in conn.execute("SELECT id FROM pk_routes ORDER BY id")]
    check(ids == [1, 4], "keeps the lowest id of each group, so the choice is stable")
    check(remove_exact_duplicates(conn, "pk_routes") == 0, "a second pass is a no-op")


def test_value_duplicates_are_reported_not_removed() -> None:
    print("value duplicates (the cocaine case)")
    conn = make_db()
    conn.executemany(
        "INSERT INTO pk_routes (id, substance_id, route, half_life_min, notes) VALUES (?,?,?,?,?)",
        [
            (1, 10, "inhalation", 56.0, "Smoked free-base (crack)."),
            (2, 10, "inhalation", 56.0, "Arterial-venous gradient; brain bolus."),
        ],
    )
    check(
        find_exact_duplicates(conn, "pk_routes") == 0, "differing prose is not an exact duplicate"
    )
    check(find_value_duplicates(conn, "pk_routes") == 1, "but it is a value duplicate")
    report = dedupe_database(conn)
    check(
        conn.execute("SELECT COUNT(*) FROM pk_routes").fetchone()[0] == 2,
        "both rows survive — which note to keep is an editorial call",
    )
    check(report.value_duplicates.get("pk_routes") == 1, "and the report says so")
    check(report.is_clean, "value duplicates never fail the gate")


def test_prose_echo_nulled() -> None:
    print("prose echoes (the sertraline case)")
    conn = make_db()
    conn.executemany(
        "INSERT INTO mechanisms_summary (substance_id, source_id, summary, description) "
        "VALUES (?,?,?,?)",
        [
            (1, 13, "Inhibits serotonin reuptake.", "Inhibits serotonin reuptake."),
            (2, 13, "Blocks DAT.", "Blocks the dopamine transporter, raising synaptic dopamine."),
            (3, 13, "Only a summary.", None),
        ],
    )
    check(find_echoes(conn, "mechanisms_summary", "summary", "description") == 1, "finds the echo")
    report = dedupe_database(conn)
    check(report.echoes_nulled.get("mechanisms_summary") == 1, "nulls exactly one")
    rows = dict(conn.execute("SELECT substance_id, description FROM mechanisms_summary").fetchall())
    check(rows[1] is None, "the echoed description is gone")
    check(rows[2].startswith("Blocks the dopamine"), "a genuinely different description survives")
    check(rows[3] is None, "an already-null description is untouched")
    check(
        conn.execute("SELECT summary FROM mechanisms_summary WHERE substance_id=1").fetchone()[0]
        == "Inhibits serotonin reuptake.",
        "the summary itself is never touched",
    )


def test_covers_tables_without_a_surrogate_key() -> None:
    print("id-less tables")
    conn = make_db()
    conn.executemany(
        "INSERT INTO aliases (substance_id, alias) VALUES (?,?)",
        [(1, "Molly"), (1, "Molly"), (1, "Ecstasy")],
    )
    check(remove_exact_duplicates(conn, "aliases") == 1, "dedupes on rowid when there is no id")
    check(conn.execute("SELECT COUNT(*) FROM aliases").fetchone()[0] == 2, "one of each survives")


def test_audit_changes_nothing() -> None:
    print("audit is read-only")
    conn = make_db()
    conn.executemany(
        "INSERT INTO pk_routes (id, substance_id, route, half_life_min, notes) VALUES (?,?,?,?,?)",
        [(1, 10, "oral", 56.0, None), (2, 10, "oral", 56.0, None)],
    )
    report = audit(conn)
    check(report.exact_removed.get("pk_routes") == 1, "reports what a pass would remove")
    check(
        conn.execute("SELECT COUNT(*) FROM pk_routes").fetchone()[0] == 2,
        "but leaves the table alone",
    )
    check(not report.is_clean, "and a removable duplicate is not clean")


def main() -> int:
    for test in (
        test_exact_duplicates_removed,
        test_value_duplicates_are_reported_not_removed,
        test_prose_echo_nulled,
        test_covers_tables_without_a_surrogate_key,
        test_audit_changes_nothing,
    ):
        test()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("all dedupe tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
