#!/usr/bin/env python3
"""Extract the four ~/Developer/piru-data raw files into
Piru-`Substance`-shaped JSON artifacts, written OUT OF the repo.

These artifacts (and the raw source files) are intentionally kept out of the
repo — only the built SQLite is committed. Run this before `pipeline/build/
sqlite.py`, which reads the JSON from the same out-of-repo directory.

Core fields match the `Substance` Codable struct exactly (so a Swift decoder
accepts each record). Source-unique data that doesn't fit the core model is
preserved under `x_*` keys so nothing is discarded before review.

Reuses `_common.py` (category/route mapping, HTML stripping, range parsing).

Paths (override with env vars):
  PIRU_DATASOURCES — raw input dir   (default ../piru-data, beside the repo)
  PIRU_EXTERNAL_DIR — JSON output dir (default /tmp/piru-extract; must match sqlite.py)
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (  # noqa: E402
    normalize_quantity_text,
    parse_range,
    piru_category,
    piru_route,
    strip_html,
)

# Repo-relative by default: this file is pipeline/fetch/brushers/extract.py, so
# the repo root is parents[3] and the raw datasets live in its sibling
# `../piru-data` (kept out of the public repo). Resolving relative to the
# checkout rather than a hardcoded home path keeps a user folder out of public
# code and finds the data wherever the repo is cloned, as long as piru-data sits
# beside it. Override with PIRU_DATASOURCES if it lives elsewhere.
#
# A wrong path here is not a harmless miss: every ingest_* reader does
# `if not path.exists(): return`, so a silent no-op extract costs ~1150
# indications, ~1658 contraindications, 33 diazepam equivalents and the NPS
# identifier set — and the build still succeeds, just thinner.
_REPO_ROOT = Path(__file__).resolve().parents[3]
DS = Path(os.environ.get("PIRU_DATASOURCES", _REPO_ROOT.parent / "piru-data"))
OUT = Path(os.environ.get("PIRU_EXTERNAL_DIR", "/tmp/piru-extract"))
OUT.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Shared builders for the Substance Codable JSON shape
# ---------------------------------------------------------------------------

_DOSE_RE = re.compile(
    r"(?P<lo>\d+(?:\.\d+)?)(?:\s*(?:-|to)\s*(?P<hi>\d+(?:\.\d+)?))?\s*(?P<unit>µg|ug|mcg|mg|g|ml|iu)?",
    re.IGNORECASE,
)


def parse_dose_cell(text):
    """'0.5-1.5mg' -> (lo, hi, unit). hi is None for single values."""
    if not text:
        return None, None, ""
    m = _DOSE_RE.search(normalize_quantity_text(text).replace(",", ".").strip())
    if not m:
        return None, None, ""
    lo = float(m.group("lo"))
    hi = float(m.group("hi")) if m.group("hi") else None
    unit = (m.group("unit") or "").lower()
    if unit in ("ug", "mcg"):
        unit = "µg"
    return lo, hi, unit


def cr(lo, hi):
    """CodableRange dict, or None."""
    if lo is None:
        return None
    if hi is None:
        hi = lo
    return {"lower": lo, "upper": hi}


def dose_range(threshold=None, light=None, common=None, strong=None, heavy=None):
    """Assemble a DoseRange dict, dropping nil keys (matches Substance encode)."""
    d = {}
    if threshold is not None:
        d["threshold"] = threshold
    if light is not None:
        d["light"] = light
    if common is not None:
        d["common"] = common
    if strong is not None:
        d["strong"] = strong
    if heavy is not None:
        d["heavy"] = heavy
    return d


def to_minutes(text):
    """'5-8 hours' / '15-40 minutes' -> (min, max) in minutes, or (None, None)."""
    lo, hi, unit = parse_range(text)
    if not lo:
        return None, None
    try:
        lo_f = float(lo)
        hi_f = float(hi) if hi else lo_f
    except ValueError:
        return None, None
    if unit.startswith("hour") or unit in ("h", "hr", "hrs"):
        lo_f *= 60
        hi_f *= 60
    return lo_f, hi_f


def dur_range(text):
    lo, hi = to_minutes(text)
    if lo is None:
        return None
    return {"min": lo, "max": hi}


def substance(
    name,
    *,
    aliases=None,
    category="Other",
    default_route="oral",
    routes=None,
    effects=None,
    half_life_minutes=None,
    mechanism=None,
    sources=None,
    tags=None,
    **ext,
):
    """Build one Substance-shaped record + x_* extensions (dropping empties)."""
    rec = {
        "name": name,
        "aliases": aliases or [],
        "category": category,
        "defaultRoute": default_route,
        "routes": routes or [],
        "effects": effects or [],
        "tags": tags or [],
    }
    if half_life_minutes is not None:
        rec["halfLifeMinutes"] = half_life_minutes
    if mechanism:
        rec["mechanismOfAction"] = mechanism
    if sources:
        rec["sources"] = sources
    for k, v in ext.items():
        if v in (None, "", [], {}):
            continue
        rec[f"x_{k}"] = v
    return rec


def write_out(name, records, meta):
    path = OUT / f"{name}.substances.json"
    path.write_text(json.dumps(records, ensure_ascii=False, indent=1))
    cats = Counter(r["category"] for r in records)
    with_dose = sum(1 for r in records if any(rt.get("doses") for rt in r["routes"]))
    with_mech = sum(1 for r in records if r.get("mechanismOfAction"))
    meta[name] = {
        "records": len(records),
        "with_dose_data": with_dose,
        "with_mechanism": with_mech,
        "categories": dict(cats.most_common()),
        "file": str(path),
    }
    print(f"  {name}: {len(records)} records  (dose={with_dose}, mech={with_mech})  -> {path}")


# ---------------------------------------------------------------------------
# benzos-cited.json  — TripSit-shaped, full dose + duration
# ---------------------------------------------------------------------------


def extract_benzos():
    data = json.loads((DS / "benzos-cited.json").read_text())
    out = []
    for e in data:
        name = e.get("pretty_name") or e.get("name")
        if not name:
            continue
        props = e.get("properties") or {}
        aliases = sorted(set((e.get("aliases") or []) + (props.get("aliases") or [])))
        categories = e.get("categories") or props.get("categories") or []
        category = piru_category(categories)
        if category == "Other":
            category = "Benzodiazepine"  # source is benzo-only

        # duration profile (global to the substance in this source)
        onset = dur_range(_fmt_dur(e.get("formatted_onset")))
        total = dur_range(_fmt_dur(e.get("formatted_duration")))
        afterglow = dur_range(_fmt_dur(e.get("formatted_aftereffects")))
        duration = {}
        if onset:
            duration["onset"] = onset
        if total:
            duration["total"] = total
        if afterglow:
            duration["afterglow"] = afterglow
        duration = duration or None

        routes = []
        fd = e.get("formatted_dose") or {}
        route_unit = "mg"
        for raw_route, cells in fd.items():
            route = piru_route(raw_route) or "oral"
            t_lo, _, t_u = parse_dose_cell(cells.get("Threshold"))
            l_lo, l_hi, l_u = parse_dose_cell(cells.get("Light"))
            c_lo, c_hi, c_u = parse_dose_cell(cells.get("Common"))
            s_lo, s_hi, s_u = parse_dose_cell(cells.get("Strong"))
            h_lo, _, h_u = parse_dose_cell(cells.get("Heavy"))
            unit = c_u or l_u or s_u or h_u or t_u or "mg"
            route_unit = unit
            doses = dose_range(
                threshold=t_lo,
                light=cr(l_lo, l_hi),
                common=cr(c_lo, c_hi),
                strong=cr(s_lo, s_hi),
                heavy=h_lo,
            )
            routes.append(
                {
                    "route": route,
                    "unit": unit,
                    "doses": doses,
                    **({"duration": duration} if duration else {}),
                }
            )
        if not routes:
            routes = [
                {
                    "route": "oral",
                    "unit": route_unit,
                    "doses": {},
                    **({"duration": duration} if duration else {}),
                }
            ]

        effects = e.get("formatted_effects") or []
        if not effects and props.get("effects"):
            effects = [x.strip() for x in props["effects"].rstrip(".").split(",") if x.strip()]

        sources = (e.get("sources") or {}).get("_general") or []
        tags = sorted({c.lower() for c in categories})

        out.append(
            substance(
                name,
                aliases=aliases,
                category=category,
                default_route=routes[0]["route"],
                routes=routes,
                effects=effects,
                sources=sources,
                tags=tags,
                source="benzos-cited",
                source_id=str((e.get("_id") or {}).get("$oid", "")),
                diazepam_equivalent_value=e.get("diazvalue"),
                dose_to_diazepam=props.get("dose_to_diazepam"),
                bioavailability=props.get("bioavailability"),
                summary=(props.get("summary") or "").strip(),
                avoid=(props.get("avoid") or "").strip(),
                tolerance=props.get("tolerance"),
                after_effects=props.get("after-effects"),
                dose_note=(e.get("dose_note") or "").strip(),
                pw_effect_links=e.get("pweffects") or None,
            )
        )
    return out


def _fmt_dur(d):
    if not isinstance(d, dict):
        return ""
    v, u = d.get("value"), d.get("_unit")
    return f"{v} {u}" if v is not None and u else ""


# ---------------------------------------------------------------------------
# pyrls — clinical pharma reference (no recreational dose)
# ---------------------------------------------------------------------------


def _txt(x):
    """pyrls list entries are sometimes plain strings, sometimes {text, moreInfo}."""
    if isinstance(x, dict):
        return x.get("text") or x.get("moreInfo") or ""
    return x or ""


def extract_pyrls():
    data = json.loads((DS / "pyrls[N=378].json").read_text())
    out = []
    for e in data:
        name = e.get("genericName")
        if not name:
            continue
        di = e.get("drugInfo") or {}
        labels = e.get("labels") or []
        brands = [b.strip() for b in (e.get("brandNames") or "").split(",") if b.strip()]
        delivery = e.get("delivery") or ""
        route = piru_route(delivery) or "oral"
        pharm = di.get("pharmacology") or {}
        mech_text = strip_html(pharm.get("mechanism"))
        mechanism = (
            {"summary": mech_text, "description": None, "references": []} if mech_text else None
        )
        indications = [
            strip_html(_txt(x)) for x in ((di.get("indications") or {}).get("labeled") or [])
        ]
        contras = [
            strip_html(_txt(x)) for x in ((di.get("contraindications") or {}).get("labeled") or [])
        ]
        # Pyrls numbers its references and points each block at one. Resolving
        # them is what lets a contraindication name the label it came from —
        # these were the only substantive claims in the app with no way to check.
        refs = {r.get("id"): r.get("url") for r in (e.get("references") or []) if r.get("url")}

        def _first_ref(block, refs=refs):
            for rid in (block or {}).get("references") or []:
                if refs.get(rid):
                    return refs[rid]
            return None

        indications_ref = _first_ref(di.get("indications"))
        contras_ref = _first_ref(di.get("contraindications"))
        boxed = [strip_html(_txt(x)) for x in (di.get("boxedWarning") or [])]
        reg = e.get("regulatoryStatus") or {}
        reg_str = "; ".join(
            (reg.get("labels") or []) + ([reg.get("description")] if reg.get("description") else [])
        )
        # Drug-class labels only; the dosageForm string is kept in its own field
        # (dosage_form=) rather than dumped into tags, where it's just chip noise.
        tags = sorted({lbl.lower() for lbl in labels} - {""})

        out.append(
            substance(
                name,
                aliases=brands,
                category=piru_category(labels),
                default_route=route,
                routes=[{"route": route, "unit": "", "doses": {}}],
                effects=[],
                mechanism=mechanism,
                tags=tags,
                source="pyrls",
                source_id=str((e.get("_id") or {}).get("$oid", "")),
                raw_classes=labels,
                brand_names=brands,
                indications=indications,
                indications_reference=indications_ref,
                contraindications=contras,
                contraindications_reference=contras_ref,
                boxed_warning=boxed,
                regulatory_status=reg_str,
                dosage_form=e.get("dosageForm"),
                delivery=delivery,
            )
        )
    return out


# ---------------------------------------------------------------------------
# medtap — FDA structured product labels (dedup by target/unii/generic)
# ---------------------------------------------------------------------------


def _first(v):
    if isinstance(v, list):
        return next((str(x).strip() for x in v if x), "")
    return str(v or "").strip()


def _section(sections, names):
    for sec in sections or []:
        if sec.get("section_name") not in names:
            continue
        txt = strip_html(" ".join(_leaf_texts(sec)))
        if txt:
            return txt
    return ""


def _leaf_texts(sec):
    """Every `text` leaf under `content` / `content_full`, in document order.

    The two keys hold the same label markup in inconsistent shapes across the
    corpus — `content` is a list in most records and a dict in others,
    `content_full` the reverse — so both are walked structurally instead of
    being indexed by an assumed type.
    """
    out = []

    def walk(v):
        if isinstance(v, dict):
            if isinstance(v.get("text"), str):
                out.append(v["text"])
            else:
                for x in v.values():
                    walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)

    walk(sec.get("content"))
    walk(sec.get("content_full"))
    return out


_LABEL_HEADER = re.compile(r"<text class='druglabel_header'>(.*?)</text>", re.S)

# The build rejects a mechanism summary over 1200 characters
# (`MAX_MECHANISM_SUMMARY_CHARS` in pipeline/build/sqlite.py). Trim below that here
# so a label whose Mechanism Of Action field runs long — some carry unmarked
# sub-sections like "Antiviral Activity" after the mechanism itself — still
# contributes its opening mechanism rather than being dropped whole.
_MECHANISM_CHAR_BUDGET = 1000


# Some label bodies repeat their own header as the first words ("Mechanism of Action
# Tenofovir DF is an acyclic nucleoside phosphonate…"), which the header/value split
# cannot see because it is prose, not markup.
_ECHOED_HEADER = re.compile(r"^\s*mechanisms?\s+of\s+action[:\s-]*", re.I)


def _strip_echoed_header(text):
    return _ECHOED_HEADER.sub("", text).strip()


def _leading_sentences(text, budget=_MECHANISM_CHAR_BUDGET):
    """`text` cut at the last sentence end that fits in `budget`."""
    if len(text) <= budget:
        return text
    cut = max(text.rfind(end, 0, budget + 1) for end in (". ", "? ", "! "))
    return text[: cut + 1].strip() if cut > 0 else text[:budget].rsplit(" ", 1)[0].strip()


def _label_fields(sections, section_name):
    """A label section's `header -> body` pairs.

    Medtap's Pharmacology section is a *table*, not prose: alternating
    `<text class='druglabel_header'>Half-life</text>` / `<content>1-4
    hours</content>` leaves. Flattening it (which `_section` does, because
    every other section really is prose) concatenates the headers into the
    body, which is how a mechanism summary came to open with the literal
    words "Mechanism Of Action" and run on through the PK table behind it.
    """
    for sec in sections or []:
        if sec.get("section_name") != section_name:
            continue
        fields, header, body = {}, None, []
        for raw in _leaf_texts(sec):
            match = _LABEL_HEADER.search(raw)
            if match:
                if header and body:
                    fields.setdefault(header, strip_html(" ".join(body)))
                header, body = match.group(1).strip(), []
            elif header:
                body.append(raw)
        if header and body:
            fields.setdefault(header, strip_html(" ".join(body)))
        if fields:
            return fields
    return {}


def extract_medtap():
    data = json.loads((DS / "Medtap-App-Pharma-DB.json").read_text())
    by_key = {}
    aliases_by = {}
    classes_by = {}
    ingredients_by = {}
    for e in data:
        target_raw = e.get("target")
        target = _first(target_raw).lower()
        unii = _first(e.get("unii")).lower()
        generic = _first(e.get("generic_name")).lower()
        key = target or unii or generic
        if not key:
            continue
        if key not in by_key:
            by_key[key] = e
            aliases_by[key] = []
            classes_by[key] = []
            ingredients_by[key] = target_raw if isinstance(target_raw, list) else None
        for fld in ("brand_name", "generic_name"):
            val = _first(e.get(fld))
            if val and val.lower() != key:
                aliases_by[key].append(val)
        cls = e.get("class")
        if isinstance(cls, list):
            classes_by[key].extend(str(c) for c in cls if c)
        elif cls:
            classes_by[key].append(str(cls))

    out = []
    for key, e in by_key.items():
        name = _first(e.get("target")) or _first(e.get("generic_name"))
        if not name:
            continue
        classes = [c for c in classes_by[key] if c and c.upper() != "OTHER"]
        route_str = e.get("route")
        routes_mapped = []
        for c in route_str if isinstance(route_str, list) else [route_str]:
            r = piru_route(c)
            if r and r not in routes_mapped:
                routes_mapped.append(r)
        default_route = routes_mapped[0] if routes_mapped else "oral"
        sections = e.get("sections") or []
        # ONLY the Mechanism Of Action field. The rest of the Pharmacology table is
        # absorption, protein binding, clearance and half-life — real data, but not a
        # mechanism, and a substance whose label carries no mechanism field gets no
        # medtap mechanism rather than its PK table under a mechanism heading.
        pharm = _leading_sentences(
            _strip_echoed_header(
                _label_fields(sections, "Pharmacology").get("Mechanism Of Action", "")
            )
        )
        mechanism = {"summary": pharm, "description": None, "references": []} if pharm else None
        indications = _section(sections, {"Indications"})
        contras = _section(sections, {"Contraindications/Cautions", "Contraindications"})
        rx = _first(e.get("rx")).upper()
        reg = "OTC" if "OTC" in rx else ("Rx" if "PRESCRIPTION" in rx else _first(e.get("rx")))
        combo = ingredients_by[key]

        out.append(
            substance(
                name,
                aliases=sorted(set(aliases_by[key])),
                category=piru_category(classes),
                default_route=default_route,
                routes=[
                    {"route": r, "unit": "", "doses": {}}
                    for r in (routes_mapped or [default_route])
                ],
                effects=[],
                mechanism=mechanism,
                tags=sorted({c.lower() for c in classes}),
                source="medtap",
                source_id=str((e.get("_id") or {}).get("$oid", "")),
                unii=_first(e.get("unii")),
                ndc=e.get("ndc"),
                raw_classes=classes,
                brand_names=sorted(set(aliases_by[key])),
                indications=indications,
                contraindications=contras,
                # The label IS the source for these; its NDC identifies which.
                label_reference=(
                    "https://dailymed.nlm.nih.gov/dailymed/search.cfm?labeltype=all&query="
                    + _first(e.get("ndc"))
                    if _first(e.get("ndc"))
                    else None
                ),
                regulatory_status=reg,
                is_combination=bool(combo and len(combo) > 1),
                ingredients=combo if (combo and len(combo) > 1) else None,
            )
        )
    return out


# ---------------------------------------------------------------------------
# nps-datahub — forensic chemistry catalogue (no pharmacology)
# ---------------------------------------------------------------------------

NPS_POS = {  # blank/duplicate headers -> fixed indices (match brush_nps.py)
    "pk": 0,
    "structure": 2,
    "names": 4,
    "syn1": 5,
    "syn2": 6,
    "iupac": 7,
    "abbr": 8,
    "hierarchy": 9,
    "type": 21,
    "tags": 133,
    "uuid": 138,
    # Melting/boiling point labels appear TWICE in the header: an early hazard
    # block and a later physical-properties block. Label-matching takes the
    # first (hazard) hit, but the physical block has far more coverage (~708 vs
    # 42 melting; ~455 vs 219 boiling), so pin both by position and prefer the
    # physical block at read time, falling back to the hazard block.
    "mp_phys": 117,
    "bp_phys": 118,
    "mp_haz": 58,
    "bp_haz": 26,
}


def _resolve_nps_cols(header):
    cols = dict(NPS_POS)
    for label, key in [
        ("Chemical formula", "formula"),
        ("CAS No.", "cas"),
        ("SMILES", "smiles"),
        ("InChIKey", "inchikey"),
        ("InChI", "inchi"),
        ("MW", "mw"),
        # Physicochemical / forensic columns (Stage 1). These labels are unique
        # in the header, so first-match is correct. logD/pKa/TPSA/HBA/HBD are
        # present-but-empty in the current CSV (PubChem fills those) — wired here
        # so a future CSV that populates them flows through with no code change.
        ("logP", "logp"),
        ("logD", "logd"),
        ("pKa", "pka"),
        ("Topological polar surface area", "tpsa"),
        ("No. of hydrogen bond acceptors", "hba"),
        ("No. of hydrogen bond donors", "hbd"),
        ("LD50 oral", "ld50_oral"),
        ("LD50 dermal", "ld50_dermal"),
    ]:
        for i, h in enumerate(header):
            if h == label:
                cols[key] = i
                break
    return cols


# NPS physicochemical cells carry units, provenance and ranges, e.g.
# "2.40130 (ChemSrc)", "66-70 °C (ChemSrc)", "367.7 mg/kg (Rat; Merck)",
# "&gt; 3900 mg/kg", or a bare "146-152". Pull a single number: a range becomes
# its midpoint, otherwise the first value; the trailing "(source)"/"; secondary"
# annotation is dropped first so a number inside it can't be picked up.
_NPS_RANGE_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*[-–~]\s*(\d+(?:\.\d+)?)")


def _nps_num(raw, *, allow_negative=False):
    if not raw:
        return None
    s = raw.replace("&gt;", ">").replace("&lt;", "<").replace("&amp;", "&")
    s = re.split(r"[(;]", s, maxsplit=1)[0].strip()
    if not s:
        return None
    # Range → midpoint (only when negatives aren't expected; logP is a signed
    # scalar, never a range, so its leading "-" must not be read as a dash).
    if not allow_negative:
        m = _NPS_RANGE_RE.match(s)
        if m:
            return round((float(m.group(1)) + float(m.group(2))) / 2.0, 4)
    m = re.search(r"[-+]?\d+(?:\.\d+)?" if allow_negative else r"\d+(?:\.\d+)?", s)
    return float(m.group()) if m else None


def _nps_int(raw):
    v = _nps_num(raw)
    return int(round(v)) if v is not None else None


def _nps_cell(row, idx):
    return row[idx] if idx is not None and idx < len(row) else None


def _derive_nps_category(tags):
    pool = " ".join(tags).lower()
    table = [
        ("cannabinoid", "Cannabinoid"),
        ("phenethylamine", "Stimulant"),
        ("amphetamin", "Stimulant"),
        ("cathinone", "Stimulant"),
        ("tryptamine", "Psychedelic"),
        ("lysergamide", "Psychedelic"),
        ("arylcyclohexylamine", "Dissociative"),
        ("dissociativ", "Dissociative"),
        ("benzodiazepine", "Benzodiazepine"),
        ("opioid", "Opioid"),
        ("fentanyl", "Opioid"),
        ("piperazine", "Empathogen"),
    ]
    for needle, cat in table:
        if needle in pool:
            return cat
    return piru_category(tags) if tags else "Other"


def _clean_nps_name(raw):
    text = (raw or "").strip()
    for suffix in (" HCl", " HBr", " HF", " sulfate", " sulphate", " tartrate", " citrate"):
        if text.lower().endswith(suffix.lower()):
            return text[: -len(suffix)].strip()
    return text


def extract_nps():
    src = DS / "nps-datahub.com-full-database[N=6405].csv"
    out = []
    seen = set()
    with src.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        C = _resolve_nps_cols(header)
        for row in reader:
            if len(row) <= C["tags"]:
                continue
            name = _clean_nps_name(row[C["names"]])
            if not name:
                continue
            k = name.lower()
            if k in seen:
                continue
            seen.add(k)
            tags_raw = [
                t.strip()
                for t in (row[C["tags"]] or "").split(";")
                if t.strip() and len(t.strip()) <= 80
            ]
            aliases = sorted(
                {a.strip() for a in (row[C["syn1"]], row[C["syn2"]], row[C["abbr"]]) if a.strip()}
            )
            type_str = row[C["type"]].strip()
            hierarchy = row[C["hierarchy"]].strip()
            tags = sorted({*(t.lower() for t in tags_raw), type_str.lower()} - {""})
            # Physicochemical / forensic properties. logP is signed; melting and
            # boiling points prefer the higher-coverage physical-properties block
            # over the hazard-sheet block (see NPS_POS). These are predicted /
            # rodent-assay values, never clinical — carried with the substance's
            # NPS-DataHub source and surfaced as forensic in the app.
            mp = _nps_num(_nps_cell(row, C.get("mp_phys"))) or _nps_num(
                _nps_cell(row, C.get("mp_haz"))
            )
            bp = _nps_num(_nps_cell(row, C.get("bp_phys"))) or _nps_num(
                _nps_cell(row, C.get("bp_haz"))
            )
            out.append(
                substance(
                    name,
                    aliases=aliases,
                    category=_derive_nps_category(tags_raw),
                    default_route="other",
                    routes=[],
                    effects=[],
                    tags=tags,
                    source="nps-datahub",
                    source_id=row[C["uuid"]].strip() or row[C["pk"]].strip(),
                    cas=row[C["cas"]].strip() if "cas" in C else "",
                    chemical_formula=row[C["formula"]].strip() if "formula" in C else "",
                    smiles=row[C["smiles"]].strip() if "smiles" in C else "",
                    inchi=row[C["inchi"]].strip() if "inchi" in C else "",
                    inchikey=row[C["inchikey"]].strip() if "inchikey" in C else "",
                    iupac=row[C["iupac"]].strip(),
                    mw=row[C["mw"]].strip() if "mw" in C else "",
                    type=type_str,
                    hierarchy=hierarchy,
                    raw_classes=tags_raw,
                    logp=_nps_num(_nps_cell(row, C.get("logp")), allow_negative=True),
                    logd=_nps_num(_nps_cell(row, C.get("logd")), allow_negative=True),
                    pka=_nps_num(_nps_cell(row, C.get("pka"))),
                    tpsa=_nps_num(_nps_cell(row, C.get("tpsa"))),
                    hba=_nps_int(_nps_cell(row, C.get("hba"))),
                    hbd=_nps_int(_nps_cell(row, C.get("hbd"))),
                    ld50_oral=_nps_num(_nps_cell(row, C.get("ld50_oral"))),
                    ld50_dermal=_nps_num(_nps_cell(row, C.get("ld50_dermal"))),
                    melting_point_c=mp,
                    boiling_point_c=bp,
                )
            )
    return out


def main():
    meta = {}
    print("Extracting -> /tmp/piru-extract/")
    write_out("benzos_cited", extract_benzos(), meta)
    write_out("pyrls", extract_pyrls(), meta)
    write_out("medtap", extract_medtap(), meta)
    write_out("nps_datahub", extract_nps(), meta)
    (OUT / "_summary.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    print("\nSummary:")
    print(json.dumps(meta, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
