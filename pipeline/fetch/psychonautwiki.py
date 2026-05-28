#!/usr/bin/env python3
"""Fetch every substance from PsychonautWiki's GraphQL endpoint and save a
bundled snapshot the SQLite build can ingest as the `psychonautwiki` source.

PsychonautWiki was the main provider of full per-route duration profiles
(onset / comeup / peak / offset / total / afterglow) in older versions of the
app, but the runtime integration was removed in commit 76d9e6f because the
API was "consistently down" at that point. The source slug was kept in the
sources table as a placeholder, with no ingest function — leaving ~46% of
substances in the bundled DB with no duration data at all, even when PW had
it. This script restores that data as a versioned snapshot the bundled SQLite
ships, dropping the runtime API dependency.

The output JSON matches the shape `_ingest_substance_record` expects via
`ingest_psychonautwiki_snapshot` in `pipeline/build/sqlite.py` — same
schema as `data/intermediate/sourced-substances.json`, with
`provenance = "psychonautwiki"`.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Any
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError

ENDPOINT = "https://api.psychonautwiki.org/"
OUTPUT = Path(__file__).resolve().parents[2] / "data" / "sources" / "psychonautwiki.json"

LIST_QUERY = "{ substances(limit: 5000) { name } }"

DETAIL_QUERY_TEMPLATE = """
{
  substances(query: %s) {
    name
    url
    commonNames
    class { chemical psychoactive }
    tolerance { full half zero }
    addictionPotential
    summary
    roas {
      name
      dose {
        units
        threshold
        light { min max }
        common { min max }
        strong { min max }
        heavy
      }
      duration {
        onset     { min max units }
        comeup    { min max units }
        peak      { min max units }
        offset    { min max units }
        total     { min max units }
        afterglow { min max units }
      }
    }
  }
}
""".strip()


def post(query: str, timeout: int = 20) -> dict[str, Any]:
    body = json.dumps({"query": query}).encode("utf-8")
    req = urlrequest.Request(
        ENDPOINT, data=body, method="POST",
        headers={"Content-Type": "application/json", "User-Agent": "piru-pw-snapshot/1.0"},
    )
    with urlrequest.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def fetch_with_retry(query: str, *, attempts: int = 4) -> dict[str, Any] | None:
    delay = 1.5
    for attempt in range(1, attempts + 1):
        try:
            payload = post(query)
        except (HTTPError, URLError, TimeoutError) as exc:
            print(f"  retry {attempt}/{attempts}: {exc}", file=sys.stderr)
            time.sleep(delay)
            delay *= 2
            continue
        if "errors" in payload:
            print(f"  GraphQL errors: {payload['errors']}", file=sys.stderr)
            return None
        return payload.get("data") or {}
    return None


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

def to_minutes(amount: float | None, units: str | None) -> float | None:
    if amount is None or units is None:
        return None
    units = units.lower()
    if units in ("minute", "minutes", "min"):
        return float(amount)
    if units in ("hour", "hours", "h"):
        return float(amount) * 60.0
    if units in ("second", "seconds", "sec", "s"):
        return float(amount) / 60.0
    if units in ("day", "days", "d"):
        return float(amount) * 60.0 * 24.0
    # Unknown unit — drop rather than guess.
    return None


def normalise_duration(d: dict | None) -> dict[str, dict[str, float]]:
    if not d:
        return {}
    out: dict[str, dict[str, float]] = {}
    for phase in ("onset", "comeup", "peak", "offset", "total", "afterglow"):
        phase_value = d.get(phase)
        if not isinstance(phase_value, dict):
            continue
        units = phase_value.get("units")
        mn = to_minutes(phase_value.get("min"), units)
        mx = to_minutes(phase_value.get("max"), units)
        if mn is None or mx is None:
            continue
        out[phase] = {"min": mn, "max": mx}
    return out


def normalise_dose(d: dict | None) -> dict[str, Any]:
    """Convert PW's dose shape ({light: {min, max}, ...}) into the
    sourced-substances format ({light: {lower, upper}, ...})."""
    if not d:
        return {}
    out: dict[str, Any] = {}
    for key in ("light", "common", "strong"):
        r = d.get(key)
        if isinstance(r, dict) and r.get("min") is not None and r.get("max") is not None:
            out[key] = {"lower": float(r["min"]), "upper": float(r["max"])}
    if d.get("threshold") is not None:
        out["threshold"] = float(d["threshold"])
    if d.get("heavy") is not None:
        out["heavy"] = float(d["heavy"])
    return out


# Chemical-class strings → the app's SubstanceCategory raw values.
# Checked first because chemical class is usually more specific than the
# psychoactive class. Without this, PW's "Depressant" psychoactive label
# (priority 3) overrides TripSit's "Benzodiazepine" label (priority 4) for
# every benzo in the catalogue, breaking class-based interaction rules.
_CHEMICAL_CATEGORY_MAP = {
    "benzodiazepines":  "Benzodiazepine",
    "cannabinoids":     "Cannabinoid",
    "cannabinoid":      "Cannabinoid",
    "phytocannabinoids":"Cannabinoid",
    "antipsychotics":   "Antipsychotic",
}

# Psychoactive class strings → SubstanceCategory raw values. Mapped
# conservatively; unknown classes drop to nil so other sources can win the
# category resolution rather than getting saddled with "Other".
_PSYCHOACTIVE_CATEGORY_MAP = {
    "stimulants":       "Stimulant",
    "stimulant":        "Stimulant",
    "psychedelics":     "Psychedelic",
    "psychedelic":      "Psychedelic",
    "dissociatives":    "Dissociative",
    "dissociative":     "Dissociative",
    "depressants":      "Depressant",
    "depressant":       "Depressant",
    "opioids":          "Opioid",
    "opioid":           "Opioid",
    "cannabinoids":     "Cannabinoid",
    "cannabinoid":      "Cannabinoid",
    "entactogens":      "Empathogen",
    "entactogen":       "Empathogen",
    "empathogens":      "Empathogen",
    "empathogen":       "Empathogen",
    "deliriants":       "Dysdelic",
    "deliriant":        "Dysdelic",
    "benzodiazepines":  "Benzodiazepine",
    "benzodiazepine":   "Benzodiazepine",
    "gabaergics":       "GABAergic",
    "gabaergic":        "GABAergic",
    "nootropics":       "Nootropic",
    "nootropic":        "Nootropic",
    "eugeroics":        "Eugeroic",
    "eugeroic":         "Eugeroic",
    "antidepressants":  "Antidepressant",
    "antidepressant":   "Antidepressant",
    "antipsychotics":   "Antipsychotic",
    "antipsychotic":    "Antipsychotic",
}


def pick_category(class_obj: dict | None) -> str | None:
    if not isinstance(class_obj, dict):
        return None
    chem = class_obj.get("chemical") or []
    for entry in chem:
        if not isinstance(entry, str):
            continue
        cat = _CHEMICAL_CATEGORY_MAP.get(entry.strip().lower())
        if cat:
            return cat
    psy = class_obj.get("psychoactive") or []
    for entry in psy:
        if not isinstance(entry, str):
            continue
        cat = _PSYCHOACTIVE_CATEGORY_MAP.get(entry.strip().lower())
        if cat:
            return cat
    return None


def pick_default_route(roas: list[dict]) -> str:
    """First with full duration → first with any dose → first → 'oral'."""
    for r in roas:
        if isinstance(r, dict) and r.get("duration") and r.get("dose"):
            return r.get("name") or "oral"
    for r in roas:
        if isinstance(r, dict) and r.get("dose"):
            return r.get("name") or "oral"
    if roas and isinstance(roas[0], dict):
        return roas[0].get("name") or "oral"
    return "oral"


def to_record(substance: dict) -> dict | None:
    name = (substance.get("name") or "").strip()
    if not name:
        return None
    roas = substance.get("roas") or []
    routes: list[dict] = []
    for r in roas:
        if not isinstance(r, dict):
            continue
        route_name = (r.get("name") or "").strip()
        if not route_name:
            continue
        dose = normalise_dose(r.get("dose"))
        duration = normalise_duration(r.get("duration"))
        # Skip route rows that contribute nothing — keeps the snapshot small.
        if not dose and not duration:
            continue
        unit = ((r.get("dose") or {}).get("units") or "mg") or "mg"
        entry: dict[str, Any] = {"route": route_name, "unit": unit}
        if dose:
            entry["doses"] = dose
        if duration:
            entry["duration"] = duration
        routes.append(entry)

    if not routes:
        # No usable route data — skip the record. The substance might still
        # be added by another source, so just don't claim PW data for it.
        return None

    aliases = []
    for alias in (substance.get("commonNames") or []):
        if isinstance(alias, str) and alias.strip() and alias.strip().lower() != name.lower():
            aliases.append(alias.strip())

    tags: list[str] = []
    chem_classes = (substance.get("class") or {}).get("chemical") or []
    for chem in chem_classes:
        if isinstance(chem, str) and chem.strip():
            tags.append(f"class:{chem.strip().lower()}")

    record: dict[str, Any] = {
        "name": name,
        "aliases": aliases,
        "defaultRoute": pick_default_route(roas),
        "routes": routes,
        "effects": [],
        "sources": [substance.get("url")] if substance.get("url") else [],
        "tags": tags,
    }
    category = pick_category(substance.get("class"))
    if category:
        record["category"] = category

    summary = (substance.get("summary") or "").strip()
    if summary:
        # PW summaries are usually short; not currently consumed by the app
        # but keep them so the snapshot stays self-describing.
        record["psychonautWikiSummary"] = summary

    return record


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    print(f"Fetching PsychonautWiki snapshot → {OUTPUT.relative_to(Path.cwd()) if OUTPUT.is_relative_to(Path.cwd()) else OUTPUT}", file=sys.stderr)
    list_data = fetch_with_retry(LIST_QUERY)
    if not list_data:
        print("Failed to list PW substances.", file=sys.stderr)
        return 1
    names = sorted({(s.get("name") or "").strip() for s in (list_data.get("substances") or []) if s.get("name")})
    print(f"  {len(names)} substances to fetch", file=sys.stderr)

    records: list[dict] = []
    failed: list[str] = []
    for i, name in enumerate(names, start=1):
        # Quote-escape the name for the inline GraphQL query.
        escaped = json.dumps(name)
        query = DETAIL_QUERY_TEMPLATE % escaped
        data = fetch_with_retry(query)
        if not data:
            failed.append(name)
            continue
        for substance in (data.get("substances") or []):
            if not isinstance(substance, dict):
                continue
            # PW search can return prefix matches — keep only the exact name.
            if (substance.get("name") or "").strip().lower() != name.lower():
                continue
            record = to_record(substance)
            if record:
                records.append({"provenance": "psychonautwiki", "substance": record})
        if i % 25 == 0:
            print(f"  {i}/{len(names)}: {len(records)} records, {len(failed)} failures", file=sys.stderr)
        # Polite rate limit — PW has historically been ratelimited under load.
        time.sleep(0.15)

    records.sort(key=lambda r: r["substance"]["name"].lower())
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(records, indent=2, ensure_ascii=False) + "\n")

    print(f"\n✓ Wrote {len(records)} records to {OUTPUT}", file=sys.stderr)
    if failed:
        print(f"  ! {len(failed)} substances failed:", file=sys.stderr)
        for n in failed:
            print(f"    - {n}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
