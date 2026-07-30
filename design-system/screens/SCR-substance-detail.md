---
id: SCR-substance-detail
type: screen
description: The core Library screen — shell-first progressive reveal, ~11 composed sections gated by disclosure tier.
edges:
  - {rel: contains, target: CMP-capsule-chip}
  - {rel: navigates_to, target: SCR-substance-data-page}
  - {rel: presents, target: SCR-color-picker}
  - {rel: presents, target: SCR-substance-share}
  - {rel: diverges_from, target: SCR-library-home}
metadata:
  screenshot: screenshots/SCR-substance-detail-caffeine.png
  screenshot_dark: screenshots/SCR-substance-detail-caffeine-dark.png
---

# Substance detail (`SubstanceDetailView`)

**Route**: `PushRoute.substance(name:)`. **Deep link**: `piru://substance/<name>`. **Files**:
`Piru/Views/Library/SubstanceDetail/` (thin 307-ln coordinator `SubstanceDetailView.swift` →
`SubstanceDetailLayout.swift` (401 ln) → per-section files + `@Observable SubstanceDetailModel`).
This folder is the best example of the repo's decomposition rule working — no file individually
exceeds ~900 lines (`SubstanceShareCard.swift` at 902 is a stateless render target, not a
"superview").

## States
Shell-first: pushed with `SubstanceLibrary.shell(name)` (`AppDestinations.swift:84-85`), then
`.task { upgradeToFullRecord() }` swaps in the full record. Not-found: `ContentUnavailableView`
at the **push** level (`AppDestinations.swift:88-94`), not inside this view. Per-section async
load gated by `DisclosurePolicy` (Casual/Curious/Pharma Nerd tier).

## Composed sections (in spine order)
Header (40pt hero title, category chip, formula, alias chips, `LogNowButton`
`.buttonStyle(.glassProminent)`) → Overview (collapse at 320 chars/5 lines) → Your History
(gated non-empty) → Dose & Duration (route chips, `DoseTierStrip`, `DurationCurveView`, phase
trio — inline-only, hidden on non-recreational spine) → Effects/intensity dial (`DoseIntensityCard`'s
draggable arc gauge, falls back to flat list without spectrum coverage) → Pharmacology cluster
(Mechanism+Monoamine unified, Receptor Literature, "Also Active" metabolites, PK/Metabolism,
interaction banners) → Medical Info (always rendered, self-hides per-substance) → Common
misconceptions (`MythBustSection`) → peptide protocol (self-hides for non-peptides) → Inventory
(shared Track/Restock pill) → Personal notes (inline, not its own file) → Reference depth
(Info/Chemistry/Sources — inline at Pharma-Nerd tier, collapse to `ShowAllRow`s at lower tiers).

## Known divergences
`DIV-021` ("Show All" implemented 3 ways on this one screen), `DIV-029` (mixed
foldable/non-foldable section headers), `DIV-020` (dose-tier iconography vs. the share card),
`DIV-026` (`StatusBanner`/`JokeBanner` fully built, zero call sites).
