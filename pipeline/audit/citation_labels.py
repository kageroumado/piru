#!/usr/bin/env python3
"""Check that a citation's human-readable LABEL describes the paper it points at.

The third distinct citation-failure mode this catalog has produced, and the only
one no existing gate can see:

1. **Fabricated identifiers** (2026-07) — DOIs that resolve to nothing. Caught by
   `verify_citations.py`.
2. **Topical misattribution** (2026-08-01) — a real DOI cited for the wrong
   molecule. Caught by `citation_topicality.py`.
3. **A mislabelled identifier** (this) — a real, resolvable, on-topic-*looking*
   identifier whose human label names a completely different document.

The instance that motivated it: fifteen arylcyclohexylamine entries cited a
source labelled `"Abelian 2024 SAR paper"` pointing at **PMID 38301014**, which
is *"In Europe, an early, cold dawn for modern humans"* — an archaeology news
piece in Science (doi:10.1126/science.ado3858). Both existing gates pass it
happily: the identifier resolves, and the topicality checker compares the paper
against a *substance name*, never against the label a curator wrote beside it.

So this compares something nobody was comparing: the year in a label like
`"Wiehle 2013 BJU Int"` against the year of the record the accompanying
identifier actually resolves to. A label is a curator's claim about what they
read; when it disagrees with the record, one of the two is wrong.

**What this does NOT catch, stated plainly:** the Abelian case itself. The label
said 2024 and PMID 38301014 *is* 2024 — the fabrication was in the surname, not
the year. Catching that needs the author list, and
`data/sources/citation-verify-cache.json` stores only `{journal, subjects,
title, year}`. Extending the cache to carry authors, then gating on surname, is
the fix for that class; this gate is the half that is buildable from the
metadata we already have, and it earns its place by having found a real mismatch
on first run (emylcamate, labelled 1961, resolves to 1959).

Deliberately narrow: it fires only on a **year**, because a year is unambiguous
and cheap to compare. A one-year gap is tolerated — online-first and issue dates
routinely differ.

Usage:
    python3 pipeline/audit/citation_labels.py
    python3 pipeline/audit/citation_labels.py --gate
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CURATED_DIR = REPO / "data/curated/substances"
VERIFY_CACHE = REPO / "data/sources/citation-verify-cache.json"
DB = REPO / "Piru/Data/piru-substances.sqlite"

#: A DOI or PMID appearing anywhere in a free-text source string.
_DOI = re.compile(r"10\.\d{4,}/[^\s,;\"')\]]+", re.I)
_PMID = re.compile(r"(?:pmid[:\s]*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{6,9})", re.I)
#: "Wiehle 2013", "Abelian 2024", "Brandt et al. 2012" — a capitalised surname
#: followed (optionally via "et al.") by a 4-digit year.
_LABEL = re.compile(r"\b([A-Z][a-zA-ZÀ-ɏ]{2,})\s+(?:et\s+al\.?,?\s*)?((?:1[89]|20)\d{2})\b")


def _strings(obj):
    if isinstance(obj, dict):
        for value in obj.values():
            yield from _strings(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from _strings(value)
    elif isinstance(obj, str):
        yield obj


def _identifier(text: str) -> str | None:
    doi = _DOI.search(text)
    if doi:
        return f"doi:{doi.group(0).rstrip('.').lower()}"
    pmid = _PMID.search(text)
    if pmid:
        return f"pmid:{pmid.group(1)}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", action="store_true", help="exit 1 on a year mismatch")
    args = parser.parse_args()

    cache = {k.lower(): v for k, v in json.loads(VERIFY_CACHE.read_text()).items() if v}

    checked = 0
    mismatches: list[tuple[str, str, str, int, int]] = []
    unresolved: list[tuple[str, str]] = []
    for path in sorted(CURATED_DIR.glob("*.json")):
        try:
            payload = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        for text in _strings(payload):
            ident = _identifier(text)
            label = _LABEL.search(text)
            if not ident or not label:
                continue
            record = cache.get(ident)
            if not record or not record.get("year"):
                unresolved.append((path.name, text.strip()[:110]))
                continue
            checked += 1
            claimed = int(label.group(2))
            actual = int(record["year"])
            # A one-year gap is routine: online-first vs issue date.
            if abs(claimed - actual) > 1:
                mismatches.append((path.name, text.strip()[:110], ident, claimed, actual))

    print("citation-labels:")
    print(f"  {checked} label(s) with a year checked against the resolved record")
    print(f"  {len(unresolved)} label(s) whose identifier has no cached year (skipped)")
    print(f"  {len(mismatches)} year mismatch(es)")
    for name, text, ident, claimed, actual in mismatches:
        print(f"\n  {name}")
        print(f"    label says {claimed}: {text!r}")
        print(f"    {ident} resolves to {actual}: {cache[ident].get('title', '')[:100]!r}")

    if args.gate and mismatches:
        print(
            f"\ncitation-labels: FAILED — {len(mismatches)} citation label(s) name a different "
            f"year than the identifier beside them resolves to. Either the label or the "
            f"identifier is wrong; check which before shipping.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
