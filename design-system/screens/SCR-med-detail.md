---
id: SCR-med-detail
type: screen
description: One med's detail — edit-in-place (no separate Edit sheet), every control bound directly to the @Model.
edges:
  - {rel: diverges_from, target: SCR-my-meds-hub}
  - {rel: duplicates, target: SCR-med-form}
metadata:
  screenshot: null
---

# Med detail (`MedDetailView`)

**Route**: `PushRoute.medDetail(identityKey:sortOrder:)`, guarded — renders nothing if the item
was deleted (`AppDestinations.swift:117-122`). **File**: `Piru/Views/Journal/DailyDose/MedDetailView.swift` (442 ln).

## Pattern (positive example)
Only 1 `@State` (`showingDeleteConfirmation`); every control binds directly to `@Bindable var item:
DailyDoseItem` (amount, unit/route pickers, schedule picker, weekday buttons `:284-297`, reminder
`DatePicker`s, Remind Me/Ask Again/Next-Dose-Window/Quiet toggles) — this is the "edit in place, no
Edit sheet" pattern the repo committed to (see project history `med-detail-edit-in-place`). Sections
are un-extracted computed properties (`:121-335`, mild version of the superview smell despite
passing the `@State` count). Delete via `confirmationDialog` → `modelContext.delete` + **env
`dismiss()`** (`:94-105`, not `navigator.dismiss()` — `DIV-011`). Header avatar `.frame(width:44,height:44)`
(`:127-128` — vs. 30×30 on the Hub, `DIV-013`).

## Known divergences
`DIV-013` (avatar size), `DIV-011` (dismissal strategy).
