---
id: SCR-tool-volumetric
type: screen
description: Volumetric dosing calculator — 3-mode segmented picker, entirely self-contained (zero component reuse).
edges:
  - {rel: variant_of, target: SCR-tools-home}
metadata:
  screenshot: screenshots/SCR-tool-volumetric.png
---

# Volumetric Dosing (`VolumetricDosingView`)

**Route**: `PushRoute.tool(.volumetric)`. **Deep link**: `piru://tool/volumetric`. **File**:
`Piru/Views/Tools/Alcohol/VolumetricDosingView.swift` (218 ln — the only file in this flow;
`ByVolumeDoseInputView`/`DrinkPresetManager` are unrelated Journal/QuickLog components sharing
the folder by topic only).

## States
3-mode segmented `Picker` (`:4-19,34-44`) drives which 2-of-4 fields show; result is `nil`-guarded
→ literal `"--"` fallback, no distinct error state.

## Tokens
Hardcoded `.yellow` "Safety" label (`:194` — `DIV-002`); `RoundedRectangle(cornerRadius:10)`
numeric-field chrome (`:111`) vs. `themeCard()`'s 22 for the 4 cards. No "not medical advice"
text; closest is the yellow-icon Safety card, same chrome as every other card (not visually
distinguished as a warning, `DIV-022`).
