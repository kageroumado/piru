#!/usr/bin/env python3
"""Fetch the full drug.community dataset via its public API, storing the raw
responses in-repo for versioned provenance.

drug.community is a JSON-powered encyclopedia of psychoactive substances, and
human-readable pages live at https://drug.community/drug/<slug>, where the slug
is ``name.lower()`` with runs of non-alphanumeric characters collapsed to ``-``
(mirrored here by :func:`slugify`).

As of the Sept-2025 redesign the whole substance roster ships in a single
MongoDB-backed bootstrap payload rather than one API call per name:

    GET https://drug.community/api/data/bootstrap  ->  { drugs: [...], ... }

Each element of ``drugs`` is the same rich per-substance object the old
``/api/info?name=<X>`` endpoint returned (drug_name, dosages, duration,
duration_curves, subjective_effects, interactions, tolerance, half_life,
citations, categories, …), so downstream consumers are unaffected — only the
transport changed. We still record the content-hashed SPA asset from the
homepage so the git history pins exactly which deploy each snapshot came from.

Why store the responses in the repo: re-running this surfaces any upstream
change as a reviewable git diff. That gives Piru a visible history of where its
drug.community data came from and when — proof of best-effort sourcing, not an
opaque one-off export.

This is sanctioned first-party use of an API the site operator provided; the
fetcher identifies itself honestly via ``User-Agent``.

Usage:
    python3 pipeline/fetch/brushers/fetch_drug_community.py

Writes:
    data/sources/drug-community.json       — array of drug profiles, sorted by slug
    data/sources/drug-community.meta.json   — fetch provenance (when / how / how many)
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SOURCES = REPO / "data/sources"
OUT = SOURCES / "drug-community.json"
META = SOURCES / "drug-community.meta.json"
# Companion datasets added in the Sept-2025 redesign (see fetch_extra_datasets).
SPECTRA_OUT = SOURCES / "drug-community-spectra.json"
EFFECTS_OUT = SOURCES / "drug-community-effects.json"
COMBOS_OUT = SOURCES / "drug-community-combinations.json"

BASE = "https://drug.community"
API = BASE + "/api/data/bootstrap"
DATA_API = BASE + "/api/data"
# Honest identification — this is not a browser and not an AI crawler; it is
# Piru's first-party data fetcher pulling an API made available to the project.
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party API use; contact via repo)"
TIMEOUT = 30
RETRIES = 2

_NONALNUM = re.compile(r"[^a-z0-9]+")
_TRIM = re.compile(r"(^-|-$)")
_ASSET = re.compile(r'src="(/assets/[^"]+\.js)"')


def slugify(name: str) -> str:
    """Mirror the site's slug function: lowercase, non-alphanumeric runs → '-'."""
    return _TRIM.sub("", _NONALNUM.sub("-", name.lower()))


def _get(url: str, accept: str = "application/json, text/html") -> bytes:
    last: Exception | None = None
    for attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
            if attempt < RETRIES:
                time.sleep(1.5 * (attempt + 1))
    raise last  # type: ignore[misc]


def current_asset() -> str | None:
    """The content-hashed SPA bundle the homepage currently references.

    Recorded purely as deploy provenance — it pins which build a snapshot was
    taken against. Best-effort: returns None rather than failing the fetch.
    """
    try:
        home = _get(BASE + "/", accept="text/html").decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - provenance only
        return None
    match = _ASSET.search(home)
    return match.group(1) if match else None


def fetch_bootstrap() -> list[dict]:
    """Fetch the full roster from the MongoDB-backed bootstrap payload.

    The data API only returns JSON when the request forbids text/html — a
    browser-style Accept gets the SPA's index.html fallback instead.
    """
    payload = json.loads(_get(API, accept="application/json"))
    drugs = payload.get("drugs") if isinstance(payload, dict) else None
    if not isinstance(drugs, list) or not drugs:
        raise SystemExit(
            "bootstrap payload had no 'drugs' array — the API shape may have changed again"
        )
    for d in drugs:
        if not isinstance(d, dict) or "drug_name" not in d:
            raise SystemExit(f"unexpected drug entry in bootstrap: {str(d)[:120]}")
    return drugs


def _write_json(path: Path, obj) -> int:
    """Write ``obj`` canonically (sorted keys, one trailing newline) and return
    its size in KB — canonicalization keeps re-fetch diffs to real changes."""
    text = json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    path.write_text(text)
    return len(text.encode("utf-8")) // 1024


def fetch_extra_datasets() -> None:
    """Snapshot the companion datasets the Sept-2025 redesign introduced.

    These live behind ``/api/data/<name>`` and are fetched once by the SPA then
    indexed client-side. We keep card-relevant slices verbatim so any upstream
    change shows up as a reviewable git diff, mirroring the main roster snapshot.
    Volatile MongoDB bookkeeping (``_id``, ``cache_key``, timestamps) is stripped
    so it can't churn the diff, and aggregate reverse-indices the app rebuilds on
    its own are dropped to keep the files reviewable. Best-effort: a failure here
    is logged but never aborts the core roster fetch above.

        intensity-spectra  → graded dose→effect model (162 substances)
        effects            → erowid effect tags by domain + sample quotes (121)
        combinations       → anecdotal drug-combo reports + top effects (2397)
    """
    # Intensity spectra: a flat list of per-substance documents. Drop the Mongo
    # bookkeeping and sort by slug for a stable ordering.
    try:
        spectra = json.loads(_get(DATA_API + "/intensity-spectra", accept="application/json"))
        cleaned = [
            {k: v for k, v in doc.items() if k not in ("_id", "cache_key", "created_at")}
            for doc in spectra
            if isinstance(doc, dict) and doc.get("drug_slug")
        ]
        cleaned.sort(key=lambda d: d["drug_slug"])
        kb = _write_json(SPECTRA_OUT, cleaned)
        print(f"  spectra:      {len(cleaned):4} substances  ({kb} KB) → {SPECTRA_OUT.name}")
    except Exception as exc:  # noqa: BLE001 - companion data is best-effort
        print(f"  ! spectra fetch failed: {exc}", file=sys.stderr)

    # Effects: {effectsIndex, drugEffects, effectsMeta}. Keep the per-substance
    # `drugEffects` (what a card would render) + the small `effectsMeta`
    # provenance block; drop the large effect→drugs reverse index the app derives.
    try:
        effects = json.loads(_get(DATA_API + "/effects", accept="application/json"))
        payload = {
            "effectsMeta": effects.get("effectsMeta"),
            "drugEffects": effects.get("drugEffects") or {},
        }
        kb = _write_json(EFFECTS_OUT, payload)
        print(
            f"  effects:      {len(payload['drugEffects']):4} substances  ({kb} KB) → {EFFECTS_OUT.name}"
        )
    except Exception as exc:  # noqa: BLE001 - companion data is best-effort
        print(f"  ! effects fetch failed: {exc}", file=sys.stderr)

    # Combinations: a flat list keyed by combo slug; no Mongo bookkeeping.
    try:
        combos = json.loads(_get(DATA_API + "/combinations", accept="application/json"))
        combos = [c for c in combos if isinstance(c, dict) and c.get("slug")]
        combos.sort(key=lambda c: c["slug"])
        kb = _write_json(COMBOS_OUT, combos)
        print(f"  combinations: {len(combos):4} pairs       ({kb} KB) → {COMBOS_OUT.name}")
    except Exception as exc:  # noqa: BLE001 - companion data is best-effort
        print(f"  ! combinations fetch failed: {exc}", file=sys.stderr)


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    asset = current_asset()
    drugs = fetch_bootstrap()
    print(f"fetched {len(drugs)} substances from {API} (deploy asset {asset})")

    # Canonicalize for a stable, reviewable diff: key by slug (so aliases that
    # resolve to the same entry can't double-list it) and sort by slug. Sort
    # object keys too (``sort_keys``) — the MongoDB-backed bootstrap emits each
    # document's fields in arbitrary order, so without this every re-fetch would
    # churn thousands of lines of pure key-reordering and bury real changes.
    by_slug: dict[str, dict] = {slugify(obj["drug_name"]): obj for obj in drugs}
    ordered = [by_slug[k] for k in sorted(by_slug)]

    prev = json.loads(OUT.read_text()) if OUT.exists() else []
    prev_names = {d.get("drug_name") for d in prev}
    new_names = {d["drug_name"] for d in ordered}

    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "drug.community",
                "api": API,
                "human_url_pattern": BASE + "/drug/{slug}",
                "fetched_at": fetched_at,
                "spa_asset": asset,
                "substance_count": len(ordered),
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

    print("\ncompanion datasets:")
    fetch_extra_datasets()
    return 0


if __name__ == "__main__":
    sys.exit(main())
