---
id: SCR-custom-substances-list
type: screen
description: List of user-created custom substances — its SheetRoute is dead code; the real navigation is a bare NavigationLink from Settings.
edges:
  - {rel: duplicates, target: SCR-custom-substance-form}
  - {rel: diverges_from, target: SCR-settings}
metadata:
  screenshot: null
---

# Custom Substances list (`CustomSubstancesListView`)

**Declared route**: `SheetRoute.customSubstancesList` — dispatches to `UnmigratedRoutePlaceholder`
(`SheetRouteView.swift:107-113`), **never actually triggered**. **Real navigation**: a bare
`NavigationLink` push from `SettingsView.swift:32-34`. **File**:
`Piru/Views/Library/Custom/CustomSubstancesListView.swift:3-78`.

## States
Empty: `ContentUnavailableView("No Substances Yet", "flask", ...)` (`:12-17`). Populated:
icon+name+category/route/unit row, swipe-delete (`.onDelete`). Add via toolbar `+` → local
`.sheet`; edit via row tap → local `.sheet(item:)` — **neither goes through the navigator**.

## Known divergence
`DIV-010` (declared `SheetRoute` case is dead; a future agent following the route enum alone
would describe UI that doesn't exist).
