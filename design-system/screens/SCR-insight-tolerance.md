---
id: SCR-insight-tolerance
type: screen
description: Predicted per-mechanism tolerance/recovery — filed under Views/Tools/Tolerance/ despite being an Insights route; the most disciplined color system in the app.
edges:
  - {rel: variant_of, target: SCR-insights-home}
  - {rel: navigates_to, target: SCR-tool-tolerance-info}
metadata:
  screenshot: screenshots/SCR-insight-tolerance.png
---

# Tolerance (`ToleranceToolView` + 6 supporting files)

**Route**: `PushRoute.insight(.tolerance)`. **Deep link**: `piru://insight/tolerance` (plus a
back-compat alias `piru://tool/tolerance`, `DeepLink.swift:144-146`, since this moved tabs).
**File**: `Piru/Views/Tools/Tolerance/ToleranceToolView.swift` (252 ln — misfiled, `DIV-025`), plus
`ToleranceCard`, `ToleranceCombinedRecovery`, `ToleranceOptionsMenu`, `TolerancePerSubstanceSection`,
`ToleranceRow`, `ToleranceSections`.

## States
True empty (`ToleranceEmptyState`), a distinct "can't predict yet" section for logged-but-unscoreable
substances, and a per-substance-mode transient loading state (`isReplayRunning`, `ProgressView`)
before falling back to the same empty copy.

## Pattern (positive example)
Family colors defined **once** in `ReceptorClasses.ReceptorClass.familyColor` (`:237-251`) and
reused consistently across the combined chart, per-mechanism cards, and per-substance rows — the
single most disciplined color system found in the whole audit (contrast Usage/Insights-hub's
ad-hoc per-chart hue picks). Bands within one bar vary *opacity* of the same hue (0.5/0.82/1.0)
rather than switching hues — an intentional "one hue = timescale" convention.

## Components
`ToleranceCombinedRecoverySection` (always-on hero, multi-series `LineMark`), mode picker via
`ToleranceOptionsMenu` (hand-drawn `Canvas` phone-thumbnail art for the mode picker — one of the
`DIV-019` Canvas-vs-Charts instances). Density scales with `UserProfile` disclosure tier.
