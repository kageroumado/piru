---
id: SCR-my-meds-hub
type: screen
description: Grouped list of tracked daily meds/supplements — navigation-only rows, no logging control on this screen.
edges:
  - {rel: navigates_to, target: SCR-med-detail}
  - {rel: diverges_from, target: SCR-med-detail}
  - {rel: duplicates, target: SCR-med-form}
metadata:
  screenshot: null
---

# My Meds hub (`MyMedsHubView`)

**Route**: `PushRoute.myMeds` (push) and `SheetRoute.dailyDoseSettings` (legacy name, wraps its
own `NavigationStack`). No direct deep link (only `piru://meds/<category>` → `.dailyDoseLog`, a
different screen — see `SCR-log-medications`). **File**: `Piru/Views/Journal/DailyDose/MyMedsHubView.swift` (289 ln).

## States
Empty: `items.isEmpty` (`:118`) → `ContentUnavailableView("No Meds Yet", "pills", ...)`
(`:180-192`) + inline Add button. Grouped by `MedTimeGroup` (morning/afternoon/evening/night/
anytime/asNeeded, `:121-138`).

## Components
`MedRow` (private, `:209-289`) — the **entire row is one `Button`** pushing `.medDetail(...)`,
**no check-circle, no logging affordance on this screen at all** (see `DIV-012`). Row icon avatar
30×30 (`:220` — vs. 44×44 on the detail screen, `DIV-013`). `NotificationSettingsView` reached via
a plain `NavigationLink` (`:150-152`) — **bypasses `AppNavigator`**, the only such bypass found in
this territory. `.navigationTitle` is `.large` (`:164`) — the only screen in this cluster using
`.large` (siblings use `.inline`).

## Known divergences
`DIV-012` (3 logging metaphors for `DailyDoseItem` across this screen / `MyMedsCard` / `LogMedicationsView`),
`DIV-013` (avatar size vs. `MedDetailView`).
