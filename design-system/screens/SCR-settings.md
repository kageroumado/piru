---
id: SCR-settings
type: screen
description: App settings — owns its own Close button instead of the shared modifier; hosts a house-voice-rule violation.
edges:
  - {rel: navigates_to, target: SCR-custom-substances-list}
  - {rel: navigates_to, target: SCR-source-priority}
  - {rel: diverges_from, target: SCR-source-priority}
metadata:
  screenshot: screenshots/SCR-settings.png
---

# Settings (`SettingsView`)

**Route**: `SheetRoute.settings`. **Deep link**: `piru://settings`. **Files**:
`Piru/Views/Settings/` (12 files, 2481 ln).

## Known divergences
Hand-rolls its own xmark toolbar button (`:151-161`) instead of the shared
`CancellationCloseButton` modifier (`DIV-016`) — visually identical, duplicated code. Houses the
one confirmed **house-voice-rule violation**: `SubstanceDatabaseView.swift:28` footer reads
"Provided for harm-reduction and educational purposes only" — directly contradicts `CLAUDE.md`'s
ban on that phrase (`DIV-017`, highest-priority fix in this whole spec). `DataStorageView` confirms
every destructive action; `SourcePriorityView`'s Reset and `SubstanceColorsListView`'s swipe-delete
(both reached from here) do not (`DIV-015`). `DiscordPromptView.swift:11` has the only raw
brand-hex (`Color(hex:"5865F2")`) in this territory. A "row = icon+title+detail" anatomy
(`DataStorageView`'s `optionRow`/`dataRow`) is hand-duplicated rather than shared.
