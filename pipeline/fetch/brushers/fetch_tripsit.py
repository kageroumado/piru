#!/usr/bin/env python3
"""Snapshot the TripSit ``drugs.json`` dataset into the repo for versioned
provenance — the same pattern as fetch_drug_community.py.

TripSit publishes its harm-reduction factsheet corpus as a single JSON document
(a map of slug → substance) at a stable GitHub raw URL. Committing a normalized
copy means a re-fetch surfaces any upstream change as a reviewable git diff:
visible history of where Piru's TripSit-derived dose/duration/effect data came
from, and when.

Note: the build currently ingests TripSit through the Swift SubstanceCollector,
which fetches this same URL. This snapshot is the committed provenance record of
that upstream state (re-fetch → diff → notice changes); switching the build to
read the snapshot directly is a clean follow-up.

Usage:
    python3 pipeline/fetch/brushers/fetch_tripsit.py

Writes:
    data/sources/tripsit.json       — the drugs.json corpus, sorted by slug
    data/sources/tripsit.meta.json   — fetch provenance (when / source / count)
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "data/sources/tripsit.json"
META = REPO / "data/sources/tripsit.meta.json"

SOURCE = "https://raw.githubusercontent.com/TripSit/drugs/master/drugs.json"
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"
TIMEOUT = 30
RETRIES = 2


def _get(url: str) -> bytes:
    last: Exception | None = None
    for _attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
    raise last  # type: ignore[misc]


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    data = json.loads(_get(SOURCE))
    if not isinstance(data, dict) or not data:
        raise SystemExit(f"unexpected TripSit payload: {type(data).__name__}")

    prev = json.loads(OUT.read_text()) if OUT.exists() else {}

    # Sort by slug for a stable, reviewable diff (preserve each entry's key order).
    ordered = {slug: data[slug] for slug in sorted(data)}
    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "TripSit drugs.json",
                "url": SOURCE,
                "human_url_pattern": "https://drugs.tripsit.me/{slug}",
                "fetched_at": fetched_at,
                "substance_count": len(ordered),
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    added = sorted(set(ordered) - set(prev))
    removed = sorted(set(prev) - set(ordered))
    print(f"wrote {len(ordered)} substances → {OUT.relative_to(REPO)}")
    print(f"  added ({len(added)}):   {added}")
    print(f"  removed ({len(removed)}): {removed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
