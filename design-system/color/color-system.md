---
id: SYS-color
type: system
status: proposed
supersedes: [Theme.legibleYellow, RouteOfAdministration.tintHexPair, PDFReportGenerator.cautionYellow, LibraryTaxonomy hand-darkened teal]
edges:
  - {rel: measured_by, target: colorimetry.py}
  - {rel: evidence, target: sampled.json}
  - {rel: evidence, target: inventory.json}
  - {rel: evidence, target: scales.json}
  - {rel: values, target: palette-L1.json}
  - {rel: implemented_by, target: asset-catalog-migration.md}
  - {rel: gated_by, target: component-sameness.md}
---

# Piru color system

**Read this first, then `palette-L1.json` for values.** Everything here is
computed from measured pixels or source, never estimated. Reproduce any number
with `python3 colorimetry.py` (self-tests) and the scripts referenced inline.

---

## 0. The one-paragraph version

Piru has **three color systems sharing one namespace**, and every color bug
found in this audit is a collision between them. Status meaning (L1), encoding
scales (L2), and per-substance identity (L3) obey different rules, but today
they draw from the same undifferentiated pool of hex literals and system hues.
The dominant failure — 21 of 33 measured text pairs below WCAG AA — is a single
pattern: **an identity color rendered as text on a tint of itself**, which is
mathematically unfixable at that color's own lightness.

---

## 1. The three layers

| Layer | What it is | Meaning-bearing? | Who chooses it | May be small text? |
|---|---|---|---|---|
| **L1 status** | `danger` `caution` `success` `info` (4 — see §4 for why not 5) | yes, closed set | designer | **yes** — that's its job |
| **L2 scales** | routes (11, nominal), dose levels (6, ordered), phases (5, arc), severity (3, ordered), adherence (4, nominal), … | yes, multi-valued | designer | yes, if tuned |
| **L3 identity** | per-substance color | **no** | user, or FNV-1a hash | **never** |

**Observed distribution** (186 classified sites, `inventory.json` `layer` field):
L1 62 · L2 53 · chrome 45 · L3 13 · **ambiguous 13**. The 13 ambiguous sites are
6 distinct collision patterns, not a grab-bag — enumerated in
`semantic-roles.md` §2.

### The collision, made visible

`screenshots/SCR-entry-detail.png` shows the "common" dose-tier pill and the
"caution" interaction pill rendering in the **identical** muted tan, one row
apart. Confirmed at source: `DoseLevelIndicator.swift:184`
(`self == .common ? Theme.legibleYellow : swiftUIColor`) and
`Interactions.swift:38` (`self == .caution ? Theme.legibleYellow : color`) both
resolve through the same token. **An L2 encoding step and an L1 status are the
same pixel value, adjacent on screen.** This is the layer collision as a
photograph rather than an argument, and it is the single best justification for
the whole system.

**Therefore: do not merge `DoseLevel.common` into `semantic/caution` even
though they would share a base hue.** That merge *is* the bug. Keep them as
separately named tokens that happen to start from the same hue, so they can be
pulled apart later without touching call sites.

### The rules

1. **A token's name states its role, never its hue.** `semantic/caution/text`,
   not `legibleYellow`. Four independent rediscoveries of "darken it for light
   mode" happened because the tokens were named after appearance
   (`Theme.swift:12`, `RouteOfAdministration.swift:60-91`,
   `LibraryTaxonomy.swift:244`, `PDFReportGenerator.swift`).

2. **`text` and `fill` are separate tokens, always.** One token cannot be both
   legible-on-white and a vivid fill — for yellow this is physically impossible
   (Oklab L 0.865 at full chroma). Splitting them makes the `legibleYellow` bug
   class *unrepresentable* rather than fixed.

3. **L3 never renders as small text, ever.** It renders as dots, rings, bar
   fills, swatches, chart strokes ≥2pt. Where a substance must be *labelled*,
   the label uses `text/primary` and the identity color appears beside it as a
   mark. See §3 for why this is not negotiable.

   **Precedence (this rule beats OFF-2(a)).** The failing self-tint chips are
   *also* the L3 population, so the two remedies collide. Resolution:
   OFF-2(a)'s derived-text-variant applies to **L1/L2 only**. L3 chips route
   through the existing `capsuleOutlineChip()` (`CapsuleChip.swift:33` —
   "secondary text, hairline outline"): a hairline stroke in the identity hue
   with neutral text. That is a third option beyond "derive a variant" and
   "reduce to a bare dot", it preserves the substance's color as a visible
   signal, and **it already ships in this codebase**.

4. **Layers are distinguished by FORM, not hue.** Status is a filled capsule
   with an icon; identity is a bare dot/ring/curve; encoding keeps its labeled
   pill. Four reasons hue bands lose:
   - They cannot fix the worst confirmed bug — the L1-vs-L2 collision above,
     where *both* colors already sit inside any band you would reserve.
   - L1 + L2 already claim nearly the whole hue wheel; there is no room left.
   - Re-banding would require re-coloring persisted user `SubstanceColor` /
     `UserColor` rows — mutating user data to fix a rendering rule.
   - Form survives color-vision deficiency. Hue separation never does.

   Tradeoff, stated plainly: form is a **convention, not compiler-enforced**.
   A follow-up hardening pass could wrap the layers in distinct Swift types
   (`StatusColor` / `RouteColor` / `IdentityColor`) so passing an identity color
   where a status is expected fails to compile. Worth doing once L1 exists to
   wrap; not a prerequisite.

---

## 2. Measured evidence

Contrast computed on **real rendered pixels** sampled from 43 screenshots
(`sampled.json`, 145 samples / 45 pairs), not on source values. Text and
non-text judged separately — chart strokes get WCAG 1.4.11's 3:1, not 4.5:1.

**Gate policy: WCAG AA is the hard gate; APCA is advisory.** `apca_min_lc()` is
deliberately conservative and Apple's own `.secondaryLabel` fails it at nearly
every size, so APCA is used here as a *diagnostic that ranks severity*, never as
a pass/fail merge blocker. Where this doc says FAIL without qualification, it
means WCAG AA.

| Population | Result |
|---|---|
| Genuine text pairs | **21 / 33 fail WCAG AA** |
| Chart lines | **4 / 5 below 3:1** |
| Low-confidence samples | 7, excluded and flagged for re-measure |

Two measured facts that invalidate source-only reasoning:

- **The light card is `#f5f5f5`, not white.** `.ultraThinMaterial` over
  `#ffffff` measures a light gray, consistently across every screen. Any
  contrast figure computed against `#FFFFFF` is optimistic.
- **Dark card is `#111111`**, matching `Theme.cardBackground`'s hardcoded
  `0.067` exactly — cross-validates the sampling pipeline.

---

## 3. Why the dominant bug is unfixable as-designed

The pattern: `SomeColor` as text on `SomeColor.opacity(a)` over the card.

```
#f9e2af on #f6f2eb  1.14   Vitamin D3 dose pill
#a6e3a1 on #f2fbf1  1.41   Magnesium chip
#f5a623 on #fef2de  1.83   Caffeine chip
#cba6f7 on #f7f2fe  1.85   Alcohol chip
#2ca2f5 on #d7e9f5  2.22   Methylphenidate dose pill
#00b3a2 on #d9f4f1  2.28   L-Theanine chip
```

To clear 4.5:1 as 11pt text on its own 12% tint, a color needs a low Oklab L in
light mode — and **the ceiling is hue-dependent**, so quote it per hue, not as
one number:

| hue | pink/red 6° | red 29° | orange 63° | yellow 90° | blue 245° | green 148° |
|---|---|---|---|---|---|---|
| max L | 0.54 | 0.54 | 0.53 | 0.52 | 0.52 | **0.50** |

**L ≤ 0.50 is the safe universal bound.** Those six offenders ship at L = 0.92,
0.86, 0.78, 0.79, 0.69, 0.69. They are too light because an identity color is chosen for *identity* —
by a user, or by `PresetColor.deterministic` (`SubstanceColor.swift:72-78`, an
FNV-1a hash of the lowercased name mod palette size). Neither selection path
has any contrast constraint, and neither can be given one without destroying
the feature.

**Independent confirmation of the ceiling:** `RouteOfAdministration`'s
hand-tuned light-mode table sits at L 0.46–0.54 across all 11 routes — someone
found this band empirically. But it still **misses its own documented ≥4.5:1
target on 5 of 11 routes** (sublingual 4.02, buccal 4.18, other 4.19,
inhalation 4.25, transdermal 4.32) because it was never checked against the
16% fill it actually renders on.

**Dark mode is worse in a specific way.** At the 0.18 fill alpha the app uses,
the self-tint pattern **cannot reach AA at any lightness** — it asymptotes at
4.48:1, because raising text lightness raises the tint proportionally. Fill
alpha must be **≤ 0.10** for the pattern to have headroom at all.

---

## 4. L1 — the semantic palette

**Space: Display P3.** Values in `palette-L1.json` (ship the `*_p3` components;
the hexes below are sRGB display-equivalents for reading only — every one is
*outside* the sRGB gamut). Derivation: per-hue chroma maximised at each gate,
`fill` = `accent` at **0.10 alpha** over the card.

**Four levels, not five.** `warning` was dropped — see below.

| Token | light | dark | on card (L/D) | on own fill (L/D) |
|---|---|---|---|---|
| `semantic/danger/text` | `#E20000` | `#FF4839` | 4.97 / 6.35 | 4.62 / 4.58 |
| `semantic/danger/accent` | `#FF0000` | `#FF0000` | 3.57 / 4.86 | — |
| `semantic/caution/text` | `#886700` | `#FFC900` | 4.87 / 12.44 | 4.54 / 5.80 |
| `semantic/caution/accent` | `#AE8400` | `#FFC900` | 3.17 / 12.44 | — |
| `semantic/success/text` | `#008000` | `#00FF00` | 4.93 / 13.36 | 4.60 / 5.97 |
| `semantic/success/accent` | `#00A800` | `#00FF00` | 3.08 / 13.36 | — |
| `semantic/info/text` | `#006DC2` | `#009FFF` | 5.03 / 6.61 | 4.69 / 4.51 |
| `semantic/info/accent` | `#0091FF` | `#0091FF` | 3.07 / 5.64 | — |

Gates: `text` ≥ 4.5:1 against **both** its own fill and the bare card;
`accent` ≥ 3:1 against the card (WCAG 1.4.11 non-text). Verified in both modes.

**Moving to P3 buys real colour at identical contrast**: danger +13% · caution +19% · success +37% · info +31% more chroma
than the sRGB ceiling allows at the same lightness.

**`fill` is derived, not authored** — `accent` at 0.10
alpha. Four `accent` + four `text` colorsets, not twelve.

**Icons inside a pill use `text`, never `accent`.** An accent-coloured glyph on
an accent-derived fill recreates the self-tint failure one level down — measured
at 2.82:1 before this rule was added.

### Why `warning` was dropped

At the chroma the gamut allows in **light** mode, `warning` (63°) and `caution`
(90°) came out **dE 0.064** apart — indistinguishable on a small pill. Two
severity levels that look identical defeat the purpose of having two. A grid
search over both modes could separate them only by pushing `caution` to 109°,
where it renders `#6E6C00` — an olive green, fighting the universal
caution-is-yellow convention.

Dropping the tier resolves it cleanly: `caution` returns to a true yellow at 90°
and the worst pairwise separation improves to **dE 0.176**
(caution/success light).

This is also supported by the audit rather than merely convenient: system
`.orange` — the de-facto warning tier — was already carrying three unrelated
meanings. **Remap:** "dangerous interaction" → `danger`; "informational" →
`info`; "tap to edit" → not a status at all, use the app accent as a control
tint.

`text/primary` stays system `.primary` so it keeps free OS-level high-contrast
tracking. Achromatic states use `text/secondary` — `neutral` is not a chromatic
token.

---

## 5. L2 — encoding scales

12 scales extracted (`scales.json`). Rules:

- **Ordered scales must be monotonic in Oklab L.** A ramp whose lightness jumps
  around reads as unordered regardless of hue.
- **Nominal scales maximize hue separation** at a fixed L/C, so no step is
  privileged by being lighter.
- **Every text-bearing step needs a `.text` variant** at the L1 lightness
  targets. `route_tint` is the only scale that attempts this today.

### Conflicts to resolve

| Conflict | Detail |
|---|---|
| **Dose level ×3 encodings** | `Substance.swift:179` `DoseLevel.color: String` returns word-strings (`"gray"`) and has **zero consumers — dead, delete it**. `DoseLevelIndicator.swift:167-177` `swiftUIColor` (fill) vs `:183-186` `labelColor` (text) diverge only at `.common`. |
| **Phase ×2 definitions** | Hex ramp `9B9BA1/3A8DEF/34C759/FF9F0A` (`SessionReportPDF`/`DosePhaseProgressBar`/`TimelineGraphView`) vs `DoseLevelIndicator.ExperiencePhase`'s `.blue/.teal/.orange/.purple`. Same dose entry: edit uses one, read uses the other, so "peak" flips orange→green. Both are **intentionally non-monotonic** — a narrative arc, not a magnitude ramp. Do not "fix" the non-monotonicity; fix the duplication. |
| **Dose intensity ×3 scales** | `dose_level` (6), `dose_tier_strip` (5, `DoseDurationCard.swift:328-334`), `dose_intensity_dial` (6 incl. Overdose, `DoseIntensityCard.swift:26-29`) — three step counts, three different greens for "Light". |
| **Inventory L2/L3 collision** | `StockStatus.barTint` (status) and `InventoryItem.supplyBarTint` (identity) compete for the same bar-fill role. Restates DIV-031. |
| **Category scale half-dark-blind** | 9 of 29 `substance_category` cases are bare `Color(red:)` with no dark variant — same pixel in both appearances. |
| **Route rendered two incompatible ways** | The substance-detail route *picker* draws selected/unselected pills in generic accent-pink/gray with **zero** route-color signal, while the read-only route badge elsewhere uses the real route tint. Same L2 concept, two renderers, one of which discards the encoding entirely. |

**Not a ramp:** `ToleranceRow.swift:44-59` bands are one identity color at three
alphas (0.5/0.82/1.0), ordered by timescale. Don't count it as a semantic ramp.

---

## 6. L3 — identity

- Sources: user pick, `UserColor`, and `PresetColor.deterministic` (FNV-1a).
- **48 presets** (CLAUDE.md says 31 — stale).
- **11 of 48 collide** with an L1/L2 anchor within 15° hue and 0.06 chroma:
  Rose/Light/Dark ≈ accent (Δh 1.0–1.4°), Tangerine ≈ warning (2.1°),
  Mustard ≈ caution (2.5°), Green/Dark Green ≈ success (7.7°).
- Under rule 4 (form, not hue) these collisions become **acceptable** — a
  mustard dot is not confusable with an amber capsule. No palette entries need
  removing.
- **`#2ca2f5` — the "blue" in PK curve strokes and several chips — is the
  `Azure` PresetColor** (`SubstanceColor.swift:86`), not `systemBlue`. L3
  leaking into chart/chrome. Route it to `semantic/info` or a `chart/series`
  token.

---

## 7. The P3 trap

Pasting existing sRGB components into a `display-p3` colorset **keeps the
numbers and changes the color**. Measured Oklab dE for naive reinterpretation:

| sample | dE |
|---|---|
| systemGreen `#34C759` | **0.0511** (worst — P3's green primary is furthest from sRGB's) |
| systemRed / Sky / Rose | 0.033–0.044 |
| neutrals (`#111111`) | **0.0000** (shared white point) |

Oklab JND ≈ 0.002, so saturated hues shift **14–25× the just-noticeable
threshold**. Use `srgb_to_p3_same_appearance()`; `generate_colorsets.py` makes
that the only reachable path for hex input.

---

## 8. Ranked offenders, with options

### OFF-1 · Three sites render pure `#FFCC00` as text — WCAG **1.39**
`DoseLevelIndicator.swift:22`, `InteractionCheckerView.swift:166`,
`InteractionTimelineView.swift:694`. Each uses a scale's `.color` (fill variant)
where `.labelColor` (text variant) exists. Effectively invisible on `#f5f5f5`.

- **(a) One-line each — swap to `.labelColor`.** → WCAG 5.08, AA. Zero risk,
  ships today, independent of everything else. **Recommended.**
- (b) Wait for the L1 migration and route to `semantic/caution/text` (5.53).
- (c) Make the fill variant `private` so the wrong one can't be reached — the
  only option that prevents recurrence. Best done *with* (a).

### OFF-2 · The self-tint pattern (21 failing pairs)
- **(a) Derived text variant.** Text on a tinted pill comes from a fixed-L
  derivative of the identity color (L 0.50 / 0.86), not the raw color. Preserves
  hue identity, guarantees contrast. **Recommended.**
- (b) Drop fill alpha to ≤0.10 and keep raw colors — necessary but *not
  sufficient*; light mode still fails for high-L hues.
- (c) Abandon colored text in pills: neutral text, identity as a leading dot.
  Cheapest, most robust, loses the tinted look.

### OFF-3 · `legibleYellow` and its three clones
Four independent solutions to one problem. Replace all with
`semantic/caution/{text,fill}`; delete `Theme.legibleYellow`,
`PDFReportGenerator.cautionYellow`, and `LibraryTaxonomy`'s hand-darkened teal.
Fold `RouteOfAdministration.tintHexPair` into generated `route/*` tokens — and
fix the 5 routes that miss their own target.

### OFF-4 · No high-contrast support anywhere
Zero hits for `isDarkerSystemColorsEnabled` / `accessibilityContrast` /
`isReduceTransparencyEnabled` across all four targets. Only the asset-catalog
migration makes this expressible (Any / Dark / Any+HC / Dark+HC).

### OFF-5 · `Theme.secondaryLabel`, 566 sites
**Corrected** — the original figures here were computed against pure
white/black, the exact source-only mistake §2 warns about, committed inside this
audit's own work. Against the **measured** card (`#f5f5f5` / `#111111`):

| | Piru | system |
|---|---|---|
| light | **3.89 — FAILS AA** | 2.17 — fails worse |
| dark | 7.79 | **9.97** |

So the light override is still better than system but **both fail**; it needs to
get *darker*, not merely be kept. The dark override loses to system and should
adopt it. Revised action: **darken light until it clears 4.5:1 on `#f5f5f5`,
adopt the system value for dark.**

### OFF-6 · Widget can't see the asset catalog
`PiruWidget`/`PiruLiveActivityExtension` lack `Piru/Assets.xcassets`;
`WidgetColors.swift:5-12` hand-rebuilds the accent (currently *correct*, but a
drift risk). `Shared/` is already in all three targets → one
`git mv Piru/Assets.xcassets Shared/` fixes it and deletes `WidgetColors.swift`.

---

## 9. Sequencing

Each step independently shippable and verifiable against the 43-screenshot
baseline.

1. **OFF-1 (a)** — three-line contrast fix. No dependencies.
2. **`git mv Assets.xcassets` → `Shared/`** — unblocks every target. Deletes
   `WidgetColors.swift`.
3. **Generate L1 colorsets** from `palette-L1.json` via `generate_colorsets.py`.
4. **Migrate `Theme.*`** to catalog lookups; drop the `UIColor{traits}`
   closures and mark accessors `nonisolated` (the `@MainActor` on
   `Interactions.swift:36` comes from `-default-isolation MainActor`, not the
   closures — a pre-existing, separately fixable issue).
5. **L2 scales** — dedupe phase, delete dead `DoseLevel.color`, unify the three
   dose-intensity scales, generate `route/*`.
6. **L3 rule enforcement** — derived text variants; identity out of chart chrome.
7. **High-contrast variants** — now expressible; author them last.

Unification of the component families that render these tokens is gated on
`component-sameness.md`: 19 instances mergeable, **7 must stay separate** with
DO-NOT-MERGE reasons recorded.
