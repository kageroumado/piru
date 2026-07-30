---
id: SCR-substance-data-page
type: screen
description: Deep-data page for one substance section (chemistry/pharmacology/sources) — reuses SubstanceDetailView's section views verbatim, forced to Pharma-Nerd disclosure.
edges:
  - {rel: variant_of, target: SCR-substance-detail}
metadata:
  screenshot: screenshots/SCR-substance-data-pharmacology.png
  screenshot_chemistry: screenshots/SCR-substance-data-chemistry.png
  screenshot_sources: screenshots/SCR-substance-data-sources.png
---

# Substance deep-data page (`SubstanceDataPageView`)

**Route**: `PushRoute.substanceData(name:section:)`, `section ∈ {chemistry, pharmacology, sources}`.
**Deep link**: `piru://substance/<name>/data/<section>`. **File**:
`Piru/Views/Library/SubstanceDetail/SubstanceDataPageView.swift:14-70`.

Reuses `ChemistrySection`/`SourcesSection`/`PharmacologySections` **verbatim** from the parent
detail screen, forced to `.pharmaNerd` policy regardless of the user's actual tier setting (`:18-19`
— "must stay valid if the tier changes"). Not-found state uses identical wording to the substance
push. `ChemistrySection` is passed `initiallyExpanded: true` here (`:53`) vs. `false` inline on the
parent detail screen (`SubstanceIdentitySections.swift:137-141`) — deliberate, to avoid a
"double-collapse void."
