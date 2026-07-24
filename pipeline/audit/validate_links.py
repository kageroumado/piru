#!/usr/bin/env python3
"""Validate the citation links Piru ships, caching the results in the repo.

Re-hitting every link on each build is wasteful and rude, so we check each
unique URL at most once and remember the verdict + date in
``data/sources/link-cache.json``. A re-run only re-checks URLs that are new,
that last came back not-ok, or whose check is older than ``STALE_DAYS``. The
committed cache is the proof that we verified each link existed at some point —
we can't be responsible for pages that later move, but we can show we checked.

Verdicts:
  - ``ok``      — final status 200–399 (the page existed when checked).
  - ``dead``    — 404 / 410 / other hard 4xx (gone). A candidate for removal.
  - ``unknown`` — timeout, connection error, 403/429 (bot-blocked, not proof of
                  death), or 5xx. Left for a later re-check; never auto-removed.

Usage:
    python3 pipeline/audit/validate_links.py [--all] [--max N] [--stale-days D]
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, date, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
CACHE = REPO / "data/sources/link-cache.json"

UA = "Piru-LinkCheck/1.0 (+https://github.com/kageroumado/piru; citation link validation)"
TIMEOUT = 15
STALE_DAYS = 30
WORKERS = 8


def classify(status: int | None, error: str | None) -> str:
    """Map an HTTP status / transport error to a verdict. Pure — unit-tested."""
    if error is not None:
        return "unknown"
    if status is None:
        return "unknown"
    if 200 <= status < 400:
        return "ok"
    if status in (403, 429) or status >= 500:
        return "unknown"  # bot-blocked or server-side — not proof of death
    return "dead"  # 404 / 410 / other hard 4xx


def needs_recheck(entry: dict | None, today: date, stale_days: int) -> bool:
    """Whether a cached entry should be re-validated. Pure — unit-tested."""
    if entry is None:
        return True
    if entry.get("verdict") != "ok":
        return True  # retry dead/unknown — sites recover, blocks lift
    checked = entry.get("checked")
    if not checked:
        return True
    try:
        age = (today - date.fromisoformat(checked)).days
    except ValueError:
        return True
    return age >= stale_days


def _open(url: str, method: str) -> tuple[int | None, str | None, str | None]:
    req = urllib.request.Request(url, method=method, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.geturl(), None
    except urllib.error.HTTPError as exc:
        return exc.code, url, None
    except Exception as exc:  # noqa: BLE001 - transport/timeout → unknown
        return None, url, type(exc).__name__


def check_url(url: str) -> dict:
    """HEAD first (cheap); fall back to GET when a server rejects HEAD."""
    status, final, error = _open(url, "HEAD")
    if error is not None or (status is not None and status in (403, 405, 501)):
        status, final, error = _open(url, "GET")
    return {
        "status": status,
        "final_url": final if final and final != url else None,
        "verdict": classify(status, error),
        "error": error,
    }


def load_cache() -> dict[str, dict]:
    if CACHE.exists():
        return json.loads(CACHE.read_text())
    return {}


def save_cache(cache: dict[str, dict]) -> None:
    ordered = {k: cache[k] for k in sorted(cache)}
    CACHE.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")


#: A well-formed DOI: `10.` + registrant + `/` + suffix (DOI handbook §2.2).
_DOI_RE = re.compile(r"^10\.\d{4,9}/\S+$")


def doi_url(doi: str) -> str:
    return f"https://doi.org/{doi}"


def pmid_url(pmid: int) -> str:
    return f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"


def db_links() -> list[str]:
    """Every distinct citation link Piru ships, as a resolvable URL — raw
    `url` links **plus** DOIs (→ doi.org) and PMIDs (→ pubmed), so a dead DOI is
    caught the same way a dead URL is. Malformed DOIs are dropped here and
    reported separately by ``malformed_citations``."""
    db = sqlite3.connect(DB)
    try:
        urls = [
            r[0]
            for r in db.execute(
                "SELECT DISTINCT url FROM citations WHERE url LIKE 'http%'"
            ).fetchall()
        ]
        dois = [
            doi_url(r[0])
            for r in db.execute(
                "SELECT DISTINCT doi FROM citations WHERE doi IS NOT NULL AND doi != ''"
            ).fetchall()
            if _DOI_RE.match(r[0])
        ]
        pmids = [
            pmid_url(r[0])
            for r in db.execute(
                "SELECT DISTINCT pmid FROM citations WHERE pmid IS NOT NULL"
            ).fetchall()
        ]
    finally:
        db.close()
    return sorted(set(urls) | set(dois) | set(pmids))


def malformed_citations() -> list[str]:
    """Offline heuristic gate: citations whose identifier is present but
    structurally invalid (a DOI that isn't `10.x/...`). These can never resolve,
    so they're build errors regardless of network state."""
    db = sqlite3.connect(DB)
    try:
        bad = [
            f"DOI {r[0]!r}" + (f" ({r[1]})" if r[1] else "")
            for r in db.execute(
                "SELECT doi, title FROM citations WHERE doi IS NOT NULL AND doi != ''"
            ).fetchall()
            if not _DOI_RE.match(r[0])
        ]
    finally:
        db.close()
    return sorted(bad)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--all", action="store_true", help="re-check every URL, ignoring cache freshness"
    )
    ap.add_argument("--max", type=int, default=0, help="cap the number of live checks this run")
    ap.add_argument("--stale-days", type=int, default=STALE_DAYS)
    ap.add_argument(
        "--gate",
        action="store_true",
        help="offline build gate: never hit the network; exit non-zero if any shipped "
        "citation is malformed or DEAD in the committed cache. Wired into pipeline/build.sh.",
    )
    args = ap.parse_args()

    # --- Offline heuristic: malformed identifiers can never resolve. ---
    malformed = malformed_citations()
    if malformed:
        print(f"MALFORMED citation identifier(s) ({len(malformed)}):", file=sys.stderr)
        for m in malformed:
            print(f"    {m}", file=sys.stderr)

    today = datetime.now(UTC).date()
    urls = db_links()
    cache = load_cache()

    # --- Build gate: verify against the committed cache, no network. ---
    if args.gate:
        shipped = set(urls)
        dead = sorted(u for u, e in cache.items() if u in shipped and e.get("verdict") == "dead")
        if dead:
            print(f"\nDEAD shipped citation link(s) ({len(dead)}):", file=sys.stderr)
            for u in dead:
                print(f"    {u}", file=sys.stderr)
        unchecked = sorted(u for u in shipped if u not in cache)
        if unchecked:
            print(
                f"\n{len(unchecked)} shipped link(s) not yet in the cache — run "
                f"`python3 pipeline/audit/validate_links.py` (network) to check them.",
                file=sys.stderr,
            )
        if malformed or dead:
            print(
                f"\nGATE FAILED: {len(malformed)} malformed, {len(dead)} dead. "
                f"Fix the citation(s) or replace the identifier.",
                file=sys.stderr,
            )
            return 1
        print(f"gate OK — {len(shipped)} shipped links, none malformed or dead in cache.")
        return 0

    # Retain DEAD verdicts as an audit trail even after the build drops those
    # citations — they are the proof we found and removed a broken link. Prune
    # only ok/unknown entries for URLs no longer shipped, to keep the file lean.
    live = set(urls)
    for stale_url in [u for u, e in cache.items() if u not in live and e.get("verdict") != "dead"]:
        del cache[stale_url]

    todo = [u for u in urls if args.all or needs_recheck(cache.get(u), today, args.stale_days)]
    if args.max and len(todo) > args.max:
        todo = todo[: args.max]

    print(f"{len(urls)} unique link(s); {len(todo)} to check ({len(urls) - len(todo)} cached)")

    checked = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for url, result in zip(todo, pool.map(check_url, todo), strict=True):
            cache[url] = {
                "verdict": result["verdict"],
                "status": result["status"],
                "checked": today.isoformat(),
                **({"final_url": result["final_url"]} if result["final_url"] else {}),
                **({"error": result["error"]} if result["error"] else {}),
            }
            checked += 1
            if checked % 50 == 0:
                print(f"  {checked}/{len(todo)}")

    save_cache(cache)

    tally: dict[str, int] = {}
    for entry in cache.values():
        tally[entry["verdict"]] = tally.get(entry["verdict"], 0) + 1
    print(f"\ncache → {CACHE.relative_to(REPO)}  ({len(cache)} links)")
    print(
        f"  ok={tally.get('ok', 0)}  dead={tally.get('dead', 0)}  unknown={tally.get('unknown', 0)}"
    )
    dead = sorted(u for u, e in cache.items() if e["verdict"] == "dead")
    if dead:
        print(f"\n  DEAD ({len(dead)}):")
        for u in dead[:40]:
            print(f"    {u}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
