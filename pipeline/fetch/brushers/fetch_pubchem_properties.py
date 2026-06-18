#!/usr/bin/env python3
"""Fetch the canonical (free-base) molecular formula + weight and the computed
physicochemical descriptors from PubChem for every ``pubchem_cid`` in the bundled
database, and snapshot them into the repo.

Why: the upstream chemistry sources hand us **salt** formulae/weights for most
compounds (DMT·HCl, MDMA·HCl, LSD tartrate, amphetamine sulfate…), while the
displayed doses are free-base-scale and the stored ``pubchem_cid`` / InChIKey
already point at the **free base** (e.g. DMT = CID 6089 = C12H16N2, 188.27).
PubChem's record for that CID is therefore the correct free-base formula/weight.
Fetching by CID is safe where a naive "strip the halide" heuristic is not —
ketamine's Cl and 2C-B's Br are structural, and PubChem keeps them.

PubChem also computes a consistent set of physicochemical descriptors — XLogP3
(logP), topological polar surface area, and H-bond donor/acceptor counts — by a
single method across every CID. We snapshot those too: where a CID is
InChIKey-verified the build prefers them over NPS-DataHub's mixed-provenance
values (one computational method beats scraped per-compound estimates). These
are predicted/computed, not measured — surfaced as forensic in the app.

The build (``pipeline/build/sqlite.py``) consumes this snapshot to overwrite the
salt formula/weight with the free base (``apply_pubchem_freebase``) and to set
logP/TPSA/HBA/HBD (``apply_pubchem_computed``). Committing the raw PubChem
response means a re-fetch surfaces any change as a reviewable git diff.

Usage:
    python3 pipeline/fetch/brushers/fetch_pubchem_properties.py

Writes:
    data/sources/pubchem-properties.json       — {cid: {formula, molecular_weight,
                                                  xlogp, tpsa, hbd, hba, complexity}}
    data/sources/pubchem-properties.meta.json   — fetch provenance
"""

from __future__ import annotations

import json
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DB = REPO / "Piru/Data/piru-substances.sqlite"
OUT = REPO / "data/sources/pubchem-properties.json"
META = REPO / "data/sources/pubchem-properties.meta.json"
OUT_IK = REPO / "data/sources/pubchem-properties-by-inchikey.json"

BASE = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid"
BASE_IK = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey"
PROPS = "MolecularFormula,MolecularWeight,XLogP,TPSA,HBondDonorCount,HBondAcceptorCount,Complexity"
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
        except urllib.error.HTTPError as exc:  # pragma: no cover - network
            # A 4xx (e.g. 404 = InChIKey unknown to PubChem) won't improve on retry.
            if 400 <= exc.code < 500:
                raise
            last = exc
            time.sleep(1.0)
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


def _num(v, places: int) -> float | None:
    try:
        return round(float(v), places) if v is not None else None
    except (TypeError, ValueError):
        return None


def _int(v) -> int | None:
    try:
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _row_props(row: dict) -> dict:
    return {
        "formula": row.get("MolecularFormula"),
        "molecular_weight": _num(row.get("MolecularWeight"), 2),
        "xlogp": _num(row.get("XLogP"), 2),
        "tpsa": _num(row.get("TPSA"), 2),
        "hbd": _int(row.get("HBondDonorCount")),
        "hba": _int(row.get("HBondAcceptorCount")),
        "complexity": _num(row.get("Complexity"), 1),
    }


def fetch_batch(cids: list[int]) -> dict[int, dict]:
    joined = ",".join(str(c) for c in cids)
    url = f"{BASE}/{joined}/property/{PROPS}/JSON"
    payload = json.loads(_get(url))
    out: dict[int, dict] = {}
    for row in payload.get("PropertyTable", {}).get("Properties", []):
        cid = row.get("CID")
        if cid is None:
            continue
        out[int(cid)] = _row_props(row)
    return out


def inchikeys_without_cid() -> list[str]:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT DISTINCT inchikey FROM substances "
            "WHERE inchikey IS NOT NULL AND pubchem_cid IS NULL ORDER BY inchikey"
        ).fetchall()
    finally:
        con.close()
    return [r[0] for r in rows]


def fetch_by_inchikey(ik: str) -> dict | None:
    """Resolve computed descriptors for one InChIKey. Returns None when PubChem
    has no record for it (404). The InChIKey is the structure itself, so the
    record is unambiguously the right molecule — also captures the CID it maps to
    for provenance (the build does not currently backfill it)."""
    url = f"{BASE_IK}/{urllib.parse.quote(ik)}/property/{PROPS}/JSON"
    try:
        payload = json.loads(_get(url))
    except urllib.error.HTTPError as exc:  # pragma: no cover - network
        if exc.code == 404:
            return None
        raise
    rows = payload.get("PropertyTable", {}).get("Properties", [])
    if not rows:
        return None
    out = _row_props(rows[0])
    cid = rows[0].get("CID")
    out["cid"] = int(cid) if cid is not None else None
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
                "source": "PubChem PUG REST — formula/weight + computed physicochemical descriptors by CID",
                "url_pattern": f"{BASE}/{{cids}}/property/{PROPS}/JSON",
                "fetched_at": fetched_at,
                "cid_count": len(ordered),
                "note": (
                    "Free-base formula/weight (the stored CID is the free base) overrides salt-form "
                    "values at build time. XLogP/TPSA/HBA/HBD are PubChem-computed descriptors; the "
                    "build prefers them over NPS-DataHub where the CID is InChIKey-verified."
                ),
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

    # CID-less but structurally-known substances (codeine, many NPS analogues):
    # resolve computed descriptors directly by InChIKey — the structure gate
    # itself — so they aren't left blank. Keyed by InChIKey; applied separately.
    iks = inchikeys_without_cid()
    ik_props: dict[str, dict] = {}
    for i, ik in enumerate(iks):
        rec = fetch_by_inchikey(ik)
        if rec is not None:
            ik_props[ik] = rec
        if i + 1 < len(iks):
            time.sleep(SPACING)
    ordered_ik = {ik: ik_props[ik] for ik in sorted(ik_props)}
    OUT_IK.write_text(json.dumps(ordered_ik, indent=2, ensure_ascii=False) + "\n")
    print(
        f"wrote {len(ordered_ik)} InChIKeys → {OUT_IK.relative_to(REPO)} "
        f"({len(iks) - len(ordered_ik)} of {len(iks)} CID-less had no PubChem record)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
