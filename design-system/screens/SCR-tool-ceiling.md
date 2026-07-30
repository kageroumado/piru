---
id: SCR-tool-ceiling
type: screen
description: Ceiling Effect explainer — static curated content, no interactive controls.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: duplicates, target: SCR-tool-tolerance-info}
metadata:
  screenshot: screenshots/SCR-tool-ceiling.png
---

# Ceiling Effect (`CeilingEffectToolView`)

**Route**: `PushRoute.tool(.ceiling)`. **Deep link**: `piru://tool/ceiling`. **File**:
`Piru/Views/Tools/Tolerance/CeilingEffectToolView.swift` (395 ln). No loading/empty/error state
(fully static data); identical `List`+`.listRowBackground(CardBackground())`+`.appNavigationBar`
boilerplate to `SCR-tool-tolerance-info`.

## Internal divergence
Two "info box" idioms within this one screen: plain list-row-background sections vs. one bespoke
`RoundedRectangle(cornerRadius:10)` tint box for the qualitative marker (`:358-359`); inconsistent
inner spacing (8/12/12) and padding (vertical 4/6/top-2) across its 3 sections. Uses softer
epistemic-humility framing ("model predictions... not absolute," `:67`) instead of a "not medical
advice" disclaimer (`DIV-022`).
