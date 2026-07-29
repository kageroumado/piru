#!/usr/bin/env python3
"""Validate the curated per-substance files in data/curated/substances/.

Stdlib-only (no jsonschema dependency, matching the build pipeline). Catches the
silent-failure modes that otherwise only surface as missing/merged data after a
full rebuild: bad enums, malformed dose ranges, protocol dosing without a
frequency, duplicate compounds across files, and slug/filename drift.

Run standalone (CI / pre-commit):
    python3 pipeline/build/validate_curated.py
Exits non-zero if any ERROR is found. Importable: validate_dir(path) -> (errors, warnings).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CURATED_DIR = REPO / "data/curated/substances"


def _normalise_route(route: str) -> str:
    """Route as the build will store it — reuses sqlite.py's normalise_route so
    source aliases (nasal→insufflation, inhaled→inhalation, ophthalmic→other,
    iv→intravenous, …) validate the same way they're ingested. Loaded lazily to
    avoid a hard import cycle with the build module."""
    import importlib.util

    if not hasattr(_normalise_route, "_fn"):
        spec = importlib.util.spec_from_file_location(
            "_bsd_routes", Path(__file__).resolve().parent / "sqlite.py"
        )
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _normalise_route._fn = mod.normalise_route
    return _normalise_route._fn(route or "")


CATEGORIES = {
    "Stimulant",
    "Psychedelic",
    "Dissociative",
    "Dysdelic",
    "Deliriant",
    "Opioid",
    "Benzodiazepine",
    "GABAergic",
    "Empathogen",
    "Cannabinoid",
    "Nootropic",
    "AMPAkine",
    "Eugeroic",
    "Depressant",
    "OrexinAntagonist",
    "Antidepressant",
    "Antipsychotic",
    "Analgesic",
    "Antihistamine",
    "Cardiovascular",
    "Antimicrobial",
    "Gastrointestinal",
    "Respiratory",
    "Endocrine",
    "Immunological",
    "Supplement",
    "Peptide",
    "Anticonvulsant",
    "Other",
}
ROUTES = {
    "oral",
    "sublingual",
    "buccal",
    "insufflation",
    "inhalation",
    "intravenous",
    "intramuscular",
    "subcutaneous",
    "transdermal",
    "rectal",
    "other",
}
# Ceiling for an acute dose-effect duration phase (minutes). 48h. Anything
# longer is a chronic/therapeutic timescale miscoded into the acute curve —
# it belongs in `durationOfAction` (the long-acting release window) instead.
ACUTE_DURATION_MAX_MINUTES = 48 * 60
DOA_UNITS = {"hours", "days", "weeks", "months"}

SUPPLIED_FORMS = {"lyophilized_vial", "solution", "topical", "implant", "oral_capsule"}
TEMPERATURES = {"room_temp", "refrigerate", "freeze"}
BINDING_ACTIONS = {
    "agonist",
    "partialAgonist",
    "antagonist",
    "inverseAgonist",
    "positiveAllostericModulator",
    "negativeAllostericModulator",
    "reuptakeInhibitor",
    "releasingAgent",
    "enzymeInhibitor",
    "channelBlocker",
    "modulator",
}
#: Valid ``misconceptions[].citations[].role`` values (mirror the iOS
#: ``MythCitation.Role`` enum and sqlite.py's ``_MYTH_ROLES``).
MYTH_ROLES = {"refutes", "retractedSource", "dataset"}
#: Soft cap on curated ``popularAliases`` — the detail header shows ~4.
POPULAR_ALIASES_MAX = 4

_GREEK = {
    "α": "alpha",
    "β": "beta",
    "γ": "gamma",
    "δ": "delta",
    "ε": "epsilon",
    "ζ": "zeta",
    "η": "eta",
    "θ": "theta",
    "κ": "kappa",
    "λ": "lambda",
    "μ": "mu",
    "ν": "nu",
    "ξ": "xi",
    "π": "pi",
    "ρ": "rho",
    "σ": "sigma",
    "τ": "tau",
    "φ": "phi",
    "χ": "chi",
    "ψ": "psi",
    "ω": "omega",
}


def slugify(name: str) -> str:
    """Canonical filename slug for a curated substance. Must stay in lockstep
    with the file layout — `validate_dir` asserts filename stem == slugify(name)."""
    s = (name or "").lower()
    for g, r in _GREEK.items():
        s = s.replace(g, r)
    s = s.replace("+", " plus ")
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "unnamed"


def _norm(s: str) -> str:
    return (s or "").lower().replace(" ", "").replace("-", "").replace(",", "")


def _validate_entry(e: dict, fname: str, err, warn) -> None:
    tag = f"{fname}"
    # Only `name` is mandatory. A file may be a full definition OR an
    # override-only record (e.g. just a popularity score or display name for a
    # scraped substance) — so category/defaultRoute/routes are optional.
    if "name" not in e:
        err.append(f"{tag}: missing required field 'name'")
    name = e.get("name", "")
    if not name:
        err.append(f"{tag}: empty name")
    if "category" in e and e["category"] not in CATEGORIES:
        err.append(f"{tag}: bad category {e.get('category')!r}")
    if "extraCategories" in e:
        ec = e["extraCategories"]
        if not isinstance(ec, list):
            err.append(f"{tag}: extraCategories must be a list")
        else:
            for c in ec:
                if c not in CATEGORIES:
                    err.append(f"{tag}: bad extraCategories entry {c!r}")
                if c == e.get("category"):
                    err.append(f"{tag}: extraCategories duplicates primary category {c!r}")
    if "aliases" in e and not isinstance(e["aliases"], list):
        err.append(f"{tag}: aliases must be a list")
    if e.get("defaultRoute") and _normalise_route(e["defaultRoute"]) not in ROUTES:
        err.append(f"{tag}: bad defaultRoute {e.get('defaultRoute')!r}")
    if "popularity" in e:
        p = e["popularity"]
        if not isinstance(p, (int, float)) or not (0.0 <= float(p) <= 1.0):
            err.append(f"{tag}: popularity must be a number in [0, 1], got {p!r}")
    if "displayName" in e and not (isinstance(e["displayName"], str) and e["displayName"].strip()):
        err.append(f"{tag}: displayName must be a non-empty string")
    route_set = set()
    for r in e.get("routes", []) or []:
        if not isinstance(r, dict):
            err.append(f"{tag}: route entry is not an object")
            continue
        rt = _normalise_route(r.get("route", ""))
        if rt not in ROUTES:
            err.append(f"{tag}: bad route {r.get('route')!r}")
        route_set.add(rt)
        for tier in ("light", "common", "strong"):
            rg = (r.get("doses") or {}).get(tier)
            if rg is not None:
                if not (isinstance(rg, dict) and "lower" in rg and "upper" in rg):
                    err.append(f"{tag}: doses.{tier} must be {{lower, upper}}")
                elif rg["lower"] > rg["upper"]:
                    err.append(f"{tag}: doses.{tier} lower > upper ({rg['lower']} > {rg['upper']})")
        if "source" in r and not (isinstance(r["source"], str) and r["source"].strip()):
            err.append(f"{tag}: route 'source' must be a non-empty reference string")
        pd = r.get("protocolDosing")
        if pd is not None and not pd.get("frequency"):
            err.append(
                f"{tag}: protocolDosing on {r.get('route')!r} has no 'frequency' (would be dropped at build)"
            )
        if (
            pd is not None
            and "source" in pd
            and not (isinstance(pd["source"], str) and pd["source"].strip())
        ):
            err.append(f"{tag}: protocolDosing 'source' must be a non-empty reference string")
        for st in (pd or {}).get("titration", []) or []:
            if "amount" not in st or "label" not in st:
                err.append(f"{tag}: titration step needs amount + label")
        dur = r.get("duration")
        if dur:
            for ph, v in dur.items():
                if not (isinstance(v, dict) and "min" in v and "max" in v):
                    err.append(f"{tag}: duration.{ph} must be {{min, max}}")
                    continue
                # `duration` is the ACUTE dose-effect timeline in MINUTES. Values
                # above ~48h mean a chronic/therapeutic timescale got miscoded
                # here (e.g. an SSRI's 2-week onset, a depot's monthly interval).
                # Those don't describe a single dose's felt curve — leave
                # `duration` off entirely so the dose logs as a marker.
                hi = max(v.get("min") or 0, v.get("max") or 0)
                if hi > ACUTE_DURATION_MAX_MINUTES:
                    err.append(
                        f"{tag}: duration.{ph} = {hi} min exceeds the acute ceiling "
                        f"({ACUTE_DURATION_MAX_MINUTES} min / 48h) — this is a chronic "
                        f"timescale, not an acute dose curve; put it in durationOfAction",
                    )
        doa = r.get("durationOfAction")
        if doa is not None:
            if not (isinstance(doa, dict) and "min" in doa and "max" in doa):
                err.append(f"{tag}: durationOfAction must be {{min, max, unit}}")
            elif str(doa.get("unit", "days")).lower() not in DOA_UNITS:
                err.append(f"{tag}: durationOfAction.unit must be one of {sorted(DOA_UNITS)}")
    # defaultRoute ideally has a matching route entry (UI default resolution).
    if e.get("defaultRoute") and route_set and _normalise_route(e["defaultRoute"]) not in route_set:
        warn.append(f"{tag}: defaultRoute {e['defaultRoute']!r} has no matching route entry")
    pp = e.get("peptideProfile")
    if pp is not None:
        if pp.get("suppliedForm") and pp["suppliedForm"] not in SUPPLIED_FORMS:
            err.append(f"{tag}: bad peptideProfile.suppliedForm {pp['suppliedForm']!r}")
        st = pp.get("storage")
        if st and st.get("temperature") not in TEMPERATURES:
            err.append(f"{tag}: bad storage.temperature {st.get('temperature')!r}")
        if e.get("category") != "Peptide":
            warn.append(
                f"{tag}: has peptideProfile but category is {e.get('category')!r}, not 'Peptide'"
            )
    if "halfLifeSource" in e and not (
        isinstance(e["halfLifeSource"], str) and e["halfLifeSource"].strip()
    ):
        err.append(f"{tag}: halfLifeSource must be a non-empty reference string")
    moa = e.get("mechanismOfAction")
    if moa is not None:
        for b in moa.get("bindings", []) or []:
            if b.get("action") not in BINDING_ACTIONS:
                err.append(f"{tag}: bad binding action {b.get('action')!r}")
            if b.get("affinity") not in (1, 2, 3):
                err.append(f"{tag}: binding affinity must be 1/2/3, got {b.get('affinity')!r}")
    # Curated editorial content (detail-header aliases + cited misconceptions).
    if "popularAliases" in e:
        aka = e["popularAliases"]
        if not isinstance(aka, list):
            err.append(f"{tag}: popularAliases must be a list")
        else:
            for a in aka:
                if not (isinstance(a, str) and a.strip()):
                    err.append(f"{tag}: popularAliases entries must be non-empty strings")
            if len(aka) > POPULAR_ALIASES_MAX:
                warn.append(
                    f"{tag}: {len(aka)} popularAliases — the header shows ~{POPULAR_ALIASES_MAX}; "
                    f"trim to the best-known names"
                )
    if "misconceptions" in e:
        myths = e["misconceptions"]
        if not isinstance(myths, list):
            err.append(f"{tag}: misconceptions must be a list")
        else:
            for i, m in enumerate(myths):
                mtag = f"{tag}: misconceptions[{i}]"
                if not isinstance(m, dict):
                    err.append(f"{mtag} must be an object")
                    continue
                if not (isinstance(m.get("claim"), str) and m["claim"].strip()):
                    err.append(f"{mtag} needs a non-empty 'claim'")
                if not (isinstance(m.get("correction"), str) and m["correction"].strip()):
                    err.append(f"{mtag} needs a non-empty 'correction'")
                cites = m.get("citations")
                # THE contract: an uncited myth-bust is just a counter-assertion.
                if not (isinstance(cites, list) and cites):
                    err.append(f"{mtag} must have at least one citation")
                    cites = []
                for j, c in enumerate(cites):
                    ctag = f"{mtag}.citations[{j}]"
                    if not isinstance(c, dict):
                        err.append(f"{ctag} must be an object")
                        continue
                    if not (isinstance(c.get("ref"), str) and c["ref"].strip()):
                        err.append(f"{ctag} needs a non-empty 'ref' reference string")
                    if "role" in c and c["role"] not in MYTH_ROLES:
                        err.append(
                            f"{ctag} bad role {c.get('role')!r} (one of {sorted(MYTH_ROLES)})"
                        )
                    if "note" in c and not (isinstance(c["note"], str) and c["note"].strip()):
                        err.append(f"{ctag} 'note' must be a non-empty string when present")
                pq = m.get("pullQuote")
                if pq is not None:
                    if not isinstance(pq, dict):
                        err.append(f"{mtag}.pullQuote must be an object")
                    elif not (
                        isinstance(pq.get("text"), str)
                        and pq["text"].strip()
                        and isinstance(pq.get("attribution"), str)
                        and pq["attribution"].strip()
                    ):
                        err.append(f"{mtag}.pullQuote needs non-empty 'text' and 'attribution'")
    # Advisory provenance norm: a substantive quantitative claim (dose ladder,
    # protocol, or half-life) should cite at least one reference somewhere
    # (substance `sources`, mechanism `references`, or a per-fact `source`).
    has_quant = e.get("halfLifeMinutes") is not None or any(
        (r.get("doses") or {}) or r.get("protocolDosing") for r in (e.get("routes") or [])
    )
    has_provenance = bool(
        e.get("sources")
        or (moa or {}).get("references")
        or any(
            r.get("source") or (r.get("protocolDosing") or {}).get("source")
            for r in (e.get("routes") or [])
        )
        or e.get("halfLifeSource")
    )
    if has_quant and not has_provenance:
        warn.append(
            f"{tag}: has dosing/half-life data but no references (add `sources` or a per-fact `source`)"
        )


def validate_dir(directory: Path = CURATED_DIR):
    """Returns (errors, warnings). errors are blocking; warnings are advisory."""
    err: list[str] = []
    warn: list[str] = []
    if not directory.is_dir():
        return [f"curated directory not found: {directory}"], warn
    by_norm: dict[str, str] = {}
    for fp in sorted(directory.glob("*.json")):
        try:
            e = json.loads(fp.read_text())
        except ValueError as exc:
            err.append(f"{fp.name}: invalid JSON ({exc})")
            continue
        if not isinstance(e, dict):
            err.append(f"{fp.name}: top-level must be a JSON object")
            continue
        _validate_entry(e, fp.name, err, warn)
        name = e.get("name", "")
        # Filename must equal slugify(name): else the file is unfindable by name
        # and re-splitting would silently create a duplicate.
        if name and fp.stem != slugify(name):
            err.append(f"{fp.name}: filename does not match slugify({name!r}) = {slugify(name)!r}")
        # No two files may describe the same compound (normalised name collision
        # → silent fact-merge onto one substance at build).
        k = _norm(name)
        if k and k in by_norm:
            err.append(f"{fp.name}: duplicate compound {name!r} also in {by_norm[k]}")
        elif k:
            by_norm[k] = fp.name
    return err, warn


def main() -> int:
    err, warn = validate_dir()
    n = len(list(CURATED_DIR.glob("*.json"))) if CURATED_DIR.is_dir() else 0
    print(f"Validated {n} curated files: {len(err)} errors, {len(warn)} warnings")
    for w in warn:
        print(f"  ⚠ {w}")
    for e in err:
        print(f"  ✘ {e}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
