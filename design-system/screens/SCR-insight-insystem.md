---
id: SCR-insight-insystem
type: screen
description: "What's active in the body right now" — shares SubstanceEliminationCurve with Session detail; split out of the Half-Life Calculator for single responsibility.
edges:
  - {rel: variant_of, target: SCR-insights-home}
  - {rel: contains, target: CMP-elimination-curve}
  - {rel: navigates_to, target: SCR-tool-calculator}
metadata:
  screenshot: screenshots/SCR-insight-insystem.png
---

# In Your System (`InYourSystemView`)

**Route**: `PushRoute.insight(.inSystem)`. **Deep link**: `piru://insight/inSystem`. **File**:
`Piru/Views/Insights/InYourSystemView.swift` (203 ln).

## States
Empty: custom icon+text block ("Nothing active right now," `:53-70`) — **not** a
`ContentUnavailableView`, a third distinct empty-state chrome within this one tab (`DIV-004`).
Deliberate 200ms delay before computing (`.task`, `:37`) to avoid a flash on tab entry.

## Components
`activeSubstanceCard` (expand/collapse, `.snappy(duration:0.3)`), decay progress `Capsule` bar
(custom, not Charts), up to `maxDosesShown=10` per-dose rows + "+N earlier" overflow,
`SubstanceEliminationCurve` (shared with Session detail's "In Your Body" section, per its own
header comment — a good extraction example). Cross-link footer → `GlanceCard` to
`SCR-tool-calculator`. `TimelineView(.periodic(from:.now, by:60))` keeps "time ago"/remaining %
live.

## Accessibility
`SubstanceEliminationCurve` correctly uses `.accessibilityElement(children:.ignore)` + label +
value despite being a raw `Canvas` (no children to collapse otherwise).
