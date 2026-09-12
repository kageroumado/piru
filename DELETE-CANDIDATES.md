# Delete candidates

Two kinds of entry, both ending in a deletion:

1. **Looks dead; scope or origin unverified.** A maintainer confirms → it goes.
2. **Live, but in the wrong layer.** The code is load-bearing *today*, so it
   cannot just be cut — the data moves to where data belongs first, and the code
   goes after. These carry a **Why it goes** field instead of "Looks dead
   because", and the migration is the work; the deletion is the easy part.

## Sibling Swift data tables — same class, scope unmeasured

- **What**: `Piru/Data/Pharmacology/SubstanceModelDatabase.swift` (the PK-patch
  `overrides` and the PD-inheritance `aliases`) and
  `MechanismOfActionDatabase.swift` (~244 names → ~40 templates).
- **Why it goes**: substance data does not belong in Swift. It ships in the bundled SQLite, built
  from `data/curated/` through the pipeline, where it is versioned, source-attributed, citable, and
  editable without a release. A second table in application code is a parallel source of truth that
  no gate checks and no citation covers — and because its name and doc comment read as canonical,
  it is where people edit first and then wonder why nothing changed.
- **Not deleted because**: neither is a straight port. `MechanismOfActionDatabase`
  carries `LocalizedStringResource` prose, so moving it means choosing between
  per-language DB rows and keeping the copy in Swift keyed by class — a design
  decision, not a column fill. `SubstanceModelDatabase.overrides` stores `ke`
  **per hour** where every other elimination path is per minute, and its
  `aliases` are a PD-inheritance relation that must never merge into the naming
  aliases.
- **To confirm**: dump the DB and diff it against the literal *before* porting
  anything — every pass so far has found real disagreements that way, and seven
  of the migration spec's own named DB targets turned out to be the wrong table,
  column or scale. `Specs/pharma-data-in-swift.md` carries the method and the
  per-item constraints.
- **Found**: 2026-08-04

## `pipeline/audit/dose_sanity.py` — the SOURCE check

- **What**: the `SOURCE` mode only (`check_sources`, `check_source_group`,
  `check_source_pair`, and the `source` value of `--check`). ROUTE and LADDER
  stay, and so do the module's tables — `adjudicate.py` imports `ROUTE_RANK`,
  `ROUTE_ALIASES`, `UNITS`, `LADDER`, `LADDER_SEQUENCES` and `TIER_BOUNDS` from
  it rather than restating them.
- **Looks dead because**: `pipeline/audit/adjudicate.py` answers the same
  question with strictly more evidence — the same median-of-the-others
  comparison, plus copy-clustering (so freeodwiki repeating PsychonautWiki is
  one vote, which SOURCE counts as two), per-source reliability weights, a
  class-level prior, and a probability instead of a ratio threshold. Every
  SOURCE finding appears in `data/adjudication/summary.md`.
- **Not deleted because**: nothing in the repo invokes it — no CI job, no
  `build.sh` step — so its callers, if any, are habits and notes outside this
  tree, and `--gate` exits non-zero on HIGH in a way someone may rely on.
- **To confirm**: `rg 'dose_sanity' ~/Developer` and ask whether anyone runs
  `--check source` by hand; then delete the three functions and the `source`
  choice, leaving ROUTE, LADDER and the tables.
- **Found**: 2026-09-10

`ActiveIngredient.swift` and the class/rule tables in
`Piru/Data/Services/Interactions.swift` were on this list and are gone:
`substances.active_ingredient_substance_id`, `interaction_rules`,
`substance_interaction_classes` and `category_interaction_classes` carry them now.
`HalfLifeDatabase.swift` left it too, deleted rather than migrated — 221 of its
534 keys were estimates for compounds with no published human pharmacokinetics,
and the rest duplicated values the DB already resolved.

## `pipeline/audit/source_link_check.py` — 1,738 lines, never invoked

- **What**: verifies every per-substance source link lands on a page about that substance (soft-404 detection, homepage fallback) plus a static audit of `AppSources.swift`; has a working `--gate`.
- **Looks dead because**: no `build.sh` step, no CI job, no skill or doc invokes it (`rg source_link_check .` → only itself).
- **Not deleted because**: it is the only link-topicality check the repo has; `validate_links.py` checks reachability, not aboutness. Someone may run it by hand before a release.
- **To confirm**: ask Kiri whether it runs before submissions; if yes, wire it into CI as a nightly, if no, delete.
- **Found**: 2026-09-11 (pipeline map)

## `pipeline/audit/apply_citation_fixes.py` + `data/curated/citation-{drops,fixes,fixes-likely,fixes-research}-2026-08-04.json`

- **What**: the script applies adjudicated citation replace/drop decisions to `data/enrichment/raw/*.json` and `data/curated/`; the four JSON files are its inputs.
- **Looks dead because**: zero references to the script or to any of the four files outside themselves. They are the residue of one completed citation-repair pass (2026-08-04).
- **Not deleted because**: whether the pass was fully applied is not recorded anywhere; the inputs are the only record of what was decided.
- **To confirm**: `git log --oneline -- data/enrichment/raw | head` around 2026-08-04 shows the applied diff → delete all five together.
- **Found**: 2026-09-11 (pipeline map)

## `pipeline/audit/validate_metabolites.py`, `pipeline/fetch/brushers/fix_enrichment_inchikeys.py`, `pipeline/fetch/brushers/freeodwiki_translate.py`

- **What**: three one-pass enrichment tools — LLM-batch metabolite validation into `metabolites-active.json`; in-place InChIKey recompute over `data/enrichment/raw`; stage 1 of a FreeOD prose-translation pass writing to `/tmp/freeod-trans/` (executes at import, no `main()`).
- **Looks dead because**: nothing references any of them; their outputs are either already merged or read by nothing.
- **Not deleted because**: each documents how a batch of committed data was produced, and an enrichment re-run would want the same procedure.
- **To confirm**: Kiri says whether enrichment batches will ever be re-run; if not, delete and keep the procedure in `pipeline/enrichment/prompts/`.
- **Found**: 2026-09-11 (pipeline map)

## `data/sources/drug-community-names.json`, `data/sources/drug-community-combinations.json`

- **What**: two drug.community extracts. `-names` has no reader and no writer; `-combinations` is written by `fetch_drug_community.py` and read by nothing.
- **Looks dead because**: `rg` finds no consumer of either.
- **Not deleted because**: the combinations matrix is the kind of thing an interaction feature would read next, and the admin of drug.community is a contact — the file may be a deliberate hold.
- **To confirm**: ask Kiri; delete `-names` regardless if she does not recognize it.
- **Found**: 2026-09-11 (pipeline map)

## `pipeline/build/sqlite.py` — `dose_context_for()`

- **What**: the insert-time dose-context classifier, called once from `add_dose`.
- **Looks dead because**: every value it writes is overwritten by `assign_dose_contexts()`, which re-applies the same table in SQL plus the curated rule; the only rows its value could survive on get `"unknown"`, the column default.
- **Not deleted because**: `add_dose` callers in tests may assert the interim value; needs a test run after removal.
- **To confirm**: delete the call and the function, run `pipeline/build/tests/test_sqlite.py`.
- **Found**: 2026-09-11 (pipeline map)

