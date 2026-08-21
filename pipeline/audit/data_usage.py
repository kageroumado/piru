#!/usr/bin/env python3
"""What the database holds that the app never says.

Every column in the bundled DB is one of four things, and only the first two are
fine:

    shown     the app reads it AND it reaches a view
    read      the app reads it and drops it before rendering   <- silent loss
    unused    populated, and no Swift file mentions it at all   <- blind spot
    empty     nothing in it, so nothing is lost

The classification is a grep, deliberately. A column is `read` when its name
appears in Swift near a mention of its table (that is where the SQL lives), and
`shown` when the camelCased form also appears under a Views directory. Both are
heuristics that can only err toward *over*-reporting usage — a column the grep
cannot find is definitively not being used, which is the direction that matters
for a blind-spot report.

`--sources` runs the same question one layer up: which fields of the external
datasets in ~/Developer/piru-data does `extract.py` never read.

    python3 pipeline/audit/data_usage.py                 # report
    python3 pipeline/audit/data_usage.py --sources       # upstream blind spots
    python3 pipeline/audit/data_usage.py --write         # + save the snapshot
    python3 pipeline/audit/data_usage.py --gate          # exit 1 if a `shown` regressed
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru" / "Data" / "piru-substances.sqlite"
SNAPSHOT = REPO / "data" / "snapshots" / "data-usage.json"
GRAPH = REPO / "data" / "snapshots" / "data-usage-graph.md"
SURFACES = Path(__file__).resolve().parent / "data_surfaces.json"
PIRU_DATA = Path.home() / "Developer" / "piru-data"

SWIFT_ROOTS = ["Piru", "Shared", "PiruWidget", "PiruLiveActivityExtension", "PiruComplication"]
VIEW_MARKERS = ("/Views/", "/Components/")

#: The source-attribution ledger names tables as string literals so the "where
#: this comes from" screen can count them. Naming a table there proves a source
#: contributed rows; it proves nothing about whether a screen renders one. Read
#: it separately or every attribution-only table reads as queried.
ATTRIBUTION_FILE = "SubstanceStore+SourceContributions.swift"

#: Columns that are plumbing, not content. They are always "used" in the sense
#: that matters (joins, keys, dedup) and never rendered, so counting them as
#: silent losses would bury the real ones.
PLUMBING = {"id", "substance_id", "source_id", "vocab_id", "class_context_id"}

#: Short camelCase forms that collide with ordinary Swift vocabulary, so a
#: whole-corpus grep for them proves nothing. These fall back to SQL-proximity
#: evidence only.
AMBIGUOUS = {
    "text",
    "name",
    "label",
    "notes",
    "note",
    "summary",
    "route",
    "routes",
    "tag",
    "action",
    "target",
    "species",
    "gene",
    "effect",
    "slug",
    "language",
    "unit",
    "count",
    "value",
    "kind",
    "status",
    "level",
    "index",
    "url",
    "title",
}


def surfaces() -> dict:
    """Where each table's content is declared to belong on screen.

    Intent only: whether it is *there* is the grep's answer, never this file's.
    Keeping the two apart is what stops a table being built, shipped, and
    forgotten with a checkbox somewhere claiming otherwise.
    """
    return json.loads(SURFACES.read_text(encoding="utf-8")) if SURFACES.exists() else {}


def swift_corpus() -> tuple[str, str, str, list[str]]:
    """(all Swift, Views-only, attribution-ledger, per-view-file bodies).

    The per-file list matters for column names that collide with ordinary
    SwiftUI vocabulary — `target`, `action`, `species`. A bare corpus-wide hit on
    those proves nothing, but a hit inside a view that *also* names the table's
    own subject is evidence the value is on screen.
    """
    every: list[str] = []
    views: list[str] = []
    ledger: list[str] = []
    view_files: list[str] = []
    for root in SWIFT_ROOTS:
        base = REPO / root
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            posix = path.as_posix()
            if "Tests" in posix or posix.endswith("Tests.swift"):
                continue
            body = path.read_text(encoding="utf-8", errors="replace")
            if path.name == ATTRIBUTION_FILE:
                ledger.append(body)
                continue
            every.append(body)
            if any(marker in posix for marker in VIEW_MARKERS):
                views.append(body)
                view_files.append(body)
    return "\n".join(every), "\n".join(views), "\n".join(ledger), view_files


def camel(column: str) -> str:
    head, *rest = column.split("_")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def neighborhoods(corpus: str, table: str, radius: int = 900) -> str:
    """The slices of Swift that mention `table` — where its SQL lives."""
    out = []
    for match in re.finditer(rf"\b{re.escape(table)}\b", corpus):
        out.append(corpus[max(0, match.start() - radius) : match.end() + radius])
    return "\n".join(out)


def word_in(needle: str, haystack: str) -> bool:
    return re.search(rf"\b{re.escape(needle)}\b", haystack) is not None


def column_stats(db: sqlite3.Connection, table: str) -> tuple[int, dict[str, int]]:
    rows = db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
    filled: dict[str, int] = {}
    cols = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")')]
    if rows:
        selects = ", ".join(f'SUM("{c}" IS NOT NULL)' for c in cols)
        counts = db.execute(f'SELECT {selects} FROM "{table}"').fetchone()
        for col, n in zip(cols, counts, strict=True):
            filled[col] = n or 0
    else:
        filled = dict.fromkeys(cols, 0)
    return rows, filled


def table_subject(table: str) -> str:
    """A word a view rendering this table is likely to name — the singular of
    the table, or its last path segment (`drug_interactions_pk` -> `interaction`)."""
    word = table.rstrip("_pk").split("_")[-1] if "_" in table else table
    return word[:-1] if word.endswith("s") else word


def classify(
    table: str,
    column: str,
    filled: int,
    corpus: str,
    views: str,
    near: str,
    view_files: list[str] | None = None,
) -> str:
    if filled == 0:
        return "empty"
    ident = camel(column)
    sql_hit = word_in(column, near)
    strong = ident not in AMBIGUOUS and len(ident) >= 5
    view_hit = strong and word_in(ident, views)
    if not view_hit and view_files:
        # Ambiguous name: require a view that names both the value and the
        # table's own subject, so `target` in a receptor card counts and
        # `target` in a layout modifier does not.
        subject = table_subject(table)
        view_hit = any(
            word_in(ident, body) and re.search(subject, body, re.IGNORECASE) for body in view_files
        )
    swift_hit = strong and word_in(ident, corpus)
    if view_hit or (sql_hit and strong and swift_hit):
        return "shown" if view_hit else "read"
    if sql_hit:
        return "read"
    if swift_hit:
        return "shown" if view_hit else "read"
    return "unused"


def audit_db() -> dict:
    if not DB.exists():
        sys.exit(f"no database at {DB} — run pipeline/fetch-db.sh")
    corpus, views, ledger, view_files = swift_corpus()
    declared = surfaces()
    renders_as = declared.get("renders_as", {})
    db = sqlite3.connect(DB)
    tables = [
        r[0]
        for r in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    report: dict[str, dict] = {}
    for table in tables:
        rows, filled = column_stats(db, table)
        near = neighborhoods(corpus, table)
        table_read = bool(
            re.search(rf"(FROM|JOIN|INTO|UPDATE)\s+{re.escape(table)}\b", corpus)
            # Some reads go through a helper that takes the table as a literal
            # (`resolvedTextRow(from: "descriptions", …)`), so the SQL keyword
            # never appears next to the name.
            or re.search(rf'"{re.escape(table)}"', corpus)
        )
        attributed = bool(re.search(rf'"{re.escape(table)}"', ledger))
        cols = {}
        for column, n in filled.items():
            if column in PLUMBING:
                verdict = "plumbing"
            else:
                verdict = classify(table, column, n, corpus, views, near, view_files)
                # A value that reaches a view under a different Swift name (a
                # struct property built inside the query) is shown; the grep
                # cannot see that on its own.
                alias = renders_as.get(f"{table}.{column}")
                if alias and verdict in {"read", "unused"}:
                    root = alias.split(".")[0].split(",")[0].strip()
                    if word_in(root, views) or "never displayed" in alias:
                        verdict = "shown"
                # A column cannot outrank its table: if no Swift SQL reads the
                # table at all, nothing in it reaches a screen through that path.
                if (
                    not table_read
                    and verdict in {"read", "shown"}
                    and not word_in(camel(column), views)
                ):
                    verdict = "unused"
            cols[column] = {"filled": n, "verdict": verdict}
        report[table] = {
            "rows": rows,
            "read_in_swift": table_read,
            "attributed_only": attributed and not table_read,
            "surface": (declared.get("tables", {}).get(table) or {}).get("surface"),
            "columns": cols,
        }
    return report


def rollup(report: dict) -> Counter:
    tally: Counter = Counter()
    for spec in report.values():
        for col in spec["columns"].values():
            tally[col["verdict"]] += 1
    return tally


def print_db_report(report: dict) -> None:
    dead = [t for t, s in report.items() if s["rows"] and not s["read_in_swift"]]
    print("=" * 78)
    print("TABLES POPULATED BUT NEVER READ BY THE APP")
    print("=" * 78)
    if not dead:
        print("  (none)")
    for table in sorted(dead, key=lambda t: -report[t]["rows"]):
        tag = "  (attribution ledger only)" if report[table]["attributed_only"] else ""
        print(f"  {report[table]['rows']:>7}  {table}{tag}")

    print()
    print("=" * 78)
    print("COLUMNS FILLED BUT NOT REACHING ANY VIEW")
    print("=" * 78)
    print(f"  {'rows':>7}  {'table.column':<46} {'filled':>7}  verdict")
    for table in sorted(report):
        spec = report[table]
        for column, col in spec["columns"].items():
            if col["verdict"] in {"unused", "read"}:
                print(
                    f"  {spec['rows']:>7}  {table + '.' + column:<46} "
                    f"{col['filled']:>7}  {col['verdict']}"
                )

    tally = rollup(report)
    print()
    print("=" * 78)
    total = sum(tally.values())
    print(
        f"  {total} columns:  shown {tally['shown']}  ·  read-then-dropped {tally['read']}  ·  "
        f"unused {tally['unused']}  ·  empty {tally['empty']}  ·  plumbing {tally['plumbing']}"
    )
    print("=" * 78)


# ---------------------------------------------------------------------------
# Upstream: which fields of the external datasets does extract.py never read?
# ---------------------------------------------------------------------------

EXTRACTOR = REPO / "pipeline" / "fetch" / "brushers" / "extract.py"

_LABEL_HEADER = re.compile(r"<text class='druglabel_header'>(.*?)</text>", re.S)


def _label_headers(section) -> list[str]:
    """The `<druglabel_header>` labels inside one MedTAP label section."""
    found: list[str] = []

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("text"), str):
                match = _LABEL_HEADER.search(node["text"])
                if match:
                    found.append(match.group(1).strip())
            else:
                for value in node.values():
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(section.get("content"))
    walk(section.get("content_full"))
    return found


def _code_only(text: str) -> str:
    """`text` with comments and docstrings removed.

    The extractor's own comments name the fields it deliberately drops
    ("absorption, protein binding, clearance and half-life"), so matching
    against raw source reports the discarded fields as read.
    """
    text = re.sub(r'("""|\'\'\')(?:.|\n)*?\1', "", text)
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def leaf_paths(node, prefix: str = "", depth: int = 0, out: Counter | None = None) -> Counter:
    out = Counter() if out is None else out
    if depth > 4:
        return out
    if isinstance(node, dict):
        for key, value in node.items():
            path = f"{prefix}.{key}" if prefix else key
            out[path] += 1
            leaf_paths(value, path, depth + 1, out)
    elif isinstance(node, list):
        for item in node[:40]:
            leaf_paths(item, prefix + "[]", depth + 1, out)
    return out


def audit_sources() -> None:
    source = _code_only(EXTRACTOR.read_text(encoding="utf-8")) if EXTRACTOR.exists() else ""
    datasets: dict[str, Counter] = {}

    pyrls = PIRU_DATA / "pyrls[N=378].json"
    if pyrls.exists():
        tally: Counter = Counter()
        for record in json.loads(pyrls.read_text()):
            leaf_paths(record, out=tally)
        datasets["pyrls"] = tally

    medtap = PIRU_DATA / "Medtap-App-Pharma-DB.json"
    if medtap.exists():
        tally = Counter()
        for record in json.loads(medtap.read_text()):
            leaf_paths({k: v for k, v in record.items() if k != "sections"}, out=tally)
            for section in record.get("sections") or []:
                name = section.get("section_name")
                tally[f"sections:{name}"] += 1
                # The Pharmacology section is a header/value table, not prose:
                # the extractor reads one of its headers and drops the rest, so
                # the section alone reading as "used" would hide the real gap.
                if name == "Pharmacology":
                    for header in _label_headers(section):
                        tally[f"sections:Pharmacology/{header}"] += 1
        datasets["medtap"] = tally

    drugbank = PIRU_DATA / "drugbank-extract.json"
    if drugbank.exists():
        tally = Counter()
        for record in json.loads(drugbank.read_text())["drugs"]:
            for key, value in record.items():
                if value not in (None, "", [], {}):
                    tally[key] += 1
        datasets["drugbank (verification-only; see the licence gate)"] = tally

    nps = PIRU_DATA / "nps-datahub.com-full-database[N=6405].csv"
    if nps.exists():
        csv.field_size_limit(10**9)
        tally = Counter()
        with nps.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                for key, value in row.items():
                    if key and value and value.strip():
                        tally[key] += 1
        datasets["nps-datahub"] = tally

    if not datasets:
        sys.exit(f"no datasets found under {PIRU_DATA}")

    for name, tally in datasets.items():
        print("=" * 78)
        print(f"{name.upper()} — fields the extractor never reads")
        print("=" * 78)
        misses = []
        for path, n in tally.most_common():
            leaf = re.split(r"[.:/]", path)[-1].replace("[]", "")
            if len(leaf) < 3 or leaf[0] in "$_":
                continue
            # Word-boundary both ways: a substring test lets `dosage_form` in
            # the extractor mask the unread `Dosage` section.
            if word_in(leaf, source) or word_in(leaf.lower(), source.lower()):
                continue
            misses.append((n, path))
        if not misses:
            print("  (every field is read)")
        for n, path in misses[:40]:
            print(f"  {n:>7}  {path}")
        print(f"  ... {len(misses)} unread field paths total")
        print()


# ---------------------------------------------------------------------------
# The graph: source -> table -> surface, coloured by whether it arrives
# ---------------------------------------------------------------------------


#: Which source populates which table, read from the DB itself so it cannot
#: drift. Tables with no `source_id` column are attributed to the build.
def _source_edges(db: sqlite3.Connection, table: str) -> list[str]:
    cols = {r[1] for r in db.execute(f'PRAGMA table_info("{table}")')}
    if "source_id" not in cols:
        return []
    return [
        r[0]
        for r in db.execute(
            f'SELECT DISTINCT src.slug FROM "{table}" t '
            f"JOIN sources src ON src.id = t.source_id ORDER BY 1"
        )
    ]


def _mermaid_id(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "_", name)


def write_graph(report: dict) -> str:
    """A Mermaid graph of every populated table: who fills it, where it is
    declared to belong on screen, and whether it gets there.

    Generated, never hand-drawn — a hand-drawn one is wrong the first time a
    table changes state, which is the failure this whole tool exists to prevent.
    """
    db = sqlite3.connect(DB)
    declared = surfaces().get("tables", {})
    lines = [
        "# Where the data goes",
        "",
        "*Generated by `pipeline/audit/data_usage.py --graph`. Do not edit.*",
        "",
        "Each populated table, the sources that fill it, and the screen it is",
        "declared to belong on. **Red** means nothing renders it. **Amber** means",
        "the app reads it and drops part of it before rendering.",
        "",
        "```mermaid",
        "graph LR",
    ]
    used_sources: set[str] = set()
    surface_nodes: set[str] = set()
    edges: list[str] = []
    nodes: list[str] = []
    classes = {"dead": [], "partial": [], "live": []}

    for table in sorted(report, key=lambda t: -report[t]["rows"]):
        spec = report[table]
        if not spec["rows"]:
            continue
        surface = (declared.get(table) or {}).get("surface")
        if surface is None and table in declared:
            continue  # deliberately not user-facing
        verdicts = [c["verdict"] for c in spec["columns"].values()]
        if not spec["read_in_swift"]:
            state = "dead"
        elif "read" in verdicts or "unused" in verdicts:
            state = "partial"
        else:
            state = "live"
        tid = _mermaid_id(table)
        nodes.append(f'    {tid}["{table}<br/>{spec["rows"]:,} rows"]')
        classes[state].append(tid)
        for slug in _source_edges(db, table):
            used_sources.add(slug)
            edges.append(f"    {_mermaid_id('src_' + slug)} --> {tid}")
        if surface:
            surface_nodes.add(surface)
            edges.append(f"    {tid} --> {_mermaid_id('ui_' + surface)}")

    lines.append("    subgraph sources[Sources]")
    for slug in sorted(used_sources):
        lines.append(f'    {_mermaid_id("src_" + slug)}("{slug}")')
    lines.append("    end")
    lines.extend(nodes)
    lines.append("    subgraph screen[On screen]")
    for surface in sorted(surface_nodes):
        lines.append(f'    {_mermaid_id("ui_" + surface)}(["{surface}"])')
    lines.append("    end")
    lines.extend(edges)
    lines.append("    classDef dead fill:#5b1a1a,stroke:#d06666,color:#fff;")
    lines.append("    classDef partial fill:#5b451a,stroke:#d0a566,color:#fff;")
    lines.append("    classDef live fill:#1a3d2b,stroke:#5fbf8f,color:#fff;")
    for state, members in classes.items():
        if members:
            lines.append(f"    class {','.join(members)} {state};")
    lines.append("```")
    lines.append("")

    lines.append("## Declared a home, not yet rendered")
    lines.append("")
    lines.append("| rows | table | belongs on | why it matters |")
    lines.append("|---:|---|---|---|")
    for table in sorted(report, key=lambda t: -report[t]["rows"]):
        spec, entry = report[table], declared.get(table) or {}
        if spec["rows"] and not spec["read_in_swift"] and entry.get("surface"):
            note = (entry.get("note") or "").replace("UNRENDERED — ", "").replace("UNREAD — ", "")
            lines.append(f"| {spec['rows']:,} | `{table}` | {entry['surface']} | {note} |")
    lines.append("")

    unmapped = [t for t, s in report.items() if s["rows"] and t not in declared]
    if unmapped:
        lines.append("## Not in the surface map")
        lines.append("")
        lines.append("Add each to `pipeline/audit/data_surfaces.json` — a home, or `null`.")
        lines.append("")
        for table in sorted(unmapped):
            lines.append(f"- `{table}`")
        lines.append("")

    GRAPH.parent.mkdir(parents=True, exist_ok=True)
    GRAPH.write_text("\n".join(lines))
    return str(GRAPH.relative_to(REPO))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sources", action="store_true", help="audit the upstream datasets instead"
    )
    parser.add_argument(
        "--graph", action="store_true", help="write the source->table->screen graph"
    )
    parser.add_argument("--write", action="store_true", help="save the snapshot")
    parser.add_argument(
        "--gate", action="store_true", help="exit 1 if a previously shown column regressed"
    )
    args = parser.parse_args()

    if args.sources:
        audit_sources()
        return 0

    report = audit_db()
    if args.graph:
        print(f"wrote {write_graph(report)}")
        return 0
    print_db_report(report)

    if args.gate and SNAPSHOT.exists():
        before = json.loads(SNAPSHOT.read_text())
        lost = [
            f"{t}.{c}"
            for t, spec in before.items()
            for c, col in spec["columns"].items()
            if col["verdict"] == "shown"
            and report.get(t, {}).get("columns", {}).get(c, {}).get("verdict") != "shown"
        ]
        if lost:
            print("\nREGRESSED — these columns no longer reach a view:")
            for name in lost:
                print(f"  {name}")
            return 1

    if args.write:
        SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
        SNAPSHOT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(f"\nwrote {SNAPSHOT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
