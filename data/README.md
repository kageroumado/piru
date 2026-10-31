# `data/` — Substance data, source of truth

Piru's substance data keeps external source records and curated corrections separately, then resolves them into the app's SQLite database. Inspect the resolved values in [`snapshots/`](snapshots/) and edit compound-specific facts in [`curated/substances/`](curated/substances/).

<details>
<summary>Source data and curation reference</summary>

## Layout

```
data/
├── sources/        Raw per-source dumps as ingested from external providers
├── curated/        Per-compound definitions and overrides, plus shared reference data
├── intermediate/   SubstanceCollector merge outputs — generated, not hand-edited
├── enrichment/     LLM-assisted deep-pharma research (peer-review-primary source)
└── snapshots/      JSON and CSV views of the built SQLite
```

### `sources/` — raw per-source dumps

One JSON or CSV file per upstream provider, in roughly the shape that
provider gives us. These are inputs to the pipeline; the app never reads
them directly.

| File | Source | Provenance slug | What it contains |
|------|--------|-----------------|------------------|
| `psychonautwiki.json` | [PsychonautWiki](https://psychonautwiki.org) GraphQL API | `psychonautwiki` | Per-substance dose ranges, duration phases, tolerance info. Refreshed by `pipeline/fetch/psychonautwiki.py`. |
| `drug-community.json` | drug.community dump | `drug.community` | User-reported dose ranges across many compounds. |
| `product-codes-openfda.json` | [openFDA NDC directory](https://open.fda.gov/apis/drug/ndc/) bulk download (public domain) | — | US marketed products with package NDCs, retail UPCs, pack sizes; pre-filtered to single-ingredient products whose active maps to a known substance. Refreshed by `pipeline/fetch/product_codes.py`; feeds the `product_codes` barcode table. |
| `product-codes-bdpm.json` | [ANSM BDPM](https://base-donnees-publique.medicaments.gouv.fr/) (Etalab open licence) | — | French products with CIP13 barcodes and presentations, same filter. Same fetcher. |

### `curated/` — definitions and overrides

[`substances/`](curated/substances/) contains one JSON file per compound: a full definition or overrides for an imported substance. The schema is [`substances.schema.json`](curated/substances.schema.json).

`pipeline/build/sqlite.py` ingests these files directly as `piru-curated`, before external sources. Cite values in their corresponding source fields, such as `halfLifeSource` beside `halfLifeMinutes`.

Shared reference data lives beside `substances/`; see the [pipeline map](../pipeline/README.md#curated-files-beside-substances).

### `intermediate/` — SubstanceCollector outputs

| File | Producer | Consumer |
|------|----------|----------|
| `sourced-substances.json` | `Tools/SubstanceCollector` | `pipeline/build/sqlite.py` |
| `substances-bundled.json` | `Tools/SubstanceCollector` (merged view) | `pipeline/build/snapshots.py`, fallback for sqlite.py |

The collector regenerates these files. Make corrections in [`curated/substances/`](curated/substances/) and rebuild through `pipeline/build.sh`.

### `enrichment/` — LLM-assisted research

Agent-generated research carries the `peer-review-primary` provenance slug and covers receptor affinities, metabolic pathways, literature citations, and class summaries. The slug says how a row was written, not where its evidence is: a row is sourced only by its own `citation_id`. A row whose record named no paper ships uncited and the app attributes it to nothing; a citation found for it later is attached through [`curated/row-citations.json`](curated/row-citations.json) (see `pipeline/README.md`, "Row citations").

```
enrichment/
├── groups/          Group assignments (one file per mechanism class) — tracked
├── raw/             Per-group LLM outputs (one file per group) — tracked
├── merged.json      Flat merge of all per-substance enrichment records — gitignored
├── class-context.json   Class-level summaries (e.g. "all NMDA antagonists") — gitignored
└── coverage.csv     One row per substance, columns flag which fields got filled — gitignored
```

Inputs to the SQLite build are `raw/*.json` (sqlite.py iterates them
directly). The three gitignored files are pure derivatives of `raw/`
produced by `pipeline/enrichment/merge.py` for inspection only — run
`python3 pipeline/enrichment/merge.py` to regenerate them locally.

### `snapshots/` — resolved database values

`pipeline/build/snapshots.py` reads the built SQLite and exports JSON and CSV. See [`snapshots/README.md`](snapshots/README.md).

</details>

## Notes

- Edit compound JSON in `curated/substances/` with citations, run `pipeline/build.sh fast`, and review the generated snapshots and build report.
- Commit changed inputs, `Piru/Data/manifest.json`, and snapshots. Maintainers must publish the matching database with `pipeline/publish-db.sh` before pushing its manifest; the SQLite file is gitignored.
