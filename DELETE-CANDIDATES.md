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
  anything. Every pass so far has found real disagreements that way, including
  planned DB targets that turned out to be the wrong table, column or scale.
- **Found**: 2026-08-04
