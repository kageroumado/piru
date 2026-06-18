#!/usr/bin/env python3
"""Resolve a PubChem ``pubchem_cid`` for every substance that has an InChIKey
but no CID, and snapshot the mapping into the repo.

Why: only a minority of the catalog carries a ``pubchem_cid``, yet a much larger
slice carries an **InChIKey** (an exact structural fingerprint). PubChem indexes
compounds by InChIKey, so ``inchikey/<IK>/cids`` returns the CID whose structure
*is* that key — an exact, unambiguous match (e.g. diazepam
AAOVKJBEBIDNHE-UHFFFAOYSA-N → CID 3016). Filling CIDs this way is safe where a
name lookup is not: the resolved CID is CID↔InChIKey-consistent **by
construction**, which is the very invariant ``apply_pubchem_freebase`` trusts.

Lifting CID coverage unlocks the downstream PubChem enrichment — free-base
formula/MW correction (``apply_pubchem_freebase``) and the widened property
fetch (XLogP/TPSA/HBA/HBD) — for every newly-resolved substance.

The snapshot also records PubChem's **molecular formula** for the resolved CID.
This is raw provenance — the build (``apply_pubchem_cids``) gates each fill on
that formula matching the substance's stored formula (exact, or a clean
salt→free-base desalt). The gate is essential: a non-trivial slice of upstream
InChIKeys are themselves *corrupt* — they point at an unrelated compound
(carfentanil's stored key → tert-butyl acetate; etizolam's → a freon; many
benzos/racetams), so resolving them faithfully yields a wrong CID. The formula
cross-check catches these because the stored formula is right while the
wrong-CID formula differs wildly (and isn't a salt of it).

The build (``pipeline/build/sqlite.py``) consumes this snapshot via
``apply_pubchem_cids`` to COALESCE-fill ``pubchem_cid`` keyed by InChIKey, gated
by formula. Committing the raw mapping means a re-resolve surfaces any change as
a reviewable git diff — visible provenance, same posture as the properties
snapshot.

Usage:
    python3 pipeline/fetch/brushers/fetch_pubchem_cids.py

Writes:
    data/sources/pubchem-cids.json        — {inchikey: {cid, formula}}
    data/sources/pubchem-cids.meta.json   — fetch provenance + ambiguous keys
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
OUT = REPO / "data/sources/pubchem-cids.json"
META = REPO / "data/sources/pubchem-cids.meta.json"

BASE = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey"
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"
TIMEOUT = 30
RETRIES = 2
SPACING = 0.22  # polite gap between requests (PubChem allows ~5 req/s)


def _get(url: str) -> bytes | None:
    """GET ``url``; return body, or ``None`` on a 404 (InChIKey not in PubChem)."""
    last: Exception | None = None
    for _attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None  # PUGREST.NotFound — no compound for this InChIKey
            last = exc
            time.sleep(1.0)
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
            time.sleep(1.0)
    raise last  # type: ignore[misc]


def inchikeys_from_db() -> list[str]:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT DISTINCT inchikey FROM substances "
            "WHERE inchikey IS NOT NULL AND pubchem_cid IS NULL "
            "ORDER BY inchikey"
        ).fetchall()
    finally:
        con.close()
    return [r[0] for r in rows]


def resolve(inchikey: str) -> tuple[int | None, str | None, list[int]]:
    """Return (chosen_cid, formula, all_cids). ``chosen_cid`` is the smallest CID
    (the primary record when PubChem holds duplicates); ``formula`` is that CID's
    molecular formula (raw provenance the build gates each fill on). ``None`` when
    unresolved. One request returns both CID and formula."""
    body = _get(f"{BASE}/{inchikey}/property/MolecularFormula/JSON")
    if body is None:
        return None, None, []
    props = json.loads(body).get("PropertyTable", {}).get("Properties", [])
    props = [p for p in props if p.get("CID")]
    if not props:
        return None, None, []
    best = min(props, key=lambda p: p["CID"])
    all_cids = sorted(int(p["CID"]) for p in props)
    return int(best["CID"]), best.get("MolecularFormula"), all_cids


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    keys = inchikeys_from_db()
    if not keys:
        raise SystemExit("no InChIKey-without-CID substances in the database")

    mapping: dict[str, dict] = {}
    ambiguous: dict[str, list[int]] = {}
    unresolved: list[str] = []
    for i, ik in enumerate(keys):
        chosen, formula, all_cids = resolve(ik)
        if chosen is None:
            unresolved.append(ik)
        else:
            mapping[ik] = {"cid": chosen, "formula": formula}
            if len(all_cids) > 1:
                ambiguous[ik] = all_cids
        if i + 1 < len(keys):
            time.sleep(SPACING)
        if (i + 1) % 100 == 0:
            print(f"  …{i + 1}/{len(keys)} resolved={len(mapping)}", file=sys.stderr)

    ordered = {ik: mapping[ik] for ik in sorted(mapping)}
    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "PubChem PUG REST — CID by InChIKey (exact structural match)",
                "url_pattern": f"{BASE}/{{inchikey}}/cids/JSON",
                "fetched_at": fetched_at,
                "queried": len(keys),
                "resolved": len(ordered),
                "unresolved": len(unresolved),
                "ambiguous_count": len(ambiguous),
                "ambiguous": dict(sorted(ambiguous.items())),
                "note": "CID resolved from the substance's own InChIKey, so it is "
                "CID↔InChIKey-consistent by construction. chosen = min(CID) when "
                "PubChem holds duplicate records for one InChIKey.",
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    print(f"wrote {len(ordered)} InChIKey→CID mappings → {OUT.relative_to(REPO)}")
    if ambiguous:
        print(f"  {len(ambiguous)} InChIKey(s) mapped to multiple CIDs (took min); see meta")
    if unresolved:
        print(f"  {len(unresolved)} InChIKey(s) not found in PubChem: {unresolved[:10]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
