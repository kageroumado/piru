#!/usr/bin/env python3
"""Merge the per-group enrichment JSON files written by the agent swarm
into one combined artifact + a coverage report.

Inputs:
  data/enrichment/raw/<group-slug>.json — each agent's output.
  Schema: an array of per-compound records plus class-context objects
  (distinguishable by `is_class_context: true`).

Outputs:
  data/enrichment/merged.json        — flat list of all per-compound records
  data/enrichment/class-context.json — list of class-context objects
  data/enrichment/coverage.csv       — one row per substance, columns indicate
                                       which deep-pharma fields got filled
"""

import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
IN_DIR = REPO / "data/enrichment/raw"
OUT_MERGED = REPO / "data/enrichment/merged.json"
OUT_CONTEXT = REPO / "data/enrichment/class-context.json"
OUT_COVERAGE = REPO / "data/enrichment/coverage.csv"


def normalise(s: str) -> str:
    return (s or "").lower().strip()


def coverage_flags(rec: dict) -> dict[str, str]:
    pharm = rec.get("pharmacology") or {}
    pk = rec.get("human_pk") or {}
    return {
        "has_binding":       "yes" if pharm.get("binding") else "no",
        "has_functional":    "yes" if pharm.get("functional") else "no",
        "has_biased":        "yes" if pharm.get("biased_agonism") else "no",
        "has_oligomers":     "yes" if pharm.get("receptor_oligomerisation") else "no",
        "has_downstream":    "yes" if pharm.get("downstream_signalling") else "no",
        "has_neuroimaging":  "yes" if pharm.get("neuroimaging") else "no",
        "has_pk_routes":     "yes" if pk.get("routes") else "no",
        "has_conc_effect":   "yes" if pk.get("concentration_effect") else "no",
        "has_metabolism":    "yes" if rec.get("metabolism") else "no",
        "has_drug_interactions": "yes" if rec.get("drug_interactions_pk") else "no",
        "has_pgx":           "yes" if rec.get("pharmacogenetics") else "no",
        "has_tolerance":     "yes" if rec.get("tolerance_and_dependence") else "no",
        "has_off_targets":   "yes" if rec.get("off_targets") else "no",
        "has_identifiers":   "yes" if (rec.get("inchikey") or rec.get("pubchem_cid") or rec.get("cas")) else "no",
        "confidence":        rec.get("confidence", ""),
    }


def main() -> int:
    if not IN_DIR.exists():
        print(f"ERROR: {IN_DIR} does not exist", file=sys.stderr)
        return 1

    per_compound: dict[str, dict] = {}  # key: normalised name
    class_contexts: list[dict] = []
    group_stats: dict[str, dict] = {}

    files = sorted(IN_DIR.glob("*.json"))
    if not files:
        print(f"ERROR: no enrichment files in {IN_DIR}", file=sys.stderr)
        return 1

    for f in files:
        try:
            entries = json.loads(f.read_text())
        except Exception as e:
            print(f"  SKIP {f.name}: parse error: {e}", file=sys.stderr)
            continue
        if not isinstance(entries, list):
            print(f"  SKIP {f.name}: not a JSON array", file=sys.stderr)
            continue

        compound_count = 0
        context_count = 0
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if entry.get("is_class_context"):
                entry["_source_group"] = f.stem
                class_contexts.append(entry)
                context_count += 1
                continue
            name = entry.get("name")
            if not name:
                continue
            key = normalise(name)
            existing = per_compound.get(key)
            entry["_source_group"] = f.stem
            if existing is None:
                per_compound[key] = entry
            else:
                # Prefer the higher-confidence record; merge fields where one is null
                conf_order = {"high": 3, "medium": 2, "low": 1, "": 0, None: 0}
                if conf_order.get(entry.get("confidence")) > conf_order.get(existing.get("confidence")):
                    per_compound[key] = entry
                else:
                    # Fill any null fields from the lower-confidence entry
                    for k, v in entry.items():
                        if existing.get(k) in (None, [], {}, "") and v not in (None, [], {}, ""):
                            existing[k] = v
            compound_count += 1

        group_stats[f.stem] = {
            "compounds": compound_count,
            "class_contexts": context_count,
        }

    OUT_MERGED.write_text(json.dumps(
        sorted(per_compound.values(), key=lambda x: x.get("name", "").lower()),
        indent=2, ensure_ascii=False
    ))
    OUT_CONTEXT.write_text(json.dumps(class_contexts, indent=2, ensure_ascii=False))

    field_keys = [
        "has_binding", "has_functional", "has_biased", "has_oligomers",
        "has_downstream", "has_neuroimaging", "has_pk_routes",
        "has_conc_effect", "has_metabolism", "has_drug_interactions",
        "has_pgx", "has_tolerance", "has_off_targets", "has_identifiers",
        "confidence",
    ]
    fieldnames = ["name", "source_group"] + field_keys
    with OUT_COVERAGE.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for rec in sorted(per_compound.values(), key=lambda x: x.get("name", "").lower()):
            row = {"name": rec.get("name", ""), "source_group": rec.get("_source_group", "")}
            row.update(coverage_flags(rec))
            w.writerow(row)

    # Coverage roll-up
    totals = defaultdict(int)
    for rec in per_compound.values():
        flags = coverage_flags(rec)
        for k, v in flags.items():
            if v == "yes":
                totals[k] += 1
        totals[f"conf_{flags['confidence']}"] += 1

    print(f"Merged {len(per_compound)} unique substances from {len(files)} group files", file=sys.stderr)
    print(f"Class-context records: {len(class_contexts)}", file=sys.stderr)
    print(file=sys.stderr)
    print("Per-group counts:", file=sys.stderr)
    for slug, s in sorted(group_stats.items()):
        print(f"  {slug:50s} {s['compounds']:5d} compounds, {s['class_contexts']:2d} class-contexts", file=sys.stderr)
    print(file=sys.stderr)
    print("Field coverage across all substances:", file=sys.stderr)
    for k in field_keys:
        if k == "confidence":
            continue
        n = totals[k]
        pct = 100 * n / max(1, len(per_compound))
        print(f"  {k:25s} {n:5d}  ({pct:5.1f}%)", file=sys.stderr)
    print(file=sys.stderr)
    print("Confidence breakdown:", file=sys.stderr)
    for c in ("high", "medium", "low", ""):
        print(f"  {c or '(none)':10s} {totals['conf_' + c]:5d}", file=sys.stderr)
    print(file=sys.stderr)
    print(f"Outputs:", file=sys.stderr)
    print(f"  {OUT_MERGED}", file=sys.stderr)
    print(f"  {OUT_CONTEXT}", file=sys.stderr)
    print(f"  {OUT_COVERAGE}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
