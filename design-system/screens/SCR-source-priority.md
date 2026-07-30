---
id: SCR-source-priority
type: screen
description: Per-field source-priority reordering screen — physically filed under Settings/, not Library/, despite being a Library-data concern.
edges:
  - {rel: diverges_from, target: SCR-substance-detail}
metadata:
  screenshot: null
---

# Source Priority (`SourcePriorityView`)

**Route**: `SheetRoute.sourcePriority` — not deep-linkable. **File**:
`Piru/Views/Settings/SourcePriorityView.swift` (misfiled relative to Library, `DIV-025`). Reached
from Substance Detail's source-attribution explainer ("Manage source priority" link,
`SubstanceDetailSupport.swift:251-253`) and from Settings.

## Known divergence
`DIV-015` — the "Reset" toolbar button (`:33-37`) resets to defaults with **no confirmation**,
unlike `DataStorageView`'s destructive actions which all confirm.
