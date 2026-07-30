---
id: SCR-help
type: screen
description: Help/FAQ content — mixes raw system secondary color with Theme.secondaryLabel in the same file.
edges:
  - {rel: diverges_from, target: SCR-settings}
metadata:
  screenshot: screenshots/SCR-help.png
---

# Help (`HelpView`)

**Route**: `SheetRoute.help`. **Deep link**: `piru://help`. **File**: `Piru/Views/Tools/HelpView.swift` (712 ln).

## Known divergences
Hand-rolls its own Close button like Settings (`:85-90`, `DIV-016`). Mixes raw `.secondary`/
`.tertiary` with occasional `Theme.secondaryLabel` (`:582`) — Settings/Onboarding standardize
entirely on `Theme.secondaryLabel`, so this file is a genuine color-token inconsistency, though
its List/`CardBackground` structure otherwise matches Settings. `groundingTip`'s
"row=icon+title+detail" anatomy is hand-duplicated rather than shared (same pattern noted on
`SCR-settings`).
