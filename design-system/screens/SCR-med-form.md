---
id: SCR-med-form
type: screen
description: Add-a-med form (the edit code path exists but is dead — MedDetailView is edit-in-place).
edges:
  - {rel: duplicates, target: SCR-med-detail}
metadata:
  screenshot: null
---

# Med form (`MedFormView`)

**Route**: presented as a sheet from `MyMedsHubView.swift:176` (Add-only in practice — no `item`
arg passed at that call site, so the "edit" code path is dead). **File**:
`Piru/Views/Journal/DailyDose/MedFormView.swift` (484 ln).

## Pattern (positive example)
Correctly uses `@Observable MedFormDraft` (`:16-54`) — only 2 `@State` in the view itself, the
`CLAUDE.md`-preferred pattern despite the 484-line length. Save button uses
`.buttonStyle(.glassProminent)` (`:127`) — the only glass-prominent Save in this cluster.

## Known divergence
Duplicates the weekday-circle-button construction **verbatim** from `MedDetailView`
(`:276-304` vs `MedDetailView.swift:281-303`) instead of sharing a subview — see
`components.md`'s reimplemented-instead-of-reused table.
