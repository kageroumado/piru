#!/usr/bin/env python3
"""Brush `benzos-cited.json` into Piru-shaped CSV.

`benzos-cited.json` is the only of the four datasets that ships
TripSit/PsychonautWiki-style structured dose ranges per route, so this is the
one brusher that emits dose + duration columns. Everything else stays blank
because the source either lacks them or contains only clinical (i.e. non-
recreational) dosing.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (
    OUTPUT_DIR,
    empty_row,
    join_unique,
    open_csv,
    parse_range,
    piru_category,
    piru_route,
)

SOURCE_PATH = Path("/Users/kirie/Developer/piru-datasources/benzos-cited.json")
OUTPUT_PATH = OUTPUT_DIR / "benzos_cited.csv"


_DOSE_VALUE_RE = re.compile(
    r"""
    (?P<lo>\d+(?:\.\d+)?)
    (?:\s*[-–]\s*(?P<hi>\d+(?:\.\d+)?))?
    \s*
    (?P<unit>µg|ug|mcg|mg|g|ml)?
    """,
    re.IGNORECASE | re.VERBOSE,
)


def parse_dose_cell(text: str | None) -> tuple[str, str]:
    """Parse "0.5-1.5mg" / "2mg" → ("0.5-1.5", "mg"). Empty inputs → ("","")."""
    if not text:
        return "", ""
    cleaned = text.replace(",", ".").strip()
    m = _DOSE_VALUE_RE.search(cleaned)
    if not m:
        return "", ""
    lo = m.group("lo")
    hi = m.group("hi")
    unit = (m.group("unit") or "").strip().lower()
    if unit in ("ug", "mcg"):
        unit = "µg"
    value = f"{lo}-{hi}" if hi else lo
    return value, unit


def format_duration_range(d: dict | None) -> str:
    """Reconstruct "5-8 hours" from `{"_unit": "hours", "value": "5-8"}`."""
    if not isinstance(d, dict):
        return ""
    value = d.get("value")
    unit = d.get("_unit")
    if value is None or unit is None:
        return ""
    return f"{value} {unit}"


def to_minutes(text: str) -> str:
    """Convert "5-8 hours" / "15-40 minutes" → midpoint in minutes (string).
    Used only when collapsing to a single representative number — the raw
    range is preserved verbatim in the dedicated onset/peak/total columns."""
    lo, hi, unit = parse_range(text)
    if not lo:
        return ""
    try:
        lo_f = float(lo)
        hi_f = float(hi) if hi else lo_f
    except ValueError:
        return ""
    mid = (lo_f + hi_f) / 2
    if unit.startswith("hour") or unit in ("h", "hr", "hrs"):
        mid *= 60
    return f"{mid:.0f}"


def brush() -> None:
    data = json.loads(SOURCE_PATH.read_text())
    fh, writer = open_csv(OUTPUT_PATH)

    for entry in data:
        name = entry.get("pretty_name") or entry.get("name", "")
        if not name:
            continue

        aliases = entry.get("aliases") or []
        categories = entry.get("categories") or []
        formatted_dose: dict = entry.get("formatted_dose") or {}
        props = entry.get("properties") or {}
        effects = entry.get("formatted_effects") or []

        # Per-route columns are emitted in a stable order so the CSV can be
        # eyeballed without losing the route↔value correspondence.
        route_order: list[str] = []
        for raw_route in formatted_dose.keys():
            mapped = piru_route(raw_route)
            if mapped and mapped not in route_order:
                route_order.append(mapped)

        units: list[str] = []
        thresholds: list[str] = []
        lights: list[str] = []
        commons: list[str] = []
        strongs: list[str] = []
        heavies: list[str] = []

        # Walk routes in the resolved order so each column lines up.
        for route in route_order:
            # Find the matching raw key (the dict is keyed by raw route names
            # like "Oral" / "Insufflated").
            raw_key = next(
                (k for k in formatted_dose if piru_route(k) == route),
                None,
            )
            doses = formatted_dose.get(raw_key) or {}

            _, t_unit = parse_dose_cell(doses.get("Threshold"))
            light_val, l_unit = parse_dose_cell(doses.get("Light"))
            common_val, c_unit = parse_dose_cell(doses.get("Common"))
            strong_val, s_unit = parse_dose_cell(doses.get("Strong"))
            heavy_val, h_unit = parse_dose_cell(doses.get("Heavy"))

            # Prefer Common's unit when present; fall back to the first non-
            # empty unit observed. Benzos data is consistent within a route.
            unit = c_unit or l_unit or s_unit or h_unit or t_unit or "mg"
            units.append(unit)

            thresholds.append(parse_dose_cell(doses.get("Threshold"))[0])
            lights.append(light_val)
            commons.append(common_val)
            strongs.append(strong_val)
            heavies.append(heavy_val)

        onset = format_duration_range(entry.get("formatted_onset"))
        duration = format_duration_range(entry.get("formatted_duration"))
        aftereffects = format_duration_range(entry.get("formatted_aftereffects"))

        notes_parts = []
        if entry.get("dose_note"):
            notes_parts.append(entry["dose_note"].strip())
        if props.get("summary"):
            notes_parts.append(props["summary"].strip())
        if props.get("avoid"):
            notes_parts.append(f"Avoid: {props['avoid'].strip()}")
        if props.get("dose_to_diazepam"):
            notes_parts.append(props["dose_to_diazepam"].strip())
        if aftereffects:
            notes_parts.append(f"After-effects: {aftereffects}")

        row = empty_row("benzos-cited")
        row.update({
            "source_id": str((entry.get("_id") or {}).get("$oid", "")),
            "name": name,
            "aliases": join_unique(aliases),
            "raw_classes": join_unique(categories),
            "piru_category": piru_category(categories),
            "default_route": route_order[0] if route_order else "oral",
            "routes": "; ".join(route_order),
            "units": "; ".join(units),
            "dose_threshold": "; ".join(thresholds),
            "dose_light": "; ".join(lights),
            "dose_common": "; ".join(commons),
            "dose_strong": "; ".join(strongs),
            "dose_heavy": "; ".join(heavies),
            "onset": onset,
            "peak": "",  # benzos-cited doesn't break peak out separately
            "total_duration": duration,
            "half_life_min": "",
            "mechanism_summary": "",
            "effects": join_unique(effects, sep=", "),
            "sources_count": str(len((entry.get("sources") or {}).get("_general", []))),
            "notes": " | ".join(notes_parts),
        })
        writer.writerow(row)

    fh.close()
    print(f"wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    brush()
