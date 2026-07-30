---
id: SCR-advanced-search
type: screen
description: Dead/unreachable pharma-nerd receptor-Ki-filter search screen — SheetRoute exists but has no live entry point anywhere in the codebase.
edges:
  - {rel: diverges_from, target: SCR-search-home}
metadata:
  screenshot: null
  status: unreachable
---

# Advanced Search (`AdvancedSearchView`) — confirmed dead

**Declared route**: `SheetRoute.advancedSearch` (`Routes.swift:150`), dispatched at
`SheetRouteView.swift:81-85`, explicitly excluded from deep-linking (`DeepLink.swift:317`). **File**:
`Piru/Views/Search/AdvancedSearchView.swift` (171 ln), doc-comment claims to be "Hidden behind a
tier check in the entry point" — **repo-wide grep found no such entry point; `navigator.present(.advancedSearch)`
does not occur anywhere.** Queries `SubstanceStore.shared.bindings(...)` directly — architecturally
unrelated to the real Search tab despite sharing its folder.

## Recommendation
See `divergences.md#DIV-026`. Either wire a real entry point (a Pharma-Nerd-tier row in Advanced
tools) or delete the screen and its route case.
