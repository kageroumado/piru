---
id: SCR-color-picker
type: screen
description: Substance color picker — a well-designed multi-step queue sheet (color one substance, auto-advance to the next).
edges:
  - {rel: variant_of, target: SCR-substance-detail}
metadata:
  screenshot: null
---

# Color Picker (`SubstanceColorPickerView` / `ColorPickerHost`)

**Route**: `SheetRoute.colorPicker(substance:remaining:dismissAllOnComplete:)` — not deep-linkable
(app-internal). **Files**: `Piru/Views/Library/Custom/SubstanceColorPickerView.swift:4-353` (the
picker), `Piru/Navigation/SheetRouteView.swift:190-237` (`ColorPickerHost`, owns save+advance-queue).

## Pattern (positive example)
`ColorPickerHost` persists the chosen color, refreshes `ActiveSessionManager`'s in-flight color
map, then either re-presents the next queued substance with `replacingTop: true` or dismisses
(`dismissAll()` vs. `dismiss()` per `dismissAllOnComplete`) — a genuinely well-designed
multi-step-queue sheet, not shared with (or needed by) anything else in the app.

## Components
Preview swatch, 8-col preset `LazyVGrid`, user-colors `LazyVGrid`, custom-shade creator (live
`ColorPicker` + hex `TextField` + validation). "Skip" falls back to the first available preset hex.
