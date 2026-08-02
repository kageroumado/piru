# Piru design system — color

Documentation and tooling for Piru's color system. Every number here is **measured or computed**,
never estimated, and every claim cites a file and line or a reproducible command.

This folder used to also hold a point-in-time design audit (a screen-by-screen graph, a divergence
register, a token census, and a screenshot corpus). That was removed 2026-08-02: it described a
build that no longer exists, and a stale audit read as current is worse than none. What survives
is the part that describes how the system *works* rather than how it looked one week.

## Start here

| I want to… | Read |
|---|---|
| Understand the layer model before touching any color | "The three systems" below |
| Change or add a semantic color | "Verifying and changing colors" below |
| Know the palette's structure | [`color/color-system.md`](color/color-system.md) |
| Know what a role means and when to use it | [`color/semantic-roles.md`](color/semantic-roles.md) |
| Work with the multi-step scales (routes, dose, phase) | [`color/scales.md`](color/scales.md) |

## The three systems

Piru runs **three color systems that share one namespace**, and nearly every color bug is a
collision between them:

| Layer | What it is | Meaning-bearing? | Chosen by | May be small text? |
|---|---|---|---|---|
| **L1 status** | `danger` `caution` `success` `info` | yes, closed set | designer | **yes** — that is its job |
| **L2 scales** | routes (11), dose levels, phases, severity, adherence | yes, multi-valued | designer | yes, if tuned |
| **L3 identity** | per-substance color | **no** | user, or an FNV-1a hash of the name | **never** |

**Four rules follow.** They are not style preferences; each exists because violating it produced a
measured failure.

1. **A token's name states its role, never its hue.** `semantic/caution/text`, not `legibleYellow`.
   Naming by appearance is why "darken it for light mode" was independently rediscovered **four
   times** — `Theme.legibleYellow`, `RouteOfAdministration.tintHexPair`, `LibraryTaxonomy`'s teal,
   and `PDFReportGenerator.cautionYellow`.

2. **`text` and `accent` are separate tokens, always.** One value cannot be both
   legible-on-a-light-card and a vivid mark — for yellow that is *physically* impossible, since at
   full chroma it sits at Oklab L 0.87. Splitting them makes the whole `legibleYellow` bug class
   **unrepresentable** rather than fixed. `fill` is derived (`accent` at 0.10 alpha) and is never
   authored.

3. **L3 identity never renders as small text.** Dots, rings, bar fills, swatches, strokes ≥2pt —
   never a caption. This is not negotiable; §3 of `color/color-system.md` proves why with
   measurements.

4. **Layers are told apart by FORM, not hue.** Status is a filled pill with an icon; identity is a
   bare dot or ring; encoding keeps its labeled pill. Hue banding was rejected for four reasons,
   including that it cannot fix the worst confirmed bug and that it would require re-coloring
   persisted user data.

   Apple's own guidance says the same: *"When color carries meaning, respect
   `.accessibilityDifferentiateWithoutColor` by adding a non-color signal — icons, patterns,
   strokes."* That setting is wired into the inventory supply bar, where color was the only thing
   separating healthy from low or empty.

## Verifying and changing colors

Everything is reproducible offline, no dependencies:

```bash
cd design-system/color
python3 colorimetry.py                                 # self-tests vs published WCAG + Oklab values
python3 make_preview.py && open palette-preview.html   # render the palette (P3, Safari)
```

To change a semantic color:

1. Edit `palette-L1.json` (ship the `*_p3` components; the hexes are sRGB display-equivalents for
   reading only — all eight are *outside* sRGB).
2. Regenerate the catalog:
   ```bash
   python3 generate_colorsets.py palette-generator-input.json --out ../../Shared/Assets.xcassets
   ```
3. Run `PiruTests/ColorContrastTests` — it verifies the tokens **at runtime**, after catalog
   resolution, at shipped precision.

### Using a token in code

**Xcode generates the accessors.** With
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`
(`project.pbxproj:395,463`), the catalog itself produces nested, compile-time checked symbols:

```swift
Color.Semantic.Caution.text     // SwiftUI
UIColor.Semantic.Info.text      // UIKit
.Semantic.Success.accent        // as a ColorResource
```

## The contrast gate

`PiruTests/ColorContrastTests.swift` — 7 tests, pure computation, no rendering, **3 ms**. It is the
reason this system can't quietly rot.

It gates what is fixed and **pins what is known broken at its measured value**. It deliberately does
*not* assert an end state: a safety net that fails on scheduled future work is noise, and noise gets
disabled.

Every known-gap expectation is **two-sided** — it fails if the value regresses, *and* fails once the
value clears its gate, prompting whoever fixed it to promote the check. Gaps cannot rot silently in
either direction.

Three gaps are currently pinned rather than hidden: dark-mode route pills (2.60–3.93), non-caution
status tiers still rendering raw orange and red as text, and `Theme.secondaryLabel` at 3.89.

## Layout

```
design-system/
└── color/
    ├── colorimetry.py             Oklab/WCAG math + self-tests (root CLAUDE.md points here)
    ├── generate_colorsets.py      palette JSON → Assets.xcassets (emits display-p3 only)
    ├── build_l2_scales.py         generates the multi-step scales
    ├── build_generator_input.py   assembles generator input from L1 + scales
    ├── make_preview.py            renders palette-preview.html
    ├── palette-L1.json            the eight semantic seeds — edit this to change a color
    ├── palette-L2.json            derived multi-step scales
    ├── scales.json / inventory.json / sampled.json
    ├── color-system.md            palette structure
    ├── semantic-roles.md          what each role means, and when to use it
    ├── scales.md                  the multi-step scales
    └── *.html                     tuning sheets (open in Safari for true P3)
```
