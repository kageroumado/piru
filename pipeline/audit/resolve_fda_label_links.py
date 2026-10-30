#!/usr/bin/env python3
"""Replace dead Drugs@FDA label PDFs with the DailyMed label they superseded to.

FDA moves a label PDF (`accessdata.fda.gov/drugsatfda_docs/label/<year>/<appl>…
lbl.pdf`) whenever it publishes a revision, so a cited PDF goes dead while the
product's label lives on. `data/sources/link-cache.json` records the dead ones.
Each is resolved deterministically:

  1. **Application number** from the filename (`/label/2013/021303s026lbl.pdf`
     → 021303), tried as NDA, then BLA, then ANDA.
  2. **Label** through DailyMed's own SPL service (`spls.json?application_number=`),
     or, when the application lists no current label, by its Drugs@FDA brand name.
     Several labels (the brand plus authorized generics) resolve to the one titled
     with the brand, else the one the Drugs@FDA sponsor labels; otherwise none.
  3. **Verified**: the SPL title or the DailyMed page body names a substance that
     cites the old link — the same fetch and body extraction the source-link gate
     uses (`source_link_check.fetch` + `visible_text`). A filename's number is not
     always the application the PDF belonged to, so this check is load-bearing.

Resolutions are cached in `data/sources/fda-label-setids.json` (committed).
`--write` rewrites each resolved URL in `data/curated/` and
`data/enrichment/raw/` to `https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=…`,
labelled with the product when the reference was a bare URL. A link that does
not resolve is left for the build to drop as dead.

    python3 pipeline/audit/resolve_fda_label_links.py --fetch          # resolve, report
    python3 pipeline/audit/resolve_fda_label_links.py --write          # rewrite inputs from the cache
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import urllib.parse
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit.source_link_check import (  # noqa: E402
    HostThrottle,
    fetch,
    normalize_for_match,
    visible_text,
)

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
LINK_CACHE = REPO / "data/sources/link-cache.json"
CACHE = REPO / "data/sources/fda-label-setids.json"
INPUTS = [REPO / "data/curated", REPO / "data/enrichment/raw"]
SPLS = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?application_number="
DRUGSFDA = "https://api.fda.gov/drug/drugsfda.json?limit=1&search=application_number:"
PAGE = "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid="
_APPL = re.compile(r"/label/\d{4}/0*(\d{5,6})[a-z]")


def dead_fda_links() -> list[str]:
    cache = json.loads(LINK_CACHE.read_text())
    return sorted(
        url
        for url, entry in cache.items()
        if entry.get("verdict") == "dead" and "accessdata.fda.gov" in url and _APPL.search(url)
    )


def citing_names(conn: sqlite3.Connection, url: str) -> list[str]:
    """Every name of every substance whose rows cite `url`."""
    sids: set[int] = set()
    tables = [
        t
        for (t,) in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        if {"citation_id", "substance_id"}
        <= {c[1] for c in conn.execute(f'PRAGMA table_info("{t}")')}
    ]
    for (cid,) in conn.execute("SELECT id FROM citations WHERE url = ?", (url,)):
        for table in tables:
            sids |= {
                s
                for (s,) in conn.execute(
                    f'SELECT substance_id FROM "{table}" WHERE citation_id = ?', (cid,)
                )
            }
    names: list[str] = []
    for sid in sorted(sids):
        names += [
            n for (n,) in conn.execute("SELECT canonical_name FROM substances WHERE id = ?", (sid,))
        ]
        names += [
            a for (a,) in conn.execute("SELECT alias FROM aliases WHERE substance_id = ?", (sid,))
        ]
    return names


def labeler(title: str) -> str:
    """The bracketed labeler at the end of an SPL title, normalized."""
    match = re.search(r"\[([^\]]+)\]\s*$", title or "")
    return normalize_for_match(match.group(1)) if match else ""


def _json(url: str, throttle: HostThrottle, key: str) -> list[dict]:
    response = fetch(url, throttle)
    if response.status != 200:
        return []
    try:
        return json.loads(response.text).get(key) or []
    except ValueError:
        return []


def application_record(number: str, throttle: HostThrottle) -> tuple[str | None, dict]:
    """The Drugs@FDA record for an application number, trying NDA, BLA, ANDA."""
    for prefix in ("NDA", "BLA", "ANDA"):
        application = f"{prefix}{number}"
        results = _json(DRUGSFDA + urllib.parse.quote(f'"{application}"'), throttle, "results")
        if results:
            return application, results[0]
    return None, {}


def choose(labels: list[dict], brands: set[str], sponsor: str) -> tuple[dict | None, str]:
    """One label out of an application's labels: the only one, else the one
    titled with the application's brand, else the one its sponsor labels."""
    if len(labels) == 1:
        return labels[0], "only label"
    branded = [
        lab
        for lab in labels
        if any(normalize_for_match(lab["title"]).startswith(b) for b in brands)
    ]
    if len(branded) == 1:
        return branded[0], "brand label"
    pool = branded or labels
    head = sponsor[:5]
    sponsored = [lab for lab in pool if head and labeler(lab["title"]).startswith(head)]
    if len(sponsored) == 1:
        return sponsored[0], "sponsor's label"
    if branded:
        # Every candidate is the brand's label reissued by a repackager, which
        # copies the manufacturer's text; any one is the same label, so the
        # lowest set id is taken to keep the choice stable.
        return min(branded, key=lambda lab: lab["setid"]), "brand label (repackaged copy)"
    return None, f"{len(pool)} labels, none titled with the brand or labelled by the sponsor"


def resolve(url: str, names: list[str], throttle: HostThrottle) -> dict:
    number = _APPL.search(url).group(1).zfill(6)
    entry: dict = {"checked": date.today().isoformat()}
    keys = {k for k in map(normalize_for_match, names) if len(k) >= 4}
    application, record = application_record(number, throttle)
    entry["application"] = application
    brands = {
        normalize_for_match(product.get("brand_name") or "")
        for product in record.get("products") or []
        if product.get("brand_name")
    }
    sponsor = normalize_for_match(record.get("sponsor_name") or "")
    labels: list[dict] = []
    for candidate in [application] if application else [f"NDA{number}", f"BLA{number}"]:
        labels = _json(SPLS + urllib.parse.quote(candidate), throttle, "data")
        if labels:
            break
    if not labels:
        # The application lists no current label, but its brand may: a product
        # relabelled under a new application keeps its name.
        for brand in sorted(b for b in brands if len(b) >= 4):
            found = _json(
                "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?drug_name="
                + urllib.parse.quote(brand),
                throttle,
                "data",
            )
            labels += [lab for lab in found if normalize_for_match(lab["title"]).startswith(brand)]
    if not labels:
        entry["verdict"] = "no DailyMed label for the application or its brand"
        return entry
    label, how = choose(labels, brands, sponsor)
    entry["chosen_by"] = how
    if label is None:
        entry["verdict"] = how
        return entry
    entry["setid"] = label["setid"]
    entry["title"] = label["title"]
    title_names = sorted(k for k in keys if k in normalize_for_match(label["title"]))
    page = fetch(PAGE + label["setid"], throttle)
    body = (
        normalize_for_match(visible_text(page.text, body_only=True)) if page.status == 200 else ""
    )
    page_names = sorted(k for k in keys if k in body)
    entry["names"] = title_names or page_names
    entry["verdict"] = "ok" if entry["names"] else "label names no citing substance"
    return entry


def product(title: str) -> str:
    named = re.match(r"\s*([^(\[]+?)\s*\(([^)]+)\)", title or "")
    if named:
        return f"{named.group(1).title()} ({named.group(2).lower()})"
    bare = re.match(
        r"\s*([^\[,]+?)\s+(?:TABLET|CAPSULE|INJECTION|SOLUTION|SPRAY|FILM|KIT)", title or ""
    )
    return bare.group(1).title() if bare else "Product"


def rewrite_inputs(resolved: dict[str, dict]) -> Counter:
    """Replace each resolved URL in the input files. A bare-URL reference gains
    the product as its label; a labelled one keeps its label."""
    counts: Counter = Counter()
    for root in INPUTS:
        for path in sorted(root.rglob("*.json")):
            text = path.read_text()
            new = text
            for old, entry in resolved.items():
                if old not in new:
                    continue
                target = PAGE + entry["setid"]
                bare = json.dumps(old)
                labelled = json.dumps(
                    f"{product(entry['title'])} label; {target}", ensure_ascii=False
                )
                if bare in new:
                    new = new.replace(bare, labelled)
                new = new.replace(old, target)
                counts["references rewritten"] += 1
            if new != text:
                path.write_text(new)
                counts["files"] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--fetch", action="store_true", help="resolve uncached links")
    parser.add_argument("--write", action="store_true", help="rewrite the input files")
    args = parser.parse_args()

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    throttle = HostThrottle(0.4)
    links = dead_fda_links()
    for url in links:
        if url not in cache and args.fetch:
            cache[url] = resolve(url, citing_names(conn, url), throttle)
    conn.close()
    if args.fetch:
        CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True, ensure_ascii=False) + "\n")

    verdicts = Counter(cache.get(url, {}).get("verdict", "not resolved yet") for url in links)
    print(f"resolve-fda-label-links: {len(links)} dead FDA label link(s)")
    for verdict, n in verdicts.most_common():
        print(f"  {n:4d}  {verdict}")
    unresolved = defaultdict(list)
    for url in links:
        if cache.get(url, {}).get("verdict") != "ok":
            unresolved[cache.get(url, {}).get("verdict", "?")].append(url)
    for verdict, urls in unresolved.items():
        for url in urls:
            print(f"  ✗ {verdict}: {url}")
    if args.write:
        resolved = {u: cache[u] for u in links if cache.get(u, {}).get("verdict") == "ok"}
        print(dict(rewrite_inputs(resolved)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
