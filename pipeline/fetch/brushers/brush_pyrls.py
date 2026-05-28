#!/usr/bin/env python3
"""Brush `pyrls[N=378].json` into Piru-shaped CSV.

Pyrls is a clinical drug reference (Tudorza, Wellbutrin, etc.) — every dose
shown there is a doctor-prescribed regimen, not a recreational dose. Per
project rules, dose + duration columns are emitted blank. The valuable
mappings are `genericName → name`, `brandNames → aliases`,
`labels → raw_classes`, `delivery → default_route`, and the short
`drugInfo.pharmacology.mechanism` HTML blurb.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (
    OUTPUT_DIR,
    empty_row,
    join_unique,
    open_csv,
    piru_category,
    piru_route,
    strip_html,
)

SOURCE_PATH = Path("/Users/kirie/Developer/piru-datasources/pyrls[N=378].json")
OUTPUT_PATH = OUTPUT_DIR / "pyrls.csv"


def split_brands(text: str | None) -> list[str]:
    """`brandNames` is a comma-separated string in this dataset."""
    if not text:
        return []
    return [b.strip() for b in text.split(",") if b.strip()]


def flatten_indications(node: dict | None) -> str:
    """`drugInfo.indications` is `{labeled: [...], offLabel: [...]}`. We keep
    labeled-only since off-label is highly contextual."""
    if not isinstance(node, dict):
        return ""
    items = node.get("labeled") or []
    return join_unique([strip_html(x) for x in items])


def flatten_contraindications(node: dict | None) -> str:
    if not isinstance(node, dict):
        return ""
    items = (node.get("labeled") or []) + (node.get("offLabel") or [])
    return join_unique([strip_html(x) for x in items])


def regulatory_status(node: dict | None) -> str:
    if not isinstance(node, dict):
        return ""
    labels = node.get("labels") or []
    desc = node.get("description") or ""
    parts = [*labels]
    if desc:
        parts.append(desc)
    return join_unique(parts)


def brush() -> None:
    data = json.loads(SOURCE_PATH.read_text())
    fh, writer = open_csv(OUTPUT_PATH)

    for entry in data:
        name = entry.get("genericName", "")
        if not name:
            continue

        drug_info = entry.get("drugInfo") or {}
        labels = entry.get("labels") or []
        brands = split_brands(entry.get("brandNames"))
        delivery = entry.get("delivery", "")
        pharm = drug_info.get("pharmacology") or {}

        row = empty_row("pyrls")
        row.update({
            "source_id": str((entry.get("_id") or {}).get("$oid", "")),
            "name": name,
            "aliases": join_unique(brands),
            "raw_classes": join_unique(labels),
            "piru_category": piru_category(labels),
            "default_route": piru_route(delivery) or "oral",
            "routes": piru_route(delivery),
            "units": "",
            # Dose + duration intentionally blank — clinical dosing only.
            "mechanism_summary": strip_html(pharm.get("mechanism")),
            "indications": flatten_indications(drug_info.get("indications")),
            "contraindications": flatten_contraindications(drug_info.get("contraindications")),
            "regulatory_status": regulatory_status(entry.get("regulatoryStatus")),
            "tags": join_unique([entry.get("dosageForm") or "", *labels]),
            "sources_count": str(len(entry.get("references") or [])),
            "notes": "",
        })
        writer.writerow(row)

    fh.close()
    print(f"wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    brush()
