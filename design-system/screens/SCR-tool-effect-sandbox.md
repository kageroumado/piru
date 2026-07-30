---
id: SCR-tool-effect-sandbox
type: screen
description: Effect Estimator sandbox — compares substances/plans; the most component-reuse-disciplined screen in the whole audit.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: variant_of, target: SCR-effect-estimates}
  - {rel: contains, target: CMP-glance-card}
metadata:
  screenshot: screenshots/SCR-tool-effect-sandbox.png
---

# Effect Estimator (`EffectSandboxView`)

**Route**: `PushRoute.tool(.effectSandbox)`. **Deep link**: `piru://tool/effectSandbox`. **File**:
`Piru/Views/Tools/EffectSandboxView.swift` (1342 ln — long, but reads as a single coherent
comparison tool, not an un-decomposed superview).

## States
Empty (`ContentUnavailableView`), populated dose list, comparison mode (2 plans), per-plan
"unmodelable" warning, row substance-not-picked vs. picked, substance-picker two-tier
Calibrated-vs-Modeled sections.

## Pattern (positive example)
Reuses `MechanisticChartView`/`MechanisticComparisonSeries`/`EffectLens` (shared with Journal's
`SCR-effect-estimates`), `EffectModelExplainerView`, `PharmacologyGlossarySheet`, `ConfidenceBadge`,
`ProvenanceBadge` — **zero invented card chrome**, everything routes through `CardBackground()`
same as 39 other files repo-wide. No `RoundedRectangle`/`.cornerRadius` literal anywhere in the
file — unique among the 11 tools. Zero `.animation()` calls.

## Known divergence
Disclaimer ("A rough guide, not medical advice") appears twice as a plain `Section` footer with no
custom styling — a third, weaker tier vs. the "Estimate Only" card pattern elsewhere (`DIV-022`).
Duplicated pinch-zoom gesture code (independently implemented here and in `ActivityExpandedChart.swift`,
see `SCR-insight-usage`).
