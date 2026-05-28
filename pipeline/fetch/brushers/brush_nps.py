#!/usr/bin/env python3
"""Brush `nps-datahub.com-full-database[N=6405].csv` into Piru-shaped CSV.

NPS Datahub is a forensic-chemistry NPS catalogue maintained by police labs
(BKA, etc.). Entries are pure chemistry — SMILES, InChI, CAS, MW, hazard
codes — with zero clinical or recreational dose data. The useful fields for
Piru are:
  * Substance names + Abbreviation → name/aliases
  * Tags (semicolon-delimited chemical class strings) → raw_classes/tags
  * Chemical formula, CAS No., SMILES → chemistry metadata
  * Hierarchy / Type of substance → classification context

Dose + duration columns remain blank for every row.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (
    OUTPUT_DIR,
    empty_row,
    join_unique,
    open_csv,
    piru_category,
)

SOURCE_PATH = Path("/Users/kirie/Developer/piru-datasources/nps-datahub.com-full-database[N=6405].csv")
OUTPUT_PATH = OUTPUT_DIR / "nps.csv"


# The NPS CSV header has a number of blank column names (legacy spreadsheet
# columns). We use the row by index because column names aren't unique.
COL_PK = 0
COL_STRUCTURE = 2
COL_SUBSTANCE_NAMES = 4
COL_SYNONYM_1 = 5
COL_SYNONYM_2 = 6
COL_IUPAC = 7
COL_ABBREVIATION = 8
COL_HIERARCHY = 9
COL_FORMULA = 11
COL_CAS = 12
COL_TYPE = 21
COL_TAGS = 133
COL_SMILES = 122
COL_UUID = 138


def parse_tags(text: str) -> list[str]:
    """`Tags` is semicolon-separated, sometimes with stray German classification
    headers like "2020/1. Von 2-Phenethylamin abgeleitete Verbindungen". We
    drop tag entries longer than 80 chars since those are descriptions, not
    classes."""
    if not text:
        return []
    out: list[str] = []
    for raw in text.split(";"):
        tag = raw.strip()
        if not tag or len(tag) > 80:
            continue
        out.append(tag)
    return out


def derive_piru_category(tags: list[str], type_str: str) -> str:
    """The NPS Tags use chemical-family vocabulary ("Phenethylamines",
    "Cannabinoids", "Tryptamines") which doesn't map 1:1 to Piru's behavioural
    `SubstanceCategory`. We translate the common families into the closest
    Piru bucket; unknowns fall through to "Other"."""
    pool = " ".join(tags).lower()
    if "cannabinoid" in pool:
        return "Cannabinoid"
    if "phenethylamine" in pool or "amphetamin" in pool or "cathinone" in pool:
        return "Stimulant"
    if "tryptamine" in pool or "lysergamide" in pool:
        return "Psychedelic"
    if "arylcyclohexylamine" in pool or "dissociativ" in pool:
        return "Dissociative"
    if "benzodiazepine" in pool:
        return "Benzodiazepine"
    if "opioid" in pool or "fentanyl" in pool:
        return "Opioid"
    if "piperazine" in pool:
        return "Empathogen"
    return piru_category(tags) if tags else "Other"


def clean_name(raw: str) -> str:
    """`Substance names` cells often include the structure-style prefix
    "MDMA HCl" plus aliases. Strip the salt suffix to get the parent
    substance name when present."""
    text = (raw or "").strip()
    # Drop the trailing salt form if present (HCl, HBr, HF, sulfate, etc.).
    for suffix in (" HCl", " HBr", " HF", " sulfate", " sulphate", " tartrate", " citrate"):
        if text.lower().endswith(suffix.lower()):
            return text[: -len(suffix)].strip()
    return text


def brush() -> None:
    fh_out, writer = open_csv(OUTPUT_PATH)

    seen_names: set[str] = set()
    rows_written = 0

    with SOURCE_PATH.open(newline="", encoding="utf-8") as f_in:
        reader = csv.reader(f_in)
        next(reader)  # header

        for row in reader:
            if len(row) <= COL_TAGS:
                continue

            name = clean_name(row[COL_SUBSTANCE_NAMES])
            if not name:
                continue

            key = name.lower()
            if key in seen_names:
                continue
            seen_names.add(key)

            aliases = [
                row[COL_SYNONYM_1].strip(),
                row[COL_SYNONYM_2].strip(),
                row[COL_ABBREVIATION].strip(),
            ]
            tags = parse_tags(row[COL_TAGS])
            hierarchy = row[COL_HIERARCHY].strip()
            type_str = row[COL_TYPE].strip()

            piru_cat = derive_piru_category(tags, type_str)

            csv_row = empty_row("nps-datahub")
            csv_row.update({
                "source_id": row[COL_UUID].strip() or row[COL_PK].strip(),
                "name": name,
                "aliases": join_unique(aliases),
                "raw_classes": join_unique(tags),
                "piru_category": piru_cat,
                "default_route": "",  # unknown by source
                "routes": "",
                # Dose + duration intentionally blank — no clinical or
                # recreational pharmacology data in this source.
                "cas_no": row[COL_CAS].strip(),
                "chemical_formula": row[COL_FORMULA].strip(),
                "tags": join_unique([*tags, type_str, hierarchy]),
                "notes": row[COL_IUPAC].strip(),
            })
            writer.writerow(csv_row)
            rows_written += 1

    fh_out.close()
    print(f"wrote {OUTPUT_PATH} ({rows_written} unique substances)")


if __name__ == "__main__":
    brush()
