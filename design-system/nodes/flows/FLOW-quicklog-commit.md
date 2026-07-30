---
id: FLOW-quicklog-commit
type: flow
description: Stage one or more doses in the QuickLog tray, then commit — dismiss fires before the SwiftData write to keep the animation unblocked.
edges:
  - {rel: part_of, target: SCR-quicklog}
metadata: {}
---

# QuickLog commit flow

1. User opens `SheetRoute.quickLog` (fullScreenCover → nested detented sheet, the dock).
2. Stages one or more doses into `DoseTrayModel` via `StagedDoseEditor`/search results.
3. Taps commit → `QuickLogView.commitTray()` (`:362-483`): fires the success haptic and calls
   `navigator.dismissAll()` **immediately** (`:381-382`), then defers the actual SwiftData
   `modelContext.insert` calls to `DispatchQueue.main.async` (`:389`) so the dismiss animation
   isn't blocked by the write.
4. If any staged dose triggers a color-assignment need, this can chain into `PAT-sheet-queue`
   (the color-picker queue) before finally landing back at the Journal root.

**Why it matters for a future agent**: don't "fix" the dismiss-before-write ordering — it's
deliberate (comment at `QuickLogView.swift:389`), not a bug to eagerly reorder for correctness.
