---
id: SCR-substance-share
type: screen
description: Share-card generator (Minimal/Standard/Rich) — dark-forced, re-implements the dose-tier visual with a different grammar than the live screen.
edges:
  - {rel: variant_of, target: SCR-substance-detail}
  - {rel: diverges_from, target: SCR-substance-detail}
metadata:
  screenshot: null
---

# Share Substance (`SubstanceShareSheet` / `SubstanceShareCard`)

**Presentation**: local `.sheet(isPresented:)` from `SubstanceDetailView.swift:215-217` — not a
`SheetRoute`. **Files**: `Piru/Views/Components/SubstanceShareSheet.swift` (segmented
Minimal/Standard/Rich picker, live `ImageRenderer` re-render), `Library/SubstanceDetail/SubstanceShareCard.swift:35-707`.

Dark-forced (`environment(\.colorScheme, .dark)`, `:127`) category-tinted "specimen plate." Own
monochrome duplicate of the duration curve (`MonochromeDoseGraph`, `:820-883`, shares math with
`DurationCurveView.swift:111-150`'s `EffectCurveShape`) but a **separately re-implemented**
dose-tier mark system (`DoseTierMark`, `:716-736`) using escalating SF Symbols instead of the live
screen's growing colored discs — see `DIV-020`.
