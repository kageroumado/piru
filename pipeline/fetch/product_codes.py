#!/usr/bin/env python3
"""Snapshot the public product-code registries the box scanner resolves against.

Two registries, both open data:

- **openFDA NDC directory** (US, public domain) — the bulk download at
  https://download.open.fda.gov/drug/ndc/drug-ndc-0001-of-0001.json.zip.
  One record per marketed product with its package NDCs and, for OTC
  products, the retail UPCs.
- **BDPM** (France, Etalab open licence) — three tab-separated files from
  https://base-donnees-publique.medicaments.gouv.fr/download/file/: `CIS_bdpm`
  (product), `CIS_COMPO_bdpm` (active substances) and `CIS_CIP_bdpm`
  (presentations, whose CIP13 is the EAN-13 on the box).

Both are far larger than the substances Piru knows, so only products whose
single active ingredient folds onto a name or alias in the committed
`data/snapshots/substances.json` are kept (the build re-resolves names against
the freshly built alias table; this filter just keeps the snapshot small).
Multi-ingredient products are dropped: a box of two actives has no single
substance page to open.

Outputs (both with a sibling `.meta.json` carrying the fetch date + counts):
    data/sources/product-codes-openfda.json
    data/sources/product-codes-bdpm.json

Usage:
    python3 pipeline/fetch/product_codes.py             # download both
    python3 pipeline/fetch/product_codes.py --openfda-json PATH --bdpm-dir DIR
                                                        # reuse local downloads
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from urllib import request as urlrequest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # pipeline/
from product_codes import (  # noqa: E402
    gtin14_from_ean,
    name_keys,
    parse_fr_presentation,
    parse_us_package,
)

REPO = Path(__file__).resolve().parents[2]
SNAPSHOT = REPO / "data/snapshots/substances.json"
OUT_OPENFDA = REPO / "data/sources/product-codes-openfda.json"
OUT_BDPM = REPO / "data/sources/product-codes-bdpm.json"

OPENFDA_URL = "https://download.open.fda.gov/drug/ndc/drug-ndc-0001-of-0001.json.zip"
BDPM_BASE = "https://base-donnees-publique.medicaments.gouv.fr/download/file/"
BDPM_FILES = ("CIS_bdpm.txt", "CIS_COMPO_bdpm.txt", "CIS_CIP_bdpm.txt")

# openFDA marketing categories that are not medicines a person would identify.
_SKIP_CATEGORY_PREFIXES = ("UNAPPROVED HOMEOPATHIC",)
# Routes that mark an OTC monograph product as a sanitizer/sunscreen/cream
# rather than a dosed medicine — thousands of "Alcohol" hand-gel listings.
_EXTERNAL_ROUTES = {"TOPICAL", "CUTANEOUS", "DENTAL", "PERIODONTAL", "IRRIGATION"}


def known_name_keys() -> set[str]:
    """Folded name/alias keys of every substance the snapshot says carries data
    (a dose ladder, a duration, a half-life, or a mechanism) — a product mapped
    to a data-less stub would open an empty page."""
    keys: set[str] = set()
    for entry in json.loads(SNAPSHOT.read_text()):
        carries_data = (
            entry.get("has_dose_data")
            or entry.get("has_duration_data")
            or entry.get("half_life_minutes")
            or entry.get("mechanism_summary")
        )
        if not carries_data:
            continue
        for name in [entry["name"], *entry.get("aliases", [])]:
            for key in name_keys(name):
                if len(key) >= 4:
                    keys.add(key)
    return keys


def matches(name: str, keys: set[str]) -> bool:
    return any(k in keys for k in name_keys(name))


def download(url: str, timeout: int = 300) -> bytes:
    req = urlrequest.Request(url, headers={"User-Agent": "piru-product-codes/1.0"})
    with urlrequest.urlopen(req, timeout=timeout) as resp:
        return resp.read()


# ---------------------------------------------------------------------------
# openFDA
# ---------------------------------------------------------------------------


def load_openfda(local: Path | None) -> list[dict]:
    if local:
        return json.loads(local.read_text())["results"]
    print(f"  downloading {OPENFDA_URL}", file=sys.stderr)
    blob = download(OPENFDA_URL)
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        name = next(n for n in zf.namelist() if n.endswith(".json"))
        return json.loads(zf.read(name))["results"]


def is_external_otc(record: dict) -> bool:
    category = record.get("marketing_category") or ""
    routes = {r.upper() for r in record.get("route") or []}
    return (
        (category.startswith("OTC") or category.startswith("UNAPPROVED"))
        and bool(routes)
        and routes <= _EXTERNAL_ROUTES
    )


def retail_upcs(record: dict) -> list[str]:
    """The record's retail UPC-As. `openfda.upc` is listed per *label set*, so
    every strength of a brand repeats the same four codes; the NDC-shaped ones
    (``03`` + NDC-10 + check) already reach their own package row through the
    NDC and are dropped here — kept, they would pin a 36 mg barcode to the
    18 mg product that happens to sort first."""
    upcs = set()
    for upc in record.get("openfda", {}).get("upc") or []:
        gtin = gtin14_from_ean(upc)
        if gtin and not gtin.startswith("003"):
            upcs.add(gtin)
    return sorted(upcs)


def snapshot_openfda(records: list[dict], keys: set[str]) -> list[dict]:
    out = []
    for r in records:
        generic = (r.get("generic_name") or "").strip()
        if not generic or not r.get("finished", True):
            continue
        if (r.get("marketing_category") or "").startswith(_SKIP_CATEGORY_PREFIXES):
            continue
        if "," in generic or " and " in generic.lower():
            continue
        if len(r.get("active_ingredients") or []) > 1:
            continue
        if is_external_otc(r):
            continue
        if not matches(generic, keys):
            continue
        ingredient = (r.get("active_ingredients") or [{}])[0]
        packages = []
        for p in r.get("packaging") or []:
            if not p.get("package_ndc"):
                continue
            parsed = parse_us_package(p.get("description") or "")
            packages.append([p["package_ndc"], *(parsed or (None, None))])
        out.append(
            {
                "ndc": r.get("product_ndc"),
                "generic": generic,
                "brand": (r.get("brand_name") or "").strip() or None,
                "strength": (ingredient.get("strength") or "").strip() or None,
                "form": r.get("dosage_form"),
                "route": (r.get("route") or [None])[0],
                "packages": packages,
                "upc": retail_upcs(r),
            }
        )
    out.sort(key=lambda p: p["ndc"] or "")
    return out


# ---------------------------------------------------------------------------
# BDPM
# ---------------------------------------------------------------------------


def load_bdpm(local_dir: Path | None) -> dict[str, list[list[str]]]:
    tables: dict[str, list[list[str]]] = {}
    for name in BDPM_FILES:
        if local_dir:
            raw = (local_dir / name).read_bytes()
        else:
            print(f"  downloading {BDPM_BASE}{name}", file=sys.stderr)
            raw = download(BDPM_BASE + name)
        # The files are served in a mix of encodings (CIS_CIP is UTF-8, the
        # other two cp1252); decode whichever succeeds.
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("cp1252")
        tables[name] = [line.split("\t") for line in text.splitlines() if line.strip()]
    return tables


def snapshot_bdpm(tables: dict[str, list[list[str]]], keys: set[str]) -> list[dict]:
    # CIS_COMPO: CIS | element | substance code | substance | dosage | dosage ref | SA/ST | link
    substances: dict[str, dict[str, str]] = {}
    for row in tables["CIS_COMPO_bdpm.txt"]:
        if len(row) < 7 or row[6].strip() != "SA":
            continue
        cis, substance, dosage = row[0].strip(), row[3].strip(), row[4].strip()
        substances.setdefault(cis, {})[substance] = dosage
    # CIS_CIP: CIS | CIP7 | presentation | status | marketing | date | CIP13 | …
    presentations: dict[str, list[list[str]]] = {}
    for row in tables["CIS_CIP_bdpm.txt"]:
        if len(row) < 7:
            continue
        cis, label, cip13 = row[0].strip(), row[2].strip(), row[6].strip()
        if len(cip13) == 13 and cip13.isdigit():
            presentations.setdefault(cis, []).append([cip13, label])
    # CIS: CIS | name | form | routes | AMM status | procedure | marketing | …
    out = []
    for row in tables["CIS_bdpm.txt"]:
        if len(row) < 4:
            continue
        cis = row[0].strip()
        actives = substances.get(cis)
        if not actives or len(actives) != 1:
            continue
        substance, dosage = next(iter(actives.items()))
        if not matches(substance, keys):
            continue
        cips = presentations.get(cis)
        if not cips:
            continue
        cips = [[cip13, *(parse_fr_presentation(label) or (None, None))] for cip13, label in cips]
        out.append(
            {
                "cis": cis,
                "name": row[1].strip(),
                "form": row[2].strip(),
                "route": row[3].strip().split(";")[0] or None,
                "substance": substance,
                "strength": dosage or None,
                "presentations": sorted(cips),
            }
        )
    out.sort(key=lambda p: p["cis"])
    return out


# ---------------------------------------------------------------------------


def write_snapshot(path: Path, rows: list[dict], meta: dict) -> None:
    # One product per line: diffable, and a grep for an NDC/CIP lands on its row.
    body = ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in rows)
    path.write_text("[\n" + body + "\n]\n", encoding="utf-8")
    path.with_suffix(".meta.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(
        f"  wrote {path.relative_to(REPO)} ({len(rows)} products, {path.stat().st_size / 1e6:.1f} MB)",
        file=sys.stderr,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--openfda-json", type=Path, help="unzipped openFDA NDC bulk JSON to reuse")
    parser.add_argument(
        "--bdpm-dir", type=Path, help="directory holding the three BDPM .txt files to reuse"
    )
    parser.add_argument("--skip-openfda", action="store_true")
    parser.add_argument("--skip-bdpm", action="store_true")
    args = parser.parse_args()

    keys = known_name_keys()
    now = datetime.now(UTC).isoformat(timespec="seconds")
    print(
        f"product codes: {len(keys)} name keys from {SNAPSHOT.relative_to(REPO)}", file=sys.stderr
    )

    if not args.skip_openfda:
        records = load_openfda(args.openfda_json)
        rows = snapshot_openfda(records, keys)
        write_snapshot(
            OUT_OPENFDA,
            rows,
            {
                "source": "openFDA NDC directory (bulk download)",
                "url": OPENFDA_URL,
                "license": "https://open.fda.gov/license/",
                "fetched_at": now,
                "products_total": len(records),
                "products_kept": len(rows),
                "packages": sum(len(r["packages"]) for r in rows),
                "upcs": sum(len(r["upc"]) for r in rows),
            },
        )

    if not args.skip_bdpm:
        tables = load_bdpm(args.bdpm_dir)
        rows = snapshot_bdpm(tables, keys)
        write_snapshot(
            OUT_BDPM,
            rows,
            {
                "source": "ANSM Base de données publique des médicaments (BDPM)",
                "url": BDPM_BASE,
                "license": "Licence Ouverte / Open Licence (Etalab)",
                "fetched_at": now,
                "products_total": len(tables["CIS_bdpm.txt"]),
                "products_kept": len(rows),
                "presentations": sum(len(r["presentations"]) for r in rows),
            },
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
