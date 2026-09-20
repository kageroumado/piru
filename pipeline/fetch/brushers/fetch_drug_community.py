#!/usr/bin/env python3
"""Fetch the substance.wiki dataset via its public API, storing the responses
in-repo for versioned provenance.

substance.wiki and drug.community are one catalog behind one read-only API,
described at https://substance.wiki/api/docs (OpenAPI document at
``/api/openapi.json``). Piru's source slug and snapshot file names say
``drug.community``; the app shows the source as substance.wiki. Human-readable
pages live at https://substance.wiki/drug/<slug>, where the slug is
``name.lower()`` with runs of non-alphanumeric characters collapsed to ``-``
(mirrored here by :func:`slugify`).

The API publishes each dataset as an immutable release:

    GET /api/data/manifest
        -> { release: { id, generatedAt, datasets: { <name>: { url, sha256, bytes } } } }
    GET /api/data/releases/<release id>/<dataset>

Every dataset is fetched through its release URL and checked against the
manifest's byte count and SHA-256, so a snapshot is one named release rather
than whatever the live endpoints served at that minute, and a truncated or
proxied response is refused instead of committed.

``bootstrap`` carries the whole substance roster: ``{ drugs: [...] }``, each
element the per-substance object ``/api/info?name=<X>`` returns (drug_name,
dosages, duration_curves, subjective_effects, categories, …).

Why store the responses in the repo: re-running this surfaces any upstream
change as a reviewable git diff. That gives Piru a visible history of where its
substance.wiki data came from and when — proof of best-effort sourcing, not an
opaque one-off export.

This is sanctioned first-party use of an API the site operator provided; the
fetcher identifies itself honestly via ``User-Agent``.

Usage:
    python3 pipeline/fetch/brushers/fetch_drug_community.py

Writes:
    data/sources/drug-community.json       — array of drug profiles, sorted by slug
    data/sources/drug-community.meta.json   — fetch provenance (release / when / how many)
    data/sources/drug-community-{spectra,effects,combinations}.json — companion datasets
"""

from __future__ import annotations

import hashlib
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
# Companion datasets (see fetch_extra_datasets).
SPECTRA_OUT = SOURCES / "drug-community-spectra.json"
EFFECTS_OUT = SOURCES / "drug-community-effects.json"
COMBOS_OUT = SOURCES / "drug-community-combinations.json"

BASE = "https://substance.wiki"
MANIFEST = BASE + "/api/data/manifest"
# Honest identification — this is not a browser and not an AI crawler; it is
# Piru's first-party data fetcher pulling an API made available to the project.
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party API use; contact via repo)"
TIMEOUT = 30
RETRIES = 2

_NONALNUM = re.compile(r"[^a-z0-9]+")
_TRIM = re.compile(r"(^-|-$)")


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


class Release:
    """One immutable publication of the catalog, as the manifest describes it."""

    def __init__(self) -> None:
        manifest = json.loads(_get(MANIFEST, accept="application/json"))
        release = manifest.get("release") if isinstance(manifest, dict) else None
        if not isinstance(release, dict) or not release.get("datasets"):
            raise SystemExit("manifest carries no release — the API contract may have changed")
        self.id: str = release["id"]
        self.generated_at: str = release["generatedAt"]
        self.schema_version = manifest.get("schemaVersion")
        self.pipeline_version = manifest.get("pipelineVersion")
        self._datasets: dict[str, dict] = release["datasets"]

    def dataset(self, name: str):
        """Fetch one dataset and refuse it unless it is the bytes the manifest names.

        The data API only returns JSON when the request forbids text/html — a
        browser-style Accept gets the SPA's index.html fallback instead.
        """
        entry = self._datasets.get(name)
        if entry is None:
            raise SystemExit(f"release {self.id[:12]} has no '{name}' dataset")
        body = _get(BASE + entry["url"], accept="application/json")
        digest = hashlib.sha256(body).hexdigest()
        if len(body) != entry["bytes"] or digest != entry["sha256"]:
            raise SystemExit(
                f"'{name}' does not match the manifest: got {len(body)} bytes / {digest[:12]}, "
                f"expected {entry['bytes']} / {entry['sha256'][:12]}"
            )
        return json.loads(body)


def fetch_bootstrap(release: Release) -> list[dict]:
    """The full roster from the release's bootstrap dataset."""
    payload = release.dataset("bootstrap")
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


def _without_ontology_stamp(drug_effects: dict) -> dict:
    """Drop the per-effect ``ontologyRelease`` block.

    Every effect row repeats the release-wide ontology identity that
    ``effectsMeta.ontologyRelease`` already states once — a seventh of the file.
    """
    return {
        slug: {
            **record,
            "effects": [
                {k: v for k, v in effect.items() if k != "ontologyRelease"}
                for effect in record.get("effects") or []
            ],
        }
        for slug, record in drug_effects.items()
    }


def fetch_extra_datasets(release: Release) -> None:
    """Snapshot the release's companion datasets.

    We keep card-relevant slices verbatim so any upstream
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
        spectra = release.dataset("intensity-spectra")
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
        effects = release.dataset("effects")
        payload = {
            "effectsMeta": effects.get("effectsMeta"),
            "drugEffects": _without_ontology_stamp(effects.get("drugEffects") or {}),
        }
        kb = _write_json(EFFECTS_OUT, payload)
        print(
            f"  effects:      {len(payload['drugEffects']):4} substances  ({kb} KB) → {EFFECTS_OUT.name}"
        )
    except Exception as exc:  # noqa: BLE001 - companion data is best-effort
        print(f"  ! effects fetch failed: {exc}", file=sys.stderr)

    # Combinations: a flat list keyed by combo slug; no Mongo bookkeeping.
    try:
        combos = release.dataset("combinations")
        combos = [c for c in combos if isinstance(c, dict) and c.get("slug")]
        combos.sort(key=lambda c: c["slug"])
        kb = _write_json(COMBOS_OUT, combos)
        print(f"  combinations: {len(combos):4} pairs       ({kb} KB) → {COMBOS_OUT.name}")
    except Exception as exc:  # noqa: BLE001 - companion data is best-effort
        print(f"  ! combinations fetch failed: {exc}", file=sys.stderr)


def main() -> int:
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
    release = Release()
    drugs = fetch_bootstrap(release)
    print(
        f"fetched {len(drugs)} substances from release {release.id[:12]} ({release.generated_at})"
    )

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
                "source": "substance.wiki",
                "api": MANIFEST,
                "api_docs": BASE + "/api/docs",
                "human_url_pattern": BASE + "/drug/{slug}",
                "fetched_at": fetched_at,
                "release_id": release.id,
                "release_generated_at": release.generated_at,
                "schema_version": release.schema_version,
                "pipeline_version": release.pipeline_version,
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
    fetch_extra_datasets(release)
    return 0


if __name__ == "__main__":
    sys.exit(main())
