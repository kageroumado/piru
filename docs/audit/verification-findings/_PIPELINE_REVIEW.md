# Substance data pipeline — design review

Written after the multi-pass audit and four rounds of fixes. This documents
what the pipeline does well, where it has structural weaknesses, and what
practical hardening is worth doing next.

## The pipeline at a glance

```
  ┌────────────────────────────┐  ┌────────────────────────┐  ┌──────────────────────┐
  │ sourced-substances.json    │  │ drug-community-data    │  │ psychonautwiki-      │
  │ (multi-source merged,      │  │ .json (raw API dump)   │  │ snapshot.json (raw   │
  │ piru-curated overrides)    │  │                        │  │ GraphQL dump)        │
  └─────────────┬──────────────┘  └────────────┬───────────┘  └──────────┬───────────┘
                │                              │                          │
                └───────────────────┬──────────┴──────────────────────────┘
                                    ▼
                ┌─────────────────────────────────────────────┐
                │ Exports/build-sqlite-database.py            │
                │  · normalise routes (smoked→inhalation, …)  │
                │  · parse units (regex + per-curve units)    │
                │  · drop inverted/regressed/ambiguous rows   │
                │  · insert per (substance, route, source_id) │
                └─────────────────────┬───────────────────────┘
                                      ▼
                ┌─────────────────────────────────────────────┐
                │ Piru/Data/piru-substances.sqlite            │
                │   sources(slug, default_priority)           │
                │   substances · dose_ranges · durations · …  │
                └─────────────────────┬───────────────────────┘
                                      ▼
                ┌─────────────────────────────────────────────┐
                │ Swift: SubstanceStore.resolvedDoseForRoute  │
                │   ORDER BY priority ASC LIMIT 1             │
                │   (per substance, per route, per field)     │
                └─────────────────────┬───────────────────────┘
                                      ▼
                ┌─────────────────────────────────────────────┐
                │ Views: DoseLevelIndicator,                  │
                │ SubstanceLibraryView, EntryRowView, …       │
                └─────────────────────────────────────────────┘

  Audit channel:
    Exports/dump-substances-for-verification.py
      → text chunks → parallel Sonnet agents → findings
```

## What this pipeline does well

**Multi-source attribution preserved end-to-end.** Every `dose_ranges` /
`durations` / `half_lives` row carries its `source_id`. The resolver picks
the highest-priority source per `(substance, route)` at query time, and the
losing values stay in the DB for audit. The dump tool surfaces the alternates
inline so reviewers can see disagreement at a glance.

**Priority-based override mechanism is clean.** Adding a `piru-curated`
entry (priority 1) to `sourced-substances.json` shadows any wrong upstream
value without deleting it or branching the source data. The 9 BLOCKER
overrides this session were one-file changes each.

**UNIQUE constraint on (substance_id, route, source_id)** prevents within-
source duplication; cross-source duplication is handled by the resolver.

**Structural sanity gate at ingest time.** Three drop conditions (gross
≥10× inversion, tier-upper regression, ambiguous unit string) reject
structurally corrupt rows. ~19 rows dropped on this build — about 0.8% of
the input — and each is logged in `manifest.json`.

**Verification channel exists and is reproducible.** A single
`python3 dump-substances-for-verification.py` regenerates the agent input.
The audit transcripts are checked in alongside the data, so any future
change can be re-reviewed against the prior baseline.

## Weaknesses worth acting on

### 1. Single-tier rows can't be sanity-checked

Tier-monotonicity needs ≥2 values to compare. Rows with just one tier (e.g.
TripSit Valerylfentanyl: bare `light 50 mg`, no other tiers) pass every
structural check even when the value is grossly wrong. Curated overrides
caught Valerylfentanyl, but a future similar row would slip through.

**Fix candidates:**

- *Substance-class sanity rules* keyed on tags. The DB already has tags
  like `fentanyl-class-potency`, `opioid`, `psychedelic`, `dissociative`.
  Reject rows where any tier is implausible for the substance's class:
  e.g. `fentanyl-class-potency` with any dose value >2 mg → drop.
  Brittle if tags are missing, but high-leverage for the worst cases.
- *Cross-substance comparison* against a hand-curated reference table
  of canonical low/typical/high doses per class. Less brittle than tag
  rules but requires maintaining the reference table.

### 2. Source priority is global, not per-route

Sources are ranked once globally (`default_priority` 1–12). PsychonautWiki
wins for most Fentanyl routes, but its transdermal entry uses the wrong
unit (`µg` instead of `µg/hr`) — handled by the curated override but
indicates a structural gap. There are real cases where Source A is
canonical for substance X's oral route but unreliable for inhalation.

**Fix candidate:** allow per-source per-(substance, route) priority
overrides in `sourced-substances.json` (a `sourcePriorityOverrides` field
on a substance entry). More flexible than blanket curated rows when only
prioritisation needs to change, not the values themselves.

### 3. The piru-curated overlay file is referenced but unused

`Tools/SubstanceCollector/curated-overlay.json` exists, the build script
defines `CURATED = REPO / "Tools/SubstanceCollector/curated-overlay.json"`,
but `main()` never calls `ingest_bundled_substances(CURATED)`. Overrides
currently live in `sourced-substances.json` instead. Two separate
files-of-truth is confusing — this session's 9 overrides went into
`sourced-substances.json`, the older 354 piru-curated entries are also
there. The standalone overlay file is dead code.

**Fix candidate:** either (a) wire `ingest_bundled_substances(CURATED)`
into main() as the first ingest step and migrate the override pattern
there, or (b) delete `curated-overlay.json` and update the `CURATED`
constant + comment. Option (a) keeps overrides in their own file
(easier to audit per-PR), option (b) keeps single-source-of-truth.

### 4. No regression-test layer

The audit catches mistakes; nothing prevents reintroducing them. If a
future PR breaks the duration unit conversion again, the only signal
is the next agent verification pass.

**Fix candidate:** add `Tools/SubstanceValidator` cases that assert
specific known-good values after a rebuild — pick ~10 widely-known
substances (caffeine oral common, MDMA oral common, LSD oral threshold,
fentanyl IV common, etc.) and fail the build if their resolved values
drift. The Validator suite already exists and is the natural home.

### 5. Tag-keyed unit invariants don't exist

The DB knows Fentanyl is tagged `fentanyl-class-potency`, but the
ingester doesn't use this to validate dose magnitude. The same goes for
benzodiazepines (always sub-100mg), psychedelics where µg vs mg matters,
opioid analogs, etc.

**Fix candidate:** add a small `_CLASS_UNIT_INVARIANTS` table mapping
tag → expected dose-magnitude range. Reject rows violating it. Same
spirit as the existing tier-inversion check, but informed by chemistry.

### 6. The dump tool's chunking is by category, not by risk

Today the 41 chunks are sized to ~50 substances per file split by
category. That's fine for full audits but inefficient when re-checking
after a focused change: the agent for "Stimulant_03" reviews 50
substances when only one was touched.

**Fix candidate:** add a `--changed-since GIT_REF` mode to the dump
script that only emits substances whose resolved values differ from a
prior baseline. Pairs naturally with regression testing.

### 7. No machine-readable findings format

Findings are markdown, parsed via `grep`. Aggregation is awkward and
not stable across agents (e.g. some wrote `1 finding written.`, others
`1 finding written`).

**Fix candidate:** ask agents for findings as JSON (one object per
finding with substance/route/severity/expected/rationale). Easier to
diff between passes and to mechanically promote BLOCKERs into curated
overrides.

## Hardening priorities

If I were going to invest more time here, in order:

1. **Wire `curated-overlay.json` into the build** (or delete it). Removes
   dead code and gives overrides their own file. ~30 min.
2. **Tag-keyed unit invariants** for the highest-risk classes:
   `fentanyl-class-potency`, `nitazene`, `benzodiazepine`, `lysergamide`.
   ~2 hours. Catches structurally consistent but content-wrong source
   rows that current checks miss.
3. **Validator regression tests** for ~20 well-known substances. Same
   shape as the existing audit checks. ~1 hour. Prevents reintroduction.
4. **JSON findings format** for the dump tool. Enables diffing audits.
   ~30 min.
5. **Per-source-per-route priority overrides** if Fentanyl-transdermal-
   style issues keep appearing. ~3 hours and a small schema change.

The structural ingestion bugs found this session are unlikely to recur
because the offending patterns now have dedicated drop conditions. The
remaining failure mode is *new* upstream content errors — and the
verification dump + agent loop is the right tool to find those.
