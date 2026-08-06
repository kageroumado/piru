#!/usr/bin/env python3
"""Fetch PubMed publication types for all cited PMIDs.

PubMed's PublicationType field is the only honest source for whether a paper is
a review, meta-analysis, or systematic review. The LLM-self-reported is_review
flags were stripped as unreliable (add63bc); this replaces them with MEDLINE
indexing.

Usage:
    python3 pipeline/fetch/pubmed_pubtypes.py          # fetch (network)
    python3 pipeline/fetch/pubmed_pubtypes.py --offline # cache only, no network

Output: data/sources/pubmed-pubtypes.json — a dict mapping PMID strings to their
publication type list. Consumed by sqlite.py's post-build is_review derivation.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

import defusedxml.ElementTree as ET

REPO = Path(__file__).resolve().parents[2]
CACHE = REPO / "data/sources/pubmed-pubtypes.json"
DB = REPO / "Piru/Data/piru-substances.sqlite"
USER_AGENT = "piru-pubtype-fetch/1.0 (https://github.com/kageroumado/piru)"

REVIEW_TYPES = frozenset(
    {
        "Review",
        "Systematic Review",
        "Meta-Analysis",
        "Scoping Review",
        "Practice Guideline",
        "Guideline",
    }
)


def load_cache() -> dict[str, list[str]]:
    if CACHE.exists():
        return json.loads(CACHE.read_text())
    return {}


def save_cache(cache: dict[str, list[str]]) -> None:
    CACHE.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")


def pmids_from_db() -> list[str]:
    import sqlite3

    if not DB.exists():
        return []
    con = sqlite3.connect(str(DB))
    rows = con.execute("SELECT DISTINCT pmid FROM citations WHERE pmid IS NOT NULL").fetchall()
    con.close()
    return [str(r[0]) for r in rows if r[0]]


def fetch_pubtypes(pmids: list[str]) -> dict[str, list[str]]:
    """Batch efetch — up to 200 PMIDs per request."""
    out: dict[str, list[str]] = {}
    for i in range(0, len(pmids), 200):
        chunk = pmids[i : i + 200]
        url = (
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=pubmed&retmode=xml&id={','.join(chunk)}"
        )
        req = Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urlopen(req, timeout=30) as resp:
                xml_data = resp.read()
        except (URLError, TimeoutError) as exc:
            print(f"  efetch failed for batch {i}-{i + len(chunk)}: {exc}", file=sys.stderr)
            continue
        root = ET.fromstring(xml_data)
        for article in root.findall(".//PubmedArticle"):
            pmid_el = article.find(".//PMID")
            if pmid_el is None or not pmid_el.text:
                continue
            pmid = pmid_el.text
            types = []
            for pt in article.findall(".//PublicationType"):
                if pt.text:
                    types.append(pt.text)
            out[pmid] = types
        time.sleep(0.4)
    return out


def main() -> None:
    offline = "--offline" in sys.argv

    cache = load_cache()
    all_pmids = pmids_from_db()
    print(f"PMIDs in DB: {len(all_pmids)}", file=sys.stderr)
    print(f"Cached: {len(cache)}", file=sys.stderr)

    missing = [p for p in all_pmids if p not in cache]
    print(f"Missing from cache: {len(missing)}", file=sys.stderr)

    if missing and not offline:
        fetched = fetch_pubtypes(missing)
        cache.update(fetched)
        save_cache(cache)
        print(f"Fetched: {len(fetched)}", file=sys.stderr)
    elif missing and offline:
        print(f"  (offline mode, {len(missing)} PMIDs skipped)", file=sys.stderr)

    review_count = sum(1 for types in cache.values() if any(t in REVIEW_TYPES for t in types))
    print(f"Reviews/meta-analyses in cache: {review_count}", file=sys.stderr)


if __name__ == "__main__":
    main()
