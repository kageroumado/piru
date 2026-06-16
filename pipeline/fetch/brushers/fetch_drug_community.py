#!/usr/bin/env python3
"""Fetch the full drug.community dataset via its public API, storing the raw
responses in-repo for versioned provenance.

drug.community is a JSON-powered encyclopedia of psychoactive substances. It
exposes a per-substance API:

    https://drug.community/api/info?name=<name | slug | alias>

and human-readable pages at https://drug.community/drug/<slug>, where the slug
is ``name.lower()`` with runs of non-alphanumeric characters collapsed to ``-``
(mirrored here by :func:`slugify`).

There is **no list endpoint**, so the substance roster is enumerated from the
single-page app's bundled dataset: the homepage references a content-hashed JS
asset that embeds every ``drug_name``. For each name we hit the official API and
keep the response verbatim.

Why store the responses in the repo: re-running this surfaces any upstream
change as a reviewable git diff. That gives Piru a visible history of where its
drug.community data came from and when — proof of best-effort sourcing, not an
opaque one-off export.

This is sanctioned first-party use of an API the site operator provided; the
fetcher identifies itself honestly via ``User-Agent`` and spaces its requests
out politely.

Usage:
    python3 pipeline/fetch/brushers/fetch_drug_community.py

Writes:
    data/sources/drug-community.json       — array of API responses, sorted by slug
    data/sources/drug-community.meta.json   — fetch provenance (when / how / how many)
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "data/sources/drug-community.json"
META = REPO / "data/sources/drug-community.meta.json"

BASE = "https://drug.community"
API = BASE + "/api/info"
# Honest identification — this is not a browser and not an AI crawler; it is
# Piru's first-party data fetcher pulling an API made available to the project.
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party API use; contact via repo)"
TIMEOUT = 20
DELAY = 0.35  # polite spacing between API calls (~2.5 min for the full roster)
RETRIES = 2

_NONALNUM = re.compile(r"[^a-z0-9]+")
_TRIM = re.compile(r"(^-|-$)")
_ASSET = re.compile(r'src="(/assets/[^"]+\.js)"')
_DRUG_NAME = re.compile(r'"drug_name":"((?:[^"\\]|\\.)*)"')


def slugify(name: str) -> str:
    """Mirror the site's slug function: lowercase, non-alphanumeric runs → '-'."""
    return _TRIM.sub("", _NONALNUM.sub("-", name.lower()))


def _get(url: str) -> bytes:
    last: Exception | None = None
    for attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json, text/html"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
            if attempt < RETRIES:
                time.sleep(1.5 * (attempt + 1))
    raise last  # type: ignore[misc]


def enumerate_names() -> tuple[list[str], str]:
    """Enumerate every drug_name from the SPA's bundled dataset.

    Returns the de-duplicated name list and the JS asset path it came from (so
    the build provenance can record exactly which deploy was scraped).
    """
    home = _get(BASE + "/").decode("utf-8", "replace")
    asset_match = _ASSET.search(home)
    if not asset_match:
        raise SystemExit("could not locate the JS asset in the drug.community homepage")
    asset = asset_match.group(1)
    js = _get(BASE + asset).decode("utf-8", "replace")
    raw_names = _DRUG_NAME.findall(js)
    seen: set[str] = set()
    names: list[str] = []
    for raw in raw_names:
        name = json.loads(f'"{raw}"')  # unescape JSON string escapes
        if name not in seen:
            seen.add(name)
            names.append(name)
    if not names:
        raise SystemExit("found the JS asset but no drug_name entries in it")
    return names, asset


def fetch_one(name: str) -> dict:
    url = API + "?" + urllib.parse.urlencode({"name": slugify(name)})
    obj = json.loads(_get(url))
    if not isinstance(obj, dict) or "drug_name" not in obj:
        raise ValueError(f"unexpected response for {name!r}: {str(obj)[:120]}")
    return obj


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    names, asset = enumerate_names()
    print(f"enumerated {len(names)} substances from {asset}")

    results: list[dict] = []
    failed: list[tuple[str, str]] = []
    for i, name in enumerate(names, 1):
        try:
            results.append(fetch_one(name))
        except Exception as exc:  # noqa: BLE001 - report and continue
            failed.append((name, str(exc)))
            print(f"  ! {name}: {exc}", file=sys.stderr)
        if i % 25 == 0:
            print(f"  {i}/{len(names)}")
        time.sleep(DELAY)

    # Canonicalize: key by slug (so aliases that resolve to the same entry can't
    # double-list it), then sort by slug for a stable, reviewable diff.
    by_slug: dict[str, dict] = {slugify(obj["drug_name"]): obj for obj in results}
    ordered = [by_slug[k] for k in sorted(by_slug)]

    prev = json.loads(OUT.read_text()) if OUT.exists() else []
    prev_names = {d.get("drug_name") for d in prev}
    new_names = {d["drug_name"] for d in ordered}

    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "drug.community",
                "api": API,
                "human_url_pattern": BASE + "/drug/{slug}",
                "fetched_at": fetched_at,
                "spa_asset": asset,
                "substance_count": len(ordered),
                "enumerated": len(names),
                "failed": [n for n, _ in failed],
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    print(f"\nwrote {len(ordered)} substances → {OUT.relative_to(REPO)}")
    added = sorted(new_names - prev_names)
    removed = sorted(prev_names - new_names)
    print(f"  added ({len(added)}):   {added}")
    print(f"  removed ({len(removed)}): {removed}")
    print(f"  failed ({len(failed)}):  {[n for n, _ in failed]}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
