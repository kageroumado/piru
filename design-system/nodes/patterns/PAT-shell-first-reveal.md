---
id: PAT-shell-first-reveal
type: pattern
description: Push a lightweight "shell" projection immediately, then upgrade to the full record asynchronously — avoids a loading spinner on push.
edges:
  - {rel: used_by, target: SCR-substance-detail}
metadata: {}
---

# Shell-first progressive reveal

**Where**: `SubstanceDetailView` is pushed with `SubstanceLibrary.shell(name)` (a lightweight
projection, `AppDestinations.swift:84-85`) and then `.task(id: baseSubstance.name) {
upgradeToFullRecord() }` (`SubstanceDetailView.swift:225-228`) swaps in the full record. Per-section
data loads further behind `DisclosurePolicy` tier gates via `@Observable SubstanceDetailModel`.

**Why**: substance lookups hit a bundled SQLite DB — this pattern means the push transition and
header render instantly (no spinner on navigate), with body sections filling in as data resolves.

**Where else this idiom could apply but doesn't (yet)**: `MedDetailView`/`InventoryItemDetailView`
push synchronously today (no shell/upgrade split) — fine at their current data size, but worth
knowing this pattern exists if either grows a slow lookup.
