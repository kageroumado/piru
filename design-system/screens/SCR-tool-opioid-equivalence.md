---
id: SCR-tool-opioid-equivalence
type: screen
description: Opioid dose-equivalence (MME) calculator — promotes unconvertible substances to a first-class warning card, unlike its Benzo sibling.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: duplicates, target: SCR-tool-benzo-equivalence}
metadata:
  screenshot: screenshots/SCR-tool-opioid-equivalence.png
---

# Opioid Equivalence (`OpioidEquivalenceToolView`)

**Route**: `PushRoute.tool(.opioidEquivalence)`. **Deep link**: `piru://tool/opioidEquivalence`.
**File**: `Piru/Views/Tools/Equivalence/OpioidEquivalenceToolView.swift` (292 ln). CDC-2022 MME
conversion; methadone/fentanyl/buprenorphine are un-convertible.

## Known divergence
Methadone/fentanyl/buprenorphine get a full first-class orange-icon `specialCard` ("Not a simple
conversion," `:217-230`) — see `SCR-tool-benzo-equivalence` for the contrasting, weaker Benzo
treatment of the same conceptual state (`DIV-023`). Color-coded caution comes from the CDC
daily-MME risk band (`:177-192`), a different concern than Benzo's conversion-uncertainty caveat.
