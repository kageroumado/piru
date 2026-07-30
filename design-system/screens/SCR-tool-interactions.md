---
id: SCR-tool-interactions
type: screen
description: Substance-pair interaction checker + a separate PK-overlap timeline drill-down.
edges:
  - {rel: variant_of, target: SCR-tools-home}
metadata:
  screenshot: screenshots/SCR-tool-interactions.png
---

# Interactions (`InteractionCheckerView` + `InteractionTimelineView`)

**Route**: `PushRoute.tool(.interactions)`. **Deep link**: `piru://tool/interactions`. **Files**:
`Piru/Views/Tools/Interactions/InteractionCheckerView.swift` (411 ln), `InteractionTimelineView.swift`
(790 ln, via `NavigationLink` at `:177-182`).

## States
No-selection, search dropdown, selected-capsules, <2-selected→nothing, no-interactions-found
(green checkmark), interactions-found list, Combination Products/Metabolic Effects conditional
sections. Timeline: missing-PK-data, populated chart, combined-depression card, overlap/no-overlap.

## Tokens
`themeCard(cornerRadius:16)` on the search dropdown (`:296`) vs. default 22 elsewhere in this
file — a 3rd radius value alongside the Timeline's `RoundedRectangle(cornerRadius:2/1)` legend
swatches. Hardcoded `.green` for success (`:146`, Timeline `:527` — `DIV-002`); hardcoded
`colorA=.blue`/`colorB=.orange` chart colors (`:325-326`). Timeline's `disclaimerCard` (`:745-758`)
is the "Estimate Only" pattern copy-pasted from Calculator (`DIV-022`).
