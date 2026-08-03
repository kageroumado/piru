# Delete candidates

Looks dead; scope or origin unverified. Kiri confirms → it goes.

## `Piru/Views/Components/PharmacologyGlossarySheet.swift:11` — `Topic.monoamine`

- **What**: the enum case plus the explainer copy written for it
- **Looks dead because**: zero call sites — no `onGlossary(.monoamine)` anywhere in the repo. Every
  other `Topic` is reachable from an ⓘ button; this one never got wired to anything. Surfaced during
  the 2026-08-03 ⓘ audit.
- **Not deleted because**: the copy is written and the monoamine hero is still on screen, so it may
  be a wiring gap rather than a dead concept — the intended ⓘ may simply never have been added.
- **To confirm**: decide whether the S↔D lean bar should have its own ⓘ. If yes, wire it; if no,
  delete the case and its copy.
- **Found**: 2026-08-03
