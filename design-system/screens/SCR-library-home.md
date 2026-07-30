---
id: SCR-library-home
type: screen
description: Library tab root — gradient "specimen" family cards (Favorites, Common, taxonomy classes, umbrella expand-in-place).
edges:
  - {rel: navigates_to, target: SCR-library-category-list}
  - {rel: diverges_from, target: SCR-substance-detail}
metadata:
  screenshot: screenshots/SCR-library-home.png
---

# Library home (`SubstanceLibraryView` / `LibraryBrowseView`)

**Route**: tab root. **Deep link**: `piru://library`. **Files**:
`Piru/Views/Library/SubstanceLibraryView.swift`, `LibraryBrowseView.swift`, `LibraryTaxonomy.swift`.

## States
Loading: full-width `ProgressView` (`LibraryBrowseView.swift:42-47`) → populated `LazyVStack` of
family cards, gated by `@State loaded` in `.task` so the screen never flashes half-built.

## Components
`LibraryFamilyCard` (private, single-card vs. umbrella-expand-in-place, `:132-292`) built on
`FamilyGradientCard<Hero,Content>` (`:103-125` — diagonal `LinearGradient` + `MoleculeView` hero
bleeding off top-trailing, shadow `color.opacity(0.3),radius:10,x:0,y:5`). `LibrarySubclassRow`
(`:298-343`), `LibraryFavoritesCard` (`:350-408`, raspberry `Color(red:0.85,green:0.26,blue:0.47)`).
12 `LibraryFamily` taxonomy entries (`LibraryTaxonomy.swift:152-307`): Common, Stimulants,
Empathogens, Hallucinogens (umbrella), Cannabinoids, Opioids (risk-badge variant), Sedatives &
Depressants (umbrella), Peptides, Mind & Cognition (umbrella), Pharmaceuticals (umbrella, 9
subclasses), Supplements, Research Chemicals, Other.

## Tokens
Title `.system(size:20,weight:.bold)`; card `cornerRadius:22`; umbrella sub-row `cornerRadius:15`.

## Known divergence
`DIV-004` (favorites-empty self-omits with no placeholder) and card-chrome mismatch vs.
`SCR-substance-detail`'s flat `CardBackground()` list-row chrome — two unrelated "card"
languages within one tab.
