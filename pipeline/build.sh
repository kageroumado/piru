#!/usr/bin/env bash
#
# How Piru's substance database is built — the ordered, invocable manifest.
#
# Every step below is a real script in this repo; this file only SEQUENCES them
# and documents the order, so "how is the DB built?" has one runnable answer.
#
# Usage:
#   pipeline/build.sh            # fast: rebuild from committed inputs (default)
#   pipeline/build.sh full       # full: re-run the upstream scrape/extract first
#
# "fast" is reproducible offline from what's committed in the repo. "full"
# refreshes the upstream snapshots and needs network + ~/Developer/piru-data.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root
MODE="${1:-fast}"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

if [ "$MODE" = "full" ]; then
  # ── Upstream source passes (network / external; refresh committed inputs) ──
  step "1/8  Fetch PsychonautWiki  → data/sources/psychonautwiki.json"
  python3 pipeline/fetch/psychonautwiki.py
  # drug.community is a manual snapshot → data/sources/drug-community.json (no script)

  step "2/8  Merge scraped web sources (Swift collector) → data/intermediate/sourced-substances.json"
  # TripSit + Wikidata + PubChem + Erowid + DEA. The collector also reads the
  # curated dir, but sqlite.py ingests curated directly (step 6), so its
  # piru-curated rows in sourced-substances.json are ignored downstream.
  # `build` is explicit on purpose: a bare `swift run SubstanceCollector`
  # prints usage and exits 0, so this step silently did nothing while the
  # build reported success (sourced-substances.json went stale from May 31).
  # The CLI now also declares a defaultSubcommand, so both spellings work.
  ( cd Tools/SubstanceCollector && swift run SubstanceCollector build )

  step "3/8  Extract out-of-repo datasets (Pyrls/MedTAP/NPS/benzos) → /tmp/piru-extract/*.json"
  # Needs ~/Developer/piru-data present (export PIRU_DATASOURCES if it moved).
  python3 pipeline/fetch/brushers/extract.py

  step "4/8  (manual) Enrichment swarm → data/enrichment/raw/*.json  — see pipeline/enrichment/"
else
  step "1-4/8  skipped (fast mode) — using committed upstream inputs"
fi

# ── Build passes (offline, reproducible from committed inputs) ──
step "5/8  Validate the curated layer (one file per substance)"
python3 pipeline/build/validate_curated.py

step "6/8  Build the bundled SQLite the app ships"
# Ingest order (see sqlite.py:main): curated dir FIRST (so its identifiers win),
# then sourced web records, PsychonautWiki, drug.community, enrichment, external
# extracts; then tag-promotion, dedup, chemnoise purge, display classification.
python3 pipeline/build/sqlite.py

step "7/8  Human-readable snapshots → data/snapshots/"
python3 pipeline/build/snapshots.py

step "8/8  Regression + invariant tests"
python3 pipeline/build/tests/test_sqlite.py
python3 pipeline/build/tests/test_overlay_integrity.py
python3 pipeline/build/tests/test_psid.py
python3 pipeline/fetch/brushers/test_freeodwiki_extract.py

step "Done. Commit: Piru/Data/piru-substances.sqlite, Piru/Data/manifest.json,"
echo  "       data/snapshots/build-report.md (+ data/ inputs only if they changed)."
