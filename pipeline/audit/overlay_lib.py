#!/usr/bin/env python3
"""Shared core for auditing the hand-curated substance overlay.

The overlay (``data/curated/substances/*.json``) is ingested as the highest-
priority source ``piru-curated``; every field it sets overrides whatever the
scraped sources independently provide. This module is the single source of truth
for *reading* both sides of that override — used by:

  * ``survey_curated_overlay.py``  — structural inventory / classification
  * ``tests/test_overlay_integrity.py`` — build-pipeline integrity gate
  * ``clean_curated_overlay.py``   — deadweight/false-data removal + flagging

Design notes learned the hard way:

  * **Chemical identity, not names.** Name/alias matching produces false
    "duplicate" signals — upstream aliases can point to a *different* canonical
    entity (e.g. "THC" is an alias of *Cannabis* in PW/TripSit, not the isolated
    cannabinoid). The robust identity key is the exact InChIKey. Only *exact*
    InChIKey collisions are merge/corruption bugs; shared connectivity-blocks
    (first 14 chars) are legitimate stereoisomer/salt families and must be left
    alone.
  * **Resolve curated→DB via aliases.** A curated file named "3-CMC" merges into
    canonical "3-Chloromethcathinone" (3-CMC becomes an alias). Looking up by the
    curated name alone misses ~25 files; the alias index closes that gap.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
CURATED_DIR = REPO / "data/curated/substances"
SOURCES_DIR = REPO / "data/sources"

CURATED_SOURCE = "piru-curated"

# Relative tolerance for calling two numeric values "the same". Dose/duration
# numbers are curated to 1-2 significant figures; within 2% is a match.
REL_TOL = 0.02

# The eight dose-ladder columns, in stored order.
DOSE_COLS = (
    "threshold",
    "light_lower",
    "light_upper",
    "common_lower",
    "common_upper",
    "strong_lower",
    "strong_upper",
    "heavy",
)

# Import the build's exact helpers so lookup keys match the DB byte-for-byte and
# curated-file gating matches the ingest. Re-exported for the survey/clean/test
# entry points (which import them from here, not from sqlite directly).
sys.path.insert(0, str(REPO / "pipeline/build"))
from sqlite import is_chemistry_noise, normalise  # noqa: E402, F401  (re-export; import-safe)


def raw_norm(s: str) -> str:
    """Loose fallback normalisation (lower + collapse ws) for a second lookup
    pass when the build's normalise() doesn't line up (e.g. raw alias text)."""
    return " ".join((s or "").lower().split())


# ---------------------------------------------------------------------------
# Numeric comparison
# ---------------------------------------------------------------------------
def close(a: float | None, b: float | None) -> bool:
    """True if both None, or both present and within REL_TOL (or both ~0)."""
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False
    if a == b:
        return True
    scale = max(abs(a), abs(b))
    if scale == 0:
        return True
    return abs(a - b) / scale <= REL_TOL


def tuples_match(c: tuple, u: tuple) -> bool:
    return len(c) == len(u) and all(close(x, y) for x, y in zip(c, u, strict=True))


def round_sig(x: float | None) -> float | None:
    return None if x is None else round(x, 3)


# ---------------------------------------------------------------------------
# DB extraction
# ---------------------------------------------------------------------------
def load_db(con: sqlite3.Connection) -> dict:
    """Return a rich model of the built DB:

        {
          "by_id":   {sid: rec},
          "by_norm": {normalized_name: rec},
          "by_alias":{alias_norm: rec},       # includes raw-lower alias keys
          "sources": {slug: id},
        }

    Each ``rec`` carries per-source facts for the override surface:
        doses[route][source]     = (unit, dose-tuple)
        durations[route][source] = {phase: (min, max)}
        category[source]         = str
        halflife[source]         = float minutes
        moa[source]              = summary str
        plus: name, norm, inchikey, pubchem_cid, and the set of contributing
        non-curated sources.
    """
    src_name = {row[0]: row[1] for row in con.execute("SELECT id, slug FROM sources")}
    src_id = {v: k for k, v in src_name.items()}

    by_id: dict[int, dict] = {}
    by_norm: dict[str, dict] = {}
    for sid, name, norm, ik, cid in con.execute(
        "SELECT id, canonical_name, normalized_name, inchikey, pubchem_cid FROM substances"
    ):
        rec = {
            "id": sid,
            "name": name,
            "norm": norm,
            "inchikey": ik,
            "pubchem_cid": cid,
            "doses": defaultdict(dict),
            "durations": defaultdict(lambda: defaultdict(dict)),
            "category": {},
            "halflife": {},
            "moa": {},
            "sources": set(),
        }
        by_id[sid] = rec
        by_norm[norm] = rec

    def mark(sid, source):
        if sid in by_id:
            by_id[sid]["sources"].add(source)

    dose_q = f"SELECT substance_id, route, source_id, unit, {', '.join(DOSE_COLS)} FROM dose_ranges"
    for row in con.execute(dose_q):
        sid, route, source_id, unit = row[0], row[1], row[2], row[3]
        if sid not in by_id:
            continue
        src = src_name[source_id]
        by_id[sid]["doses"][route][src] = (unit, tuple(row[4:]))
        mark(sid, src)

    for sid, route, source_id, phase, mn, mx in con.execute(
        "SELECT substance_id, route, source_id, phase, min_minutes, max_minutes FROM durations"
    ):
        if sid not in by_id:
            continue
        src = src_name[source_id]
        by_id[sid]["durations"][route][src][phase] = (mn, mx)
        mark(sid, src)

    for sid, source_id, category in con.execute(
        "SELECT substance_id, source_id, category FROM categories"
    ):
        if sid not in by_id:
            continue
        src = src_name[source_id]
        by_id[sid]["category"][src] = category
        mark(sid, src)

    for sid, source_id, minutes in con.execute(
        "SELECT substance_id, source_id, half_life_minutes FROM half_lives"
    ):
        if sid not in by_id:
            continue
        src = src_name[source_id]
        by_id[sid]["halflife"][src] = minutes
        mark(sid, src)

    for sid, source_id, summary in con.execute(
        "SELECT substance_id, source_id, summary FROM mechanisms_summary WHERE language='en'"
    ):
        if sid not in by_id:
            continue
        src = src_name[source_id]
        by_id[sid]["moa"][src] = (summary or "").strip()
        mark(sid, src)

    by_alias: dict[str, dict] = {}
    for sid, alias, alias_norm in con.execute(
        "SELECT substance_id, alias, alias_normalized FROM aliases"
    ):
        rec = by_id.get(sid)
        if rec is None:
            continue
        by_alias.setdefault(alias_norm, rec)
        by_alias.setdefault(raw_norm(alias), rec)

    return {"by_id": by_id, "by_norm": by_norm, "by_alias": by_alias, "sources": src_id}


def resolve(db: dict, name: str, aliases: list[str] | None = None) -> dict | None:
    """Resolve a curated name (+ its aliases) to a DB rec, trying the build's
    normalise, then a loose norm, then the alias index on all candidates."""
    aliases = aliases or []
    for cand in [name, *aliases]:
        if not cand:
            continue
        for key in (normalise(cand), raw_norm(cand)):
            rec = db["by_norm"].get(key) or db["by_alias"].get(key)
            if rec is not None:
                return rec
    return None


# ---------------------------------------------------------------------------
# Curated-file field extraction
# ---------------------------------------------------------------------------
def dose_tuple(doses: dict) -> tuple:
    def rng(key, end):
        v = doses.get(key)
        return v.get(end) if isinstance(v, dict) else None

    return (
        doses.get("threshold"),
        rng("light", "lower"),
        rng("light", "upper"),
        rng("common", "lower"),
        rng("common", "upper"),
        rng("strong", "lower"),
        rng("strong", "upper"),
        doses.get("heavy"),
    )


def duration_dict(dur: dict) -> dict:
    out = {}
    for phase, v in dur.items():
        if isinstance(v, dict) and "min" in v and "max" in v:
            out[phase] = (v["min"], v["max"])
    return out


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
def classify_scalar(curated, upstream: dict, eq) -> dict:
    others = {s: v for s, v in upstream.items() if s != CURATED_SOURCE}
    if not others:
        return {"verdict": "ABSENT", "curated": curated, "upstream": {}}
    for src, val in others.items():
        if eq(curated, val):
            return {
                "verdict": "MATCH",
                "curated": curated,
                "matched_source": src,
                "upstream": others,
            }
    return {"verdict": "DIVERGE", "curated": curated, "upstream": others}


def classify_dose(unit, ctuple, upstream_doses: dict) -> dict:
    others = {s: v for s, v in upstream_doses.items() if s != CURATED_SOURCE}
    if not others:
        return {"verdict": "ABSENT", "curated": ctuple, "unit": unit, "upstream": {}}
    for src, (u_unit, u_vals) in others.items():
        if u_unit == unit and tuples_match(ctuple, u_vals):
            return {
                "verdict": "MATCH",
                "curated": ctuple,
                "unit": unit,
                "matched_source": src,
                "upstream": {s: v[1] for s, v in others.items()},
            }
    return {
        "verdict": "DIVERGE",
        "curated": ctuple,
        "unit": unit,
        "upstream": {s: v[1] for s, v in others.items()},
    }


def classify_duration(cdur: dict, upstream_dur: dict) -> dict:
    others = {s: v for s, v in upstream_dur.items() if s != CURATED_SOURCE}
    if not others:
        return {"verdict": "ABSENT", "curated": cdur, "upstream": {}}
    for src, u_phases in others.items():
        shared = set(cdur) & set(u_phases)
        if shared and all(
            close(cdur[p][0], u_phases[p][0]) and close(cdur[p][1], u_phases[p][1]) for p in shared
        ):
            return {"verdict": "MATCH", "curated": cdur, "matched_source": src, "upstream": others}
    return {"verdict": "DIVERGE", "curated": cdur, "upstream": others}


# ---------------------------------------------------------------------------
# Curated file iteration
# ---------------------------------------------------------------------------
def load_curated_files() -> list[tuple[Path, dict]]:
    out = []
    for fp in sorted(CURATED_DIR.glob("*.json")):
        try:
            out.append((fp, json.loads(fp.read_text())))
        except (ValueError, OSError):
            out.append((fp, None))
    return out


def analyze_file(entry: dict, rec: dict | None) -> dict:
    """Classify every overriding field of one curated entry against its DB rec.
    Returns {fields, verdict_counts, dose_fingerprints, dur_fingerprints}."""
    fields: dict = {}
    dose_fps: list = []
    dur_fps: list = []

    if entry.get("category"):
        fields["category"] = classify_scalar(
            entry["category"], rec["category"] if rec else {}, lambda a, b: a == b
        )
    if entry.get("halfLifeMinutes") is not None:
        fields["halflife"] = classify_scalar(
            float(entry["halfLifeMinutes"]), rec["halflife"] if rec else {}, close
        )
    moa = entry.get("mechanismOfAction") or {}
    csummary = (moa.get("summary") or moa.get("description") or "").strip()
    if csummary:
        fields["moa"] = classify_scalar(csummary, rec["moa"] if rec else {}, lambda a, b: a == b)

    route_fields: dict = {}
    for r in entry.get("routes") or []:
        if not isinstance(r, dict):
            continue
        route = r.get("route", "")
        unit = r.get("unit", "mg")
        rf: dict = {}
        doses = r.get("doses") or {}
        if doses:
            ctuple = dose_tuple(doses)
            if any(v is not None for v in ctuple):
                up = rec["doses"].get(route, {}) if rec else {}
                rf["doses"] = classify_dose(unit, ctuple, up)
                dose_fps.append(((unit, tuple(round_sig(v) for v in ctuple)), route))
        dur = r.get("duration") or {}
        cdur = duration_dict(dur)
        if cdur:
            up = rec["durations"].get(route, {}) if rec else {}
            rf["duration"] = classify_duration(cdur, up)
            dur_fps.append(
                (
                    (
                        route,
                        tuple(
                            sorted((p, round_sig(a), round_sig(b)) for p, (a, b) in cdur.items())
                        ),
                    ),
                    route,
                )
            )
        if rf:
            route_fields[route] = rf
    if route_fields:
        fields["routes"] = route_fields

    counts: dict[str, int] = defaultdict(int)
    for key, val in fields.items():
        if key == "routes":
            for rf in val.values():
                for res in rf.values():
                    counts[res["verdict"]] += 1
        else:
            counts[val["verdict"]] += 1

    return {
        "fields": fields,
        "verdict_counts": dict(counts),
        "dose_fingerprints": dose_fps,
        "dur_fingerprints": dur_fps,
    }


# ---------------------------------------------------------------------------
# Cross-substance / cross-family analysis
# ---------------------------------------------------------------------------
def resolved_category(entry: dict, rec: dict | None) -> str | None:
    """The category the app would display: the curated file's own category wins
    (it is highest priority); otherwise the best non-curated source's."""
    if entry.get("category"):
        return entry["category"]
    if not rec:
        return None
    cats = rec["category"]
    if CURATED_SOURCE in cats:
        return cats[CURATED_SOURCE]
    return next(iter(cats.values()), None)


def inchikey_duplicates(db: dict) -> list[dict]:
    """Exact-InChIKey collisions across DISTINCT substance rows. Each is either a
    merge failure (same compound, two rows) or identifier corruption (two
    different compounds sharing a wrong InChIKey). Connectivity-block matches are
    deliberately NOT reported — those are legitimate stereoisomer families."""
    groups: dict[str, list] = defaultdict(list)
    for rec in db["by_id"].values():
        ik = rec.get("inchikey")
        if ik and len(ik) >= 27:  # full standard InChIKey (14-1-1 blocks)
            groups[ik].append(rec["name"])
    out = []
    for ik, names in groups.items():
        if len(names) > 1:
            out.append({"inchikey": ik, "substances": sorted(names)})
    return sorted(out, key=lambda g: (-len(g["substances"]), g["inchikey"]))


# Recognized isomer-code conventions, matched against a variant's name to guess
# its stereo code + display name relative to the racemate/parent. Order matters:
# longer/more-specific prefixes first. This only SEEDS the curated fold map — a
# human confirms each family (some connectivity-block twins are regioisomers or
# false InChIKey collisions, NOT enantiomers to fold). See
# Specs/stereoisomer-and-release-form-axes.md.
_ISOMER_PREFIXES = [
    ("es", "S"),  # Esketamine, Escitalopram, Eszopiclone
    ("ar", "R"),  # Armodafinil
    ("dex", "D"),  # Dexmethylphenidate, Dextroamphetamine, Dextromethorphan
    ("dextro", "D"),
    ("levo", "L"),  # Levomethorphan, Levomilnacipran
    ("lev", "L"),  # Levetiracetam (note: false-ish; human-gated)
    ("r-(-)-", "R"),
    ("s-(+)-", "S"),
    ("r-", "R"),
    ("s-", "S"),
    ("d-", "D"),
    ("l-", "L"),
]


def _guess_isomer_code(variant: str, parent: str) -> str | None:
    """Best-effort stereo code for `variant` relative to `parent`, from its name
    prefix. Returns None when no convention matches (human must supply)."""
    v = variant.lower().strip()
    p = parent.lower().strip()
    for prefix, code in _ISOMER_PREFIXES:
        if v.startswith(prefix) and v != p:
            return code
    return None


def isomer_families(db: dict) -> list[dict]:
    """Candidate stereoisomer families to fold under one parent with an isomer
    selector — the raw material for `_ISOMER_FAMILIES` in the build.

    Clusters substance rows by InChIKey *connectivity block* (first 14 chars =
    same 2D skeleton, differing only in stereo/charge layer). A cluster of ≥2 is
    a fold candidate: same molecule, different chirality (Ketamine/Esketamine,
    Citalopram/Escitalopram, the enantiomer pairs). For each cluster it nominates
    a `parent` (the member whose name is a prefix-substring of the others, i.e.
    the racemate — else the shortest name) and tags each variant with a guessed
    isomer code + display name.

    This is a PROPOSAL, not ground truth: connectivity twins can be regioisomers
    or InChIKey false-collisions that must NOT be folded, so every family is
    human-gated before entering the curated map. Exact-InChIKey collisions are
    reported separately by inchikey_duplicates() (those are merge/corruption
    bugs, not stereo families)."""
    blocks: dict[str, list[dict]] = defaultdict(list)
    for rec in db["by_id"].values():
        ik = rec.get("inchikey")
        if ik and len(ik) >= 14:
            blocks[ik[:14]].append(rec)

    families = []
    for blk, recs in blocks.items():
        names = sorted({r["name"] for r in recs})
        if len(names) < 2:
            continue
        # Distinct FULL InChIKeys in the block: 1 => same stereo (a merge bug, not
        # a stereo family); ≥2 => genuine stereo variants worth folding.
        full_keys = {r["inchikey"] for r in recs}
        if len(full_keys) < 2:
            continue
        parent = _nominate_parent(names)
        variants = []
        for n in names:
            if n == parent:
                continue
            variants.append({"name": n, "isomer": _guess_isomer_code(n, parent), "display": n})
        families.append(
            {
                "connectivity": blk,
                "parent": parent,
                "variants": variants,
                "all_names": names,
                "needs_code": [v["name"] for v in variants if v["isomer"] is None],
            }
        )
    return sorted(families, key=lambda f: (-len(f["all_names"]), f["parent"]))


def _nominate_parent(names: list[str]) -> str:
    """Pick the racemate/parent: prefer a name that is a case-insensitive
    substring of every other (the bare stem, e.g. "Ketamine" ⊂ "Esketamine"),
    else the shortest name."""
    for cand in sorted(names, key=len):
        stem = cand.lower()
        if all(stem in other.lower() for other in names if other != cand):
            return cand
    return min(names, key=len)


def pubchem_cid_duplicates(db: dict) -> list[dict]:
    groups: dict[int, list] = defaultdict(list)
    for rec in db["by_id"].values():
        cid = rec.get("pubchem_cid")
        if cid:
            groups[cid].append(rec["name"])
    return sorted(
        ({"cid": cid, "substances": sorted(n)} for cid, n in groups.items() if len(n) > 1),
        key=lambda g: (-len(g["substances"]), g["cid"]),
    )


# ---------------------------------------------------------------------------
# Chemical-family heuristic (for clone-cluster triage)
# ---------------------------------------------------------------------------
# A shared dose/duration block is only *suspicious* if it spans substances that
# are not plausibly the same dosing family. We approximate "same family" by a
# coarse name-stem: strip common NPS positional/greek/halogen prefixes so
# "3-CMC"/"4-CMC" or "Delta-8-THC"/"Delta-10-THC" read as one family, while
# "2-Fluorodeschloroketamine"/"Lithium orotate" read as two.
import re  # noqa: E402

_FAMILY_STRIP = re.compile(
    r"^(?:\d+[a-z]?[-,]?|alpha|beta|gamma|delta|dl|d|l|r|s|n|o|"
    r"iso|nor|meth|di|tri|tetra|penta|[2-6][a-z]?-?)+[\s-]*",
    re.IGNORECASE,
)


def family_stem(name: str) -> str:
    n = re.sub(r"[^a-z0-9]", "", normalise(name))
    stripped = _FAMILY_STRIP.sub("", n)
    return stripped or n


def cross_family(names: list[str]) -> bool:
    """True if a set of substances sharing one block spans ≥2 dissimilar stems —
    a copy-paste / template signal rather than a real family default."""
    stems = {family_stem(n) for n in names}
    return len(stems) >= 2


def clone_clusters(fps: dict, category_of: dict) -> list[dict]:
    """Group dose/duration fingerprints into clone clusters — the build/curation
    smell where ≥2 substances carry an identical dose or duration profile.

    Single source of truth for the survey report, the clean tool, and the
    overlay-integrity test, which previously each re-derived the same rule.

    ``fps`` maps a fingerprint key to a list of ``(substance, route)`` members;
    ``category_of`` maps a substance name to its resolved category. Returns one
    dict per cluster of ≥2 distinct substances — **cross-category clusters
    first** (near-certain copy bugs), then by descending size — each carrying:
    ``block``, ``members`` (the raw ``(substance, route)`` list), ``substances``
    (sorted unique), ``categories`` (sorted unique resolved), ``cross_category``
    (spans ≥2 categories) and ``cross_family`` (spans ≥2 name-stems)."""
    out = []
    for key, members in fps.items():
        subs = sorted({s for s, _ in members})
        if len(subs) < 2:
            continue
        cats = sorted({category_of.get(s) for s in subs if category_of.get(s)})
        out.append(
            {
                "block": key,
                "members": list(members),
                "substances": subs,
                "categories": cats,
                "cross_category": len(cats) >= 2,
                "cross_family": cross_family(subs),
            }
        )
    return sorted(out, key=lambda c: (not c["cross_category"], -len(c["substances"])))
