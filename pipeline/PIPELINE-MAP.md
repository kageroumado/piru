# PIPELINE-MAP

A read of the code, not of the docs. Every claim below was checked against the
script it describes; where `pipeline/README.md` or `data/snapshots/README.md`
says something the code does not do, that is called out as **README stale**.

Companions: [`PIPELINE-MAP.dot`](PIPELINE-MAP.dot) — the same graph, one node
per file, for `dot -Tsvg` (rendered: `PIPELINE-MAP.svg`); and
[`PIPELINE-MAP-overview.dot`](PIPELINE-MAP-overview.dot) — the stage-level
picture a person can read (`PIPELINE-MAP-overview.png` / `.svg`).

Mapped at `67b6399f`. One stage landed while this was being written and is not
described below: `pipeline/build/dose_gates.py`, called from `sqlite.py`'s
`main()` between the ingest passes and `finalise`, reading
`data/curated/dose-class-gates.json` and deleting the dose rows it rejects.

---

## a. Stages in execution order

`pipeline/build.sh` is the manifest. It `cd`s to the repo root and takes one
argument, `fast` (default) or `full`.

```bash
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root
MODE="${1:-fast}"
```

### Full mode only — upstream refresh (network)

These five run **only** when `MODE = full`. In `fast` mode the script prints
`step "1-2,4/8  skipped (fast mode) — using committed upstream inputs"` and
jumps to step 3.

| # | `build.sh` line | Entry point | Inputs | Outputs |
|---|---|---|---|---|
| 1/8 | `python3 pipeline/fetch/psychonautwiki.py` | `fetch/psychonautwiki.py` | `https://api.psychonautwiki.org/` GraphQL, list query then one detail query per name, 0.15 s apart | `data/sources/psychonautwiki.json` |
| 1b/8 | `python3 pipeline/fetch/subfxonex.py` | `fetch/subfxonex.py` | one hash-pinned release URL on `raw.githubusercontent.com` (overridable as `argv[1]`) | `data/sources/subfxonex.json`, `.meta.json` |
| 1c/8 | `python3 pipeline/fetch/dosewiki.py` | `fetch/dosewiki.py` | `https://dose.wiki/api/v1/substances?limit=100` then `/substances/{slug}`, 6 concurrent; reads the existing snapshot to skip unchanged `publicRevision` | `data/sources/dosewiki.json`, `.meta.json` |
| 2/8 | `( cd pipeline/fetch/collector && swift run SubstanceCollector build )` | Swift SPM package | TripSit `drugs.json`, Wikidata SPARQL, PubChem PUG REST, Erowid PIHKAL 001–179 / TIHKAL 001–055, plus a hand-curated in-source DEA schedule table (no network) | `data/intermediate/sourced-substances.json` + `substances-bundled.json` — **see the defect below** |
| 2b/8 | `python3 pipeline/fetch/product_codes.py` | `fetch/product_codes.py` | openFDA NDC bulk zip, ANSM BDPM `CIS_*.txt`, **and `data/snapshots/substances.json`** (the name allowlist) | `data/sources/product-codes-openfda.json` + `-bdpm.json` + two `.meta.json` |
| 4/8 | — prints a note only | the enrichment swarm is manual | | `data/enrichment/raw/*.json` |

Drug.community has no fetch step in `build.sh` at all — the comment says
"drug.community is a manual snapshot → data/sources/drug-community.json (no
script)", but `pipeline/fetch/brushers/fetch_drug_community.py` **is** that
script. It is simply never invoked from here.

**Defect — the collector writes to a directory that is not the repo's.**
`SubstanceCollectorCLI.swift:27,30,36` still carries the defaults from when the
package lived at `Tools/SubstanceCollector/`:

```swift
var output: String = "../../data/intermediate/substances-bundled.json"
var sourcedOutput: String = "../../data/intermediate/sourced-substances.json"
var curatedOverlay: String = "../../data/curated/substances"
```

From `pipeline/fetch/collector/` those resolve to `pipeline/data/…`, which does
not exist. `JSONWriter.writeFile` calls
`createDirectory(withIntermediateDirectories: true)`, so a `full` run would
**create `pipeline/data/intermediate/` and write there**, leaving the real
`data/intermediate/` untouched and the build reporting success. The curated
overlay dir also misses, and `CuratedOverlayLoader` downgrades that to a
warning. Consistent with this, both files in `data/intermediate/` are dated
2026-08-01, three days before commit `888f3f31` moved the package. Three
segments are needed, not two.

### Both modes — extract, build, snapshot, gate

| # | `build.sh` line | Entry point | Role |
|---|---|---|---|
| 3/8 | `python3 pipeline/fetch/brushers/extract.py` | `fetch/brushers/extract.py` | Brushes the four private datasets in `$PIRU_DATASOURCES` (default `../piru-data`) into `Substance`-shaped JSON in `$PIRU_EXTERNAL_DIR` (default `/tmp/piru-extract`). Offline. No-ops per missing file. |
| 5/8 | `python3 pipeline/build/validate_curated.py` | `build/validate_curated.py` | Stdlib validation of all 739 files in `data/curated/substances/` — enums, inverted ranges, slug/filename drift, duplicate compounds, popularity bounds. Exits non-zero on any error. |
| 6/8 | `python3 pipeline/build/sqlite.py` | `build/sqlite.py` (15,054 lines) | Builds `Piru/Data/piru-substances.sqlite` + `Piru/Data/manifest.json` + `data/snapshots/build-report.md`. Detail below. |
| 7/10 | `python3 pipeline/build/snapshots.py` | `build/snapshots.py` | Reads the **built SQLite** → `data/snapshots/substances.csv`, `substances.json`, `gaps.csv`. |
| 8/10 | `python3 pipeline/audit/signature_coverage.py --write` | `audit/signature_coverage.py` | Rewrites the receptor-signature coverage baseline at `data/snapshots/signature-coverage.json`. |
| 9/10 | seven `python3 …` test invocations | see below | Regression + invariant tests. |
| 10/10 | `python3 pipeline/audit/validate_links.py --gate` | `audit/validate_links.py` | **Network.** Despite the step label "Citation link gate (offline — no network)", this script fetches every cited URL/DOI/PMID with 8 worker threads and rewrites `data/sources/link-cache.json`. The label is wrong. |

Step 9's seven tests, in order:
`build/tests/test_sqlite.py`, `test_overlay_integrity.py`, `test_psid.py`,
`test_product_codes.py`, `fetch/brushers/test_freeodwiki_extract.py`,
`build/tests/test_dosewiki.py`, `build/tests/test_drugbank_adjudications.py`.

Note the step numbering breaks mid-file: steps 1–6 are labelled `/8`, steps
7–10 are labelled `/10`, and there is no step numbered 4 in `fast` mode.

### Inside `build/sqlite.py` — the ingest order

`main()` (line 14083) deletes the old file, runs `SCHEMA_SQL`, seeds the source
table, and then ingests. The order is load-bearing and the comments say why.

1. **Curated first** — `ingest_curated_substances(CURATED_DIR)`. Curated
   identifiers win the `COALESCE` in `upsert_substance` and curated names seed
   the wikidata allowlist.
2. `ingest_sourced_substances(SOURCED)` — the collector output, per-record
   attribution. Falls back to `ingest_bundled_substances(BUNDLED)` with a
   warning if the file is missing.
3. `ingest_psychonautwiki_snapshot`, `ingest_drug_community`,
   `ingest_drug_community_experiential`, `ingest_freeodwiki`, `ingest_subfxonex`.
4. `ingest_enrichment(f)` for every `data/enrichment/raw/*.json`.
5. External extracts: `ingest_pyrls`, `ingest_medtap`, `ingest_benzos_cited`,
   `ingest_nps`. Before `promote_via_tags` so pyrls categories participate, and
   before `classify_compounds` so `regulatory_status` is final.
6. `ingest_dosewiki` — last of the substance-data sources, because it joins by a
   hand-reviewed map and creates no substance, so every source that *can* create
   one must have run.
7. `ingest_curated_mechanisms` → `ingest_pharmacology_flagship` →
   `ingest_class_mechanisms`. Class mechanisms last of the binding passes: it
   writes only where no source measured that target, so it must see the final panel.
8. `promote_via_tags` — a substance resolving to `Other` whose tags identify a
   class gets an extra `piru-curated` category row.
9. The merge cascade: `fold_greek_capital_display_names` →
   `repair_comma_split_aliases` → `dedup_substances` (union-find over
   name↔alias edges; only data-poor stubs merge) → `apply_forced_merges` →
   `merge_self_flagged_duplicates` → `collapse_route_suffixes` →
   `fold_curated_brands` → `fold_salt_families` → `apply_salt_metadata` →
   `fold_isomer_families`.
10. Drops: `drop_junk_and_inert` → `drop_removed_substances` (deliberately
    **outranks** a curated file) → `drop_orphan_stubs` → chemnoise alias purge →
    alias chem-caps → `_TAG_BLOCKLIST` purge →
    `purge_overbroad_research_chemical_tag` → `prune_generic_book_citations` →
    `drop_dead_citations(LINK_CACHE)`.
11. Chemistry reconciliation: identifier reconciliation (auto then manual) →
    `reject_unparseable_smiles` → `apply_structural_duplicate_merges` →
    `apply_pubchem_cids` → `apply_identifier_corrections` →
    `apply_pubchem_freebase` → `apply_pubchem_computed` →
    `normalize_protonation_smiles` → `reconcile_formula_from_structure` →
    `reconcile_formula_mass` → `ingest_molecule_shapes`.
12. Interaction rules: `ingest_interaction_rules` (curated, first — the UNIQUE
    class pair is what makes it beat TripSit) then `ingest_tripsit_combos`.
13. Prose enforcement: `enforce_voice_rule`, `enforce_us_english`,
    `assert_effects_are_readable_in_english`.
14. `scrub_durations` → `flag_dose_less_stubs` → `apply_wikipedia_popularity` →
    `apply_category_overrides` → `classify_compounds` (bakes `display_class`,
    must run last of the classifiers) → `strip_medical_rx_doses` →
    `assign_dose_contexts` → `suppress_therapeutic_doses` → re-flag stubs →
    `curate_common_card`.
15. `assign_substance_uids` — the PSID FAMILY, pinned via
    `data/curated/substance-ids.json`, assigned only once every merge and rename
    has settled.
16. The ~25 curated sidecar ingesters (see the table in `README.md`), then
    `build_substance_forms` / `build_product_strengths` / `build_product_durations`
    / `build_ester_pk` / `build_product_codes` / `audit_alias_collisions`.
17. `is_review` back-fill from `data/sources/pubmed-pubtypes.json`,
    `dedupe_database` (from `build/dedupe.py`), `wal_checkpoint` →
    `journal_mode = DELETE` → `VACUUM` → `ANALYZE`, sha256, manifest, build report.

Curated files `sqlite.py` consults directly (path constants at lines 112–176 and
2649–2654): `substance-ids.json`, `removed-substances.json`, `substances/`,
`mechanisms.json`, `class-mechanisms.json`, `pharmacology-flagship.json`,
`dose-source-exceptions.json`, `structural-duplicates.json`,
`dosewiki-ids.json`, plus (via `CURATED_DIR.parent / …` inside the ingesters)
`half-lives.json`, `opioid-mme.json`, `intrinsic-efficacy.json`,
`by-volume-dosing.json`, `zero-order-kinetics.json`, `saturable-kinetics.json`,
`bioavailability-by-dose.json`, `attenuation-bands.json`, `regional-names.json`,
`interaction-rules.json`, `substance-interaction-classes.json`,
`category-interaction-classes.json`, `tolerance-modulation.json`,
`substance-flags.json`, `enzyme-modulators.json`,
`combination-metabolites.json`, `withdrawal-bands.json`,
`taper-interventions.json`, `class-reference-compounds.json`,
`class-representatives.json`, `drug-classes.json`, `alias-kinds.json`,
`benzo-equivalence-ashton.json`, `class-contexts.json`,
`tripsit-combo-classes.json`, `drugbank-adjudications.json`, and — through
`pipeline/collision_registry.py` — `inchikey-collisions.json`,
`isomer-families.json`, `release-families.json`, `brands.json`,
`product-strengths.json`, `product-durations.json`, `ester_pk/*.json`.

### CI (`.github/workflows/ci.yml`) — a different, larger set of gates

CI never runs `build.sh`. It fetches the DB with `pipeline/fetch-db.sh`, then
runs 9 audit gates + 5 audit tests + 11 build tests + ruff + the curated
validator. Only two audit scripts are on *both* the build path and CI
(`signature_coverage.py`, and `validate_links.py` only on the build path).
`pipeline/ci_local.py` re-runs CI's Python job locally by **parsing ci.yml**
rather than restating it, and is wired as a pre-push hook.

---

## b. Source-priority model

### The Python side declares the order

`build/sqlite.py:311` holds `SOURCES`, a list of `(slug, display_name,
description)` in priority order. `Build.seed_sources()` (line 6017) writes it to
the `sources` table with `default_priority = index`. The shipped order:

| 1–6 | 7–12 | 13–18 |
|---|---|---|
| piru-curated | erowid-pihkal | pyrls |
| peer-review-primary | erowid-tihkal | medtap |
| drug.community | pdsp | benzos-cited |
| psychonautwiki | pubchem | nps-datahub |
| tripsit | wikidata | freeodwiki |
| dailymed | dea-orange-book | dosewiki |

Every fact-bearing table carries a `source_id`. Nothing is resolved at build
time — the DB ships every source's claim and the app picks.

### The Swift side applies it

`SubstanceReadModel` builds the ranking as generated SQL, not as a stored
column (`Piru/Data/SubstanceDB/SubstanceReadModel.swift:141-154`):

```swift
private nonisolated static func buildPriorityCaseSQL(_ order: [String]) -> String {
    guard !order.isEmpty else { return "999" }
    let cases = order.enumerated().map { idx, slug in
        "WHEN '\(slug.replacingOccurrences(of: "'", with: "''"))' THEN \(idx)"
    }.joined(separator: " ")
    return "CASE src.slug \(cases) ELSE 999 END"
}
```

Two shapes use it: `ORDER BY <case> ASC LIMIT 1` for a single value, and
`ROW_NUMBER() OVER (PARTITION BY … ORDER BY <case> ASC)` for a set (dose ladders
partition on `substance_id, route, salt_form, isomer`; durations partition per
phase, so different sources can fill different phases of one curve).

The array it is built from is **not** `sources.default_priority`. It is
`SubstanceStore.enabledSourceOrder`, read from a separate `source_preferences`
table in the user-prefs DB (`SubstanceStore.swift:575-583`), seeded from the
bundled defaults and reconciled on a DB upgrade.
`currentSourceOrderMigration` (value `1`) forces existing installs back onto the
bundled order when bumped. `reorderableSourceSlugs` exposes only six sources in
the UI: `piru-curated`, `peer-review-primary`, `drug.community`,
`psychonautwiki`, `tripsit`, `dailymed`.

Priority is **per field, not per record**. Category, half-life, dose ladders,
durations, tolerance, diazepam equivalents, mechanism prose, descriptions,
metabolism and PK interactions are priority picks. Tags, indications,
contraindications, effects, subjective effects, citations and peptide profiles
are **unions** across all enabled sources. `resolvedTextRow` additionally fails
open: if no enabled source has prose, it re-runs the query without the enabled
filter (`:713-726`) so a substance still shows something.

`AppSources.swift` is attribution and display only — it feeds no resolution.

### Where `dose-source-exceptions.json` is applied

**Python build only.** Nothing in Swift reads it
(`rg -n 'dose-source-exceptions|doseSourceException'` → 3 hits, all
`pipeline/build/sqlite.py:155,7818,8325`).

It is a **pre-resolution filter**, not a resolution rule: the offending rows
never enter `dose_ranges` / `durations`, so the ordinary `ORDER BY <case> LIMIT
1` simply falls through to the next-priority source. 107 entries across six
source slugs (erowid-pihkal 64, drug.community 11, erowid-tihkal 9,
psychonautwiki 8, tripsit 8, freeodwiki 7). Three `@functools.cache`d maps read
it — `_dose_skip_map` (8322), `_duration_drop_map` (8343), `_route_drop_map`
(8356) — and `_exception_for` (8370) looks up by the source's own record name
*and* by the canonical name it resolved to, because PsychonautWiki files
CDP-Choline as "Citicoline".

Four ingest sites apply it, not one: the generic `_ingest_substance_record`
(7828, covering PW / TripSit / both Erowid books), `ingest_drug_community`
(8408, 8438, 8474), `ingest_freeodwiki` (9055), and `_dosewiki_reviewed` (9332).
Three granularities: drop the ladder and keep the duration; drop the durations
and keep the ladder (nothing backfills — the route renders curve-less rather
than with a fictional curve); drop the route entirely.

### Where the adjudicator fits: nowhere

`pipeline/audit/adjudicate.py` (3,239 lines) is **standalone**. It reads the
built SQLite, `audit/adjudicator_weights.json`, `audit/binding_target_map.json`,
`data/sources/chembl-cache.json`, `data/sources/dosewiki.json`,
`data/curated/dosewiki-ids.json` and `Specs/evidence/dosewiki/`, and writes
`data/adjudication/` (gitignored) — `cells.jsonl`, `sources.json`,
`summary.md`, `calibration-top100.md`, `resolution-candidates.json`, and
per-source markdown.

Nothing in `build.sh`, `ci.yml` or `.pre-commit-config.yaml` invokes it, and
neither the build nor the Swift app reads any of its output or its weights file.
Its own test, `audit/tests/test_adjudicate.py`, is the **only** audit test CI
does not run. The README is explicit that this is by design ("It decides
nothing"), and the code matches: its verdicts reach the product only by a human
editing `data/curated/`.

The similarly-named `data/curated/drugbank-adjudications.json` is a different
thing entirely and **is** on the build path (`sqlite.py:3714`, `:11147`), gated
by `build/tests/test_drugbank_adjudications.py` from `build.sh:80`.

---

## c. The dose.wiki path

**Fetch** — `pipeline/fetch/dosewiki.py`, `build.sh` step 1c (full only).
The projection is an allowlist and the exclusions are licensing, not taste,
because a snapshot committed to a public repo is a redistribution:

```python
LICENSE_BLOCKED = ("interactions", "reagent_testing", "reagent_testing_normalized")
```

`interactions` is TripSit's non-commercial combination data and the reagent
fields are ProtestKit's. `priority: low` drafts are never requested.
`MIN_RECORDS = 200` refuses to overwrite the committed snapshot with a thin run.
Nine further fields are dropped for content reasons (`subjective_effects`,
`history_culture`, `legality`, `harm_potential`, `citations`,
`source_citations`, `comparisons`, `pharmacology.receptor_profile`), each with
its reason inline. `build/tests/test_dosewiki.py` walks the whole file asserting
no blocked or dropped key survives at any depth — a CI gate and a `build.sh`
step 9 test.

**Join** — `data/curated/dosewiki-ids.json`, hand-reviewed and structural.
`ingest_dosewiki` (sqlite.py:9151) raises `SystemExit` on any published slug the
file does not decide, and again if a joined `substance_uid` disagrees with the
pin in `substance-ids.json`. Joining by name alone had put dose.wiki's *2C-B*
page onto *bk-2C-B*.

**Ingest** — two gates, drawn at what a reader could act on:

| Written | Gate |
|---|---|
| `substances` chemistry (SMILES / InChIKey / CAS / formula / MW / IUPAC) | any published article, into a NULL-or-empty column only. InChIKey recomputed with RDKit and must match; CAS must pass its check digit; a connectivity skeleton another substance already owns is refused (dose.wiki gives a plant its active molecule's structure) |
| `aliases` | any published article |
| `dose_ranges`, `durations`, `half_lives` | `expert_reviewed` only. `moderate`→`common`, both micro signs fold to `µg`, `come_up`/`after_effects`→`comeup`/`afterglow`, `dose_context = recreational`; the half-life only where neither `half_lives` nor `pk_routes` has one |
| `bindings` | `expert_reviewed`, a stated Ki/EC50/IC50 with a unit (never a `<`/`>` threshold), an action mapped explicitly from `tag`/`efficacy`, and an inline `[cite:…]` resolving to a DOI or PMID. `confidence = LOW` |
| `descriptions` | `expert_reviewed`, after `prose.enforce_voice`, skipped if the banned phrase survives |
| `substances.dosewiki_slug` | any matched article |

`ingest_dosewiki` creates **no** substance. `add_category` refuses `dosewiki`
outright, as it refuses `drug.community` — category is what the interaction
engine keys on. An action that maps to nothing leaves the row out rather than
falling back to `modulator`, which would un-classify the substance. A
monoamine-transporter row whose measure contradicts its action (a releaser
reported as a Ki) is dropped rather than re-filed.

**Rank** — last of 18 in `SOURCES`, so every number resolves only into a hole.
The one exception is `descriptions`, via the `source_field_priority` table.
`SOURCE_FIELD_PRIORITY` (sqlite.py:399) has exactly one entry and
`seed_source_field_priority` (6026) stores `ranks["piru-curated"] + 1 = 1`.
`SubstanceReadModel.resolvedTextRow` joins that table **only when a caller
passes `fieldPriority`**, and `resolvedDescription` (`:734-737`) is the sole
call site in the app:

```swift
let rank = fieldPriority == nil
    ? priorityCaseSQL
    : "COALESCE(sfp.priority, \(priorityCaseSQL))"
```

Worth noting: `priorityCaseSQL` ranks are 0-based while the stored override is
`1`, so dose.wiki's descriptions **tie** with `peer-review-primary` rather than
sitting strictly beneath `piru-curated`. The tie breaks on the second `ORDER BY`
term, so peer-review-primary still wins. The note's wording "directly after
piru-curated" overstates what the number does.

---

## d. The drug.community path

**Fetch** — `pipeline/fetch/brushers/fetch_drug_community.py`, never invoked by
`build.sh` (its comment claims there is no script). One call to
`https://drug.community/api/data/bootstrap` plus three companion datasets from
`/api/data/{intensity-spectra,effects,combinations}`. Writes five files:

| File | Read by |
|---|---|
| `data/sources/drug-community.json` | `sqlite.py:146` → `ingest_drug_community` (8403) |
| `data/sources/drug-community-spectra.json` | `sqlite.py:150` → `ingest_drug_community_experiential` (8563) |
| `data/sources/drug-community-effects.json` | `sqlite.py:151` → same |
| `data/sources/drug-community-combinations.json` | **nobody** — written and never read |
| `data/sources/drug-community.meta.json` | provenance only |

`data/sources/drug-community-names.json` exists in the tree, is written by **no**
script and read by **no** script.

**Transform** — `pipeline/build/drug_community_effects.py` is imported by
`sqlite.py:49,52`. It is pure and dependency-free so it can be unit-tested. Two
producers: `spectrum_levels` maps dc's six fixed intensity levels onto Piru's
dose-band vocabulary (`Threshold/Light/Common/Strong/Heavy/Overdose`, with
"Extreme" becoming Overdose) carrying band description, top effects with
frequencies, and generic high-band warnings; `reported_effects` merges the
spectrum's frequency and emergence band with dc's per-effect domain and a
representative quote, folding dc's 21 fine domains into five UI groups.
`build/dc_effect_aliases.json` sits beside it as the alias table.

**What is deliberately dropped.** The module docstring is explicit: dc's
harm-reduction/warning prose and tolerance claims are not ingested, "see the
`drug-community-data-trust` project note". So dc contributes structured
experiential signal and dose ladders, and none of its prose.

**Rank** — 3rd of 18, ahead of PsychonautWiki. That is the highest-ranked
non-curated, non-literature source. It carries 11 entries in
`dose-source-exceptions.json`, the most of any source after the Erowid books,
and its `DOSE_CONTEXT_BY_SOURCE` entry is `recreational` with a note that it is
genuinely mixed. `add_category` refuses it.

---

## e. Data-flow graph

```mermaid
flowchart LR
  subgraph upstream["Upstream (network, full mode only)"]
    PWAPI[(api.psychonautwiki.org)]
    DWAPI[(dose.wiki API)]
    SFXAPI[(SubFxOnEx release)]
    FDAAPI[(openFDA NDC + ANSM BDPM)]
    COLLUP[(TripSit / Wikidata / PubChem / Erowid)]
    DCAPI[(drug.community bootstrap)]
  end

  subgraph fetch["pipeline/fetch"]
    PWF(psychonautwiki.py)
    DWF(dosewiki.py)
    SFXF(subfxonex.py)
    PCF(product_codes.py)
    COLL(SubstanceCollector.swift)
    DCF(brushers/fetch_drug_community.py)
    EXT(brushers/extract.py)
  end

  subgraph private["Out of repo"]
    PD[(~/Developer/piru-data)]
    TMP[/tmp/piru-extract/]
  end

  subgraph sources["data/sources + data/intermediate"]
    PWJ[psychonautwiki.json]
    DWJ[dosewiki.json]
    SFXJ[subfxonex.json]
    PCJ[product-codes-*.json]
    SRC[intermediate/sourced-substances.json]
    DCJ[drug-community*.json]
    TSJ[tripsit.json]
    FODJ[freeodwiki.json]
    MEDJ[medtap-pk.json]
    PUBJ[pubchem-*.json + identifier-corrections*.json]
    WIKJ[wikipedia-popularity.json]
    LINKJ[link-cache.json]
    PTJ[pubmed-pubtypes.json]
  end

  subgraph curated["data/curated"]
    CSUB[substances/*.json x739]
    CSIDE[~35 sidecar .json + ester_pk/]
    DSE[dose-source-exceptions.json]
    DWIDS[dosewiki-ids.json]
  end

  ENR[data/enrichment/raw/*.json]

  subgraph build["pipeline/build"]
    VAL(validate_curated.py)
    SQL(sqlite.py)
    SNAP(snapshots.py)
  end

  subgraph out["Artifacts"]
    DB[(piru-substances.sqlite)]
    MAN[manifest.json]
    REP[snapshots/build-report.md]
    SNAPS[snapshots/substances.json + csv + gaps.csv]
  end

  subgraph gates["Gates on the build path"]
    SIG(signature_coverage.py --write)
    VL(validate_links.py --gate)
    TESTS(7 tests)
  end

  subgraph standalone["Standalone audit (nothing calls these)"]
    ADJ(adjudicate.py)
    ADJOUT[data/adjudication/*]
    DBK(compare_to_drugbank.py)
    HLP(halflife_from_primary.py)
    DUMP(dump_substance_library.py / dump_for_verification.py)
  end

  PWAPI --> PWF --> PWJ
  DWAPI --> DWF --> DWJ
  SFXAPI --> SFXF --> SFXJ
  FDAAPI --> PCF --> PCJ
  COLLUP --> COLL --> SRC
  DCAPI --> DCF --> DCJ
  PD --> EXT --> TMP
  SNAPS -.name allowlist.-> PCF

  CSUB --> VAL
  CSUB --> SQL
  CSIDE --> SQL
  DSE --> SQL
  DWIDS --> SQL
  PWJ & DWJ & SFXJ & PCJ & SRC & DCJ & TSJ & FODJ & MEDJ & PUBJ & WIKJ & LINKJ & PTJ --> SQL
  ENR --> SQL
  TMP --> SQL
  SQL --> DB
  SQL --> MAN
  SQL --> REP
  DB --> SNAP --> SNAPS
  DB --> SIG
  DB --> VL --> LINKJ
  DB --> TESTS
  DB --> ADJ --> ADJOUT
  DB --> DBK
  DB --> HLP -.--write.-> CSIDE
  DB --> DUMP
  PD --> DBK
  PD --> HLP
```

The Graphviz version, with dead nodes red and standalone-audit nodes gray, is
[`PIPELINE-MAP.dot`](PIPELINE-MAP.dot).

One cycle is worth naming: `sqlite.py` → `snapshots.py` →
`data/snapshots/substances.json` → `fetch/product_codes.py` →
`data/sources/product-codes-*.json` → `sqlite.py`. The barcode fetcher filters
against the previous build's name list, so a substance added this pass cannot
gain a product code until the next `full` run.

---

## f. Dead / unused / unconnected code

Evidence convention below: the `rg` was run from the repo root with
`--glob '!**/.build/**' --glob '!**/__pycache__/**'` and the file itself
excluded.

### f.1 Whole orphan scripts — nothing anywhere references them

| Path | What it does | Evidence | Safe to delete? |
|---|---|---|---|
| `pipeline/audit/source_link_check.py` (1,738 lines) | Verifies every per-substance source link lands on a page about that substance, with homepage-fallback and soft-404 detection, plus a static audit of `AppSources.swift`. Has a `--gate` that is offline-safe. | `rg -n --hidden 'source_link_check.py' . --glob '!pipeline/audit/source_link_check.py'` → **zero hits**. Not in `ci.yml`, not in `build.sh`, not even in `pipeline/README.md`. | **No — wire it up instead.** It is the largest never-run gate in the repo and it checks something no other gate does. Its `--gate` mode is offline and belongs in `ci.yml`. |
| `pipeline/audit/apply_citation_fixes.py` (290 lines) | Applies adjudicated citation repairs (replace/drop) to `data/enrichment/raw/*.json` and `data/curated/`, with a byte-preserving serializer. | `rg -n --hidden 'apply_citation_fixes.py' . --glob '!pipeline/audit/apply_citation_fixes.py'` → **zero hits**. | Scope unclear. It is the only writer path for citation repairs, and its four input files are also dead (below) — the whole citation-fix workflow is a completed one-off. Candidate for `DELETE-CANDIDATES.md`, not for deletion. |
| `pipeline/audit/validate_metabolites.py` (410 lines) | Validates per-class LLM batches of active metabolites and merges survivors into `data/enrichment/raw/metabolites-active.json`. | `rg -n --hidden 'validate_metabolites.py' . --glob '!pipeline/audit/validate_metabolites.py'` → **zero hits**. | Scope unclear — it is a tool for a research pass that may recur. |
| `pipeline/fetch/brushers/fix_enrichment_inchikeys.py` (152 lines) | Recomputes hallucinated InChIKeys in `data/enrichment/raw/*.json` from their SMILES, in place. | `rg -n 'fix_enrichment_inchikeys' . --glob '!…/fix_enrichment_inchikeys.py'` → `(no matches)`. | Scope unclear. A one-off repair whose damage class (LLM-fabricated identifiers) can recur. |
| `pipeline/fetch/brushers/freeodwiki_translate.py` (165 lines) | Stage 1 of 2 of a FreeOD English-prose recovery pass. Writes to `/tmp/freeod-trans/`, which nothing reads. Has no `main()` — it executes at import. | `rg -n 'freeodwiki_translate' . --glob '!…/freeodwiki_translate.py'` → `(no matches)`. | **Yes** — it writes only to `/tmp` and its stage 2 does not exist in the repo. |
| `pipeline/remove_members.py` (103 lines) | One-off Swift refactoring tool: brace-aware removal of named type members. | `rg -n 'remove_members' . --glob '!pipeline/remove_members.py'` → `(no matches)`. | **Yes.** A Swift-editing script in a data pipeline directory, used once. |
| `pipeline/split_decls.py` (182 lines) | One-off Swift refactoring tool: splits a `.swift` into header + relocated decl chunks per a `spec.json`. | `rg -n 'split_decls' . --glob '!pipeline/split_decls.py'` → `(no matches)`. | **Yes**, same reasoning. |
| `pipeline/promote.sh` (22 lines) | Companion to `split_decls.py` — strips `private`/`fileprivate` from just-split-out top-level types. | `rg -n 'promote\.sh' .` → only its own line 2. | **Yes**, same reasoning. |
| `pipeline/validator/` | Empty directory containing only a `.DS_Store`. `git ls-files pipeline/validator` → empty; `git log -- pipeline/validator` → empty. It is the shell of the `SubstanceValidator` SPM package deleted in `888f3f31`. | `rg -n 'pipeline/validator' .` → no code hits. | **Yes** — untracked, empty, and nothing knows it exists. |

### f.2 Manual-but-load-bearing — the script is never invoked, its output *is* on the build path

These are not dead, but the connection between the script and the data is
carried only by prose. A contributor cannot tell from `build.sh` that these
exist.

`fetch/pubmed_pubtypes.py` (→ `pubmed-pubtypes.json`, drives `is_review`),
`brushers/fetch_tripsit.py` (→ `tripsit.json`, drives the interaction matrix),
`brushers/fetch_drug_community.py` (→ four dc files),
`brushers/fetch_pubchem_cids.py`, `brushers/fetch_pubchem_properties.py`,
`brushers/fetch_wikipedia_popularity.py` (→ popularity, which decides the
Research-Chemical purge and the adjudicator's top-100),
`brushers/reconcile_identifiers_pubchem.py`, `brushers/medtap_pk.py`,
`brushers/freeodwiki_extract.py`, `enrichment/build_groups.py`,
`enrichment/merge.py`, `audit/halflife_from_primary.py` (the only sanctioned
writer of `data/curated/half-lives.json`).

`build.sh full` claims to be "re-run the upstream scrape" but refreshes only
five of these thirteen.

### f.3 Manual audit tools — run by a human, referenced only by docs

`audit/adjudicate.py`, `audit/citation_sourcing.py`, `audit/compare_to_pw.py`
(which has no `argparse` and no `__main__` guard — it prints on import),
`audit/cited_identifiers.py`, `audit/survey_curated_overlay.py`,
`audit/clean_curated_overlay.py`, `audit/dump_substance_library.py`,
`audit/dump_for_verification.py`, `audit/dose_sanity.py` (its CLI only — its
tables are imported by `adjudicate.py`, and `DELETE-CANDIDATES.md:35` already
records its SOURCE check as superseded), `audit/compare_to_drugbank.py` (its
CLI only — five of its functions are imported elsewhere),
`pipeline/publish-db.sh`, `pipeline/run-tests.sh`,
`pipeline/annotate_screenshot.py`.

`annotate_screenshot.py` has a stale caller: `.claude/skills/naive-user-test/SKILL.md:68`
still invokes `python3 Tools/annotate_screenshot.py`, a path that has not
existed since `888f3f31`.

### f.4 Unused functions inside used modules

- `pipeline/audit/overlay_lib.py` — ten public-named helpers with no *external*
  caller, all used inside the module: `raw_norm`, `close`, `tuples_match`,
  `round_sig`, `dose_tuple`, `duration_dict`, `classify_scalar`,
  `classify_dose`, `classify_duration`, `family_stem`. Not dead; misnamed.
  The eight genuinely exported are `load_db`, `resolve`, `load_curated_files`,
  `analyze_file`, `resolved_category`, `inchikey_duplicates`, `isomer_families`,
  `clone_clusters`, plus `pubchem_cid_duplicates` and `cross_family` used only by
  `survey_curated_overlay.py`.
- `pipeline/audit/papers.py` and `pipeline/audit/europepmc.py` — **no** uncalled
  public members. Every one is reached from at least one of
  `citation_sourcing`, `citation_topicality`, `verify_citations`,
  `validate_metabolites`, `cited_identifiers`, `halflife_from_primary`.
- `pipeline/audit/citation_labels.py` — module-shaped only in name; its sole
  public function is `main`.
- `pipeline/build/sqlite.py:226` — **`dose_context_for()` is dead work.** It is
  called once, at insert time (line 6674), and every value it writes is
  overwritten later by `assign_dose_contexts()` (13411), which re-applies
  `DOSE_CONTEXT_BY_SOURCE` in SQL, adds the `piru-curated` rule, and re-runs the
  `_THERAPEUTIC_NOTE_MARKERS` scan as a `LIKE` sweep. The only rows the
  insert-time value could survive on are rows from a source absent from
  `DOSE_CONTEXT_BY_SOURCE`, for which it returns `"unknown"` — the same value the
  column already defaults to.
- `pipeline/build/sqlite.py:296-308` — a comment block explaining that
  `data/curated/overlay.json` is baked into `sourced-substances.json` by the
  collector and that "new curated overrides go into data/curated/overlay.json".
  That file does not exist, the mechanism was replaced by
  `data/curated/substances/`, and `pipeline/README.md:31` says so explicitly. The
  comment describes something that is gone, which the repo's own CLAUDE.md
  forbids.

### f.5 Data files under `data/` that no script reads

| File | Status |
|---|---|
| `data/curated/citation-drops-2026-08-04.json` | **zero readers.** `rg -n --fixed-strings 'citation-drops-2026-08-04.json' --glob '!data/**' .` → no output. |
| `data/curated/citation-fixes-2026-08-04.json` | zero readers, same command shape |
| `data/curated/citation-fixes-2026-08-04-likely.json` | zero readers |
| `data/curated/citation-fixes-2026-08-04-research.json` | zero readers |
| `data/sources/drug-community-names.json` | zero readers **and zero writers** — not produced by `fetch_drug_community.py` |
| `data/sources/drug-community-combinations.json` | written by `fetch_drug_community.py:56`, read by nothing |
| `data/sources/product-codes-openfda.meta.json`, `product-codes-bdpm.meta.json` | zero readers; provenance sidecars by design (the other `.meta.json` files are the same, each referenced only by its own writer) |
| `data/enrichment/merged.json`, `class-context.json`, `coverage.csv` | zero readers. `.gitignore:75-79` says so outright: "pure derivatives of `data/enrichment/raw/*.json` … **not consumed by any downstream pipeline step**". **README stale** — `pipeline/README.md:180-182` says `merge.py` produces "the three artifacts the inspectors and the SQLite build care about". The build reads `data/enrichment/raw/*.json` directly (`main()`'s `ENRICHMENT_DIR.glob`). |

The four `citation-*-2026-08-04*.json` files are exactly the inputs
`apply_citation_fixes.py` takes — an orphan script and its four orphan inputs,
the residue of one completed citation-repair pass. That is a coherent five-file
deletion, or a coherent five-file `DELETE-CANDIDATES.md` entry.

### f.6 Counts by class

| Class | Count |
|---|---|
| Whole orphan scripts (zero references) | 8 + 1 empty directory |
| Dead data files (zero readers) | 7 (+3 `.meta.json` sidecars by design) |
| Manual-but-load-bearing fetchers | 13 |
| Manual audit tools (docs-only references) | 13 |
| Dead function inside a live module | 1 (`dose_context_for`) |
| Stale comment blocks describing removed mechanisms | 3 (`sqlite.py:296`, `data/snapshots/README.md`, `build.sh:32`) |
| Never-run gates that exist and work | 1 (`source_link_check.py --gate`) |
| Audit tests not in CI | 1 (`test_adjudicate.py`) |

---

## g. Observations for a data-quality refactor

**1. The same fact is computed twice, and only one of them counts.**
`dose_context` is set at insert (`sqlite.py:6674`) and then wholly overwritten
by `assign_dose_contexts()`. Deleting the insert-time call would remove a
function, a lookup table read per row, and one place for the two rules to drift
apart.

**2. Two InChIKey oracles, two toolkits.** `sqlite.py:754`'s
`inchikey_from_smiles` uses RDKit and gates the dose.wiki chemistry ingest;
`pipeline/chem_ids.py:38`'s `obabel_inchikey` shells out to OpenBabel and gates
CI's `test_identifier_integrity`. RDKit and OpenBabel do not always agree on
tautomers and stereo perception, so the ingest gate and the CI gate can hold
different opinions about the same SMILES. One oracle, or an explicit note about
why two.

**3. Elimination is stored twice.** `half_lives` and `pk_routes` both carry it,
and `audit/pk_sanity.py --gate` exists precisely because nothing else compares
them. The gate is the right ratchet; the duplication is the underlying issue,
and `derive_half_lives_from_pk()` deliberately widens it.

**4. The curated directory is ingested twice, and one copy is thrown away.**
The Swift collector loads `data/curated/substances` as step 5/5 and writes
`piru-curated` rows into `sourced-substances.json`; `sqlite.py` ingests the same
directory directly, first. `build.sh:32-34` says the collector's rows "are
ignored downstream". So the collector does work whose only effect is to make
`sourced-substances.json` larger and to give the file a second, staler copy of
the curated layer. Passing `--curated-overlay` a nonexistent path would be
harmless; it currently *is* a nonexistent path, by accident (see §a).

**5. A curated file that silently outranks everything, including curation.**
`drop_removed_substances` is documented as "deliberately UNPROTECTED by the
curated layer" — a name in `removed-substances.json` deletes a substance even if
someone wrote a full curated file for it. That is a defensible policy, but it is
the one place where the precedence runs backwards from everywhere else, and it
is visible only in a comment at `sqlite.py:119`.

**6. `dose-source-exceptions.json` is a resolution override that resolution
never sees.** Because it filters at ingest, the DB carries no record that a
source *had* a ladder and it was refused. `provenance` / `sourcesProviding` in
the app will report the next source as though it simply won. For 107 hand-argued
exceptions with written reasons, none of that reasoning is reachable from the
shipped artifact.

**7. The adjudicator and the shipped resolution do not share a vocabulary.**
`adjudicate.py` computes per-source, per-column reliability; the app applies one
global ordering that is the same for every substance, route and field. There is
no mechanism — no table, no column — by which an adjudicated verdict could
become a resolution rule short of a human writing a curated file. If the
adjudicator is going to pay for itself, the missing piece is a
per-(substance, column, source) override table, which is exactly the shape
`source_field_priority` already demonstrates for one field.

**8. `source_field_priority` has one row and one reader.** The mechanism is
general (field × source × rank) and the schema, the writer and the Swift join
are all in place, but it holds a single row and `resolvedDescription` is the
only call site. Either that is the intended minimal use or it is scaffolding
waiting for observation 7.

**9. Nothing in the build path is quadratic.** `dedup_substances` is union-find
over two hash maps; `structural_dupes` groups by a key; the alias sweeps are
one query per row, not per pair. The expensive steps are I/O and shelling out:
`check_identifier_integrity` runs `obabel` once per row (~200 s, which is why
pre-commit path-gates it) and `validate_links` makes a network request per
citation. The adjudicator's class prior is the one place with a real
peers-of-peers shape, and it is off the build path entirely.

**10. `build.sh full` is not a full refresh.** Five of the eighteen sources are
refreshed by it; drug.community, TripSit, PubChem properties and CIDs, Wikipedia
popularity, FreeOD, MedTAP PK, identifier reconciliation and PubMed publication
types all have working fetchers that `build.sh` never calls. A reader who runs
`full` and sees "re-run the upstream scrape" will believe their snapshots are
current.

**11. The build's own link gate is mislabelled and is the only network step in
`fast` mode.** `build.sh:82` says "Citation link gate (offline — no network)",
but `validate_links.py` opens sockets and rewrites `link-cache.json`. Since
`fast` mode is sold as offline and reproducible, this is the one thing that
makes it neither.

**12. Documentation drift, itemized.**
`pipeline/README.md:180-182` credits `merge.py`'s outputs to the build (they are
read by nothing, per `.gitignore`).
`data/snapshots/README.md:9-11` says the snapshots are generated "from the same
SubstanceCollector outputs that feed the SQLite build" — `snapshots.py` reads
the built SQLite, which `pipeline/README.md:112` gets right.
`data/snapshots/README.md`'s diagram names `data/curated/overlay.json`, which
does not exist.
`build.sh:32` claims drug.community has "no script".
`build.sh`'s step denominators change from `/8` to `/10` halfway down.
`pipeline/README.md` does not mention `pubmed_pubtypes.py`, `chem_ids.py`,
`collision_registry.py`, `psid.py`, `product_codes.py`, `ci_local.py`,
`fetch-db.sh` or `publish-db.sh` at all.
