---
id: SCR-entry-edit
type: screen
description: Standalone entry-edit form, reached only via swipe/context-menu from a session's day view — duplicates EntryDetailView's edit logic independently.
edges:
  - {rel: variant_of, target: SCR-entry-detail}
  - {rel: diverges_from, target: SCR-entry-detail}
metadata:
  screenshot: null
---

# Entry edit (`EntryFormView`)

**Route**: `SheetRoute.entryEdit(timestamp:id:)` only — **not reachable from `EntryDetailView`
or the flat Journal list**, presented exclusively from `Session/DayEntryRow.swift:52-59` (swipe)
and `:67-71` (context menu). No deep link (excluded, `DeepLink.swift`).
**File**: `Piru/Views/Journal/EntryFormView.swift` (633 ln). Not captured in the screenshot pass
(requires a swipe gesture inside Session detail — reachable via `axe swipe` on a `DayEntryRow` if
a future pass needs the screenshot).

## States
By-volume vs. weight input toggle (`:21-56`); location present/absent (`:100-122`); full-width
destructive `Button("Delete Entry")` (`:156-161`) with **no counterpart in `EntryDetailView`**.

## Anti-pattern flag
**21 raw `@State` properties** (`:12-42`) — the clearest `CLAUDE.md` "superview" violation found
in the Journal territory (`DIV-027`). Duplicates unit-normalization/by-volume math/save-commit
logic that `EntryDraft` (`EntryDraft.swift:9`, `@Observable`) already solves for `EntryDetailView`
— this view doesn't use it. Icon-only `xmark`/`checkmark` toolbar vs. `EntryDetailView`'s text
`Cancel`/`Done` for the same concept; `.navigationBarTitleDisplayMode(.inline)` vs. `.large`.

## Recommended fix
Migrate onto `@Observable EntryDraft` and delete the duplicated state — this closes both
`DIV-027`'s worst non-QuickLog offender and the toolbar-icon/title-mode divergence in one pass.
