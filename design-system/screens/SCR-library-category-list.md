---
id: SCR-library-category-list
type: screen
description: Category/tag/favorites browse list — serves 3 semantically different lists through one screen, no empty state.
edges:
  - {rel: variant_of, target: SCR-library-home}
  - {rel: diverges_from, target: SCR-search-home}
metadata:
  screenshot: null
---

# Category / Tag / Favorites browse (`SubstanceCategoryListView`)

**Route**: `PushRoute.libraryCategory(SubstanceCategory)` / `.libraryTag(String)` / `.libraryFavorites`.
**File**: `Piru/Views/Library/SubstanceLibraryView.swift:304-429`.

## States
Resolved off-main in `.task(id: listSignature)` → populated `List`. **No dedicated empty state**
— an empty category renders an empty `List`, unlike Search's explicit "No Results" (`DIV-004`).
Favorites disables the sort menu (`isBrowse` false when both category/tag are nil, `:319-321,413-426`)
since favorites keep the user's own order; category/tag lists sort by popularity/name.

## Components
`SubstanceRowView` (`:433-499`) — category-color dot, title/subtitle, trailing "Limited data"
capsule for stub substances or a category-color capsule chip. Swipe-favorite/unfavorite
(`.swipeActions`, `:392-400`).

## Known divergence
`DIV-004` (no empty state, unlike Search's sibling lists).
