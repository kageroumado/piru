---
id: SCR-search-home
type: screen
description: A real 5th tab (role .search), not a modal — 3-phase landing/focusedEmpty/typing surface reusing Library's family-card visual language.
edges:
  - {rel: diverges_from, target: SCR-library-home}
  - {rel: diverges_from, target: SCR-advanced-search}
metadata:
  screenshot: screenshots/SCR-search-home.png
---

# Search (`SearchLandingView` / `ContentView`'s `SearchTabScope`/`SearchSurface`)

**Route**: `AppTab.search`, a genuine 5th tab — `Tab("Search", ..., value: .search, role:.search)`
(`ContentView.swift:237-245`), the iOS 26 auto-relocating search tab. **Deep link**: `piru://search`
(bare tab switch only — no scope/query param). **Files**: `ContentView.swift:364-535`,
`Piru/Views/Search/SearchLandingView.swift` (339 ln).

## 3 phases (driven by `\.isSearching`, split across a parent/child view — a documented SwiftUI
quirk: reading `isSearching` in the same body that declares `.searchable` always sees `false`)
- **landing**: `SearchLandingView` — Recent, Recent Doses (limit 3), `HelpCard`, `ClassBrowseGroup`.
- **focusedEmpty**: same recent groups without the browse grid (limit 8) — **self-hide with no
  fallback message** if both are empty (a blank scroll view for a brand-new user, `DIV-004`).
- **typing**: native segmented `ScopePickerBar` (Journal/Library) switches between
  `SubstanceLibraryView(searchText:)` and `EntryListView(searchText:)` — reusing each tab's own
  empty/no-results states rather than inventing a third.

## Components
`ClassBrowseGroup` reuses Library's `FamilyGradientCard` visual language verbatim (per its own doc
comment) — a deliberate, documented cross-tab reuse, not a divergence.

## Known non-relationship
`AdvancedSearchView` (`SCR-advanced-search`) shares the `Views/Search/` folder but is
architecturally unrelated and dead (`DIV-026`) — don't conflate the two when navigating this graph.
