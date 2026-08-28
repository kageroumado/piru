#!/usr/bin/env python3
"""FDA label pharmacokinetics from the MedTAP corpus, as a reviewed sidecar.

`extract_medtap` parses the label's Pharmacology block as a header/value table
and keeps one field, Mechanism Of Action. The rest of that table is half-life,
protein binding, volume of distribution and clearance for ~250 substances — real
numbers, US-government public domain, and until now discarded.

They are **not** parsed at build time. The values are prose ("approximately 12
hours in adults and 6 hours in children"), and a build that guesses at prose
ships a wrong number silently. This writes `data/sources/medtap-pk.json` once;
that file is committed, reviewable as a diff, and ingested deterministically.

Two guards, both of which caught a real misattribution:

- **Combination products are skipped entirely.** A label for an oral
  contraceptive lists each ingredient's kinetics, and taking the first value
  gave ethynodiol estradiol's 36-hour half-life.
- **A value naming a substance is refused** unless that substance is the one it
  is being attributed to. The parser already rejects multi-ingredient strings by
  counting numbers; this catches the single-value case it cannot see.

    python3 pipeline/fetch/brushers/medtap_pk.py            # report
    python3 pipeline/fetch/brushers/medtap_pk.py --write    # + write the sidecar
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SOURCE = Path.home() / "Developer" / "piru-data" / "Medtap-App-Pharma-DB.json"
DB = REPO / "Piru" / "Data" / "piru-substances.sqlite"
OUT = REPO / "data" / "sources" / "medtap-pk.json"

sys.path.insert(0, str(REPO / "pipeline" / "build"))
from sqlite import normalise  # noqa: E402

# The half-life parser from the DrugBank cross-check: clean single values and
# ranges with explicit units only, everything else refused. Reused rather than
# rewritten so both paths reject the same shapes, and so its 18 tests cover this.
_spec = importlib.util.spec_from_file_location(
    "cdb", REPO / "pipeline" / "audit" / "compare_to_drugbank.py"
)
_cdb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cdb)
parse_half_life = _cdb.parse_half_life
parse_half_life_mean = _cdb.parse_half_life_mean

_LABEL_HEADER = re.compile(r"<text class='druglabel_header'>(.*?)</text>", re.S)
_TAGS = re.compile(r"<[^>]+>")
#: "estradiol:   36 hours" — a value belonging to a named substance.
_ATTRIBUTED = re.compile(r"^\s*([A-Za-z][A-Za-z0-9''\- ]{2,30})\s*:")
_PERCENT = re.compile(r"^[^0-9]{0,40}?(\d{1,3}(?:\.\d+)?)\s*%")
_VD = re.compile(r"^[^0-9]{0,40}?(\d+(?:\.\d+)?)\s*(?:L|liters?)\s*/\s*kg")

#: How far two independent half-lives may differ and still be the same claim.
#: Generous — the point is to catch a label quoting a different *quantity*, not
#: to arbitrate between two plausible numbers.
AGREEMENT_RATIO = 3.0


def independent_half_lives() -> dict[str, float]:
    """The database's own half-lives, as an independent check on the label value.

    A label's "Half-life" field is not always an elimination half-life:
    pravastatin's 77 hours is the duration of cholesterol-synthesis inhibition,
    hydrocortisone's 6-8 is biological rather than plasma, and carisoprodol's 8
    belongs to meprobamate. Nothing in the field says which — but a second
    source disagreeing by more than a factor of three does, and that is enough
    to refuse rather than arbitrate.

    MedTAP's own rows are excluded: this sidecar is where they came from, so a
    value would otherwise corroborate itself.
    """
    db = sqlite3.connect(DB)
    try:
        rows = db.execute(
            """
            SELECT lower(s.canonical_name), h.half_life_minutes
              FROM half_lives h
              JOIN substances s ON s.id = h.substance_id
              JOIN sources src ON src.id = h.source_id
             WHERE h.half_life_minutes > 0 AND src.slug <> 'medtap'
             -- Worst priority first, so the best-priority row is the one that
             -- survives the comprehension below.
             ORDER BY src.default_priority DESC
            """
        ).fetchall()
    finally:
        db.close()
    return {name: float(minutes) for name, minutes in rows}


def label_fields(section: dict) -> dict[str, str]:
    """The Pharmacology section's `header -> value` pairs."""
    texts: list[str] = []

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("text"), str):
                texts.append(node["text"])
            else:
                for value in node.values():
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(section.get("content"))
    walk(section.get("content_full"))

    fields: dict[str, str] = {}
    header, body = None, []
    for raw in texts:
        match = _LABEL_HEADER.search(raw)
        if match:
            if header and body:
                fields.setdefault(header, " ".join(body))
            header, body = match.group(1).strip(), []
        elif header:
            body.append(raw)
    if header and body:
        fields.setdefault(header, " ".join(body))
    return {k: _TAGS.sub(" ", v).strip() for k, v in fields.items()}


def attributed_to_other(value: str, substance: str) -> bool:
    """Whether `value` opens by naming a substance that is not `substance`."""
    match = _ATTRIBUTED.match(value)
    if not match:
        return False
    return normalise(match.group(1)) != normalise(substance)


def piru_index(db: sqlite3.Connection) -> dict[str, str]:
    index: dict[str, str] = {}
    for canonical, display in db.execute("SELECT canonical_name, display_name FROM substances"):
        index.setdefault(normalise(canonical), canonical)
        if display:
            index.setdefault(normalise(display), canonical)
    for alias, canonical in db.execute(
        "SELECT a.alias_normalized, s.canonical_name FROM aliases a "
        "JOIN substances s ON s.id = a.substance_id"
    ):
        index.setdefault(alias, canonical)
    return index


def harvest() -> tuple[dict, dict]:
    db = sqlite3.connect(DB)
    index = piru_index(db)
    records = json.loads(SOURCE.read_text())

    out: dict[str, dict] = {}
    stats = {
        "products": 0,
        "combination_skipped": 0,
        "half_life": 0,
        "half_life_rejected": 0,
        "misattributed": 0,
        "protein_binding": 0,
        "vd": 0,
    }
    for record in records:
        target = record.get("target")
        ingredients = target if isinstance(target, list) else []
        if len(ingredients) > 1:
            stats["combination_skipped"] += 1
            continue
        name = (ingredients[0] if ingredients else record.get("generic_name")) or ""
        canonical = index.get(normalise(str(name))) or index.get(
            normalise(record.get("generic_name") or "")
        )
        if not canonical:
            continue
        stats["products"] += 1
        for section in record.get("sections") or []:
            if section.get("section_name") != "Pharmacology":
                continue
            fields = label_fields(section)
            entry = out.setdefault(canonical, {"substance": canonical})
            # The label IS the citation for these numbers, and its NDC is what
            # identifies the product whose label they came from. Without it the
            # build's uncited-numeric gate rejects the rows, correctly.
            if record.get("ndc"):
                entry.setdefault("ndc", str(record["ndc"]))
                entry.setdefault("brand", record.get("brand_name") or "")

            raw = fields.get("Half-life", "")
            if raw and "half_life_minutes" not in entry:
                if attributed_to_other(raw, canonical):
                    stats["misattributed"] += 1
                else:
                    parsed = parse_half_life(raw)
                    if parsed:
                        # A label that states a mean beside its range has already
                        # named the point estimate; the midpoint would be
                        # arithmetic of ours wearing the label's authority.
                        # Phenelzine's "1.2 to 11.6 hours (mean 11.6)" is the
                        # case that shows it — the midpoint contradicts the
                        # sentence it was computed from.
                        stated = parse_half_life_mean(raw)
                        entry["half_life_minutes"] = round(
                            stated if stated is not None else (parsed[0] + parsed[1]) / 2, 1
                        )
                        entry["half_life_low_minutes"] = round(parsed[0], 1)
                        entry["half_life_high_minutes"] = round(parsed[1], 1)
                        entry["half_life_label"] = raw[:200]
                        stats["half_life"] += 1
                    else:
                        stats["half_life_rejected"] += 1

            raw = fields.get("Protein Binding", "")
            if (
                raw
                and "protein_binding_pct" not in entry
                and not attributed_to_other(raw, canonical)
            ):
                match = _PERCENT.match(raw)
                if match and float(match.group(1)) <= 100:
                    entry["protein_binding_pct"] = float(match.group(1))
                    entry["protein_binding_label"] = raw[:200]
                    stats["protein_binding"] += 1

            raw = fields.get("Volume Of Distribution", "")
            if raw and "vd_l_per_kg" not in entry and not attributed_to_other(raw, canonical):
                match = _VD.match(raw)
                if match:
                    entry["vd_l_per_kg"] = float(match.group(1))
                    entry["vd_label"] = raw[:200]
                    stats["vd"] += 1

    # A record that parsed nothing is not worth a row.
    out = {k: v for k, v in out.items() if len(v) > 1}

    # Cross-check every half-life against an independent value. A disagreement
    # is a refusal, not a merge: it means the label is quoting a different
    # quantity and nothing in the field says which.
    reference = independent_half_lives()
    conflicts: list[dict] = []
    for name, entry in out.items():
        minutes = entry.get("half_life_minutes")
        known = reference.get(name.lower())
        if minutes is None or known is None:
            continue
        ratio = max(minutes, known) / max(1e-9, min(minutes, known))
        if ratio <= AGREEMENT_RATIO:
            entry["half_life_corroborated"] = True
            continue
        conflicts.append(
            {
                "substance": name,
                "label_minutes": minutes,
                "independent_minutes": known,
                "label": entry.get("half_life_label"),
            }
        )
        for key in (
            "half_life_minutes",
            "half_life_low_minutes",
            "half_life_high_minutes",
            "half_life_label",
        ):
            entry.pop(key, None)
    stats["half_life_conflicts"] = len(conflicts)
    out = {k: v for k, v in out.items() if len(v) > 1}
    return out, stats, conflicts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write the sidecar")
    args = parser.parse_args()

    if not SOURCE.exists():
        sys.exit(f"no MedTAP corpus at {SOURCE}")
    entries, stats, conflicts = harvest()

    db = sqlite3.connect(DB)
    have_half_life = {
        r[0]
        for r in db.execute(
            "SELECT s.canonical_name FROM half_lives h JOIN substances s ON s.id = h.substance_id"
        )
    }
    new_half_life = [
        k for k, v in entries.items() if "half_life_minutes" in v and k not in have_half_life
    ]

    print(f"{len(entries)} substances with at least one parsed value")
    for key, value in stats.items():
        print(f"  {key:<22} {value}")
    if conflicts:
        print("\nREFUSED — a second source disagrees by more than 3x, so the label is")
        print("quoting a different quantity and nothing in the field says which:")
        for conflict in conflicts:
            print(
                f"  {conflict['substance']:<20} label {conflict['label_minutes'] / 60:>6.1f} h  "
                f"vs {conflict['independent_minutes'] / 60:>6.1f} h   <- {conflict['label'][:44]}"
            )

    # A half-life the reference set cannot reach is not corroborated and not
    # refused — it is unchecked, and it enters at `medtap` priority anyway. Say
    # so: the refusal rule can only fire where a second source exists, and the
    # entries with none are exactly where a wrong quantity gets through.
    unchecked = sorted(
        k
        for k, v in entries.items()
        if "half_life_minutes" in v and not v.get("half_life_corroborated")
    )
    print(f"\n{len(unchecked)} half-lives no second source could check:")
    for name in unchecked:
        entry = entries[name]
        print(
            f"  {name:<26} {entry['half_life_minutes'] / 60:>6.1f} h   <- {entry['half_life_label'][:50]}"
        )

    print(f"\n{len(new_half_life)} of them have NO half-life in the database today:")
    for name in sorted(new_half_life)[:20]:
        entry = entries[name]
        print(
            f"  {name:<26} {entry['half_life_low_minutes'] / 60:>6.1f}–"
            f"{entry['half_life_high_minutes'] / 60:<6.1f} h   <- {entry['half_life_label'][:50]}"
        )

    if args.write:
        OUT.write_text(
            json.dumps(
                {
                    "_meta": {
                        "source": "MedTAP FDA structured product labels",
                        "generator": "pipeline/fetch/brushers/medtap_pk.py",
                        "what": "Reviewed PK values parsed from label Pharmacology tables. "
                        "Each value keeps the label string it came from so a reviewer "
                        "can check it without the corpus.",
                    },
                    "entries": [entries[k] for k in sorted(entries)],
                    "refused_half_lives": conflicts,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n"
        )
        print(f"\nwrote {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
