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
