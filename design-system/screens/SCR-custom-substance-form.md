---
id: SCR-custom-substance-form
type: screen
description: One form serving three modes — net-new custom substance, edit existing custom, or personalize a shipped substance.
edges:
  - {rel: duplicates, target: SCR-custom-substances-list}
  - {rel: variant_of, target: SCR-custom-substances-list}
metadata:
  screenshot: null
---

# Custom Substance form (`CustomSubstanceFormView`)

**Declared route**: `SheetRoute.customSubstanceForm(id:)` — also dead (`UnmigratedRoutePlaceholder`).
**Real navigation**: local `.sheet` from `CustomSubstancesListView.swift:71-76` (add/edit), **or**
`PersonalizeSubstanceHost` (`SheetRouteView.swift:242-254`, this route IS live) which hosts the
exact same view with `personalizing:` set — i.e. Personalize Substance is not a distinct screen,
it's this form in its third mode. **File**: `Piru/Views/Library/Custom/CustomSubstanceFormView.swift:10-389`.

## States
`isPersonalizing` (`:57-59`) branches copy/fields at `:199-214,319-322`. `Form` with 7 `Section`s:
Name/Display-name, Classification, Dosing Defaults, Dose Ranges, Half-life, Duration
(toggle-gated), Notes. Duplicate-name `.alert` (`:311-315`).
