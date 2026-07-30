---
id: SCR-tool-benzo-equivalence
type: screen
description: Benzodiazepine dose-equivalence calculator — the more visually consistent of the two equivalence tools, but silently demotes unconvertible substances.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: duplicates, target: SCR-tool-opioid-equivalence}
metadata:
  screenshot: screenshots/SCR-tool-benzo-equivalence.png
---

# Benzo Equivalence (`BenzoEquivalenceToolView`)

**Route**: `PushRoute.tool(.benzoEquivalence)`. **Deep link**: `piru://tool/benzoEquivalence`.
**File**: `Piru/Views/Tools/Equivalence/BenzoEquivalenceToolView.swift` (381 ln). Shares identical
`resultCard`/dose-input-chip/"Safety" card tokens with `SCR-tool-opioid-equivalence` — the two
most visually consistent sibling tools in the audit.

## Known divergences
Always shows an inline orange `.caption2` "tables disagree" caveat on success (`:179-183`) — no
Opioid equivalent (different concern there, CDC-MME risk band). **Unsupported-substance handling
is the sharper gap**: silently demotes to `"--"` + small caption (`unconvertibleReason`, `:199-204`)
vs. Opioid's full first-class warning card for the same conceptual state (`DIV-023`). Uses a
full-screen searchable `.sheet` picker (~100 entries) vs. Opioid's inline `Menu` (9 entries) — an
intentional, list-size-justified divergence. `safetyPoint(_:)` helper duplicated verbatim in both
files (`:297-308` here, `OpioidEquivalenceToolView.swift:269-280`).
