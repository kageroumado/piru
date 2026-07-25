#!/usr/bin/env python3
"""Verify that every citation in the built DB resolves *and* is about its claim.

`validate_links.py` already answers "does this link load?". It cannot answer the
question that actually caught a fabricated reference: **is the thing on the other
end the paper this row needed?** A DOI can resolve perfectly and still be a
cardiology trial cited for a CYP2D6 metabolism claim, and a whole enrichment
batch can share one plausible-looking DOI that belongs to none of its rows.

So this resolves each identifier to real metadata and compares it against the
claim citing it:

    DOI  → Crossref (title, journal, subject areas)
    PMID → PubMed esummary (title, journal, year)
    URL  → host classification only (no title to compare)

then scores the paper's title/journal/subjects against the claim's own terms —
the substance, the enzyme, the metabolite, the receptor target — with fuzzy
matching, so "CYP2D6" still matches "cytochrome P450 2D6" and "MDMA" matches
"3,4-methylenedioxymethamphetamine".

Verdicts, in descending severity:

    UNRESOLVED  the identifier resolves to nothing. Fabricated, retracted, or
                mistyped. This is the class that shipped `dmd.31.4.388`.
    OFF_TOPIC   resolves to a real paper with *no* overlap with the claim —
                a completely different subject. Needs a human.
    WEAK        some overlap, below threshold. Usually fine (a review with a
                generic title); listed so it can be skimmed.
    OK          the paper is plainly about the claim.

Network results are cached in `data/sources/citation-verify-cache.json`, so a
re-run is offline and CI can gate on the committed cache.

    python3 pipeline/audit/verify_citations.py                 # verify (network)
    python3 pipeline/audit/verify_citations.py --offline       # cache only
    python3 pipeline/audit/verify_citations.py --gate          # exit 1 on UNRESOLVED
    python3 pipeline/audit/verify_citations.py --limit 50      # quick pass
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
CACHE = REPO / "data/sources/citation-verify-cache.json"
USER_AGENT = "piru-citation-verifier/1.0 (https://github.com/kageroumado/piru)"

#: Expansions so a claim term matches how a paper title would write it. Keys are
#: matched as whole tokens against claim terms; values join the paper-side terms.
SYNONYMS: dict[str, tuple[str, ...]] = {
    "mdma": ("methylenedioxymethamphetamine", "ecstasy"),
    "mda": ("methylenedioxyamphetamine",),
    "mde": ("methylenedioxyethylamphetamine", "mdea"),
    "lsd": ("lysergic", "lysergide"),
    "thc": ("tetrahydrocannabinol", "cannabis", "cannabinoid"),
    "dmt": ("dimethyltryptamine",),
    "5-ht": ("serotonin", "serotonergic"),
    "da": ("dopamine",),
    "ne": ("noradrenaline", "norepinephrine"),
    "sert": ("serotonin transporter",),
    "dat": ("dopamine transporter",),
    "net": ("norepinephrine transporter", "noradrenaline transporter"),
    "comt": ("catechol", "methyltransferase"),
    "ugt": ("glucuronosyltransferase", "glucuronidation", "conjugation"),
    "mao": ("monoamine oxidase",),
    "pk": ("pharmacokinetic",),
}

#: Hosts that are legitimate reference targets. A citation URL outside these is
#: reported — not as wrong, but as worth a look.
KNOWN_HOSTS = {
    "doi.org",
    "dx.doi.org",
    "pubmed.ncbi.nlm.nih.gov",
    "www.ncbi.nlm.nih.gov",
    "ncbi.nlm.nih.gov",
    "pubchem.ncbi.nlm.nih.gov",
    "psychonautwiki.org",
    "en.wikipedia.org",
    "drugbank.com",
    "go.drugbank.com",
    "dailymed.nlm.nih.gov",
    "www.accessdata.fda.gov",
    "accessdata.fda.gov",
    "www.fda.gov",
    "fda.gov",
    "erowid.org",
    "www.erowid.org",
    "tripsit.me",
    "drugs.com",
    "www.drugs.com",
    "link.springer.com",
    "www.sciencedirect.com",
    "onlinelibrary.wiley.com",
    "journals.plos.org",
    "www.nature.com",
    "pmc.ncbi.nlm.nih.gov",
    # Drug-monitoring bodies and forensic centres — primary sources for NPS,
    # which often have no journal article at all.
    "www.emcdda.europa.eu",
    "emcdda.europa.eu",
    "www.euda.europa.eu",
    "euda.europa.eu",
    "cfsre.org",
    "www.cfsre.org",
    "www.unodc.org",
    "unodc.org",
    "www.who.int",
    "who.int",
    "www.deadiversion.usdoj.gov",
}

STOPWORDS = {
    "the",
    "and",
    "for",
    "with",
    "from",
    "its",
    "via",
    "of",
    "in",
    "a",
    "an",
    "to",
    "by",
    "on",
    "at",
    "is",
    "are",
    "as",
    "that",
    "this",
    "human",
    "humans",
    "study",
    "effects",
    "effect",
    "role",
    "novel",
    "using",
    "after",
    "during",
    "new",
    "data",
}


@dataclass
class Claim:
    """What a citation is being used to support, flattened to searchable terms."""

    citation_id: int
    terms: set[str] = field(default_factory=set)
    where: set[str] = field(default_factory=set)

    def describe(self) -> str:
        return f"{', '.join(sorted(self.where))}: {' / '.join(sorted(self.terms)[:6])}"


def tokenize(text: str | None) -> set[str]:
    if not text:
        return set()
    raw = re.split(r"[^a-z0-9]+", text.lower())
    return {t for t in raw if len(t) > 2 and t not in STOPWORDS}


def expand(terms: set[str]) -> set[str]:
    out = set(terms)
    for term in terms:
        for extra in SYNONYMS.get(term, ()):
            out |= tokenize(extra)
        # CYP2D6 → cyp, 2d6 so it can match "cytochrome P450 2D6"
        if m := re.fullmatch(r"cyp(\d[a-z]\d+)", term):
            out |= {"cytochrome", "p450", m.group(1)}
    return out


def fuzzy_contains(needle: str, haystack: set[str], threshold: float = 0.86) -> bool:
    if needle in haystack:
        return True
    for word in haystack:
        # Substring containment, both directions: a paper titled "…ketamine
        # metabolites" *is* the source for hydroxynorketamine, and a paper on
        # "methylenedioxymethamphetamine" is about MDMA. Ratio-based matching
        # alone misses these — the strings differ too much in length.
        if len(needle) >= 5 and len(word) >= 5 and (needle in word or word in needle):
            return True
        if (
            abs(len(word) - len(needle)) <= 4
            and SequenceMatcher(None, needle, word).ratio() >= threshold
        ):
            return True
    return False


def overlap_score(claim_terms: set[str], paper_terms: set[str]) -> float:
    """Fraction of claim terms the paper mentions, fuzzily. 0 = different subject."""
    if not claim_terms:
        return 1.0
    hits = sum(1 for t in claim_terms if fuzzy_contains(t, paper_terms))
    return hits / len(claim_terms)


# --------------------------------------------------------------------------- DB


def load_claims(conn: sqlite3.Connection) -> dict[int, Claim]:
    """Every citation_id in the DB, with the terms of the rows that cite it."""
    claims: dict[int, Claim] = defaultdict(lambda: Claim(citation_id=0))
    tables = [
        r[0]
        for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
    ]
    for table in tables:
        cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")').fetchall()]
        if "citation_id" not in cols:
            continue
        # Columns worth comparing against a paper title.
        term_cols = [
            c
            for c in cols
            if c
            in {
                "enzyme",
                "metabolite_name",
                "target",
                "action",
                "route",
                "phase",
                "effect",
                "name",
                "summary",
                "notes",
                "interaction",
                "gene",
            }
        ]
        joins = "substance_id" in cols
        select = ", ".join(f't."{c}"' for c in ["citation_id", *term_cols])
        sql = f'SELECT {select}{", s.canonical_name" if joins else ""} FROM "{table}" t'
        if joins:
            sql += " LEFT JOIN substances s ON s.id = t.substance_id"
        sql += " WHERE t.citation_id IS NOT NULL"
        for row in conn.execute(sql).fetchall():
            cid = row[0]
            claim = claims[cid]
            claim.citation_id = cid
            claim.where.add(table)
            for value in row[1:]:
                if isinstance(value, str):
                    claim.terms |= tokenize(value)
    return dict(claims)


def load_citations(conn: sqlite3.Connection) -> list[dict]:
    return [
        dict(zip(("id", "doi", "pmid", "url", "title"), row, strict=True))
        for row in conn.execute(
            "SELECT id, doi, pmid, url, title FROM citations ORDER BY id"
        ).fetchall()
    ]


# ---------------------------------------------------------------------- network


def _get_json(url: str, timeout: int = 20) -> dict | None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError):
        return None


def resolve_doi(doi: str) -> dict | None:
    data = _get_json(f"https://api.crossref.org/works/{urllib.parse.quote(doi)}")
    if not data or data.get("status") != "ok":
        return None
    msg = data.get("message", {})
    title = " ".join(msg.get("title") or [])
    journal = " ".join(msg.get("container-title") or [])
    return {
        "title": title,
        "journal": journal,
        "subjects": msg.get("subject") or [],
        "year": (msg.get("issued", {}).get("date-parts") or [[None]])[0][0],
    }


def resolve_pmids(pmids: list[int]) -> dict[int, dict]:
    """Batch PubMed lookups — esummary takes up to 200 ids per request."""
    out: dict[int, dict] = {}
    for i in range(0, len(pmids), 150):
        chunk = pmids[i : i + 150]
        data = _get_json(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
            f"?db=pubmed&retmode=json&id={','.join(str(p) for p in chunk)}"
        )
        result = (data or {}).get("result", {})
        for pmid in chunk:
            rec = result.get(str(pmid))
            if rec and not rec.get("error"):
                out[pmid] = {
                    "title": rec.get("title", ""),
                    "journal": rec.get("fulljournalname") or rec.get("source", ""),
                    "subjects": [],
                    "year": (rec.get("pubdate") or "")[:4],
                }
        time.sleep(0.4)  # NCBI asks for ≤3 requests/second without an API key
    return out


# ----------------------------------------------------------------------- verify


def verdict_for(citation: dict, meta: dict | None, claim: Claim | None) -> tuple[str, str]:
    """(verdict, detail) for one citation."""
    identifier = citation["doi"] or citation["pmid"] or citation["url"]
    if citation["doi"] or citation["pmid"]:
        if meta is None:
            return "UNRESOLVED", f"{identifier} resolves to no record"
        paper_terms = expand(
            tokenize(meta.get("title"))
            | tokenize(meta.get("journal"))
            | tokenize(" ".join(meta.get("subjects") or []))
        )
        claim_terms = expand(claim.terms) if claim else set()
        # Long claim texts (notes) swamp the score; weight the score on the terms
        # most likely to appear in a title.
        score = overlap_score({t for t in claim_terms if len(t) > 3}, paper_terms)
        title = (meta.get("title") or "")[:70]
        if not claim_terms:
            return "OK", f"{title} (no claim terms to compare)"
        if score == 0:
            return "OFF_TOPIC", f"{title} — nothing in common with: {claim.describe()}"
        if score < 0.15:
            return "WEAK", f"{title} (score {score:.2f})"
        return "OK", f"{title} (score {score:.2f})"
    host = urllib.parse.urlparse(citation["url"] or "").netloc.lower()
    if host and host not in KNOWN_HOSTS:
        return "WEAK", f"unrecognised host {host}"
    return "OK", host or "no identifier"


def load_cache() -> dict:
    if CACHE.exists():
        return json.loads(CACHE.read_text())
    return {}


def save_cache(cache: dict) -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--offline", action="store_true", help="use only the cache")
    parser.add_argument("--gate", action="store_true", help="exit 1 on UNRESOLVED")
    parser.add_argument("--limit", type=int, default=0, help="check at most N citations")
    parser.add_argument("--refresh", action="store_true", help="ignore cached metadata")
    parser.add_argument("--json", type=Path, help="write the full per-citation result here")
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    citations = load_citations(conn)
    claims = load_claims(conn)
    conn.close()

    if args.limit:
        citations = citations[: args.limit]

    cache = {} if args.refresh else load_cache()

    # Resolve everything missing from the cache: PMIDs batched, DOIs one by one.
    if not args.offline:
        want_pmids = [
            c["pmid"] for c in citations if c["pmid"] and f"pmid:{c['pmid']}" not in cache
        ]
        if want_pmids:
            print(f"Resolving {len(want_pmids)} PMID(s) via PubMed…", file=sys.stderr)
            for pmid, meta in resolve_pmids(want_pmids).items():
                cache[f"pmid:{pmid}"] = meta
            for pmid in want_pmids:
                cache.setdefault(f"pmid:{pmid}", None)
        want_dois = [c["doi"] for c in citations if c["doi"] and f"doi:{c['doi']}" not in cache]
        if want_dois:
            print(f"Resolving {len(want_dois)} DOI(s) via Crossref…", file=sys.stderr)
            for n, doi in enumerate(want_dois, 1):
                cache[f"doi:{doi}"] = resolve_doi(doi)
                if n % 25 == 0:
                    print(f"  {n}/{len(want_dois)}", file=sys.stderr)
                    save_cache(cache)
                time.sleep(0.12)
        save_cache(cache)

    buckets: dict[str, list[str]] = defaultdict(list)
    records: list[dict] = []
    for citation in citations:
        key = (
            f"doi:{citation['doi']}"
            if citation["doi"]
            else f"pmid:{citation['pmid']}"
            if citation["pmid"]
            else None
        )
        meta = cache.get(key) if key else None
        if key and key not in cache and args.offline:
            buckets["UNCHECKED"].append(f"[{citation['id']}] {key}")
            continue
        verdict, detail = verdict_for(citation, meta, claims.get(citation["id"]))
        buckets[verdict].append(f"[{citation['id']}] {key or citation['url']} — {detail}")
        records.append(
            {
                "citation_id": citation["id"],
                "identifier": key or citation["url"],
                "verdict": verdict,
                "detail": detail,
                "resolved_title": (meta or {}).get("title"),
                "claim": claims[citation["id"]].describe() if citation["id"] in claims else None,
            }
        )

    total = len(citations)
    print(f"\nverify-citations: {total} citation(s) in {args.db.name}")
    for verdict in ("UNRESOLVED", "OFF_TOPIC", "WEAK", "UNCHECKED", "OK"):
        rows = buckets.get(verdict, [])
        if not rows:
            continue
        print(f"\n{verdict}: {len(rows)}")
        if verdict != "OK":
            for row in rows[:40]:
                print(f"  {row}")
            if len(rows) > 40:
                print(f"  … and {len(rows) - 40} more")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(records, indent=1) + "\n")
        print(f"\nfull result → {args.json}")

    if args.gate and buckets.get("UNRESOLVED"):
        print(
            f"\nverify-citations: FAILED — {len(buckets['UNRESOLVED'])} citation(s) "
            "resolve to nothing",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
