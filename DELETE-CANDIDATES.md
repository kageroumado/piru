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

## `pipeline/audit/apply_citation_fixes.py`

- **What**: applies an adjudicated batch of citation replace/drop/unsource decisions to `data/enrichment/raw/*.json` and `data/curated/`.
- **Looks dead because**: nothing calls it and it has no input files. Every 2026-08-04 batch it was written for is applied (`--dry-run` changed 0 records for each), so those inputs were deleted.
- **Not deleted because**: it is the only writer that edits a wrong `reference` in place with a byte-preserving serializer; a new citation that fails a gate may need it. Sourcing a row that has no citation goes through `data/curated/row-citations.json` instead.
- **To confirm**: decide whether the next wrong-reference batch goes through this script or the row-citations sidecar.
- **Found**: 2026-09-11 (pipeline map)

## `Shared/Skin/Skin.swift` — `SkinEphemeris.air`, `SkinPaperGarden.grain`, `SkinArcade.grid`
- **What**: three palette tokens, each with a matching asset color, that are assigned in the palette initializers and never read
- **Looks dead because**: Periphery 3.8 reports them assign-only; no renderer in `Piru/Views/Components/Skin*.swift` reads them
- **Not deleted because**: they are design tokens with paired assets, and the Ephemeris doc comment gives `air` its own token deliberately — the renderer may simply not have caught up with the design
- **To confirm**: ask whether the Ephemeris sector ticks, Paper Garden grain and Arcade grid are meant to use them; if not, delete the three properties and their colorsets
- **Found**: 2026-09-24
