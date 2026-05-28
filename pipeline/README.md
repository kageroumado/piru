# `pipeline/` — substance data processing

All the processing code that turns external substance data into Piru's
bundled SQLite database lives here. The data itself lives in
[`../data/`](../data/); the app artifact ships from
[`../Piru/Data/piru-substances.sqlite`](../Piru/Data/).

## Layout

```
pipeline/
├── fetch/        Ingesters that pull from external sources
├── enrichment/   LLM-driven deep-pharma research workflow
├── build/        Produces the bundled SQLite + the human-readable snapshots
└── audit/        After-the-fact inspection + comparison tools
```

## End-to-end flow

```
                                                  ┌─ data/curated/overlay.json (hand-maintained)
                                                  │
  PsychonautWiki API ──► fetch/psychonautwiki.py ──► data/sources/psychonautwiki.json ──┐
  TripSit / MedTAP /                                                                    │
  NPS / Pyrls       ──► fetch/brushers/*.py     ──► data/sources/brushers/*.csv         │
  drug.community    ──► (manual snapshot)       ──► data/sources/drug-community.json    │
                                                                                        ▼
                                              Tools/SubstanceCollector (Swift CLI)
                                              merges all sources + applies curated overlay
                                                                                        │
                                                                                        ▼
                                              data/intermediate/sourced-substances.json
                                              data/intermediate/substances-bundled.json
                                                                                        │
                                                                                        │ + data/enrichment/raw/*.json
                                                                                        │   (from agent-swarm research,
                                                                                        │    see enrichment/README below)
                                                                                        ▼
                                              build/sqlite.py
                                                                                        │
                                                                                        ▼
                                              Piru/Data/piru-substances.sqlite  ← app ships this
                                              Piru/Data/manifest.json
                                                                                        │
                                                                                        ▼
                                              build/snapshots.py
                                                                                        │
                                                                                        ▼
                                              data/snapshots/substances.{json,csv}  ← humans read this
                                              data/snapshots/gaps.csv
```

## Running the pipeline

From the repo root, in order:

```bash
# 1. Optionally refresh upstream snapshots (only when external data has changed)
python3 pipeline/fetch/psychonautwiki.py        # ~30 min, paginated GraphQL
python3 pipeline/fetch/brushers/brush_all.py    # quick — local CSVs

# 2. Merge raw sources + apply curated overlay (Swift)
cd Tools/SubstanceCollector && swift run SubstanceCollector && cd ../..

# 3. (Optional) Run an enrichment pass — see pipeline/enrichment/ for the multi-step workflow

# 4. Build the bundled SQLite the app reads
python3 pipeline/build/sqlite.py

# 5. Build the human-readable snapshots committed under data/snapshots/
python3 pipeline/build/snapshots.py
```

After step 5, commit `data/intermediate/`, `data/snapshots/`,
`Piru/Data/piru-substances.sqlite`, and `Piru/Data/manifest.json`.

## Sub-pipeline overviews

### `fetch/`
- **`psychonautwiki.py`** — paginated GraphQL crawl of psychonautwiki.org;
  writes `data/sources/psychonautwiki.json`.
- **`brushers/`** — small Python brushers per non-API source (TripSit
  combo data, MedTAP NDC dump, NPS DataHub, Pyrls). Each `brush_<name>.py`
  writes one CSV to `data/sources/brushers/`. `brush_all.py` runs them
  all in sequence.

### `enrichment/`
LLM-assisted research used to fill gaps external sources don't cover
(receptor affinities, primary-literature citations, class-context).

1. **`build_groups.py`** — partitions every substance in
   `data/intermediate/substances-bundled.json` into mechanism-class
   groups. Writes `data/enrichment/groups/<group-slug>.json`.
2. **(External)** — each group is handed to an LLM agent along with the
   prompts in `prompts/system.md` (general agent) or `prompts/kimi.md`
   (Kimi-specific). Each agent writes its output to
   `data/enrichment/raw/<group-slug>.json`.
3. **`merge.py`** — merges all `raw/*.json` into the three artifacts the
   inspectors and the SQLite build care about (`merged.json`,
   `class-context.json`, `coverage.csv`).

### `build/`
- **`sqlite.py`** — the main build script. Ingests every input source,
  resolves per-field priority, writes `Piru/Data/piru-substances.sqlite`
  + `manifest.json` + `docs/audit/sqlite-build-report.md`.
- **`snapshots.py`** — produces the GitHub-friendly mirror of the shipped
  data at `data/snapshots/`.
- **`tests/test_sqlite.py`** — regression tests for dose-string parsing
  bugs + end-to-end invariants on the built database. Run with
  `python3 pipeline/build/tests/test_sqlite.py`.

### `audit/`
- **`compare_to_pw.py`** — compares resolved DB values to PsychonautWiki
  (our high-trust reference) and flags divergences. Output:
  `docs/audit/pw-divergence.md`.
- **`dump_substance_library.py`** — emits the by-category text dumps
  that live in `data/snapshots/by-category/`.
- **`dump_for_verification.py`** — emits richer per-substance dumps
  suitable for parallel human or LLM review. Output is gitignored under
  `docs/audit/verification-dump/`.

## Reproducibility

Every script can be run from the repo root with no arguments — paths are
absolute relative to `pipeline/__file__`. No environment variables, no
config files. If a script needs a different location it accepts that as
an argument.
