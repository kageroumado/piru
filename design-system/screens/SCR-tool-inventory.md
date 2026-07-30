---
id: SCR-tool-inventory
type: screen
description: Inventory list + item detail/edit/form — the largest multi-screen Tools flow (8 files), with a real cross-tab-reused shared-bar component.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: contains, target: CMP-substance-search-field}
  - {rel: diverges_from, target: SCR-substance-detail}
metadata:
  screenshot: screenshots/SCR-tool-inventory.png
---

# Inventory (`InventoryListView` + 7 files)

**Route**: `PushRoute.tool(.inventory)` (list); sheets `SheetRoute.inventoryItemForm(id:prefillSubstance:prefillSalt:)`/
`.inventoryItemEdit(id:)` → `InventoryItemFormHost`/`InventoryItemEditHost`
(`SheetRouteView.swift:101-105`, neither supports push navigation). **Deep link**: `piru://tool/inventory`
(list only). **Files**: `Piru/Views/Tools/Inventory/` — `InventoryListView`, `InventoryListModel`,
`InventoryItemDetailView`, `InventoryItemEditView`, `InventoryItemForm`, `InventoryMenus`,
`InventorySupport`, `InventoryClassOrderView`.

## States
Empty-inventory vs. no-search-matches (distinct `ContentUnavailableView`s, `InventoryListView.swift:126-152`),
populated grouped/flat list, collapsed sections, manual-reorder mode, `StockStatus`
(`.ok`/`.low`/`.out`, orange/red), item-detail has/no-baseline + has/no-runout-estimate, form
validation via disabled-confirm only, edit-view "item vanished" → silent dismiss.

## Shared reuse (confirmed real, not duplicated)
`InventoryStepperRow` (also `HealthSettingsView`/`OnboardingHealthStep`), `SubstanceSearchField`
(also Journal/Insights), `InventorySupplyBar`/`StockAmountText` (also `InventoryStockSection.swift`
in Substance Detail, `SubstanceCardView.swift`).

## Known divergences
`DIV-031` (`InventorySupplyBar` color-philosophy split between Inventory's own screens and the two
external reuse sites). Filter-chip capsule (`InventoryMenus.swift:225-227`) vs. the visually-rhyming
Track/Restock pill in `InventoryStockSection.swift:99-101` — near-identical, not identical, tokens.
`SubstanceDot` (`InventorySupport.swift:314-324`) appears dead (`DIV-026`). No "not medical advice"
disclaimer anywhere — intentional, since this is a logistics tool not a dosing-advice screen.
