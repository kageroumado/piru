---
id: SCR-session-detail
type: screen
description: One session's full detail — PK timeline, dose rows, body-load, safety, recovery; edit actions route through a second environment channel.
edges:
  - {rel: contains, target: CMP-theme-card}
  - {rel: contains, target: CMP-elimination-curve}
  - {rel: navigates_to, target: SCR-entry-detail}
  - {rel: navigates_to, target: SCR-comedown-guide}
  - {rel: diverges_from, target: SCR-journal-home}
metadata:
  screenshot: screenshots/SCR-session-detail.png
---

# Session detail (`SessionDetailView`)

**Route**: `PushRoute.session(id:)` and `SheetRoute.sessionDetail` (via `CurrentSessionHost`,
resolves most-recent session). **Deep link**: `piru://day` (sheet) / `piru://session/<uuid>` (push).
**File**: `Piru/Views/Journal/Session/SessionDetailView.swift` (675 ln).

## States
Empty: `entries.isEmpty` → `ContentUnavailableView("No Entries", "pill", ...)` (`:355-360`).
Otherwise entirely conditional composition, no loading spinner. `EffectEstimatesCard` self-omits
(no placeholder) when mechanistic modeling is unsupported/absent (`:389-400`).

## Components
`SessionTimelineSection`, `UnmodeledFormNote`, `EffectEstimatesCard`, `VitalsOfferBanner`, an
**inline un-extracted "Note" `Section`** (`:406-439` — breaks this screen's own per-section-file
pattern), `SessionEntryListSection`, `SessionBodyLoadSection`, `SessionSafetySection`,
`SessionRecoverySection`. Toolbar: plain share button + `SessionMenu`. Sheets (via a **second,
parallel `sessionEditingService` environment channel**, distinct from `AppNavigator`):
`SessionNoteEditor`, `TimeAdjustSheet`, `MoveToSessionView`, `SessionShareSheet`,
`SubstanceColorPickerView`.

## Tokens
Corner-radius tally within this one folder: `16`×2 (`SessionCardView.swift:169,204`), `8`×1
(mini-graph clip), `18`×1 (`SessionNoteEditor.swift:16`) — 3 radii, no shared constant.
`SessionNoteEditor` is the only file in the folder using `.thickMaterial` + a raw
`Color.primary.opacity(0.08)` hairline instead of `CardBackground()`/`.themeCard()`.

## Known divergences
`DIV-009` (dual navigation channel: imperative `navigator.push` + `sessionEditingService`,
mixed in one `DayEntryRow` context menu), `DIV-015` (no delete confirmation on row/note delete,
unlike `EntryDetailView`), `DIV-005` (this screen's rows use the shared `EntryRowView`/`DayEntryCore`
— correctly, unlike the flat Journal list).
