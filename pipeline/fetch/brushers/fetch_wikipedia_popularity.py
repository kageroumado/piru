#!/usr/bin/env python3
"""Derive a reproducible popularity signal from English-Wikipedia pageviews.

Popularity drives the library's "by popularity" sort — it should surface
recognizable substances above the long tail of obscure research chemicals. Hand
numbers aren't defensible; pageviews are: every value traces to a public
Wikimedia API and the committed snapshot is the provenance.

Method, per substance:
  1. Resolve a candidate name (canonical name / display name / clean aliases) to
     an English-Wikipedia article, following redirects, skipping disambiguation.
  2. Verify the article is actually a chemical/drug — its Wikidata item must
     carry a chemical identifier (PubChem CID / InChIKey / ChEMBL / ChemSpider).
     This stops generic-word collisions (our "Cake" joke entry must NOT inherit
     the dessert's pageviews; "Ice" must not become frozen water).
  3. Sum the last 12 complete months of pageviews for that article.
Scores are log-normalized to [0,1] (pageviews are heavy-tailed: cannabis dwarfs
2-Bromo-4,5-MDMA by orders of magnitude).

Usage:
    python3 pipeline/fetch/brushers/fetch_wikipedia_popularity.py

Writes:
    data/sources/wikipedia-popularity.json       — {name: {article, monthly_views, score}}
    data/sources/wikipedia-popularity.meta.json   — fetch provenance
"""

from __future__ import annotations

import json
import math
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DB = REPO / "Piru/Data/piru-substances.sqlite"
OUT = REPO / "data/sources/wikipedia-popularity.json"
META = REPO / "data/sources/wikipedia-popularity.meta.json"

UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"
WP_API = "https://en.wikipedia.org/w/api.php"
WD_API = "https://www.wikidata.org/w/api.php"
PV_API = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/all-agents"
# Wikidata properties that mark an item as a chemical compound / drug.
CHEM_PROPS = {"P662", "P235", "P592", "P661", "P231"}  # PubChem, InChIKey, ChEMBL, ChemSpider, CAS
TIMEOUT = 30
MONTHS = 12

# Substance names that collide with a high-traffic *non-drug* chemical article
# (and so inherit absurd pageviews): elements/biomolecules nobody takes as the
# drug. NOT the legit mineral supplements (Magnesium/Iron/Zinc/Selenium/…), whose
# element-article views are a fair popularity proxy.
NON_DRUG_NAMES = {
    "dna",
    "rna",
    "silver",
    "hydrogen",
    "oxygen",
    "nitrogen",
    "carbon",
    "helium",
    "gold",
    "water",
    "air",
    "salt",
    "sugar",
    "ozone",
    "carbon dioxide",
}


def _get(url: str) -> dict | None:
    for _ in range(3):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            time.sleep(1)
        except (urllib.error.URLError, TimeoutError):
            time.sleep(1)
    return None


def substances() -> list[dict]:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT id, canonical_name, display_name FROM substances ORDER BY canonical_name"
        ).fetchall()
        aliases: dict[int, list[str]] = {}
        for sid, alias in con.execute("SELECT substance_id, alias FROM aliases"):
            aliases.setdefault(sid, []).append(alias)
    finally:
        con.close()
    out = []
    for sid, name, display in rows:
        out.append({"id": sid, "name": name, "display": display, "aliases": aliases.get(sid, [])})
    return out


def _clean_candidates(s: dict) -> list[str]:
    """Plausible Wikipedia-title candidates: the name, then short latin aliases.
    Skip CJK / overlong / numeric-only aliases that never title an article."""
    cands = [s["name"]]
    if s["display"]:
        cands.append(s["display"])
    for a in s["aliases"]:
        if 2 <= len(a) <= 40 and a.isascii() and any(c.isalpha() for c in a):
            cands.append(a)
    seen, uniq = set(), []
    for c in cands:
        k = c.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(c)
    return uniq[:6]


def resolve_titles(titles: list[str]) -> dict[str, dict]:
    """Batch-resolve up to 50 titles → {input: {article, qid, disambig}} for the
    ones that land on a real article (redirects followed)."""
    out: dict[str, dict] = {}
    for i in range(0, len(titles), 50):
        chunk = titles[i : i + 50]
        params = {
            "action": "query",
            "format": "json",
            "redirects": "1",
            "prop": "pageprops",
            "ppprop": "disambiguation|wikibase_item",
            "titles": "|".join(chunk),
        }
        d = _get(f"{WP_API}?{urllib.parse.urlencode(params)}")
        if not d:
            continue
        q = d.get("query", {})
        # input → normalized → redirect target
        norm = {n["from"]: n["to"] for n in q.get("normalized", [])}
        redir = {r["from"]: r["to"] for r in q.get("redirects", [])}
        pages = {p.get("title"): p for p in q.get("pages", {}).values()}
        for t in chunk:
            cur = norm.get(t, t)
            cur = redir.get(cur, cur)
            p = pages.get(cur)
            if not p or "missing" in p:
                continue
            pp = p.get("pageprops", {})
            out[t] = {
                "article": p["title"],
                "qid": pp.get("wikibase_item"),
                "disambig": "disambiguation" in pp,
            }
        time.sleep(0.2)
    return out


def chemical_qids(qids: list[str]) -> set[str]:
    """The subset of Wikidata items carrying a chemical-identifier property."""
    ok: set[str] = set()
    qids = [q for q in qids if q]
    for i in range(0, len(qids), 50):
        chunk = qids[i : i + 50]
        params = {
            "action": "wbgetentities",
            "format": "json",
            "props": "claims",
            "ids": "|".join(chunk),
        }
        d = _get(f"{WD_API}?{urllib.parse.urlencode(params)}")
        if not d:
            continue
        for qid, ent in d.get("entities", {}).items():
            claims = ent.get("claims", {})
            if CHEM_PROPS & set(claims):
                ok.add(qid)
        time.sleep(0.2)
    return ok


def _date_range() -> tuple[str, str]:
    now = datetime.now(UTC)
    # End at the first of the current month (exclusive of the partial month);
    # start MONTHS before that.
    end_y, end_m = now.year, now.month
    sy = end_y - (MONTHS // 12)
    sm = end_m - (MONTHS % 12)
    if sm <= 0:
        sm += 12
        sy -= 1
    return f"{sy:04d}{sm:02d}01", f"{end_y:04d}{end_m:02d}01"


def pageviews(article: str, start: str, end: str) -> int:
    title = urllib.parse.quote(article.replace(" ", "_"), safe="")
    d = _get(f"{PV_API}/{title}/monthly/{start}/{end}")
    if not d:
        return 0
    return sum(item.get("views", 0) for item in d.get("items", []))


def _fetch_views_for(subs: list[dict]) -> dict[str, dict]:
    """Resolve → chemical-verify → pageviews for the given substances. Returns
    {name: {article, monthly_views}} for the ones that map to a chemical article.
    This is the only part that hits the network."""
    all_titles: list[str] = []
    for s in subs:
        s["candidates"] = _clean_candidates(s)
        all_titles.extend(s["candidates"])
    resolved = resolve_titles(sorted(set(all_titles)))
    print(f"resolved {len(resolved)} / {len(set(all_titles))} candidate titles", file=sys.stderr)

    qids = {r["qid"] for r in resolved.values() if r["qid"] and not r["disambig"]}
    chem = chemical_qids(sorted(qids))
    print(f"{len(chem)} / {len(qids)} resolved articles are chemicals", file=sys.stderr)

    article_of: dict[str, str] = {}
    for s in subs:
        for c in s["candidates"]:
            r = resolved.get(c)
            if r and not r["disambig"] and r["qid"] in chem:
                article_of[s["name"]] = r["article"]
                break

    start, end = _date_range()
    uniq = sorted(set(article_of.values()))
    views: dict[str, int] = {}
    with ThreadPoolExecutor(max_workers=12) as pool:
        futs = {pool.submit(pageviews, art, start, end): art for art in uniq}
        for i, fut in enumerate(as_completed(futs)):
            views[futs[fut]] = fut.result()
            if i % 200 == 0:
                print(f"  pageviews {i}/{len(uniq)}", file=sys.stderr)
    return {
        name: {"article": art, "monthly_views": round(views[art] / MONTHS)}
        for name, art in article_of.items()
    }


def main() -> int:
    # Incremental by default: the committed snapshot is the cache, so a re-run
    # only fetches substances added since (no ~2000 requests per run). `--all`
    # forces a full refresh of the pageview numbers.
    force_all = "--all" in sys.argv
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    subs = [s for s in substances() if s["name"].lower() not in NON_DRUG_NAMES]
    db_names = {s["name"] for s in subs}
    existing = {} if (force_all or not OUT.exists()) else json.loads(OUT.read_text())
    # The set of substances already *attempted* (mapped or not) lives in the meta
    # so unmapped ones aren't re-resolved every run — only genuinely new names are.
    checked = set()
    if not force_all and META.exists():
        checked = set(json.loads(META.read_text()).get("checked", []))

    todo = [s for s in subs if s["name"] not in checked]
    print(
        f"{'full refresh' if force_all else 'incremental'}: "
        f"{len(existing)} cached, {len(todo)} to fetch",
        file=sys.stderr,
    )
    fetched = _fetch_views_for(todo) if todo else {}

    # Merge cached + new, keyed by the live DB names (prunes removed substances).
    merged: dict[str, dict] = {}
    for name in db_names:
        if name in fetched:
            merged[name] = fetched[name]
        elif name in existing:
            e = existing[name]
            merged[name] = {"article": e["article"], "monthly_views": e["monthly_views"]}

    # Re-normalize ALL entries on the current global max — cheap, no network — so
    # newly-added substances slot onto the same [0,1] scale as the cached ones.
    maxlog = math.log10(max((m["monthly_views"] for m in merged.values()), default=1) + 1) or 1.0
    out = {
        name: {
            "article": m["article"],
            "monthly_views": m["monthly_views"],
            "score": round(math.log10(m["monthly_views"] + 1) / maxlog, 4),
        }
        for name, m in merged.items()
    }

    ordered = {k: out[k] for k in sorted(out)}
    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "English Wikipedia pageviews (Wikimedia REST), chemical-verified via Wikidata",
                "window": f"{_date_range()[0]}–{_date_range()[1]} ({MONTHS} months)",
                "fetched_at": fetched_at,
                "newly_fetched": len(fetched),
                "mapped": len(ordered),
                "of_total": len(subs),
                "normalization": "score = log10(monthly_views+1) / log10(max+1)",
                "checked": sorted(db_names),
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )
    print(
        f"wrote {len(ordered)} / {len(subs)} substances → {OUT.relative_to(REPO)}", file=sys.stderr
    )
    top = sorted(ordered.items(), key=lambda kv: -kv[1]["score"])[:12]
    for name, d in top:
        print(
            f"  {d['score']:.3f}  {name}  ({d['article']}, {d['monthly_views']}/mo)",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
