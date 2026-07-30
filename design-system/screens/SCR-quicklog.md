---
id: SCR-quicklog
type: screen
description: App-wide quick-log flow — fullScreenCover hosting a native detented sheet (the dock), with its own hand-built UISheetPresentationController detent state machine.
edges:
  - {rel: contains, target: CMP-salt-isomer-picker}
  - {rel: diverges_from, target: CMP-theme-card}
  - {rel: presents, target: SCR-color-picker}
metadata:
  screenshot: screenshots/SCR-quicklog.png
  screenshot_dark: screenshots/SCR-quicklog-dark.png
---

# QuickLog (`QuickLogSheet` / `QuickLogDock`)

**Route**: `SheetRoute.quickLog(routine:prefillSubstance:)`. **Deep link**:
`piru://quicklog[?routine=][?substance=]`. **Files**: `Piru/Views/QuickLog/` (17 files, 6606 ln).

## Presentation stack
`fullScreenCover` (`QuickLogView`) hosting a **second, nested, native detented `.sheet`**
(`DockSheetHost`) for the dock — fullScreenCover → sheet, two layers. `commitTray()`
(`QuickLogView.swift:362-483`) fires success haptic + `navigator.dismissAll()` immediately
(`:381-382`), deferring the SwiftData insert to `DispatchQueue.main.async` (`:389`) so the dismiss
animation isn't blocked.

## States
`isBare` (peek vs. grown, `QuickLogDock.swift:125-127`), `searchActive`/`searchFocused`
(`:397-416`), `awaitingBareCollapse` (`:144-151`), content-loading gate (`QuickLogSupport.swift:210`),
empty state `ContentUnavailableView` (`:246-252`), tray `isCommittable` (`DoseTray.swift:386-388`).

## The dock-shear invariant
`QuickLogDock.swift:324-331` documents the exact 14.2pt(bare)/15.4pt(medium)/16.0pt(large)
search-bar-below-platter measurements, established by fixed `.padding(.horizontal,16).padding(.top,16)`
(`:263-264`). Detents are driven by a hand-built `UISheetPresentationController.animateChanges`
call (`:588-663`) rather than SwiftUI's own detent binding, documented as intentional (SwiftUI's
own binding animates by displacing bottom-pinned content).

## Components
`TrayStagedListCard`/`TrayRow`/`StagedDoseEditor` (1063 ln) — row↔editor morph via
`matchedGeometryEffect`; swipe-to-delete via `TraySwipeRow` (180pt threshold). Reuses shared
`SaltPicker`/`IsomerPicker` (`StagedDoseEditor.swift:138-149`) but hand-rolls its route menu, note
pill, drink-type chip, grapefruit toggle instead of a shared `PickerStyle`.

## Known divergences
`DIV-014` (internal card chrome bypasses `Theme.themeCard()` — deliberate, rides the native
sheet's own platter, but means it won't pick up a future `Theme.cardBackground` retheme),
`DIV-027` (`StagedDoseEditor` 21 state properties, `QuickLogDock` 12 — the two worst/third-worst
superview violations in the app).

## Positive compliance example
`QuickLogEditSheet.swift:234-236` composes a `String` interpolation specifically to avoid
`Text + Text`, with an in-code comment citing the exact house rule — cite this as the canonical
pattern when documenting the ban elsewhere.
