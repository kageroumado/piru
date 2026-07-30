---
id: SCR-log-medications
type: screen
description: Batch-log sheet for a med category — exclude-before-logging metaphor, the third of three DailyDoseItem logging patterns.
edges:
  - {rel: diverges_from, target: SCR-my-meds-hub}
metadata:
  screenshot: null
---

# Log Medications (`LogMedicationsView`, in `LogDailyDoseView.swift`)

**Route**: `SheetRoute.dailyDoseLog(category:)`. **Deep link**: `piru://meds/<category>`.
**File**: `Piru/Views/Journal/DailyDose/LogDailyDoseView.swift` (247 ln).

## States / interactions
Per-item `Toggle` (`:51-59`) — the **exclude-before-logging** metaphor (third distinct logging
pattern in the Meds cluster, see `DIV-012`). "Log N Items" → `attemptLog()` → interaction check →
`logSelected()` or `InteractionWarningSheet`; on success calls **`navigator.dismissAll()`**
(`:184`) — the only screen in the whole Journal territory that clears the entire sheet/nav chain
on success (`DIV-011`).

## Known divergences
`DIV-012`, `DIV-011`.
