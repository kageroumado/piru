# `pipeline/` — substance data processing

All the processing code that turns external substance data into Piru's
bundled SQLite database lives here. The data itself lives in
[`../data/`](../data/); the app artifact ships from
[`../Piru/Data/piru-substances.sqlite`](../Piru/Data/).

## Layout

```
pipeline/
├── build.sh      The ordered, invocable build manifest — start here
├── fetch/        Ingesters that pull from external sources
├── enrichment/   LLM-driven deep-pharma research workflow
├── build/        Produces the bundled SQLite + validates the curated layer
└── audit/        After-the-fact inspection + comparison tools
```

`pipeline/build.sh` is the single answer to "how is the DB built?" — every step
is a real script and that file sequences them in order. `pipeline/build.sh fast`
rebuilds from committed inputs (offline, reproducible); `pipeline/build.sh full`
re-runs the upstream scrape/extract first.

## Curated data

Hand-curated substance data lives in [`../data/curated/substances/`](../data/curated/substances/)
as **one JSON file per compound** (`<slug>.json`, where `slug == slugify(name)`).
A file is either a **full definition** (compounds the scrapers miss — RCs,
peptides) or an **override-only** record (just the fields we adjust on a scraped
substance — a popularity score, a display-name, a category correction, CJK search
aliases, a dose-basis fix). There is no separate overlay/override file and no
in-code curation dict: one file fully describes one substance.

- Schema: [`../data/curated/substances.schema.json`](../data/curated/) (editor support).
- **Cite a number where the number is, not on the substance.** The `sources`
  array is substance-level provenance; it does not cite any particular value.
  A per-fact citation is a sibling field — `halfLifeSource` next to
  `halfLifeMinutes`, and the same pattern elsewhere — and that is what the
  citation gates can actually check. Adding another URL to `sources` looks like
  citing the number and is not.
- Enforced validator: `build/validate_curated.py` (stdlib, build-consistent route
  normalisation). Run before every build; CI/test gate via `tests/test_sqlite.py`.
- `build/sqlite.py` ingests this directory **directly** as the `piru-curated`
  source, FIRST — so curated chemical identifiers win the COALESCE and a curated
  category beats a later tag-promotion. (The Swift collector also reads the dir,
  but any `piru-curated` rows it leaves in `sourced-substances.json` are ignored.)

### Curated files beside `substances/`

Facts that are not *about one compound* live in their own file at the root of
`data/curated/`, one per concern, each read by a single ingester in `sqlite.py`.
Names resolve by canonical name **or alias**, so a file can use the name a reader
would recognise (`MDA`) rather than the canonical row
(`3,4-Methylenedioxyamphetamine`); an unresolved name is counted as `unmatched` in
the build's line for that step, so a permanently-unmatched entry is a signal to
fix, not noise to tolerate.

| file | table | what it decides |
|---|---|---|
| `class-reference-compounds.json` | `class_reference_compounds` | the recognisable peers labelled on a signature axis |
| `class-representatives.json` | `class_representatives` | the per-class PK stand-in the tolerance fallback models a PK-less substance as |
| `substance-flags.json` | `substance_flags` | booleans an engine reads and nothing renders |
| `regional-names.json` | `regional_names` | which spelling of a name to display in which regions |
| `opioid-mme.json` | `opioid_mme` | oral morphine-milligram-equivalent factors, and which opioids must never be converted |
| `interaction-rules.json` | `interaction_rules` | which class pairs interact and how badly; ingested ahead of TripSit's matrix so a curated verdict wins the pair |
| `substance-interaction-classes.json` | `substance_interaction_classes` | the interaction class a name carries, overriding its category |
| `category-interaction-classes.json` | `category_interaction_classes` | the interaction class each category falls back to |
| `tolerance-modulation.json` | `tolerance_modulation` | which receptor class, while onboard, slows another's tolerance development |
| `enzyme-modulators.json` | `enzyme_modulators`, `pharmacology_matchers` | which drugs and lifestyle contexts inhibit or induce a clearing enzyme |
| `combination-metabolites.json` | `combination_metabolites`, `pharmacology_matchers`, `metabolism.conditional_combination_id` | which drug pairs react to form a third active species |
| `alias-kinds.json`, `brands.json` | `aliases` | alias provenance, brand flagships |
| `drug-classes.json` | `substances.drug_class` | normalized antidepressant subclass (SSRI/SNRI/NRI/…), not the interaction class |

Adding one is: a path read in the ingester, DDL in `SCHEMA_SQL`, a method on
`Build`, a call + `print` in `main()`, the table in the build-report row-count
list, and a declaration in `audit/data_surfaces.json` so it cannot be built and
silently never rendered.

## End-to-end flow

```
  PsychonautWiki API ─► fetch/psychonautwiki.py ─► data/sources/psychonautwiki.json ─┐
  drug.community     ─► (manual snapshot)        ─► data/sources/drug-community.json  │
  TripSit/Wikidata/PubChem/Erowid/DEA ─► fetch/collector (Swift) ──────────►          │
                                          data/intermediate/sourced-substances.json   │
                                                                                      ▼
  data/curated/substances/*.json  ──────────────────────────────────────────►  build/sqlite.py
  (hand-curated; validated by                                                    (ingest order: curated
   build/validate_curated.py)                                                     FIRST, then web sources,
                                  data/enrichment/raw/*.json  ─────────────────►  PW, drug.community,
                                  (agent-swarm research)                          enrichment, external
                                  /tmp/piru-extract/*.json  ───────────────────►  extracts; then promote,
                                  (Pyrls/MedTAP/NPS/benzos,                        dedup, classify)
                                   via fetch/brushers/extract.py)                          │
                                                                                          ▼
                                              Piru/Data/piru-substances.sqlite  ← app ships this
                                              Piru/Data/manifest.json
                                              data/snapshots/build-report.md
                                                                                          │
                                                                          build/snapshots.py
                                                                                          ▼
                                              data/snapshots/substances.{json,csv}  ← humans read this
```

Note: `snapshots.py` reads the **built SQLite**, so the snapshots mirror exactly
what ships — resolved categories, curated overrides, references, casing — and
are deterministic (ordered by canonical name). Regenerate and commit them
alongside a DB rebuild.

## Running the pipeline

From the repo root, use the ordered manifest:

```bash
pipeline/build.sh          # fast: validate curated → build SQLite → snapshots → tests
pipeline/build.sh full     # also re-run upstream scrape/extract first (network + datasources)
```

`build.sh` is the source of truth for the steps and their order; it just
invokes the per-step scripts (`fetch/psychonautwiki.py`, the Swift collector,
`fetch/brushers/extract.py`, `build/validate_curated.py`, `build/sqlite.py`,
`build/snapshots.py`, `tests/test_sqlite.py`). Each is runnable standalone from
the repo root with no arguments.

Most curation changes only touch `data/curated/substances/` — for those, the
fast path is enough (it's offline and reproducible from committed inputs). A
`full` run is only needed when upstream external data has actually changed; it
requires network and `~/Developer/piru-data`.

After a build, commit `Piru/Data/piru-substances.sqlite`, `Piru/Data/manifest.json`,
and `data/snapshots/build-report.md` (+ any `data/` inputs that genuinely
changed). The raw `piru-data` files and `/tmp/piru-extract` JSON are
deliberately NOT committed — only the built SQLite is.

## Sub-pipeline overviews

### `fetch/`
- **`psychonautwiki.py`** — paginated GraphQL crawl of psychonautwiki.org;
  writes `data/sources/psychonautwiki.json`.
- **`brushers/extract.py`** — extracts the four out-of-repo datasets
  (`~/Developer/piru-data`: TripSit-benzos, MedTAP, NPS DataHub,
  Pyrls) into `Substance`-shaped JSON written to `/tmp/piru-extract`
  (out of repo). `build/sqlite.py` ingests those directly. `_common.py`
  holds the shared category/route/dose parsing helpers.

Fetching the *papers* those citations point at is not here — a paper cache
belongs outside this repo (it is public, and an open-access license permits
reading a paper, not vendoring it into someone else's git history). Piru's half
is `audit/cited_identifiers.py`, which emits the identifiers this database
cites. See [Researching a claim](#researching-a-claim).

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
- **`validate_curated.py`** — stdlib validator for `data/curated/substances/`.
  Catches the silent-failure modes (bad enums, inverted dose ranges, protocol
  dosing with no frequency, duplicate compounds across files, slug/filename
  drift, out-of-range popularity). Run before every build; importable as
  `validate_dir()`. Exits non-zero on any error.
- **`sqlite.py`** — the main build script. Ingests the curated dir first, then
  every web/enrichment/external source, resolves per-field priority, writes
  `Piru/Data/piru-substances.sqlite` + `manifest.json` +
  `data/snapshots/build-report.md`.
- **`snapshots.py`** — GitHub-friendly mirror at `data/snapshots/`, generated
  FROM the built SQLite (resolved + deterministic), so it reflects exactly what
  the app ships.
- **`tests/test_sqlite.py`** — dose-string parsing regressions, curated-file
  validation (incl. synthetic edge cases), and end-to-end invariants on the
  built database (categories, dedup, dose ceilings, curated-override
  resolution, citations). Run with `python3 pipeline/build/tests/test_sqlite.py`.

### `audit/`
- **`compare_to_pw.py`** — compares resolved DB values to PsychonautWiki
  (our high-trust reference) and flags divergences. Output:
  `data/snapshots/pw-divergence.md`.
- **`compare_to_drugbank.py`** — cross-checks the resolved DB against the
  DrugBank XML release in `~/Developer/piru-data` (verification only — no
  DrugBank data ships; its license restricts redistribution, so the output
  stays in the gitignored `data/snapshots/verification-dump/`). Flags
  half-life divergences, InChIKey/CAS identity conflicts, and emits a
  research work-list of half-life gaps with the PubMed ids DrugBank cites —
  seeds for the [Researching a claim](#researching-a-claim) ladder, never
  values to copy. First run builds a compact cache
  (`~/Developer/piru-data/drugbank-extract.json`) from the 1.6 GB XML;
  `--re-extract` rebuilds it after a new DrugBank drop. Settled questions are
  recorded in `data/curated/drugbank-adjudications.json` — a divergence where
  ours was verified against a primary source, or a substance with no honest
  single half-life — so each run reports only NEW work; the counts it suppresses
  are always printed, and `build/tests/test_drugbank_adjudications.py` fails if
  an entry goes stale. Beyond half-lives it checks **coverage the app depends
  on**: an enzyme DrugBank calls the substance a substrate of that no
  `metabolism` row names (the modulator catalog — grapefruit/CYP3A4,
  smoking/CYP1A2 — is joined against that table, so a missing row silently
  removes the card with no empty state to notice), a CYP2D6 substrate with no
  `pharmacogenetics` row (no metabolizer readout), and metabolites named by a
  DrugBank reaction that no row carries.
- **`dump_substance_library.py`** — emits the by-category text dumps
  that live in `data/snapshots/by-category/`.
- **`dump_for_verification.py`** — emits richer per-substance dumps
  suitable for parallel human or LLM review. Output is gitignored under
  `data/snapshots/verification-dump/`.

## Researching a claim

A curated number has to come from somewhere a later reader can check, and a
citation that resolves is not yet a citation that supports the claim. The order:

1. **Identify the paper** — PubMed/OpenAlex/ChEMBL MCP tools, or a DOI you have.
2. **Read the full text.** Fetched papers belong in a cache **outside this
   repo** — it is public, and an open-access license permits reading a paper,
   not vendoring it into someone else's git history. Nothing here reads that
   cache, so its location is yours to choose.
3. **Check the claim against the text** — grep the paper for the number itself.
4. **Record it** in `data/curated/substances/<slug>.json`, then rebuild.
5. **Gate it** — `audit/verify_citations.py --gate`.

`audit/cited_identifiers.py` emits the identifiers this database cites,
most-cited first, so a bounded run covers the papers the most rows depend on:

```bash
pipeline/audit/cited_identifiers.py            # every DOI/PMID cited
pipeline/audit/cited_identifiers.py --limit 50 # the 50 most-cited
```

Pipe that into whatever fetches full text for you.

### What a paper-fetching CLI should do

The maintainers use a private `papers` CLI for this. If you want to build your
own (any language, any architecture), here is what it needs to provide:

1. **Fetch by identifier** — accept a DOI, PMID, PMCID, or arXiv id; locate
   the paper via open-access routes (Unpaywall, PubMed Central, Sci-Hub,
   arXiv); download the PDF.
2. **Convert to text** — turn the PDF into searchable Markdown or plain text,
   preserving tables (that is where the binding values live). Store the result
   in a local cache directory **outside this repo**.
3. **Metadata lookup** — given an identifier, return title, authors, journal,
   year, and DOI without fetching the full paper. Triangulating across
   registries (Crossref, OpenAlex, Europe PMC, arXiv) catches errors a single
   source misses. This is the cheap first pass before committing to a download.
4. **Batch mode** — accept a file of identifiers (one per line, as emitted by
   `audit/cited_identifiers.py`) and fetch them all, skipping cache hits.
5. **Anchor + verify** — pin a specific claim to a quoted sentence in the
   paper, then re-verify that the quote still appears (a string comparison
   that can gate CI).
6. **Cache semantics** — a fetch is a no-op when the cache already holds the
   result. The cache is rebuildable from the PDFs: metadata in front matter,
   index derived. A paper fetched once is cheap to read in every future session.

The output of (1) + (2) is a readable file at a predictable path. The output of
(3) is structured metadata (JSON or stdout fields). The output of (5) is
exit-zero-or-not, suitable for a CI gate.

If you use an open-access fetcher, expect roughly three-quarters of these to
come back with no free copy — that is the state of the pharmacology literature,
not a bug. Such a paper is a library request; **do not cite a number from a
paper nobody read**. An identifier no registry resolves is suspicious but not
proof of fabrication: that verdict belongs to `audit/verify_citations.py`, which
weighs topicality too.

## Reproducibility

Every script can be run from the repo root with no arguments — paths are
absolute relative to `pipeline/__file__`. No environment variables, no
config files. If a script needs a different location it accepts that as
an argument.
