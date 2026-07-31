# Piru design system

Written for whoever touches this next — human or agent. Every number here is
**measured or computed**, never estimated, and every claim cites a file and line
or a reproducible command. Where something is unverified, it says so.

> **Voice rule applies to everything in this folder's scope.** See the root
> `CLAUDE.md`: Piru is a reference, a record, and a model. The phrase "harm
> reduction" never appears in consumer copy.

---

## Start here

| If you want to… | Read |
|---|---|
| Pick a color for something | [`color/color-system.md`](color/color-system.md) §1 (the three layers) then §4 (tokens) |
| Know why a color is what it is | [`color/color-system.md`](color/color-system.md) §3, and re-derive with `color/colorimetry.py` |
| Change or add a semantic color | [`color/palette-L1.json`](color/palette-L1.json) → `color/generate_colorsets.py` → run the contrast test |
| Reuse an existing component | [`components.md`](components.md), then `color/component-sameness.md` for what must **not** be merged |
| Find spacing / type / radius conventions | [`tokens.md`](tokens.md) |
| See what is inconsistent and why | [`divergences.md`](divergences.md) — 31 ranked findings |
| Understand a screen's structure | [`screens/`](screens/) — one node file per screen |
| Continue the migration | [`color/migration-plan.md`](color/migration-plan.md) |

---

## The one thing to understand

Piru runs **three color systems that share one namespace**, and nearly every
color bug found in the audit is a collision between them:

| Layer | What it is | Meaning-bearing? | Chosen by | May be small text? |
|---|---|---|---|---|
| **L1 status** | `danger` `caution` `success` `info` | yes, closed set | designer | **yes** — that is its job |
| **L2 scales** | routes (11), dose levels, phases, severity, adherence | yes, multi-valued | designer | yes, if tuned |
| **L3 identity** | per-substance color | **no** | user, or an FNV-1a hash of the name | **never** |

**Four rules follow.** They are not style preferences; each exists because
violating it produced a measured failure.

1. **A token's name states its role, never its hue.** `semantic/caution/text`,
   not `legibleYellow`. Naming by appearance is why "darken it for light mode"
   was independently rediscovered **four times** — `Theme.legibleYellow`,
   `RouteOfAdministration.tintHexPair`, `LibraryTaxonomy`'s teal, and
   `PDFReportGenerator.cautionYellow`.

2. **`text` and `accent` are separate tokens, always.** One value cannot be both
   legible-on-a-light-card and a vivid mark — for yellow that is *physically*
   impossible, since at full chroma it sits at Oklab L 0.87. Splitting them
   makes the whole `legibleYellow` bug class **unrepresentable** rather than
   fixed. `fill` is derived (`accent` at 0.10 alpha) and is never authored.

3. **L3 identity never renders as small text.** Dots, rings, bar fills,
   swatches, strokes ≥2pt — never a caption. This is not negotiable, and §3 of
   the color spec proves why with measurements.

4. **Layers are told apart by FORM, not hue.** Status is a filled pill with an
   icon; identity is a bare dot or ring; encoding keeps its labeled pill. Hue
   banding was rejected for four reasons, including that it cannot fix the worst
   confirmed bug and that it would require re-coloring persisted user data.

   This is not just our conclusion — Apple's own guidance says the same thing:
   *"When color carries meaning, respect `.accessibilityDifferentiateWithoutColor`
   by adding a non-color signal — icons, patterns, strokes."* That setting is now
   wired into the inventory supply bar, where color was the only thing separating
   healthy from low or empty. Other color-only signals remain — see open gaps.

---

## What the audit found

Contrast measured on **real rendered pixels** from 43 screenshots, not on source
values — because the light card is `.ultraThinMaterial`, whose rendered color
cannot be derived from source at all.

| | |
|---|---|
| Genuine text pairs failing WCAG AA | **21 of 33** |
| Chart lines below the 3:1 non-text floor | **4 of 5** |
| Distinct color-decision sites | ~1300 (211 hardcoded literals) |
| Accessibility-contrast handling *at audit time* | **zero** — now closed; every scale token ships Any+HC / Dark+HC slots |

**The 21 failures are one bug, 21 times:** an identity color rendered as text on
a tint of *itself*. It is unfixable at that color's own lightness — clearing
4.5:1 as 11pt text on a 12% self-tint needs Oklab **L ≤ 0.50**, and the
offenders ship at 0.69–0.92, because an identity color is chosen for identity
and carries no contrast constraint.

Two measured facts that invalidate reasoning from source alone:

- **The light card is `#f5f5f5`, not white.** Any ratio computed against
  `#FFFFFF` is optimistic. This mistake put a wrong number in the audit's *own*
  findings once (`Theme.secondaryLabel`, reported 4.25, actually **3.89**).
- **The dark card is `#111111`**, matching `Theme.cardBackground` exactly —
  which cross-validates the sampling pipeline.

---

## Verifying and changing colors

Everything is reproducible offline, no dependencies:

```bash
cd design-system/color
python3 colorimetry.py                    # self-tests vs published WCAG + Oklab values
python3 make_preview.py && open palette-preview.html   # render the palette (P3, Safari)
```

To change a semantic color:

1. Edit `palette-L1.json` (ship the `*_p3` components; the hexes are sRGB
   display-equivalents for reading only — all eight are *outside* sRGB).
2. Regenerate the catalog:
   ```bash
   python3 generate_colorsets.py palette-generator-input.json --out ../../Shared/Assets.xcassets
   ```
3. Run `PiruTests/ColorContrastTests` — it verifies the tokens **at runtime**,
   after catalog resolution, at shipped precision.

### Using a token in code

**Xcode generates the accessors.** With
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`
(`project.pbxproj:395,463`), the catalog itself produces nested, compile-time
checked symbols:

```swift
Color.Semantic.Caution.text     // SwiftUI
UIColor.Semantic.Info.text      // UIKit
.Semantic.Success.accent        // as a ColorResource
```

Do **not** hand-write an accessor file. `Color("semantic/caution/text")` is
string lookup: a typo compiles cleanly and silently resolves to a fallback
colour at runtime. The generated symbols make that a build error, resolve the
right bundle per target, and cost nothing to maintain. `generate_colorsets.py`
deliberately has no Swift-emitting option.

**In practice, use the leading-dot shorthand** from
`Shared/SemanticColors.swift`:

```swift
Text("Caution").foregroundStyle(.cautionText)
Circle().fill(.dangerAccent)
```

Xcode emits the `ShapeStyle` shorthand only for `AccentColor` — namespaced
assets don't get one, so `.foregroundStyle(.Semantic.Caution.text)` does not
compile. `SemanticColors.swift` restores it the way SwiftUI's own `.red` works.
It is *sugar over the generated symbols*, never a re-declaration: each value
forwards to the catalog symbol, so there are still no strings and a renamed
colorset is still a build error. Names are flat because leading-dot syntax
resolves against static members of the extended type — a nested `enum` would not
participate, which is precisely why the raw generated symbols need the `Color.`
prefix.

### Choosing `text` vs `accent`

| Token | For | Gate |
|---|---|---|
| `…Text` | small copy, **and any glyph inside a filled pill** | WCAG AA 4.5:1 vs the card *and* vs its own fill |
| `…Accent` | standalone marks on the card — dots, bar fills, chip strokes, chart series | 3:1 non-text |

`fill` is not a token — it is `accent` at 0.10 alpha. Derive it, never author it.
A pill icon in `accent` on an `accent`-derived fill recreates the self-tint
failure one level down, measured at 2.82:1.

**The P3 trap, stated once so nobody repeats it:** pasting sRGB components into
a `display-p3` colorset keeps the numbers and *changes the color*, silently
re-saturating it. Measured Oklab dE for that mistake runs 0.033–0.051 on
saturated hues against a JND of ~0.002 — 14–25× visible. `generate_colorsets.py`
makes the correct conversion the only reachable path for hex input.

**Quantization bites.** Two route tints passed in floating point and failed
after 8-bit rounding (4.4988 and 4.5046 against a 4.5 gate). Leave headroom, and
prefer Oklch over hex as the source of truth.

---

## The contrast gate

`PiruTests/ColorContrastTests.swift` — 7 tests, pure computation, no rendering,
**3 ms**. It is the reason this system can't quietly rot.

It gates what is fixed and **pins what is known broken at its measured value**.
It deliberately does *not* assert the migration's end state: a safety net that
fails on scheduled future work is noise, and noise gets disabled.

Every known-gap expectation is **two-sided** — it fails if the value regresses,
*and* fails once the value clears its gate, prompting whoever fixed it to
promote the check. Gaps cannot rot silently in either direction.

Three gaps are currently pinned rather than hidden: dark-mode route pills
(2.60–3.93), non-caution status tiers still rendering raw orange and red as
text, and `Theme.secondaryLabel` at 3.89.

---

## Layout of this folder

```
design-system/
├── README.md              you are here
├── references.md          provenance, external sources, what lives only locally
├── tokens.md              observed spacing / type / radius / motion, with real frequencies
├── components.md          de-facto component inventory
├── divergences.md         31 ranked inconsistencies, with file:line
├── graph.json             99-node machine-readable graph of the app
├── screens/               one node file per screen (42)
├── nodes/                 patterns and flows
└── color/
    ├── color-system.md            THE color spec — read this one
    ├── colorimetry.py             engine (self-tested; sRGB/P3/Oklab, WCAG, APCA)
    ├── palette-L1.json            the values, with every gate verified
    ├── generate_colorsets.py      palette → .colorset (Xcode makes the accessors)
    ├── make_preview.py            palette → HTML preview
    ├── palette-preview.html       rendered preview (open in Safari for true P3)
    ├── migration-plan.md          6-phase progressive migration, phases 0–2 done
    ├── review.md                  adversarial design review of the palette
    ├── semantic-roles.md          L1/L2/L3 classification of 186 sites
    ├── scales.md / scales.json     12 encoding scales
    ├── component-sameness.md      what may and may NOT be merged
    ├── asset-catalog-migration.md P3 + high-contrast catalog mechanics
    └── inventory.json / sampled.json   the evidence
```

---

## Open gaps

Beyond the three contrast gaps the test pins, three conventions in Apple's
SwiftUI guidance are currently unmet app-wide. None is in scope for the color
migration; all are worth their own pass.

| Gap | Status |
|---|---|
| Increase Contrast | **Closed.** Every scale token now ships Any+HC / Dark+HC slots at AAA, verified on device — the badge resolves `#9E062D` with the setting on versus `#D5073F` without. This was impossible before the catalog migration: a `UIColor { traits }` closure branches on `userInterfaceStyle` alone and cannot express a contrast axis. |
| `.accessibilityDifferentiateWithoutColor` | **Partly closed.** Wired into the inventory supply bar, where colour was the only thing separating healthy from low or empty. Other colour-only signals remain — an audit of the rest is worth its own pass. |
| Avoid `UIColor` in SwiftUI | **Closed** by retiring `Theme`'s closures. |
| `.caption2` used heavily | **Open — 207 sites.** Apple's guidance: `.caption2` is *extremely* small, avoid; `.caption` is small, use carefully. This is also where the contrast gates bite hardest. |
| Reduce Transparency | **Open — 0 call sites.** The card fill is `.ultraThinMaterial` everywhere. |

---

## Status

Migration phases 0–2 are **done and committed**; see
[`color/migration-plan.md`](color/migration-plan.md) for what each phase did and
what remains. Phase 3 (token burndown) is next, Phase 5 (identity-layer
enforcement) carries the largest visual change and is deliberately last.
