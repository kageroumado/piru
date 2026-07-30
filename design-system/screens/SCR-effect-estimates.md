---
id: SCR-effect-estimates
type: screen
description: Multi-lens PK/PD chart pushed from a session's Effect Estimates card; shares MechanisticChartView with the Tools-tab Effect Estimator sandbox.
edges:
  - {rel: variant_of, target: SCR-tool-effect-sandbox}
  - {rel: contains, target: CMP-accessibility-primitives}
metadata:
  screenshot: null
---

# Effect Estimates (`EffectEstimatesView`, Journal/Mechanistic)

**Route**: `NavigationLink` from `SessionDetailView.swift:391`'s `EffectEstimatesCard` (not a
top-level `PushRoute`/`SheetRoute` — reached only from within Session detail).
**File**: `Piru/Views/Journal/Mechanistic/EffectEstimatesView.swift` (547 ln).

## States
`isBusySession` (doses.count > 5) shows an inline warning `Section`, not a separate screen state
(`:192-214`). Per-lens `MechanisticChartView` fixed `height: 200`; `MechanisticVitalsCards` only
for the `.strain` lens.

## Components
`MechanisticChartView.swift` (567 ln, shared with `SCR-tool-effect-sandbox`) — the real PK/PD
`Canvas` chart, 6 `@State` for pan/zoom (at the "~6 is a smell" line but cohesive). **The one
chart in the whole Journal tab with real VoiceOver narration**: synthesized sentences like "peaked
Euphoric about 45 min after the first dose" (`:146-161`) — directly resolves the historical
"silent charts" defect for this chart. `NavigationLink` to `EffectModelExplainerView` (pure
schematic) and `DopamineErrorDiagram`.

## Known divergence
`DIV-008` (this chart narrates itself; its Journal-tab sibling `ActiveNowWindowGraph` opts out
via `.accessibilityHidden(true)`).
