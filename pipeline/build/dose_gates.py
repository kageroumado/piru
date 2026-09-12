"""Build-time gates over the dose and duration rows every source contributed.

The source order decides which claim shows when sources disagree. It cannot
catch a claim that is wrong on its own terms — a fentanyl-analog ladder written
in milligrams, a come-up of five seconds on a swallowed pill — because nothing
outranks a row nobody else has. These gates are the deterministic checks that
run over the finished ingest, before dedup, and delete what fails them. Each
deletion is written to ``data/snapshots/dose-gate-report.md`` with the rule and
the values, so the source can be told and the rule can be argued with.

Two kinds of rule:

* **Class ceilings** (``data/curated/dose-class-gates.json``) — for a class
  context whose members are dosed in micrograms, any ladder tier above a stated
  mass is not a dose but a unit slip or a copied error, and it goes unless the
  row carries a citation or comes from an exempt source.
* **Absorption floors** — a phase of under one minute on a route that has to
  absorb through a membrane (oral, sublingual, rectal, transdermal, buccal,
  insufflation) is a units error, whatever the source. Inhaled and injected
  routes are exempt: a smoked or IV come-up of seconds is real.

Nothing here reads a second source: a gate is a fact about the row itself.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GATES_PATH = REPO / "data/curated/dose-class-gates.json"
REPORT_PATH = REPO / "data/snapshots/dose-gate-report.md"

#: Routes whose onset physically cannot complete inside a minute.
ABSORBED_ROUTES = ("oral", "sublingual", "buccal", "rectal", "transdermal", "insufflation")
ABSORPTION_FLOOR_MINUTES = 1.0

#: Mass units the ceilings are compared in, as multiples of one milligram.
_MG_PER_UNIT = {"mg": 1.0, "µg": 0.001, "ug": 0.001, "mcg": 0.001, "g": 1000.0}

TIERS = (
    "threshold",
    "light_lower",
    "light_upper",
    "common_lower",
    "common_upper",
    "strong_lower",
    "strong_upper",
    "heavy",
)


@dataclass
class GateHit:
    rule: str
    substance: str
    source: str
    route: str
    detail: str


@dataclass
class GateResult:
    hits: list[GateHit] = field(default_factory=list)

    def by_rule(self) -> dict[str, list[GateHit]]:
        out: dict[str, list[GateHit]] = {}
        for hit in self.hits:
            out.setdefault(hit.rule, []).append(hit)
        return out


def load_gates(path: Path = GATES_PATH) -> list[dict]:
    if not path.exists():
        return []
    return [g for g in json.loads(path.read_text()).get("gates") or [] if g.get("class_context")]


def mg_factor(unit: str | None) -> float | None:
    """Milligrams per one of `unit`, or None for a unit that is not a plain mass
    (µg/kg, mL, units) — those are outside what a ceiling can judge."""
    head = (unit or "").strip().split()[0].lower() if unit else ""
    return _MG_PER_UNIT.get(head)


def apply_class_ceilings(cur: sqlite3.Cursor, gates: list[dict], result: GateResult) -> int:
    deleted = 0
    for gate in gates:
        ceiling = float(gate["max_tier_mg"])
        exempt = tuple(gate.get("exempt_sources") or ())
        rows = cur.execute(
            f"""
            SELECT d.id, su.canonical_name, src.slug, d.route, d.unit, d.citation_id,
                   {", ".join("d." + t for t in TIERS)}
              FROM dose_ranges d
              JOIN substances su ON su.id = d.substance_id
              JOIN sources src ON src.id = d.source_id
              JOIN substance_classes sc ON sc.substance_id = su.id
              JOIN class_contexts cc ON cc.id = sc.class_context_id
             WHERE cc.slug = ?
            """,
            (gate["class_context"],),
        ).fetchall()
        for row in rows:
            row_id, name, slug, route, unit, citation_id, *tiers = row
            if slug in exempt or citation_id is not None:
                continue
            factor = mg_factor(unit)
            if factor is None:
                continue
            offending = [
                (tier, value)
                for tier, value in zip(TIERS, tiers, strict=True)
                if value is not None and value * factor > ceiling
            ]
            if not offending:
                continue
            cur.execute("DELETE FROM dose_ranges WHERE id = ?", (row_id,))
            deleted += 1
            worst = max(offending, key=lambda pair: pair[1])
            result.hits.append(
                GateHit(
                    rule=f"class ceiling · {gate['class_context']} ≤ {ceiling:g} mg",
                    substance=name,
                    source=slug,
                    route=route,
                    detail=(
                        f"{worst[0]} {worst[1]:g} {unit} — {len(offending)} tier(s) above the "
                        f"ceiling; {gate.get('reason', '')}".rstrip("; ")
                    ),
                )
            )
    return deleted


def apply_absorption_floor(cur: sqlite3.Cursor, result: GateResult) -> int:
    placeholders = ", ".join("?" * len(ABSORBED_ROUTES))
    rows = cur.execute(
        f"""
        SELECT d.id, su.canonical_name, src.slug, d.route, d.phase, d.min_minutes, d.max_minutes
          FROM durations d
          JOIN substances su ON su.id = d.substance_id
          JOIN sources src ON src.id = d.source_id
         WHERE d.route IN ({placeholders})
           AND d.phase IN ('onset', 'comeup', 'peak', 'offset', 'afterglow', 'total')
           AND d.max_minutes < ?
        """,
        (*ABSORBED_ROUTES, ABSORPTION_FLOOR_MINUTES),
    ).fetchall()
    for row_id, name, slug, route, phase, low, high in rows:
        cur.execute("DELETE FROM durations WHERE id = ?", (row_id,))
        result.hits.append(
            GateHit(
                rule="absorption floor · phase under 1 min on an absorbed route",
                substance=name,
                source=slug,
                route=route,
                detail=f"{phase} {low:g}–{high:g} min",
            )
        )
    return len(rows)


def run(cur: sqlite3.Cursor, *, gates_path: Path = GATES_PATH) -> GateResult:
    result = GateResult()
    apply_class_ceilings(cur, load_gates(gates_path), result)
    apply_absorption_floor(cur, result)
    return result


def write_report(result: GateResult, path: Path = REPORT_PATH) -> None:
    lines = [
        "# Dose gate report",
        "",
        "Rows the build deleted because they fail a rule about themselves — a class "
        "ceiling from `data/curated/dose-class-gates.json`, or a phase too short for "
        "its route. Each is a row to report upstream; each rule is in "
        "`pipeline/build/dose_gates.py`.",
        "",
        f"{len(result.hits)} row(s) deleted.",
        "",
    ]
    for rule, hits in sorted(result.by_rule().items()):
        lines += [f"## {rule}", "", "| substance | source | route | detail |", "|---|---|---|---|"]
        for hit in sorted(hits, key=lambda h: (h.substance, h.source, h.route)):
            lines.append(f"| {hit.substance} | {hit.source} | {hit.route} | {hit.detail} |")
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines))
    # The same rows as data, for `audit/upstream_report.py` to list per source.
    path.with_suffix(".json").write_text(
        json.dumps([hit.__dict__ for hit in result.hits], indent=2, ensure_ascii=False) + "\n"
    )
