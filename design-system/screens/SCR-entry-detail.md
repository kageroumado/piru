---
id: SCR-entry-detail
type: screen
description: One logged dose — PK timeline, dose card, session context, notes; toggles into an inline edit mode.
edges:
  - {rel: variant_of, target: SCR-entry-edit}
  - {rel: contains, target: CMP-capsule-chip}
  - {rel: navigates_to, target: SCR-session-detail}
  - {rel: diverges_from, target: SCR-entry-edit}
metadata:
  screenshot: screenshots/SCR-entry-detail.png
---

# Entry detail (`EntryDetailView`)

**Route**: `PushRoute.entry(timestamp:id:)` (`AppDestinations.swift:46-54`) and
`SheetRoute.entryDetail` (`SheetRouteView.swift:46-52`), both via `EntryLookupView`'s id-then-±2s-window
resolver — **renders nothing if resolution fails** (no `ContentUnavailableView`).
**Deep link**: `piru://entry/<unix-ts>[?id=<uuid>]`. **File**: `Piru/Views/Journal/EntryDetailView.swift` (340 ln).

## States
Toggles `EntryReadContent`/`EntryEditContent` via `isEditing`, `.snappy(duration:0.28)` (`:74-96,113`).
Toolbar: read = text `Edit` + `EntryDoseMenu` (⋯); edit = text `Cancel`/`Done` (disabled while
`draft.parsedAmount == nil`). `.confirmationDialog("Delete this entry?")` (`:115-125`); sheets:
`SubstanceColorPickerView`, `LocationPickerView`.

Read content (`EntryReadContent.swift`, 339 ln): timeline present/absent, ALDH2 alcohol card,
oral-cannabis 11-OH-THC card, metabolite section (gated on resolution), ramp-down link (gated on
`resolvedDuration != nil`, bare `.foregroundStyle(.green)` "Active" badge — the one hardcoded
system color in this cluster). Chart frame 176pt (read) vs 160pt (edit) for the identical
`EntryTimelineGraph`.

## Components
`EntryAboutSection`, `EntryContextSection` (only file with hardcoded `cornerRadius:12` on its
`Map`), `EntrySessionSection` (caps sibling rows at 3, "+N more"), `EntryDraft` (`@Observable`,
pure state — **not reused by `EntryFormView`**, see `SCR-entry-edit`).

## Tokens
Hero chip = `heroChip` (`CapsuleChip.swift:20-26`) vs. row/session chips = `capsuleChip`
(`:7-13`) — `DIV-006`. Leading-inset drift within this one screen: `12` (graph), `20` (hero),
`10` (map, in `EntryContextSection`), `6` (graph preview in edit mode) — 4 values, no shared
constant.

## Known divergences
`DIV-006` (chip metrics), `DIV-027` (`EntryFormView` duplicates this screen's `EntryDraft` logic
instead of reusing it).
