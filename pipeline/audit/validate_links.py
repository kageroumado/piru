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


def db_urls() -> list[str]:
    db = sqlite3.connect(DB)
    try:
        rows = db.execute(
            "SELECT DISTINCT url FROM citations WHERE url LIKE 'http%' ORDER BY url"
        ).fetchall()
    finally:
        db.close()
    return [r[0] for r in rows]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--all", action="store_true", help="re-check every URL, ignoring cache freshness"
    )
    ap.add_argument("--max", type=int, default=0, help="cap the number of live checks this run")
    ap.add_argument("--stale-days", type=int, default=STALE_DAYS)
    args = ap.parse_args()

    today = datetime.now(UTC).date()
    urls = db_urls()
    cache = load_cache()

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
