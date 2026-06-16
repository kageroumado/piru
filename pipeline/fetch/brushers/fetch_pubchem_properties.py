#!/usr/bin/env python3
"""Fetch the canonical (free-base) molecular formula + weight from PubChem for
every ``pubchem_cid`` in the bundled database, and snapshot it into the repo.

Why: the upstream chemistry sources hand us **salt** formulae/weights for most
compounds (DMT·HCl, MDMA·HCl, LSD tartrate, amphetamine sulfate…), while the
displayed doses are free-base-scale and the stored ``pubchem_cid`` / InChIKey
already point at the **free base** (e.g. DMT = CID 6089 = C12H16N2, 188.27).
PubChem's record for that CID is therefore the correct free-base formula/weight.
Fetching by CID is safe where a naive "strip the halide" heuristic is not —
ketamine's Cl and 2C-B's Br are structural, and PubChem keeps them.

The build (``pipeline/build/sqlite.py``) consumes this snapshot to overwrite the
salt formula/weight with the free base. Committing the raw PubChem response means
a re-fetch surfaces any change as a reviewable git diff — visible provenance.

Usage:
    python3 pipeline/fetch/brushers/fetch_pubchem_properties.py

Writes:
    data/sources/pubchem-properties.json       — {cid: {formula, molecular_weight}}
    data/sources/pubchem-properties.meta.json   — fetch provenance
"""

from __future__ import annotations

import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DB = REPO / "Piru/Data/piru-substances.sqlite"
OUT = REPO / "data/sources/pubchem-properties.json"
META = REPO / "data/sources/pubchem-properties.meta.json"

BASE = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid"
PROPS = "MolecularFormula,MolecularWeight"
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"
TIMEOUT = 30
RETRIES = 2
BATCH = 100  # CIDs per request — keeps the URL well under PubChem's length cap
SPACING = 0.25  # polite gap between requests (PubChem allows ~5 req/s)


def _get(url: str) -> bytes:
    last: Exception | None = None
    for _attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
            time.sleep(1.0)
    raise last  # type: ignore[misc]


def cids_from_db() -> list[int]:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT DISTINCT pubchem_cid FROM substances WHERE pubchem_cid IS NOT NULL ORDER BY pubchem_cid"
        ).fetchall()
    finally:
        con.close()
    return [int(r[0]) for r in rows]


def fetch_batch(cids: list[int]) -> dict[int, dict]:
    joined = ",".join(str(c) for c in cids)
    url = f"{BASE}/{joined}/property/{PROPS}/JSON"
    payload = json.loads(_get(url))
    out: dict[int, dict] = {}
    for row in payload.get("PropertyTable", {}).get("Properties", []):
        cid = row.get("CID")
        formula = row.get("MolecularFormula")
        mw = row.get("MolecularWeight")
        if cid is None:
            continue
        try:
            mw_val = round(float(mw), 2) if mw is not None else None
        except (TypeError, ValueError):
            mw_val = None
        out[int(cid)] = {"formula": formula, "molecular_weight": mw_val}
    return out


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    cids = cids_from_db()
    if not cids:
        raise SystemExit("no pubchem_cid values in the database")

    props: dict[int, dict] = {}
    for i in range(0, len(cids), BATCH):
        chunk = cids[i : i + BATCH]
        props.update(fetch_batch(chunk))
        if i + BATCH < len(cids):
            time.sleep(SPACING)

    # Sort by CID for a stable, reviewable diff; keys as strings (JSON object keys).
    ordered = {str(cid): props[cid] for cid in sorted(props)}
    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "PubChem PUG REST — MolecularFormula + MolecularWeight by CID",
                "url_pattern": f"{BASE}/{{cids}}/property/{PROPS}/JSON",
                "fetched_at": fetched_at,
                "cid_count": len(ordered),
                "note": "Free-base formula/weight (the stored CID is the free base); overrides salt-form values at build time.",
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    missing = sorted(set(cids) - set(props))
    print(f"wrote {len(ordered)} CIDs → {OUT.relative_to(REPO)}")
    if missing:
        print(f"  no PubChem property for {len(missing)} CID(s): {missing[:20]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
