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
        spec = importlib.util.spec_from_file_location("_bsd_routes", Path(__file__).resolve().parent / "sqlite.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _normalise_route._fn = mod.normalise_route
    return _normalise_route._fn(route or "")

CATEGORIES = {"Stimulant", "Psychedelic", "Dissociative", "Dysdelic", "Deliriant", "Opioid",
    "Benzodiazepine", "GABAergic", "Empathogen", "Cannabinoid", "Nootropic", "AMPAkine",
    "Eugeroic", "Depressant", "Antidepressant", "Antipsychotic", "Analgesic", "Antihistamine",
    "Cardiovascular", "Antimicrobial", "Gastrointestinal", "Respiratory", "Endocrine",
    "Immunological", "Supplement", "Peptide", "Anticonvulsant", "Other"}
ROUTES = {"oral", "sublingual", "insufflation", "inhalation", "intravenous", "intramuscular",
    "subcutaneous", "transdermal", "rectal", "other"}
SUPPLIED_FORMS = {"lyophilized_vial", "solution", "topical", "implant", "oral_capsule"}
TEMPERATURES = {"room_temp", "refrigerate", "freeze"}
BINDING_ACTIONS = {"agonist", "partialAgonist", "antagonist", "inverseAgonist",
    "positiveAllostericModulator", "negativeAllostericModulator", "reuptakeInhibitor",
    "releasingAgent", "enzymeInhibitor", "channelBlocker", "modulator"}

_GREEK = {"α":"alpha","β":"beta","γ":"gamma","δ":"delta","ε":"epsilon","ζ":"zeta","η":"eta",
    "θ":"theta","κ":"kappa","λ":"lambda","μ":"mu","ν":"nu","ξ":"xi","π":"pi","ρ":"rho",
    "σ":"sigma","τ":"tau","φ":"phi","χ":"chi","ψ":"psi","ω":"omega"}


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
    for k in ("name", "aliases", "category", "defaultRoute", "routes"):
        if k not in e:
            err.append(f"{tag}: missing required field '{k}'")
    name = e.get("name", "")
    if not name:
        err.append(f"{tag}: empty name")
    if e.get("category") not in CATEGORIES:
        err.append(f"{tag}: bad category {e.get('category')!r}")
    if e.get("defaultRoute") and _normalise_route(e["defaultRoute"]) not in ROUTES:
        err.append(f"{tag}: bad defaultRoute {e.get('defaultRoute')!r}")
    if not isinstance(e.get("aliases", []), list):
        err.append(f"{tag}: aliases must be a list")
    route_set = set()
    for r in e.get("routes", []) or []:
        if not isinstance(r, dict):
            err.append(f"{tag}: route entry is not an object"); continue
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
        pd = r.get("protocolDosing")
        if pd is not None and not pd.get("frequency"):
            err.append(f"{tag}: protocolDosing on {r.get('route')!r} has no 'frequency' (would be dropped at build)")
        for st in (pd or {}).get("titration", []) or []:
            if "amount" not in st or "label" not in st:
                err.append(f"{tag}: titration step needs amount + label")
        dur = r.get("duration")
        if dur:
            for ph, v in dur.items():
                if not (isinstance(v, dict) and "min" in v and "max" in v):
                    err.append(f"{tag}: duration.{ph} must be {{min, max}}")
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
            warn.append(f"{tag}: has peptideProfile but category is {e.get('category')!r}, not 'Peptide'")
    moa = e.get("mechanismOfAction")
    if moa is not None:
        for b in moa.get("bindings", []) or []:
            if b.get("action") not in BINDING_ACTIONS:
                err.append(f"{tag}: bad binding action {b.get('action')!r}")
            if b.get("affinity") not in (1, 2, 3):
                err.append(f"{tag}: binding affinity must be 1/2/3, got {b.get('affinity')!r}")


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
            err.append(f"{fp.name}: invalid JSON ({exc})"); continue
        if not isinstance(e, dict):
            err.append(f"{fp.name}: top-level must be a JSON object"); continue
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
