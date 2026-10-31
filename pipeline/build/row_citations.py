"""Per-row citations from ``data/curated/row-citations.json``.

A row in a pharmacology table carries its citation in ``citation_id``. Most get
one from the input that wrote them (an enrichment block's ``reference``, a
curated file's ``halfLifeSource``). This sidecar is for the rest: rows whose
input names no source, sourced afterwards by a pass that checked the source
against the row. Every pass writes here, so there is one place a sourced
citation lives and one format a reviewer reads.

One entry names one row by a stable identity, never a rowid:

    {
      "table": "pharmacogenetics",          # a table with substance_id, source_id, citation_id
      "substance": "MDMA",                  # canonical name after every merge
      "source": "peer-review-primary",      # the row's source slug
      "match": {"gene": "CYP2D6"},          # further columns, compared with IS
      "claim_sha1": "3f2a9c01b7de",         # see claim_sha1(); required where CLAIM_COLUMNS names one
      "ref": "doi:10.3389/fgene.2012.00235",# doi:/pmid:/https:// — parsed by the build's own parser
      "title": "…",                         # optional; shown when the ref has no registry title
      "accessed": "2026-10-30",
      "via": "references_consulted",        # which pass proposed it
      "evidence": "abstract names MDMA; names CYP2D6"
    }

The claim hash pins the citation to the text it was checked against. When the
row's prose changes, the entry stops matching and the test fails: the new prose
has to be checked again, because the paper supported the old sentence.

Applied by the build after every row is written (``apply``), and re-checked
against the built DB by ``pipeline/build/tests/test_row_citations.py``: an entry
that matches no row, more than one row, or a row already citing something else
is stale, and fails that test.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from collections import Counter
from collections.abc import Callable
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROW_CITATIONS = REPO / "data/curated/row-citations.json"

#: The prose column each table's claim lives in. An entry on one of these
#: tables must carry ``claim_sha1`` of that column.
CLAIM_COLUMNS: dict[str, str] = {
    "downstream_signalling": "summary",
    "pharmacogenetics": "phenotype_effects",
    "mechanisms_summary": "summary",
    "descriptions": "text",
    "off_targets": "clinical_consequence",
    "drug_interactions_pk": "clinical_effect",
    "neuroimaging": "finding",
    "biased_agonism": "interpretation",
    "metabolism": "notes",
    "functional_assays": "notes",
    "bindings": "notes",
}

#: Which passes may write an entry. A new pass adds its name here, so an entry
#: can always be traced to the code that proposed it.
VIA = {"references_consulted", "dailymed-ndc", "haiku", "hand"}
#: Passes that stamp the run date into `via`, so entries from two runs stay
#: distinguishable: `audit/source_with_haiku.py` writes `haiku-assisted YYYY-MM-DD`.
VIA_DATED = re.compile(r"^haiku-assisted \d{4}-\d{2}-\d{2}$")

REQUIRED = ("table", "substance", "source", "ref", "accessed", "via", "evidence")
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def claim_sha1(text: str | None) -> str:
    """Twelve hex characters of the SHA-1 of the claim, whitespace collapsed.

    Whitespace is collapsed because the build reflows prose (`clean_wiki_prose`)
    and a reflow is not a different claim."""
    return hashlib.sha1(" ".join((text or "").split()).encode("utf-8")).hexdigest()[:12]


def load(path: Path = ROW_CITATIONS) -> list[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    entries = data.get("entries") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        raise SystemExit(f"{path}: expected an object with an `entries` list")
    return entries


def save(entries: list[dict], path: Path = ROW_CITATIONS) -> None:
    """Write entries in one stable order, so a re-run of a pass that finds
    nothing new leaves an empty diff."""
    data = json.loads(path.read_text()) if path.exists() else {}
    data["entries"] = sorted(entries, key=entry_key)
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")


def entry_key(entry: dict) -> tuple:
    """The row identity an entry names. Two entries with one key would fight
    over the row, so the test rejects duplicates."""
    match = tuple(sorted((k, str(v)) for k, v in (entry.get("match") or {}).items()))
    return (
        entry.get("table") or "",
        (entry.get("substance") or "").lower(),
        entry.get("source") or "",
        match,
        entry.get("claim_sha1") or "",
    )


def table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')}


def problems(entry: dict, conn: sqlite3.Connection | None = None) -> list[str]:
    """Schema problems with one entry. With a connection, also checks that the
    table and the match columns exist."""
    out = [f"missing `{field}`" for field in REQUIRED if not entry.get(field)]
    if entry.get("via") and entry["via"] not in VIA and not VIA_DATED.match(entry["via"]):
        out.append(f"unknown via {entry['via']!r} (allowed: {sorted(VIA)})")
    if entry.get("accessed") and not _DATE.match(str(entry["accessed"])):
        out.append(f"accessed {entry['accessed']!r} is not YYYY-MM-DD")
    ref = str(entry.get("ref") or "")
    if ref and not re.match(r"(?i)^(doi:10\.|pmid:\d+$|https?://)", ref):
        out.append(f"ref {ref!r} is not doi:/pmid:/http(s)://")
    table = entry.get("table")
    if table in CLAIM_COLUMNS and not entry.get("claim_sha1"):
        out.append(f"`{table}` rows need claim_sha1 of {CLAIM_COLUMNS[table]}")
    if conn is not None and table:
        columns = table_columns(conn, table)
        if not {"substance_id", "source_id", "citation_id"} <= columns:
            out.append(f"table {table!r} has no substance_id/source_id/citation_id")
        for column in entry.get("match") or {}:
            if column not in columns:
                out.append(f"match column {column!r} is not on {table}")
    return out


def find_rows(conn: sqlite3.Connection, entry: dict) -> list[tuple[int, int | None]]:
    """``(rowid, citation_id)`` of every row the entry names."""
    table = entry["table"]
    match = entry.get("match") or {}
    claim_column = CLAIM_COLUMNS.get(table)
    select_claim = f', t."{claim_column}"' if claim_column else ", NULL"
    clauses = ["lower(s.canonical_name) = lower(?)", "src.slug = ?"]
    params: list[object] = [entry["substance"], entry["source"]]
    for column, value in sorted(match.items()):
        clauses.append(f't."{column}" IS ?')
        params.append(value)
    rows = conn.execute(
        f'SELECT t.rowid, t.citation_id{select_claim} FROM "{table}" t '
        "JOIN substances s ON s.id = t.substance_id "
        "JOIN sources src ON src.id = t.source_id "
        f"WHERE {' AND '.join(clauses)}",
        params,
    ).fetchall()
    want = entry.get("claim_sha1")
    return [(rowid, cid) for rowid, cid, claim in rows if not want or claim_sha1(claim) == want]


def cite_string(entry: dict) -> str:
    """The reference string handed to the build's ``cite()``, title included in
    the form ``parse_reference`` reads it back from."""
    ref = str(entry["ref"]).strip()
    title = (entry.get("title") or "").strip()
    if not title:
        return ref
    if ref.lower().startswith("http"):
        return f"{title}; {ref}"
    if ref.lower().startswith("doi:"):
        return f"{ref} {title}"
    return ref


def apply(
    conn: sqlite3.Connection,
    entries: list[dict],
    cite: Callable[[str], int | None],
) -> tuple[Counter, list[str]]:
    """Attach each entry's citation to the one row it names.

    Returns counts per outcome and one line per entry that could not be
    applied. Nothing here overwrites a citation a row already has: an entry
    whose row is already cited is reported, not applied."""
    counts: Counter = Counter()
    failures: list[str] = []
    for entry in entries:
        label = f"{entry.get('table')} · {entry.get('substance')} · {entry.get('match') or {}}"
        issues = problems(entry, conn)
        if issues:
            counts["invalid"] += 1
            failures.append(f"{label}: {'; '.join(issues)}")
            continue
        rows = find_rows(conn, entry)
        if len(rows) != 1:
            counts["unmatched" if not rows else "ambiguous"] += 1
            failures.append(f"{label}: matches {len(rows)} rows")
            continue
        rowid, existing = rows[0]
        cid = cite(cite_string(entry))
        if cid is None:
            counts["uncitable"] += 1
            failures.append(f"{label}: ref {entry['ref']!r} is not a citable reference")
            continue
        if existing is not None:
            counts["already_cited" if existing == cid else "conflict"] += 1
            if existing != cid:
                failures.append(f"{label}: row already cites citation {existing}")
            continue
        conn.execute(f'UPDATE "{entry["table"]}" SET citation_id = ? WHERE rowid = ?', (cid, rowid))
        counts[f"applied:{entry['table']}"] += 1
        counts["applied"] += 1
    return counts, failures
