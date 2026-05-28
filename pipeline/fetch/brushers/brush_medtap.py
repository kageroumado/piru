#!/usr/bin/env python3
"""Brush `Medtap-App-Pharma-DB.json` into Piru-shaped CSV.

Medtap ships one entry per NDC code, so the 1000-row file collapses to
~343 unique substances when deduped by `target` (or `unii` as fallback).
For each unique substance we merge brand names, classes, and pick the
first non-empty Indications / Dosage / Pharmacology sections — those are
the human-readable HTML blurbs FDA structured labels carry.

Every dose shown here is OTC/Rx clinical dosing — dose + duration columns
stay blank per project rules.
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

SOURCE_PATH = Path("/Users/kirie/Developer/piru-datasources/Medtap-App-Pharma-DB.json")
OUTPUT_PATH = OUTPUT_DIR / "medtap.csv"


def first_str(value) -> str:
    """`target`, `unii`, `brand_name`, `generic_name` are usually strings but
    sometimes lists. We always want a single canonical value — pick the
    first non-empty entry."""
    if isinstance(value, list):
        for v in value:
            if v:
                return str(v).strip()
        return ""
    return str(value or "").strip()


def normalise_target(value) -> str:
    """Single canonical lowercased key for dedup."""
    return first_str(value).lower()


def normalise_route(value) -> str:
    """`route` can be `"oral"`, `"IM, IV"`, or a list. We collapse to a
    semicolon-joined list of Piru routes, stable-ordered, deduped."""
    if not value:
        return ""
    if isinstance(value, list):
        candidates = value
    else:
        candidates = [value]
    out: list[str] = []
    for c in candidates:
        mapped = piru_route(c)
        if mapped and mapped not in out:
            out.append(mapped)
    return "; ".join(out)


def normalise_class(value) -> list[str]:
    if isinstance(value, list):
        return [str(v) for v in value if v]
    if value:
        return [str(value)]
    return []


def section_text(sections: list[dict], section_name: str) -> str:
    """Return the first non-empty text content for the named section.
    Medtap stores content as either `content.text` (single block) or
    `content_full` (list of {style,text} pairs). Both shapes appear within
    the same dataset, so we try both and join non-empty pieces."""
    for sec in sections or []:
        if sec.get("section_name") != section_name:
            continue

        parts: list[str] = []
        content = sec.get("content")
        if isinstance(content, dict) and content.get("text"):
            parts.append(content["text"])
        elif isinstance(content, list):
            for piece in content:
                if isinstance(piece, dict) and piece.get("text"):
                    parts.append(piece["text"])

        full = sec.get("content_full")
        if isinstance(full, list):
            for piece in full:
                if isinstance(piece, dict) and piece.get("text"):
                    parts.append(piece["text"])
        elif isinstance(full, dict) and full.get("text"):
            parts.append(full["text"])

        joined = strip_html(" ".join(parts))
        if joined:
            return joined
    return ""


def brush() -> None:
    data = json.loads(SOURCE_PATH.read_text())

    # Dedup by `target` (or `unii` when target is empty/multi). First entry
    # for each key wins for scalar fields; aliases + classes are merged across
    # all entries that share the key.
    by_key: dict[str, dict] = {}
    aliases_by_key: dict[str, list[str]] = {}
    classes_by_key: dict[str, list[str]] = {}

    for entry in data:
        target = normalise_target(entry.get("target"))
        unii = first_str(entry.get("unii")).lower()
        generic = first_str(entry.get("generic_name")).lower()
        key = target or unii or generic
        if not key:
            continue

        if key not in by_key:
            by_key[key] = entry
            aliases_by_key[key] = []
            classes_by_key[key] = []

        brand = first_str(entry.get("brand_name"))
        if brand:
            aliases_by_key[key].append(brand)
        gn = first_str(entry.get("generic_name"))
        if gn and gn.lower() != key:
            aliases_by_key[key].append(gn)
        classes_by_key[key].extend(normalise_class(entry.get("class")))

    fh, writer = open_csv(OUTPUT_PATH)

    for key, entry in by_key.items():
        name = first_str(entry.get("target")) or first_str(entry.get("generic_name"))
        if not name:
            continue

        sections = entry.get("sections") or []
        classes = classes_by_key[key]
        rx_value = first_str(entry.get("rx"))
        regulatory = "OTC" if "OTC" in rx_value.upper() else ("Rx" if "PRESCRIPTION" in rx_value.upper() else rx_value)

        # Indications + Pharmacology sections carry the mechanism narrative.
        indications = section_text(sections, "Indications")
        pharmacology = section_text(sections, "Pharmacology")
        contras = section_text(sections, "Contraindications/Cautions")

        # Trim narratives to a reasonable cell length so the CSV stays
        # scannable in a spreadsheet. Long text degrades the rest of the
        # row's readability; the underlying JSON stays available if needed.
        def clamp(text: str, limit: int = 400) -> str:
            return text if len(text) <= limit else text[: limit - 1] + "…"

        row = empty_row("medtap")
        row.update({
            "source_id": str((entry.get("_id") or {}).get("$oid", "")) or first_str(entry.get("unii")),
            "name": name,
            "aliases": join_unique(aliases_by_key[key]),
            "raw_classes": join_unique(classes),
            "piru_category": piru_category(classes),
            "default_route": (normalise_route(entry.get("route")).split(";")[0].strip() or "oral"),
            "routes": normalise_route(entry.get("route")),
            "mechanism_summary": clamp(pharmacology),
            "indications": clamp(indications),
            "contraindications": clamp(contras),
            "regulatory_status": regulatory,
            "tags": join_unique(classes),
            "sources_count": "",
            "notes": "",
        })
        writer.writerow(row)

    fh.close()
    print(f"wrote {OUTPUT_PATH} ({len(by_key)} unique substances from {len(data)} NDC entries)")


if __name__ == "__main__":
    brush()
