#!/usr/bin/env python3
"""English-text enrichment for data/sources/freeodwiki.json — stage 1 of 2.

FreeOD's substance prose is Chinese, and most of it was itself translated *from*
PsychonautWiki. So rather than machine-translating Chinese back into English (a
lossy round-trip), we recover the authentic English in two stages:

  STAGE 1 (this script): for every FreeOD record that has a PsychonautWiki page,
  pull the real PW lead prose via the MediaWiki extracts API (exintro+explaintext,
  redirects on). That text is attributed to PsychonautWiki, not machine-translated.
  Writes /tmp/freeod-trans/pw-leads.json {page_slug: {title, extract, query}} and
  /tmp/freeod-trans/mt-remainder.json (the page_slugs PW does NOT cover).

  STAGE 2 (offline LLM, not in this script): the remainder — obscure research
  chemicals PW lacks — is machine-translated from FreeOD's zh into English in
  PsychonautWiki's register, and effect names are mapped to canonical PW Subjective
  Effect Index names.

A merge step then writes description_en/description_en_source/description_en_mt,
mechanism_en/mechanism_en_mt, and subjective_effects_en back onto each record;
ingest_freeodwiki() in sqlite.py honours the source + flag so PW prose is
attributed to `psychonautwiki` and the translated remainder to `freeodwiki`.
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://psychonautwiki.org/w/api.php"
UA = "PiruApp/1.0 (harm-reduction substance app; +https://github.com/)"
CJK = re.compile(r"[一-鿿]")

REPO = Path(__file__).resolve().parents[3]
with open(REPO / "data/sources/freeodwiki.json", encoding="utf-8") as fh:
    recs = json.load(fh)


def candidates(rec):
    """English name candidates for a PW title lookup, best first."""
    out = []
    t = (rec.get("title") or "").strip()
    if t and not CJK.search(t):
        out.append(t)
    for n in rec.get("names") or []:
        n = (n or "").strip()
        # drop parenthetical, keep latin-only, length>=2
        n = re.sub(r"[（(].*?[)）]", "", n).strip()
        if n and not CJK.search(n) and len(n) >= 2 and n not in out:
            out.append(n)
    return out[:4]


# Build a query plan: map each candidate title -> list of page_slugs wanting it.
# Query in batches; redirects=1 resolves aliases (Molly -> MDMA).
slug_cands = {r["page_slug"]: candidates(r) for r in recs}
# Round 1 uses the first candidate for each record; later rounds retry the next.
leads = {}  # page_slug -> {title, extract, query}


def fetch_titles(titles):
    """Return {normalized_query_title: extract} for a batch of <=20 titles."""
    params = {
        "action": "query",
        "prop": "extracts",
        "exintro": "1",
        "explaintext": "1",
        "redirects": "1",
        "format": "json",
        "titles": "|".join(titles),
    }
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        d = json.load(resp)
    q = d.get("query", {})
    # Map requested title -> resolved title via normalized + redirects.
    alias = {}
    for n in q.get("normalized", []):
        alias[n["from"]] = n["to"]
    for r in q.get("redirects", []):
        alias[r["from"]] = r["to"]

    def resolve(t):
        seen = set()
        while t in alias and t not in seen:
            seen.add(t)
            t = alias[t]
        return t

    title_extract = {}
    for p in q.get("pages", {}).values():
        if "missing" in p:
            continue
        ex = (p.get("extract") or "").strip()
        if ex:
            title_extract[p["title"]] = ex
    # Map each requested title to an extract through the alias chain.
    res = {}
    for t in titles:
        res[t] = title_extract.get(resolve(t))
    return res


remaining = list(slug_cands.keys())
for round_i in range(4):
    # one candidate per still-unmatched record this round
    want = {}  # title -> [slugs]
    for s in remaining:
        if s in leads:
            continue
        cands = slug_cands[s]
        if round_i < len(cands):
            want.setdefault(cands[round_i], []).append(s)
    if not want:
        break
    titles = list(want.keys())
    print(f"round {round_i}: querying {len(titles)} titles", file=sys.stderr)
    for i in range(0, len(titles), 20):
        batch = titles[i : i + 20]
        try:
            res = fetch_titles(batch)
        except Exception as e:  # noqa: BLE001
            print(f"  batch error: {e}", file=sys.stderr)
            time.sleep(2)
            continue
        for t, ex in res.items():
            if ex:
                for s in want[t]:
                    if s not in leads:
                        leads[s] = {"title": t, "extract": ex, "query": t}
        time.sleep(0.5)

with open("/tmp/freeod-trans/pw-leads.json", "w", encoding="utf-8") as fh:
    json.dump(leads, fh, ensure_ascii=False, indent=1)
matched = set(leads)
missing = [r["page_slug"] for r in recs if r["page_slug"] not in matched]
print(f"\nPW leads matched: {len(matched)} / {len(recs)}")
print(f"no PW page (machine-translation remainder): {len(missing)}")
with open("/tmp/freeod-trans/mt-remainder.json", "w", encoding="utf-8") as fh:
    json.dump(missing, fh, ensure_ascii=False, indent=1)
