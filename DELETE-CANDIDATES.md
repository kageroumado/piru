# Delete candidates

Two kinds of entry, both ending in a deletion:

1. **Looks dead; scope or origin unverified.** A maintainer confirms → it goes.
2. **Live, but in the wrong layer.** The code is load-bearing *today*, so it
   cannot just be cut — the data moves to where data belongs first, and the code
   goes after. These carry a **Why it goes** field instead of "Looks dead
   because", and the migration is the work; the deletion is the easy part.

## `Piru/Views/Components/PharmacologyGlossarySheet.swift:11` — `Topic.monoamine`

- **What**: the enum case plus the explainer copy written for it
- **Looks dead because**: zero call sites — no `onGlossary(.monoamine)` anywhere in the repo. Every
  other `Topic` is reachable from an ⓘ button; this one never got wired to anything. Surfaced during
  the 2026-08-03 ⓘ audit.
- **Not deleted because**: the copy is written and the monoamine hero is still on screen, so it may
  be a wiring gap rather than a dead concept — the intended ⓘ may simply never have been added.
- **To confirm**: decide whether the S↔D lean bar should have its own ⓘ. If yes, wire it; if no,
  delete the case and its copy.
- **Found**: 2026-08-03

## `Piru/Data/Pharmacology/HalfLifeDatabase.swift` — the whole file

- **What**: 534 hardcoded `"substance": minutes` entries plus `halfLife(for:)`, read at 13 call
  sites as `substance?.halfLifeMinutes ?? HalfLifeDatabase.halfLife(for: name)`.
- **Why it goes**: substance data does not belong in Swift. It ships in the bundled SQLite, built
  from `data/curated/` through the pipeline, where it is versioned, source-attributed, citable, and
  editable without a release. A second table in application code is a parallel source of truth that
  no gate checks and no citation covers — and because its name and doc comment read as canonical,
  it is where people edit first and then wonder why nothing changed.
- **Not deleted because**: **it is not dead — 281 of its 534 entries (53%) are values the bundled
  DB does not have.** Deleting today silently drops a half-life for those substances, which
  collapses their PK curves. Measured 2026-08-04 against the current DB:
  - **244** — substance exists in the DB, has no half-life. These are the migration payload.
  - **37** — substance absent from the DB entirely (needs a curated file first, or is out of scope).
  - **253** — already covered by the DB; redundant, and the DB already wins via the `??`.
- **To confirm**: migrate, then delete. Per value, that means a `halfLifeMinutes` (+ `halfLifeSource`
  citation) in `data/curated/substances/<slug>.json`, then `pipeline/build.sh fast`. The blocker is
  provenance, not mechanism: the Swift table cites only a file-level source list (DrugBank, PubMed,
  DailyMed, TripSit, PsychonautWiki), so no individual number has a citation, and moving an uncited
  number into curated data just relocates the problem. Values without a findable source should not
  be carried over. Once the file is empty of unique data, delete it and the 13 `??` fallbacks with it.
- **Found**: 2026-08-04

## Sibling Swift data tables — same class, scope unmeasured

- **What**: `Piru/Data/Pharmacology/SubstanceModelDatabase.swift`,
  `MechanismOfActionDatabase.swift`, `ActiveIngredient.swift`, and the class/rule tables in
  `Piru/Data/Services/Interactions.swift`.
- **Why it goes**: same principle as `HalfLifeDatabase` — data in Swift, uncitable and unversioned.
- **Not deleted because**: none has been measured against the bundled DB the way HalfLifeDatabase
  was, and at least one is not a straight port — interaction rules are class-based logic, not
  per-substance values, so "move it to the data layer" may mean designing a schema rather than
  filling a column. Listed so the principle is on record, not as an approved deletion.
- **To confirm**: measure each against the DB (the HalfLifeDatabase entry above shows the method),
  then decide per file whether it is a migration or a redesign.
- **Found**: 2026-08-04
