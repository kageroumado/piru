#!/usr/bin/env python3
"""Recompute the ``inchikey`` of every ``data/enrichment/raw/*.json`` entry from
its (trustworthy) ``smiles``, fixing the LLM enrichment swarm's hallucinated keys.

Background: the "deep-pharma enrichment swarm" produced correct human-readable
chemistry (name, IUPAC, SMILES, CAS) but **fabricated the 27-char InChIKey hash**
— a measured ~72% of entries carry an InChIKey that does not match their own
SMILES (carfentanil's key → tert-butyl acetate; etizolam's → a freon;
bromazepam's → vortioxetine). Those wrong keys then flow into ``substances`` via
``ingest_enrichment``, poisoning structural dedup and any InChIKey→CID/PubChem
enrichment.

The SMILES is reliable, so the fix is deterministic: recompute the standard
InChIKey from SMILES with OpenBabel (already a local tool; matches PubChem's
standard InChIKey). This edits the raw files **in place** at the line level —
only the ``inchikey`` value changes, so the diff is one line per fixed entry and
all other formatting is preserved.

Entries with no SMILES (can't recompute offline) are handled with
``--cas-fallback``: the entry's CAS — also reliable in the swarm output — is
resolved to PubChem's standard InChIKey. Without the flag they're left untouched
and reported. The rare SMILES OpenBabel can't parse fall back to CAS too.

Usage:
    python3 pipeline/fetch/brushers/fix_enrichment_inchikeys.py [--dry-run] [--cas-fallback]
"""

from __future__ import annotations

import glob
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RAW = REPO / "data/enrichment/raw"

sys.path.insert(0, str(REPO / "pipeline"))  # for chem_ids
from chem_ids import obabel_inchikey  # noqa: E402

_NAME = re.compile(r'^\s*"name"\s*:')
_SMILES = re.compile(r'^(\s*"smiles"\s*:\s*")([^"]*)(".*)$')
_INCHIKEY = re.compile(r'^(\s*"inchikey"\s*:\s*")([^"]*)(".*)$')
_CAS = re.compile(r'^\s*"cas"\s*:\s*"([^"]*)"')

_cas_cache: dict[str, str | None] = {}


def cas_inchikey(cas: str) -> str | None:
    """Resolve a CAS number to PubChem's standard InChIKey (network)."""
    if cas in _cas_cache:
        return _cas_cache[cas]
    url = (
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/"
        f"{urllib.parse.quote(cas)}/property/InChIKey/JSON"
    )
    key = None
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "Piru-DataFetcher/1.0", "Accept": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            props = json.loads(resp.read()).get("PropertyTable", {}).get("Properties", [])
        if props:
            key = props[0].get("InChIKey")
    except (urllib.error.URLError, TimeoutError, ValueError):
        key = None
    _cas_cache[cas] = key
    return key


def _lookahead_cas(lines: list[str], start: int) -> str | None:
    """The CAS field follows inchikey in each object — scan forward to it,
    stopping at the next entry boundary."""
    for line in lines[start + 1 : start + 8]:
        if _NAME.match(line):
            return None
        m = _CAS.match(line)
        if m:
            return m.group(1) or None
    return None


def fix_file(path: Path, dry: bool, cas_fallback: bool) -> dict:
    lines = path.read_text().splitlines(keepends=True)
    cur_smiles: str | None = None
    changed = same = no_smiles = failed = 0
    for i, line in enumerate(lines):
        if _NAME.match(line):
            cur_smiles = None  # new entry — forget any prior smiles
            continue
        m = _SMILES.match(line)
        if m:
            cur_smiles = m.group(2) or None
            continue
        m = _INCHIKEY.match(line)
        if not m:
            continue
        old = m.group(2)
        new = obabel_inchikey(cur_smiles) if cur_smiles else None
        if not new and cas_fallback:
            cas = _lookahead_cas(lines, i)
            if cas:
                new = cas_inchikey(cas)
        if not new:
            if not cur_smiles:
                no_smiles += 1
            else:
                failed += 1
            continue
        if new == old:
            same += 1
            continue
        lines[i] = (
            f"{m.group(1)}{new}{m.group(3)}\n"
            if line.endswith("\n")
            else f"{m.group(1)}{new}{m.group(3)}"
        )
        changed += 1
    if changed and not dry:
        path.write_text("".join(lines))
    return {"changed": changed, "same": same, "no_smiles": no_smiles, "failed": failed}


def main() -> int:
    dry = "--dry-run" in sys.argv
    cas_fallback = "--cas-fallback" in sys.argv
    files = sorted(glob.glob(str(RAW / "*.json")))
    tot = {"changed": 0, "same": 0, "no_smiles": 0, "failed": 0}
    for fp in files:
        r = fix_file(Path(fp), dry, cas_fallback)
        for k in tot:
            tot[k] += r[k]
        if r["changed"] or r["failed"] or r["no_smiles"]:
            print(
                f"  {Path(fp).name:42s} fixed={r['changed']:3d} ok={r['same']:3d} "
                f"no-smiles={r['no_smiles']:2d} obabel-fail={r['failed']:2d}"
            )
    tag = " (dry-run)" if dry else ""
    print(
        f"\nTotal{tag}: fixed={tot['changed']} already-correct={tot['same']} "
        f"no-smiles={tot['no_smiles']} obabel-fail={tot['failed']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
