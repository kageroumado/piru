---
id: tokens
type: index
description: Observed design tokens harvested from source, with real frequencies, plus the proposed canonical token set.
---

# Tokens — observed vs. proposed

Counts are exact `rg` matches across `Piru/` + `Shared/` on 2026-07-29 (see commands below each
table — rerun them to refresh). "Proposed" is the convergence target; "compliant" call sites
already match it, "non-compliant" are the outliers a migration would touch. This file is the
`token`-type node collection referenced by `graph.json` (one logical node per row group, e.g.
`TOK-font-caption`, `TOK-radius-22`, `TOK-color-secondary-label`).

Full node bodies for the highest-value tokens live inline below rather than as separate files —
grep this file for the id comment (`<!-- id: TOK-... -->`) when `graph.json` points here.

## 1. Typography (`.font(...)`, 1186 call sites)

```
rg -o '\.font\([^)]*\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-font-scale -->
| Rank | Exact call | Count | Notes |
|---|---|---|---|
| 1 | `.font(.caption)` | 216 | dominant micro-copy size |
| 2 | `.font(.subheadline)` | 131 | |
| 3 | `.font(.subheadline.weight(.semibold))` | 121 | row-title weight |
| 4 | `.font(.caption2)` | 121 | badges/metadata |
| 5 | `.font(.caption.weight(.semibold))` | 54 | |
| 6 | `.font(.headline)` | 48 | section headers |
| 7 | `.font(.subheadline.weight(.medium))` | 46 | |
| 8 | `.font(.caption2.weight(.semibold))` | 38 | |
| 9 | `.font(.title3)` | 25 | |
| 10 | `.font(.body.weight(.semibold))` | 24 | |
| 11 | `.font(.body)` | 21 | |
| — | `.font(.caption2.weight(.medium))` | 17 | |
| — | `.font(.footnote.weight(.semibold))` | 16 | |
| — | `.font(.footnote)` | 13 | |
| — | `.font(.caption2.weight(.bold))` | 13 | |
| — | `.font(.title3.weight(.semibold))` | 12 | |
| — | `.font(.caption.weight(.medium))` | 12 | |
| — | `.font(.largeTitle)` | 8 | |
| — | `.font(.caption.monospaced())` | 9 | debug/monospace data (route strings, hex) |
| — | `.font(.title2)` | 7 | |

**Bespoke pixel sizes (`.system(size:...)`) — 60+ distinct call sites, not Dynamic-Type-scaled.** Concentrated in three areas: hand-rolled `Canvas` chart axis labels (`MechanisticChartView.swift:283,308,326,468` — sizes 8-11), hero display titles (`SubstanceDetailLayout.swift:326` size 40 weight heavy rounded; `LibraryBrowseView.swift:207` size 20 bold), and small numeric tier discs (`DoseTierStrip`, sizes 7-18). These are the accessibility-scaling gap in the codebase — see `DIV-018`.

**Proposed canonical scale**: keep the 11 semantic Apple text styles above as the vocabulary (do **not** introduce a parallel custom scale) — `.largeTitle` (screen hero), `.title2`/`.title3` (card/section titles), `.headline` (section headers, `isHeader` trait), `.subheadline`(+`.semibold`/`.medium`) (row titles), `.body`(+`.semibold`) (primary reading text), `.footnote`(+`.semibold`) (secondary line), `.caption`/`.caption2`(+weight) (badges, metadata, chart legends). Reserve `.system(size:)` for exactly two justified cases — `Canvas`-drawn chart labels (no `Text` view to scale) and the two 40pt/20pt hero display titles — and require every other bespoke size to migrate to the nearest semantic style (`DIV-018`).

## 2. Padding (683 call sites)

```
rg -o '\.padding\([^)]*\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-spacing-scale -->
| Exact call | Count |
|---|---|
| `.padding(.vertical, 4)` | 61 |
| `.padding()` (system default) | 51 |
| `.padding(.vertical, 2)` | 43 |
| `.padding(.horizontal, 16)` | 33 |
| `.padding(.top, 4)` | 22 |
| `.padding(.vertical, 8)` | 21 |
| `.padding(.horizontal)` (system default) | 21 |
| `.padding(.horizontal, 8)` | 19 |
| `.padding(.horizontal, 12)` | 19 |
| `.padding(.vertical, 10)` | 18 |
| `.padding(.horizontal, 10)` | 18 |
| `.padding(14)` | 15 — concentrated in QuickLog (`DockGroupedCard`, tray rows) |
| `.padding(.vertical, 6)` | 14 |
| `.padding(.horizontal, 14)` | 13 |
| `.padding(12)` | 9 |
| `.padding(16)` | 8 |
| `.padding(.leading, 16)` | 8 |

**Spacing (`spacing:` in stacks/grids, 833 call sites)**: `8`(162) > `6`(102) > `12`(88) > `10`(85) > `0`(72) > `2`(70) > `4`(69) > `3`(53) > `5`(40) > `14`(28) > `16`(27). An 8pt-ish base grid is the de facto convention (8/16/12/4 dominate — an implicit 4pt unit), but there is no shared spacing enum; every file picks integer literals ad hoc.

**Proposed**: adopt a `Spacing` enum (`xxs=2, xs=4, s=8, m=12, l=16, xl=20, xxl=24`) mapping onto the already-dominant values — this changes zero visual output for the top ~70% of call sites (they already land on 4/8/12/16) and gives the long tail (3, 5, 7, 9, 11, 13, 18, 20, 26, 28 — each ≤12 occurrences) a name to round to.

## 3. Corner radius

```
rg -o 'cornerRadius:\s*[0-9.]+' Piru Shared --no-filename | sort | uniq -c | sort -rn
rg -o 'themeCard\([^)]*\)|themeCard\(\)|themeCapsule\(\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-radius -->
| Value | Explicit-literal count | Source of truth? |
|---|---|---|
| **22** | `Theme.themeCard()` default (60 call sites use the modifier bare) + 2 explicit `cornerRadius: 22` | **Yes** — `Theme.swift:93`, "matches the system grouped-list / Library card rounding" |
| 16 | 14 explicit + 6 `themeCard(cornerRadius: 16)` | `Theme.swift:101`'s *other* default (the "for rows inside a shared grouped container" variant) — legitimately a second first-class token, not an outlier |
| 10 | 19 | no owner — Calculator's dose field, Volumetric's numeric field, Benzo/Opioid's input chips, `InventorySupport` |
| 12 | 14 | no owner — QuickLog help/suggestion cards, `EducationCard` row pill, Ceiling's info box |
| 8 | 6 | mini-graph clips |
| 20 | 4 + 2 `themeCard(cornerRadius: 20)` | Search's `SubstanceRowsCard` |
| 18 | 4 | `SessionNoteEditor` |
| 9, 5, 4, 6, 15, 17, 36, 3, 14, 2, 1, 1.5 | ≤6 each | one-off, no reuse |

**26 (`DoseTrayMetrics.cardCornerRadius`) is QuickLog's own centralized token** — not in the grep above (it's a named constant, not a literal at the call site) but functions as a fourth de-facto system alongside 22/16/10.

**Proposed canonical radii**: `Theme.Radius.card = 22` (hero/standalone cards — already dominant via `themeCard()`), `Theme.Radius.nestedCard = 16` (cards inside a grouped container — already `themeCard(cornerRadius:16)`), `Theme.Radius.control = 10` (input fields, chips, small controls — promote the already-most-common outlier value to a named token), `Theme.Radius.tightClip = 8` (mini-graph/thumbnail clips). Every other literal (12, 9, 5, 4, 6, 15, 17, 18, 20, 26, 36 …) should round to the nearest of these four on next touch. See `DIV-001`.

## 4. Color

```
rg -o '\.foregroundStyle\([^)]*\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
rg -o '\.(red|green|blue|orange|yellow|purple|pink|teal|indigo|cyan|mint|brown)\b' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-color-semantic -->
| Token | Count | Owner |
|---|---|---|
| `Theme.secondaryLabel` | 491 | `Theme.swift:20` — the dominant secondary-text color, correctly overrides the system's too-light gray |
| `Theme.accent` | 85 | `Theme.swift:6` — brand pink/hot-pink |
| `.primary` | 79 | system semantic |
| `.secondary` | 43 | system semantic — **coexists with `Theme.secondaryLabel` as a second "secondary text" token**; `HelpView.swift` mixes both in the same file (`DIV-011`) |
| `.tertiary` | 31 | |
| `.white` (+ opacity variants) | 32 + ~35 | almost entirely inside colored/gradient hero cards (`FamilyGradientCard`, `SubstanceShareCard`) — legitimate, not a violation |

**Bare system hue literals** (`.red`/`.green`/`.blue`/`.orange`/`.yellow`/`.purple`/`.teal`/`.pink`/`.cyan`/`.indigo`/`.mint`/`.brown`): **345 total occurrences**, no `Theme.success`/`Theme.warning`/`Theme.danger` token exists anywhere in `Theme.swift`. Every "success" state (green checkmarks, interaction-clear states, adherence-complete) and every "caution"/"warning" state (orange, yellow safety cards) hand-picks the system hue per file — confirmed independently by all 5 mapping passes as the single most repeated cross-tab divergence. See `DIV-002`.

**Raw `Color(red:green:blue:)` / `Color(hex:)` literals**: 278 total `Color(` call sites. The `Color(hex:)` family (~35 sites) is legitimate — it's how user/substance palette colors are stored and rehydrated (`SubstanceColor`, `PresetColor`). But a further ~40 sites are one-off `Color(red:green:blue:)` triples with no named constant (mock-onboarding palette, share-card neurotransmitter colors, `LibraryFavoritesCard`'s raspberry `Color(red:0.85,green:0.26,blue:0.47)`, Discord brand hex) — each is a small, defensible one-off individually, but collectively there is no registry of "these are the app's non-`Theme` named colors."

**Materials/glass**: `.ultraThinMaterial`(3), `.regularMaterial`(5), `.thickMaterial`(2), `.bar`(5), `.glassEffect(...)`(1), `buttonStyle(.glassProminent)`(11), `buttonStyle(.glass)`(3). Glass usage is deliberately sparse — most "elevated" surfaces use `Theme.themeCard()` (a `.ultraThinMaterial`-in-light / solid-in-dark hybrid, not raw Material) or ride a native sheet's own platter (QuickLog). `.glassProminent` buttons are the app's primary-CTA convention (Log Now, Save, commit actions) — see `components.md#GlassProminentCTA`.

## 5. Icon / hit-target sizing

```
rg -o '\.frame\(width: ?[0-9.]+, ?height: ?[0-9.]+\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-icon-size -->
Dominant square frames: `8×8`(13), `7×7`(10), `10×10`(10), `6×6`(6), `9×9`(5) — these are chart dots/ticks, not icons. Real icon/avatar tiles: `44×44`(4, med-detail avatar/hit-targets), `24×24`(4), `22×22`(3), `16×16`(3), `42×42`(2, QuickLog stepper buttons — hardcoded, not `@ScaledMetric`), `40×40`(1). **Avatar-tile size disagrees between the two Meds screens showing the same `DailyDoseItem`**: 30×30 in `MyMedsHubView.swift:220` vs. 44×44 in `MedDetailView.swift:127` — see `DIV-013`.

## 6. Motion

```
rg -o '\.animation\([^,)]*' Piru Shared --no-filename | sort | uniq -c | sort -rn
rg -o 'withAnimation\([^)]*\)' Piru Shared --no-filename | sort | uniq -c | sort -rn
```

<!-- id: TOK-motion -->
| Curve | `withAnimation` count | `.animation(value:)` count |
|---|---|---|
| `.snappy` (bare) | 58 | 8 |
| `.easeInOut(duration: 0.2)` | 9 | 2 |
| `.easeInOut(duration: 0.3)` | 6 | — |
| `.snappy(duration: 0.3)` | 3 | — |
| `.snappy(duration: 0.28)` | 2 | 1 |
| `.spring(response: 0.4, dampingFraction: 0.84)` | 1 | 1 |
| `.smooth` variants | 3 | 2 |

**`.snappy` is the dominant, de-facto standard curve** (66 combined call sites vs. everything else combined ~35) — QuickLog alone accounts for 43 of the 58 bare `withAnimation(.snappy)` sites. **Proposed**: codify `.snappy` as the house default for state toggles/expand-collapse (already true in practice), reserve `.spring(response:dampingFraction:)` for the one documented case that needs it (`SessionMenu`'s graph shrink/expand, reused verbatim in `SessionTimelineSection.swift:39` — the shared spring constant deserves a named `Animation` static instead of two copy-pasted literals).

## 7. Other recorded primitives

- **`Capsule()` fills**: 137 call sites, no shared `ChipStyle`/`capsule(tint:)` modifier despite `CapsuleChip.swift` existing with exactly that API (`capsuleChip(tint:)`/`heroChip(tint:)`) — at least 6 call sites in Library/Inventory/Tolerance/Meds hand-roll the identical visual with drifted opacity (0.12/0.15/0.16) and padding. See `DIV-003`.
- **`ContentUnavailableView`**: 15 files / 18 call sites — the dominant empty-state idiom, but at least 4 screens (category/tag/favorites browse, Search's `focusedEmpty` phase, `InYourSystemView`, Insights-hub's inline glance cards) use a hand-rolled alternative instead. See `DIV-004`.
- **`.confirmationDialog`**: 4 call sites. **`.alert`**: 11. Destructive-action confirmation is inconsistent — `DataStorageView` confirms every destructive action, `SourcePriorityView`'s Reset and `SubstanceColorsListView`'s swipe-delete do not. See `DIV-015`.
- **Shadow**: only 8 call sites total, all `.black.opacity(0.1–0.3)` variants with no shared token — low-usage, low-risk, but still 8 independently-chosen opacities for what reads as one "card lift" effect.
