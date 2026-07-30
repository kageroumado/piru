---
id: SCR-tool-calculator
type: screen
description: Half-Life Calculator — filed under Views/Insights/ despite being a Tools-tab tool; the one hand-rolled Canvas decay chart outside In Your System.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: diverges_from, target: SCR-insight-insystem}
metadata:
  screenshot: screenshots/SCR-tool-calculator.png
---

# Half-Life Calculator (`HalfLifeCalculatorView`)

**Route**: `PushRoute.tool(.calculator)`. **Deep link**: `piru://tool/calculator`. **File**:
`Piru/Views/Insights/HalfLifeCalculatorView.swift` (417 ln — misfiled, `DIV-025`). Bidirectionally
cross-linked with `SCR-insight-insystem` via `GlanceCard`.

## States
No-data-with-escape-hatch ("Use Custom Half-Life" CTA, `:375-383`); otherwise gated behind
`if let halfLife, dose > 0` — a distinct "not-yet-configured" state, neither empty nor populated.

## Charting divergence
`decayChart` is hand-rolled `Canvas`/`Path` (`:175-260`) — not Swift Charts, unlike Usage/
Tolerance/Insights-hub. See `DIV-019`.

## Tokens
Root `VStack(spacing:20)` (`:43`) vs. 16 elsewhere; bespoke `RoundedRectangle(cornerRadius:8)`
dose-input background (`:139`); unit picker built as a `Menu`-of-buttons rather than a `Picker`;
the only `TextField` in this audit using native `.roundedBorder` style instead of
`Theme.inputBackground` chrome (`:156`). `disclaimerSection` (`:392-405`) is structurally
identical to Interactions Timeline's "Estimate Only" card (`DIV-022`).
