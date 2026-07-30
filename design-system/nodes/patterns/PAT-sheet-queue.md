---
id: PAT-sheet-queue
type: pattern
description: A sheet route that carries a "remaining" queue and re-presents itself with replacingTop when the user finishes one item, dismissing only when the queue empties.
edges:
  - {rel: used_by, target: SCR-color-picker}
metadata: {}
---

# Multi-step sheet queue (`replacingTop`)

**Where**: `SheetRoute.colorPicker(substance:remaining:dismissAllOnComplete:)`. `ColorPickerHost`
(`SheetRouteView.swift:190-237`) persists the pick, then either re-presents the next queued
substance via `navigator.present(.colorPicker(...), replacingTop: true)` or dismisses
(`dismissAll()`/`dismiss()` depending on `dismissAllOnComplete`). Replaces the older chained
`onDismiss` callback loop that used to live in `LogDailyDoseView`/`QuickLogView`.

**Reuse candidate**: this is the only place in the app using `replacingTop` for a queue today.
Any future "do N of these one at a time" flow (e.g. bulk-assign categories) should reach for this
same route-carries-the-queue shape rather than inventing a new completion-callback pattern.
