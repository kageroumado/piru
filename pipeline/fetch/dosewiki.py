#!/usr/bin/env python3
"""Fetch dose.wiki's published substance articles into the bundled snapshot.

dose.wiki (https://dose.wiki, CC0 1.0) is an encyclopedia compiled from ten
reference sites — PsychonautWiki, TripSit and Erowid among them — with an
editorial merge applied on top and a first-pass prose review by a subject-matter
expert recorded per article as ``expert_reviewed``. Piru ingests it last in the
source order, so its numbers only resolve where nothing else has any.

The fetch takes the **API**, not the daily `SubstanceIndex.json` export: the
export withholds ``expert_reviewed`` and ``publicRevision``, and every gate in
``Build.ingest_dosewiki`` is written against the first of those.

Two filters run here rather than at build time, because a snapshot committed to
this public repo is a redistribution of whatever is in it:

* ``priority: low`` is dose.wiki's unpublished-draft tier. Those articles are
  withheld from its own export and 309 of 310 are unreviewed; they are never
  requested.
* ``LICENSE_BLOCKED`` names the fields Piru may not redistribute at all.

Usage:
    python3 pipeline/fetch/dosewiki.py

Writes:
    data/sources/dosewiki.json        the trimmed, slug-sorted snapshot
    data/sources/dosewiki.meta.json   provenance + what the run saw
"""

from __future__ import annotations

import gzip
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from urllib import error as urlerror
from urllib import request as urlrequest

API = "https://dose.wiki/api/v1"
ROSTER = API + "/substances?limit=100"
RECORD = API + "/substances/{slug}"
LICENSE_URL = "https://dose.wiki/docs/license"
LICENSE = (
    "CC0 1.0. The interaction and reagent fields are excluded: they carry "
    "TripSit's and ProtestKit's terms, not dose.wiki's."
)
UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"

#: Concurrent record requests. Six holds the whole 267-record pass to ~3 s
#: without asking a volunteer site for more than a browser would.
CONCURRENCY = 6

#: Refuse to overwrite the committed snapshot with a run that came back thin —
#: a roster served during a deploy, or a network that failed most of the way in.
MIN_RECORDS = 200

OUTPUT = Path(__file__).resolve().parents[2] / "data" / "sources" / "dosewiki.json"
META = OUTPUT.with_suffix(".meta.json")

#: Fields Piru may never redistribute. ``interactions`` is TripSit's combination
#: data under non-commercial terms and the reagent fields are ProtestKit's; Piru
#: ships on the App Store and this repo is public, so neither may reach
#: ``data/sources/``. Piru ingests TripSit's matrix from TripSit directly.
LICENSE_BLOCKED = ("interactions", "reagent_testing", "reagent_testing_normalized")

#: Fields dropped for content reasons, each with the reason it is dropped.
DROPPED = {
    # Every effect list is either machine-written or Josie Kins' Subjective
    # Effect Index, which Piru already carries through SubFxOnEx and FreeOD.
    "subjective_effects": "effect prose Piru sources elsewhere",
    # AI-drafted narrative sections with no Piru surface to render them.
    "history_culture": "AI-drafted narrative, no surface",
    # 4,049 country claims a reader could act on, with no Piru table or screen.
    "legality": "per-country legal claims with no surface",
    # Graded addiction/psychosis/seizure risk as AI prose plus level words with
    # no published rubric, and Piru has no table that could hold a risk grade.
    "harm_potential": "AI-graded risk with no rubric and no surface",
    # Landing pages — an EMCDDA index, a Bluelight thread, an archive.org
    # capture. Piru's `is_identifier_citation` already rejects that shape.
    "citations": "landing pages, not citeable works",
    "source_citations": "landing pages, not citeable works",
    # The key exists on every record and is empty on every record.
    "comparisons": "empty on every record",
    # Identical to `binding_sites` row-for-row with the affinity dropped, so
    # reading both doubles every binding.
    "pharmacology.receptor_profile": "a restatement of binding_sites",
}

#: The whole of what the snapshot carries. Anything absent from this list is
#: absent from the file, so a field dose.wiki adds later arrives only when
#: someone decides it should.
KEPT_TOP_LEVEL = (
    "slug",
    "title",
    "summary",
    "priority",
    "expert_reviewed",
    "publicRevision",
    "identification",
    "classification",
    "dosage",
    "duration",
    "tolerance",
)

#: The pharmacology sub-keys Piru reads. `pharmacodynamics` and
#: `pharmacokinetics` are AI-drafted prose and stay out.
KEPT_PHARMACOLOGY = (
    "binding_sites",
    "metabolites",
    "route_half_life",
    "route_half_life_notes",
)


def get_json(url: str, timeout: int = 60) -> dict:
    """One GET, gzip-decoded. urllib advertises no encoding and decompresses
    nothing, so both halves are done here."""
    req = urlrequest.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
    with urlrequest.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            raw = gzip.decompress(raw)
    return json.loads(raw)


def roster() -> tuple[list[dict], int]:
    """Every substance preview the API lists, and the total it reports."""
    rows: list[dict] = []
    total = 0
    url = ROSTER
    while url:
        page = get_json(url)
        rows.extend(page.get("data") or [])
        total = (page.get("meta") or {}).get("total") or total
        cursor = (page.get("pagination") or {}).get("next_cursor")
        url = f"{ROSTER}&cursor={cursor}" if cursor else None
    return rows, total


def project(record: dict) -> dict:
    """The record trimmed to what Piru stores.

    Built by naming what is kept rather than by deleting what is not, so a field
    dose.wiki adds cannot arrive in the snapshot unnoticed.
    """
    out = {key: record[key] for key in KEPT_TOP_LEVEL if key in record}
    pharmacology = record.get("pharmacology") or {}
    kept_pharmacology = {key: pharmacology[key] for key in KEPT_PHARMACOLOGY if key in pharmacology}
    if kept_pharmacology:
        out["pharmacology"] = kept_pharmacology
    # A bibliographic record is fact, not a licensed excerpt, so a reference may
    # be stored — but only one that names a work a reader can reach.
    references = [
        ref for ref in (record.get("references") or []) if ref.get("doi") or ref.get("pmid")
    ]
    if references:
        out["references"] = references
    return out


def fetch_record(slug: str) -> dict | None:
    try:
        return (get_json(RECORD.format(slug=slug)) or {}).get("data")
    except (urlerror.URLError, TimeoutError, ValueError) as error:
        print(f"  ! {slug}: {error}", file=sys.stderr)
        return None


def previous_records() -> dict[str, dict]:
    """The committed snapshot's projections, keyed by slug."""
    if not OUTPUT.exists():
        return {}
    try:
        payload = json.loads(OUTPUT.read_text())
    except ValueError:
        return {}
    return {rec["slug"]: rec for rec in payload.get("records") or [] if rec.get("slug")}


def main() -> int:
    previews, total = roster()
    published = sorted(
        {row["slug"] for row in previews if row.get("slug") and row.get("priority") != "low"}
    )
    drafts = len(previews) - len(published)
    print(f"dose.wiki roster: {total} substances, {len(published)} published, {drafts} drafts")

    committed = previous_records()
    with ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
        fetched = list(pool.map(fetch_record, published))

    records: list[dict] = []
    unchanged = 0
    for slug, record in zip(published, fetched, strict=True):
        prior = committed.get(slug)
        if record is None:
            # The article is still published; this run just could not read it.
            # Keeping the committed projection loses nothing and drops nobody.
            if prior:
                records.append(prior)
            continue
        if prior and prior.get("publicRevision") == record.get("publicRevision"):
            records.append(prior)
            unchanged += 1
            continue
        records.append(project(record))

    if len(records) < MIN_RECORDS:
        print(
            f"only {len(records)} records came back (floor {MIN_RECORDS}) — "
            f"refusing to overwrite {OUTPUT}",
            file=sys.stderr,
        )
        return 1

    records.sort(key=lambda rec: rec["slug"])
    reviewed = sum(1 for rec in records if rec.get("expert_reviewed"))
    fetched_at = datetime.now(UTC).isoformat(timespec="seconds")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(
            {
                "fetched_at": fetched_at,
                "license": LICENSE,
                "license_url": LICENSE_URL,
                "records": records,
            },
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
        )
        + "\n"
    )
    META.write_text(
        json.dumps(
            {
                "source": "dose.wiki public API",
                "api": API,
                "human_url_pattern": "https://dose.wiki/{slug}",
                "license": LICENSE,
                "license_url": LICENSE_URL,
                "license_blocked_fields": list(LICENSE_BLOCKED),
                "dropped_fields": DROPPED,
                "fetched_at": fetched_at,
                "roster_total": total,
                "published_count": len(published),
                "draft_skipped": drafts,
                "records_written": len(records),
                "records_unchanged": unchanged,
                "expert_reviewed_count": reviewed,
                "reference_count": sum(len(rec.get("references") or []) for rec in records),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(
        f"Saved {len(records)} records ({reviewed} expert-reviewed, "
        f"{unchanged} unchanged) → {OUTPUT}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
