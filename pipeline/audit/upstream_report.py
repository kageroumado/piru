#!/usr/bin/env python3
"""Write the defect report one upstream source can act on.

Piru ingests dose.wiki and drug.community, and both are maintained by people
Kiri talks to. This turns what the build and the adjudicator know about a
source into one Markdown file per source: every row that is wrong on its own
terms, every value the independent sources contradict, every row Piru refuses
to ship and why, and the questions only the source can answer.

    python3 pipeline/audit/upstream_report.py dosewiki
    python3 pipeline/audit/upstream_report.py drug.community
    python3 pipeline/audit/upstream_report.py dosewiki --preamble notes.md --out report.md

Reads: the source snapshot in `data/sources/`, `data/adjudication/cells.jsonl`
(run `pipeline/audit/adjudicate.py` first — the report refuses to run on a
stale or missing one older than the built DB), `data/curated/dose-source-
exceptions.json`, and `data/snapshots/dose-gate-report.json`. Writes to
`Specs/evidence/upstream-reports/<source>-<date>.md` unless `--out` says
otherwise. Offline and deterministic.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CELLS = REPO / "data/adjudication/cells.jsonl"
DB = REPO / "Piru/Data/piru-substances.sqlite"
EXCEPTIONS = REPO / "data/curated/dose-source-exceptions.json"
GATE_JSON = REPO / "data/snapshots/dose-gate-report.json"
OUT_DIR = REPO / "Specs/evidence/upstream-reports"

SOURCES = {
    "dosewiki": {
        "title": "dose.wiki",
        "snapshot": REPO / "data/sources/dosewiki.json",
        "cell_sources": ("dosewiki", "dosewiki-api"),
    },
    "drug.community": {
        "title": "drug.community",
        "snapshot": REPO / "data/sources/drug-community.json",
        "cell_sources": ("drug.community",),
    },
}

TIER_ORDER = ("threshold", "light", "moderate", "common", "strong", "heavy")


def fmt(value: float | None) -> str:
    if value is None:
        return "—"
    if abs(value) >= 100:
        return f"{value:,.0f}"
    return f"{value:g}"


# ------------------------------------------------------------- dose.wiki checks


def inchikey_of(smiles: str) -> str | None:
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem.inchi import MolToInchiKey
    except ImportError:
        return None
    RDLogger.DisableLog("rdApp.*")
    mol = Chem.MolFromSmiles(smiles)
    return MolToInchiKey(mol) if mol else None


def rdkit_formula(smiles: str) -> tuple[str | None, float | None]:
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import Descriptors, rdMolDescriptors
    except ImportError:
        return None, None
    RDLogger.DisableLog("rdApp.*")
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None, None
    return rdMolDescriptors.CalcMolFormula(mol), Descriptors.MolWt(mol)


def dosewiki_internal(records: list[dict]) -> dict[str, list[str]]:
    """Defects visible in a dose.wiki record alone."""
    findings: dict[str, list[str]] = defaultdict(list)
    structures: dict[str, list[str]] = defaultdict(list)
    for rec in records:
        slug = rec["slug"]
        reviewed = "reviewed" if rec.get("expert_reviewed") else "unreviewed"
        ident = rec.get("identification") or {}
        smiles = (ident.get("smiles") or "").strip()
        formula = (ident.get("molecular_formula") or "").strip()
        weight = (ident.get("molecular_weight") or "").split()
        if smiles:
            computed, mw = rdkit_formula(smiles)
            if computed:
                structures[inchikey_of(smiles) or computed].append(slug)
            if computed and formula and formula != computed:
                kind = "truncated" if computed.startswith(formula) else "different"
                findings["formula"].append(
                    f"| `{slug}` | {reviewed} | `{formula}` | `{computed}` | {kind} |"
                )
            if computed and not formula:
                findings["formula"].append(
                    f"| `{slug}` | {reviewed} | *(empty)* | `{computed}` | missing |"
                )
            if mw and weight:
                try:
                    stated = float(weight[0])
                    if abs(stated - mw) > 1.0:
                        findings["weight"].append(
                            f"| `{slug}` | {reviewed} | {stated:g} | {mw:.2f} |"
                        )
                except ValueError:
                    pass
        elif ident:
            findings["no_structure"].append(f"`{slug}`")

        for route in (rec.get("dosage") or {}).get("routes") or []:
            bands = route.get("dose_ranges") or {}
            units = {(b or {}).get("unit") for b in bands.values() if isinstance(b, dict)}
            units.discard(None)
            units.discard("")
            if len(units) > 1:
                findings["mixed_units"].append(
                    f"| `{slug}` | {reviewed} | {route.get('route')} | {', '.join(sorted(units))} |"
                )
            if any(
                isinstance(b, dict) and (b.get("min") is not None) and not b.get("unit")
                for b in bands.values()
            ):
                findings["missing_unit"].append(f"| `{slug}` | {reviewed} | {route.get('route')} |")
            sequence: list[tuple[str, float]] = []
            for tier in TIER_ORDER:
                band = bands.get(tier)
                if not isinstance(band, dict):
                    continue
                for edge in ("min", "max"):
                    value = band.get(edge)
                    if isinstance(value, (int, float)):
                        sequence.append((f"{tier}.{edge}", float(value)))
            for (name_a, a), (name_b, b) in zip(sequence, sequence[1:], strict=False):
                if b < a:
                    findings["ladder"].append(
                        f"| `{slug}` | {reviewed} | {route.get('route')} | {name_a} {a:g} > {name_b} {b:g} |"
                    )
                    break

        for route in (rec.get("duration") or {}).get("routes") or []:
            stages = route.get("stages") or {}
            for stage, value in stages.items():
                if isinstance(value, dict):
                    lo, hi = value.get("min"), value.get("max")
                    if isinstance(lo, (int, float)) and isinstance(hi, (int, float)) and lo > hi:
                        findings["stage_inverted"].append(
                            f"| `{slug}` | {reviewed} | {route.get('route')} | {stage} {lo:g}–{hi:g} {value.get('unit') or ''} |"
                        )

        seen_targets: Counter[str] = Counter()
        for row in (rec.get("pharmacology") or {}).get("binding_sites") or []:
            target = row.get("target") or ""
            if "[cite:" in target or "[citation" in target:
                findings["target_marker"].append(f"| `{slug}` | `{target}` |")
            seen_targets[re.sub(r"\[.*?\]", "", target).strip().lower()] += 1
            tag = (row.get("tag") or "").lower()
            eff = (row.get("efficacy") or "").lower()
            # An inverse agonist blocks the receptor in practice, so an antagonist
            # tag over an inverse-agonist efficacy is a refinement; agonist over
            # antagonist is a contradiction.
            if tag and eff and "inverse agonist" not in eff:
                pairs = (("agonist", "antagonist"), ("antagonist", "agonist"))
                for a, b in pairs:
                    if (
                        re.search(rf"\b{a}\b", tag)
                        and not re.search(rf"\b(partial )?{a}\b", eff)
                        and re.search(rf"\b{b}\b", eff)
                    ):
                        findings["tag_vs_efficacy"].append(
                            f"| `{slug}` | {row.get('target')} | tag `{row.get('tag')}` | efficacy `{row.get('efficacy')}` |"
                        )
        for target, n in sorted(seen_targets.items()):
            if n > 1 and target:
                findings["duplicate_target"].append(f"| `{slug}` | {target} | {n} rows |")

    for key, slugs in structures.items():
        if len(slugs) > 1:
            findings["shared_structure"].append(
                f"| `{key.split('|')[0]}` | {', '.join(f'`{s}`' for s in sorted(slugs))} |"
            )
    return findings


# --------------------------------------------------------- drug.community checks


def parse_dc(text: str | None) -> tuple[float, float] | None:
    """The build's own reading of a drug.community dose string, so a row is
    "unparseable" here exactly when the build drops it."""
    sys.path.insert(0, str(REPO / "pipeline/build"))
    import sqlite as build  # noqa: PLC0415 — the build module, loaded on first use

    if not text or not isinstance(text, str):
        return None
    got = build.Build._parse_dc_range(text)
    if got:
        return float(got["lower"]), float(
            got["upper"] if got.get("upper") is not None else got["lower"]
        )
    scalar = build.Build._parse_dc_scalar(text)
    return (float(scalar), float(scalar)) if scalar is not None else None


def dc_internal(records: list[dict]) -> dict[str, list[str]]:
    findings: dict[str, list[str]] = defaultdict(list)
    point_phase: Counter[str] = Counter()
    curves = 0
    for rec in records:
        name = rec.get("drug_name") or "?"
        for route in (rec.get("dosages") or {}).get("routes_of_administration") or []:
            ranges = route.get("dose_ranges") or {}
            parsed: list[tuple[str, float, float]] = []
            for tier in ("threshold", "light", "common", "strong", "heavy"):
                raw = ranges.get(tier)
                if raw is None:
                    continue
                got = parse_dc(raw)
                if got is None:
                    findings["unparseable_dose"].append(
                        f"| {name} | {route.get('route')} | {tier} | `{raw}` |"
                    )
                    continue
                parsed.append((tier, *got))
            for (ta, la, ha), (tb, lb, hb) in zip(parsed, parsed[1:], strict=False):
                if lb < la or hb < ha:
                    findings["ladder"].append(
                        f"| {name} | {route.get('route')} | {ta} {la:g}–{ha:g} then {tb} {lb:g}–{hb:g} |"
                    )
                    break
            if not ranges:
                findings["empty_ladder"].append(f"| {name} | {route.get('route')} |")
        for entry in rec.get("duration_curves") or []:
            curve = entry.get("duration_curve")
            if not isinstance(curve, dict):
                continue
            curves += 1
            method = entry.get("method") or "oral"
            unit = (curve.get("units") or "hours").lower()
            bounds: dict[str, tuple[float, float]] = {}
            for phase in ("onset", "peak", "offset", "after_effects"):
                window = curve.get(phase)
                if (
                    isinstance(window, dict)
                    and isinstance(window.get("start"), (int, float))
                    and isinstance(window.get("end"), (int, float))
                ):
                    bounds[phase] = (float(window["start"]), float(window["end"]))
                    if window["start"] == window["end"]:
                        point_phase[phase] += 1
                    if window["end"] < window["start"]:
                        findings["window_inverted"].append(
                            f"| {name} | {method} | {phase} {window['start']:g}–{window['end']:g} {unit} |"
                        )
            order = [p for p in ("onset", "peak", "offset", "after_effects") if p in bounds]
            for a, b in zip(order, order[1:], strict=False):
                if bounds[b][1] <= bounds[a][1]:
                    findings["window_order"].append(
                        f"| {name} | {method} | {b} ends at {bounds[b][1]:g} {unit}, before or with {a} ending at {bounds[a][1]:g} |"
                    )
                    break
            td = curve.get("total_duration")
            if (
                isinstance(td, dict)
                and isinstance(td.get("min"), (int, float))
                and isinstance(td.get("max"), (int, float))
            ):
                if td["max"] < td["min"]:
                    findings["window_inverted"].append(
                        f"| {name} | {method} | total {td['min']:g}–{td['max']:g} {unit} |"
                    )
                if "offset" in bounds and bounds["offset"][1] > td["max"] * 1.5:
                    findings["total_vs_offset"].append(
                        f"| {name} | {method} | offset ends at {bounds['offset'][1]:g} {unit}, total says {td['min']:g}–{td['max']:g} |"
                    )
            missing = [p for p in ("onset", "peak", "offset") if p not in bounds]
            if missing:
                findings["missing_phase"].append(f"| {name} | {method} | {', '.join(missing)} |")
    findings["_curves"] = [str(curves)]
    findings["_point_phase"] = [f"{k}: {v}" for k, v in point_phase.most_common()]
    return findings


# ------------------------------------------------------------- adjudicator rows


def load_cells() -> list[dict]:
    if not CELLS.exists():
        sys.exit(
            "data/adjudication/cells.jsonl is missing — run pipeline/audit/adjudicate.py first"
        )
    if DB.exists() and CELLS.stat().st_mtime < DB.stat().st_mtime:
        sys.exit(
            "data/adjudication/cells.jsonl is older than the built DB — re-run pipeline/audit/adjudicate.py"
        )
    return [json.loads(line) for line in CELLS.read_text().splitlines() if line.strip()]


def describe_key(key: str) -> str:
    parts = key.split("|")
    column = parts[0]
    if column == "dose":
        _, route, salt, isomer, context, basis, tier = parts
        return f"{route} {context} dose · {tier.replace('_', ' ')}"
    if column == "duration":
        _, route, salt, isomer, phase, edge = parts
        return f"{route} {phase} · {edge}"
    return key.replace("|", " · ")


def adjudicated_rows(cells: list[dict], sources: tuple[str, ...]) -> tuple[list[str], list[str]]:
    """(probable errors, unclear) as table rows for one source."""
    errors: list[tuple[float, str]] = []
    unclear: list[tuple[float, str]] = []
    for cell in cells:
        mine = [v for v in cell["values"] if v["source"] in sources]
        others = [v for v in cell["values"] if v["source"] not in sources]
        if not mine or not others:
            continue
        best = max(mine, key=lambda v: v["probability"])
        p = best["probability"]
        if p < 0.3:
            continue
        # A cell where every source repeats one value has nobody to contradict
        # it; a cell where a competing value scores at least as high is the
        # other source's row (a two-way tie is flagged on both sides and would
        # otherwise be reported to both maintainers as theirs).
        if cell.get("independent_clusters", 0) < 2:
            continue
        if any(other["probability"] >= p for other in others):
            continue
        unit = cell.get("unit") or ""
        competing = "; ".join(
            f"{v['source']} {fmt(v['value']) if isinstance(v['value'], (int, float)) else v['value']}"
            for v in sorted(others, key=lambda v: v["source"])
        )
        mine_text = (
            fmt(best["value"]) if isinstance(best["value"], (int, float)) else str(best["value"])
        )
        why = ", ".join(best.get("top_features") or [])
        row = (
            f"| {p:.2f} | {cell['substance']} | {describe_key(cell['key'])} | **{mine_text} {unit}** "
            f"| {competing} | {why} |"
        )
        (errors if p >= 0.5 else unclear).append((p, row))
    errors.sort(key=lambda t: -t[0])
    unclear.sort(key=lambda t: -t[0])
    return [r for _, r in errors], [r for _, r in unclear]


# ----------------------------------------------------------------- Piru blocks


def blocked_rows(slug: str) -> list[str]:
    rows: list[str] = []
    if EXCEPTIONS.exists():
        for entry in json.loads(EXCEPTIONS.read_text()).get(slug) or []:
            routes = ", ".join(entry.get("routes") or ["every route"])
            what = {"route": "route removed", "durations": "timeline removed"}.get(
                entry.get("drop"), "ladder removed"
            )
            rows.append(f"| {entry.get('name')} | {routes} | {what} | {entry.get('note', '')} |")
    if GATE_JSON.exists():
        for hit in json.loads(GATE_JSON.read_text()):
            if hit.get("source") == slug:
                rows.append(
                    f"| {hit['substance']} | {hit['route']} | gate: {hit['rule']} | {hit['detail']} |"
                )
    return rows


# ------------------------------------------------------------------------ main


def section(
    title: str, intro: str, header: str, rows: list[str], limit: int | None = None
) -> list[str]:
    if not rows:
        return []
    out = [f"### {title}", "", intro, "", header, "|" + "---|" * (header.count("|") - 1)]
    shown = rows if limit is None else rows[:limit]
    out += shown
    if limit is not None and len(rows) > limit:
        out.append("")
        out.append(
            f"*{len(rows) - limit} more rows omitted; the full set is in `data/adjudication/sources/`.*"
        )
    out.append("")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("source", choices=sorted(SOURCES))
    parser.add_argument("--preamble", type=Path, help="Markdown to place after the title")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--limit", type=int, default=400, help="cap on adjudicator rows per table")
    args = parser.parse_args(argv)
    spec = SOURCES[args.source]
    payload = json.loads(spec["snapshot"].read_text())
    records = payload.get("records") if isinstance(payload, dict) else payload
    fetched = payload.get("fetched_at", "") if isinstance(payload, dict) else ""
    cells = load_cells()
    today = date.today().isoformat()

    lines = [f"# {spec['title']} — data issues found by Piru's pipeline", ""]
    lines.append(
        f"*Generated {today} by `pipeline/audit/upstream_report.py` from the {spec['title']} "
        f"snapshot Piru ingests{f' (fetched {fetched})' if fetched else ''}, {len(records)} records. "
        "Sections A and C are facts about single rows; section B compares each value against every "
        "other source Piru carries (PsychonautWiki, TripSit, FreeOD Wiki, Erowid, dose.wiki, "
        "drug.community, Piru's curated layer and cited primary literature), with copies of one "
        "upstream counted as one vote. P is the adjudicator's probability that the value is the "
        "wrong one; it is a ranking, not a verdict.*",
    )
    lines.append("")
    if args.preamble:
        lines += [args.preamble.read_text().rstrip(), ""]

    lines += ["## A. Rows that contradict themselves", ""]
    if args.source == "dosewiki":
        f = dosewiki_internal(records)
        lines += section(
            "Molecular formula does not match the SMILES",
            "The formula field disagrees with the structure on the same page (formula recomputed with RDKit from `identification.smiles`). `truncated` means the string stops at the first letter of a two-letter element symbol.",
            "| slug | review | stated formula | from SMILES | kind |",
            f["formula"],
        )
        lines += section(
            "Molecular weight does not match the SMILES",
            "More than 1 g/mol from the structure's own average mass.",
            "| slug | review | stated | from SMILES |",
            f["weight"],
        )
        lines += section(
            "Pages sharing one structure",
            "Two slugs, one molecule (same InChIKey). Either a duplicate page or a wrong structure on one of them: `2-mmc` carries plain methcathinone's.",
            "| InChIKey | slugs |",
            f["shared_structure"],
        )
        lines += section(
            "Dose tiers that overlap or go backwards",
            "A lower tier's edge is above a higher tier's, so the bands overlap and 'heavy' can read as less than 'strong'; `butyrfentanyl` mixes mg and µg inside one ladder.",
            "| slug | review | route | where |",
            f["ladder"],
        )
        lines += section(
            "Ladders mixing units",
            "Tiers of one route in two units; the numbers cannot be compared inside the ladder.",
            "| slug | review | route | units |",
            f["mixed_units"],
        )
        lines += section(
            "Bands with a value and no unit", "", "| slug | review | route |", f["missing_unit"]
        )
        lines += section(
            "Duration stages with min above max",
            "",
            "| slug | review | route | stage |",
            f["stage_inverted"],
        )
        lines += section(
            "Binding rows with a citation marker inside the target name",
            "The `[cite:…]` leaked into `target`, so a reader keying on the target sees a phantom receptor.",
            "| slug | target |",
            f["target_marker"],
        )
        lines += section(
            "Binding rows whose tag and efficacy disagree",
            "The tag says one action and the efficacy text the opposite.",
            "| slug | target | tag | efficacy |",
            f["tag_vs_efficacy"],
        )
        lines += section(
            "Duplicate substance × target binding rows",
            "",
            "| slug | target | rows |",
            f["duplicate_target"],
        )
        if f["no_structure"]:
            lines += [
                "### Pages with identification but no SMILES",
                "",
                ", ".join(f["no_structure"]),
                "",
            ]
    else:
        f = dc_internal(records)
        lines += [
            "### Timelines are single boundaries, so every derived phase is a point",
            "",
            f"Across {f['_curves'][0]} duration curves each phase is an absolute window with one `start` and one "
            "`end`. Piru turns those into phase lengths (come-up = peak.start − onset.end, and so on), and "
            "a length made from two single numbers is a single number: 2,555 of the 3,988 duration rows "
            "Piru derives from drug.community have min == max, against 1 of 1,637 from PsychonautWiki. "
            "Where a phase is genuinely uncertain (IV heroin peaks somewhere in 30–60 min after a come-up "
            "of seconds to minutes), the schema cannot say so. The `iso_start`/`iso_end` arrays suggest "
            "the format could carry two values per boundary; if it did, Piru would read them as a range.",
            "",
        ]
        lines += section(
            "Windows that end before or with the previous phase",
            "Read as absolute times from ingestion (the way IV heroin's curve reads: onset 0–0.5 min, peak 30–60, offset 120–240, after-effects 240–720), an offset that ends before the peak ends, or after-effects that end with the offset, is a contradiction — and these look like windows written as per-phase *lengths* instead. Piru reads every curve as absolute, so each of these phases collapses to zero and is dropped. Which semantic is intended, per curve or per dataset, is the question this list is asking.",
            "| substance | route | where |",
            f["window_order"],
        )
        lines += section(
            "Offset runs well past the stated total",
            "",
            "| substance | route | where |",
            f["total_vs_offset"],
        )
        lines += section(
            "Windows with end before start",
            "",
            "| substance | route | where |",
            f["window_inverted"],
        )
        lines += section(
            "Curves missing a phase", "", "| substance | route | missing |", f["missing_phase"]
        )
        lines += section(
            "Dose ladders that go backwards", "", "| substance | route | where |", f["ladder"]
        )
        lines += section(
            "Dose strings Piru cannot parse",
            "Anything the build's parser cannot read as a number. Placeholders (`—`, `not recommended`) are deliberate and harmless — the build skips the tier — so this list exists to catch the ones that were meant to be numbers, like a comparison operator or a thin-space thousands separator.",
            "| substance | route | tier | text |",
            f["unparseable_dose"],
        )
        lines += section(
            "Routes with an empty ladder", "", "| substance | route |", f["empty_ladder"]
        )

    errors, unclear = adjudicated_rows(cells, spec["cell_sources"])
    lines += ["## B. Values the other sources contradict", ""]
    lines += section(
        "Probable errors (P ≥ 0.5)",
        "Your value against everything else Piru holds for the same quantity. `slip_10x` means the ratio to the consensus is almost exactly 10 (a decimal or unit slip); `sole_dissenter` means every independent source agrees against this value; `route_order_violation` means the ladder needs more drug by a more direct route.",
        "| P | substance | quantity | this source | others | why |",
        errors,
        args.limit,
    )
    lines += section(
        "Unclear (0.3 ≤ P < 0.5)",
        "Disagreements the data cannot settle — often a different basis (salt vs freebase, plant material vs alkaloid, opioid-naive vs tolerant) that neither side states.",
        "| P | substance | quantity | this source | others | why |",
        unclear,
        args.limit,
    )

    blocked = blocked_rows(args.source)
    lines += ["## C. Rows Piru does not ship from this source", ""]
    if blocked:
        lines += (
            [
                "Each is either a hand-written exception with its evidence (`data/curated/dose-source-exceptions.json`) or a build gate — a rule the row fails on its own terms (`pipeline/build/dose_gates.py`).",
                "",
                "| substance | routes | what | why |",
                "|---|---|---|---|",
            ]
            + blocked
            + [""]
        )
    else:
        lines += ["None.", ""]
    OUT = args.out or (OUT_DIR / f"{args.source}-{today}.md")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines))
    print(f"{OUT}  ({len(errors)} probable errors, {len(unclear)} unclear, {len(blocked)} blocked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
