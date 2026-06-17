#!/usr/bin/env python3
"""Extract the four ~/Developer/piru-datasources raw files into
Piru-`Substance`-shaped JSON artifacts, written OUT OF the repo.

These artifacts (and the raw source files) are intentionally kept out of the
repo — only the built SQLite is committed. Run this before `pipeline/build/
sqlite.py`, which reads the JSON from the same out-of-repo directory.

Core fields match the `Substance` Codable struct exactly (so a Swift decoder
accepts each record). Source-unique data that doesn't fit the core model is
preserved under `x_*` keys so nothing is discarded before review.

Reuses `_common.py` (category/route mapping, HTML stripping, range parsing).

Paths (override with env vars):
  PIRU_DATASOURCES — raw input dir   (default ~/Developer/piru-datasources)
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
    parse_range,
    piru_category,
    piru_route,
    strip_html,
)

DS = Path(os.environ.get("PIRU_DATASOURCES", Path.home() / "Developer" / "piru-datasources"))
OUT = Path(os.environ.get("PIRU_EXTERNAL_DIR", "/tmp/piru-extract"))
OUT.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Shared builders for the Substance Codable JSON shape
# ---------------------------------------------------------------------------

_DOSE_RE = re.compile(
    r"(?P<lo>\d+(?:\.\d+)?)(?:\s*[-–]\s*(?P<hi>\d+(?:\.\d+)?))?\s*(?P<unit>µg|ug|mcg|mg|g|ml|iu)?",
    re.IGNORECASE,
)


def parse_dose_cell(text):
    """'0.5-1.5mg' -> (lo, hi, unit). hi is None for single values."""
    if not text:
        return None, None, ""
    m = _DOSE_RE.search(text.replace(",", ".").strip())
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
            {"summary": mech_text, "description": mech_text, "references": []}
            if mech_text
            else None
        )
        indications = [
            strip_html(_txt(x)) for x in ((di.get("indications") or {}).get("labeled") or [])
        ]
        contras = [
            strip_html(_txt(x)) for x in ((di.get("contraindications") or {}).get("labeled") or [])
        ]
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
                contraindications=contras,
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
        parts = []
        c = sec.get("content")
        if isinstance(c, dict) and c.get("text"):
            parts.append(c["text"])
        for piece in sec.get("content_full") or []:
            if isinstance(piece, dict) and piece.get("text"):
                parts.append(piece["text"])
        txt = strip_html(" ".join(parts))
        if txt:
            return txt
    return ""


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
        pharm = _section(sections, {"Pharmacology"})
        mechanism = {"summary": pharm, "description": pharm, "references": []} if pharm else None
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
    ]:
        for i, h in enumerate(header):
            if h == label:
                cols[key] = i
                break
    return cols


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
