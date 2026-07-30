---
id: SCR-tools-home
type: screen
description: Tools tab root — 3 different presentation tiers for the same 11 tools (rich glance cards, plain rows, a foldable education row).
edges:
  - {rel: contains, target: CMP-glance-card}
  - {rel: contains, target: CMP-app-chrome}
  - {rel: navigates_to, target: SCR-tool-interactions}
metadata:
  screenshot: screenshots/SCR-tools-home.png
---

# Tools home (`ToolsView`)

**Route**: tab root. **Deep link**: `piru://tools`. **File**: `Piru/Views/Tools/ToolsView.swift` (108 ln).
`enum Tool` (11 cases, `:6-72`) each with `name`/`subtitle`/`icon`.

## Layout — 3 presentation tiers for one list of 11 tools
1. `EducationCard()` (foldable, hides Ceiling/ToleranceInfo/Recovery behind a tap, its own
   `EducationRow` chrome — tinted icon tile + `Color.primary.opacity(0.05)` pill,
   `RoundedRectangle(cornerRadius:12)` — matching neither `GlanceCard` nor the summary cards).
2. `InteractionsSummaryCard`/`InventorySummaryCard` — rich glance cards with live data previews.
3. Plain `GlanceCard` rows for the remaining 6 tools (effectSandbox, calculator, volumetric,
   benzoEquivalence, opioidEquivalence, pharma) — subtitle-only, no live preview.

## Known divergence
Three chrome tiers for a flat list of equally-important tools is itself worth a design decision
— not filed as a numbered DIV since it may be intentional information-hierarchy, but flagged for
review alongside `DIV-025` (two of the 11 tools' views are filed outside `Views/Tools/`).
