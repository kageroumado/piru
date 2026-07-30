---
id: SCR-tool-tolerance-info
type: screen
description: "How Tolerance Works" explainer — the most internally disciplined static-content screen in the Tools tab.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: duplicates, target: SCR-tool-ceiling}
  - {rel: navigates_to, target: SCR-insight-tolerance}
metadata:
  screenshot: screenshots/SCR-tool-tolerance-info.png
---

# How Tolerance Works (`ToleranceExplainerView`)

**Route**: `PushRoute.tool(.toleranceInfo)`. **Deep link**: `piru://tool/toleranceInfo`. **File**:
`Piru/Views/Tools/Tolerance/ToleranceExplainerView.swift` (230 ln). **Distinct from
`Insight.tolerance`** (`SCR-insight-tolerance`) — linked from it via "How tolerance works," not the
same screen. Zero interactive controls (confirmed via grep — no Picker/Slider/Button/`.sheet`).

## Pattern (positive example)
Exactly 3 font tokens used throughout; one consistent `.padding(.vertical,4)` everywhere
(`:142,154,228`); no bespoke chrome at all — the most disciplined static screen audited. Uses
"estimates, not a measurement of you" framing instead of a literal "not medical advice" phrase
(`DIV-022`).
