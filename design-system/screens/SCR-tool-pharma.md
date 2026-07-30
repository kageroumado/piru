---
id: SCR-tool-pharma
type: screen
description: Pharma Search — a sortable pharmacokinetics table across every substance; filed under Library/SubstanceDetail/ despite being a Tools tool.
edges:
  - {rel: variant_of, target: SCR-tools-home}
  - {rel: diverges_from, target: CMP-substance-search-field}
metadata:
  screenshot: screenshots/SCR-tool-pharma.png
---

# Pharma Search (`PharmaTableView`)

**Route**: `PushRoute.tool(.pharma)`. **Deep link**: `piru://tool/pharma`. **File**:
`Piru/Views/Library/SubstanceDetail/PharmaTableView.swift` (667 ln — misfiled, `DIV-025`;
confirmed single-purpose, no other call site despite its folder name suggesting a substance-detail
cross-link).

## States
Loading, empty-filtered, populated table, and a distinctive 3rd per-cell state distinguishing
"still resolving" (`…`) from "genuinely missing" (`—`) (`:299-313`).

## Known divergences
Hand-rolls its own search `TextField`+clear button instead of the shared `SubstanceSearchField`
(`components.md`'s reimplemented table). `Color.primary.opacity(0.035)` bespoke zebra-stripe
(`:316`). **Zero disclaimer** — the one Tools screen presenting pharmacology data with no
uncertainty caveat at all (`DIV-022`).
