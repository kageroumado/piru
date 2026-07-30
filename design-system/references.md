# References and provenance

Where every number in this folder came from, what is authoritative, and what
lives only on one machine.

---

## Not in this repo

**The screenshot corpus (43 PNGs, ~30 MB)** lives at
`Specs/design-system/screenshots/` — and `Specs/` is gitignored
(`.gitignore:39`), so it is **local to one machine and in no commit**.

It is the evidence behind the measured surfaces (`#f5f5f5`, `#111111`) and the
45 sampled contrast pairs. The derived values are committed here
(`color/sampled.json`), so the *conclusions* survive; the raw pixels do not.

Screenshots also go stale as the app changes, which is why they were not
committed. To regenerate:

```bash
# a booted simulator, iPhone 17 Pro Max / iOS 26.5
xcrun simctl ui booted appearance light      # or dark
xcrun simctl openurl booted 'piru://...'     # grammar: Piru/Navigation/DeepLink.swift
xcrun simctl io booted screenshot out.png
```

Launch args that matter: `-piruPersona dailyMeds|sporadicMeds|rareOpener` seeds
fixtures; `-piruNoDemoData` suppresses the 424 demo doses a DEBUG build
otherwise seeds into an empty store.

One screenshot is worth keeping in mind even without the file:
`SCR-entry-detail.png` shows the "common" dose-tier pill and the "caution"
interaction pill rendering in the **identical** tan, one row apart — an L2
encoding step and an L1 status resolving to the same pixel value, adjacent on
screen. Confirmed at source: `DoseLevelIndicator.swift:184` and
`Interactions.swift:38` both route through `Theme.legibleYellow`.

---

## Standards and algorithms

| Used for | Source | Note |
|---|---|---|
| Contrast ratio | WCAG 2.1 §1.4.3 (text), §1.4.11 (non-text) | The **hard gate**. Text 4.5:1, non-text 3:1. |
| Perceptual contrast | APCA-W3 0.1.9 | **Advisory only.** Apple's own `.secondaryLabel` fails it at nearly every size, so it ranks severity — it is never a merge blocker. |
| Perceptual color space | Oklab / Oklch, Björn Ottosson (2020) | Used for lightness targets, hue preservation, and "do these read as different colors". JND ≈ 0.002; the practical floor for two small pills is ~0.10. |
| Gamut mapping | CSS Color 4 style — binary-search chroma, hold L and h | Preserves hue exactly, which naive RGB clipping does not. |
| Wide gamut | Display P3 (Apple), sRGB transfer function | Same TRC as sRGB, different primaries. |

**A correctness note that is easy to get wrong:** WCAG defines relative
luminance with the *sRGB primaries*. Applying those coefficients to P3
components is simply wrong — measured 6% off. `colorimetry.py` takes CIE Y from
XYZ instead, which is identical to the WCAG formula for sRGB input and correct
for P3. Likewise `UIColor.getRed` reports **extended** sRGB for a P3 asset
(components outside [0,1]), so the transfer functions must be sign-preserving or
a naive `pow` returns NaN and poisons every ratio downstream.

---

## Verified against the codebase

Every claim in this folder cites `file.swift:line`. The load-bearing ones, and
how they were confirmed:

| Claim | How verified |
|---|---|
| `AccentColor` is the app's only colorset, and is P3 | Read `Contents.json`; `find -name '*.colorset'` |
| Zero P3 usage in Swift | `rg 'displayP3\|\.p3'` across all four targets → 0 |
| Zero accessibility-contrast handling | `rg -i 'isDarkerSystemColorsEnabled\|accessibilityContrast\|legibilityWeight\|colorSchemeContrast'` → 0, twice, independently |
| Widget could not see the asset catalog | `project.pbxproj` `fileSystemSynchronizedGroups`; `PiruWidget/WidgetColors.swift:5-12` said so itself |
| Auto-assigned substance colors are an FNV-1a hash | `Shared/Models/SubstanceColor.swift:72-78` |
| `PresetColor.all` has 48 entries | `grep -c` — note `CLAUDE.md` says 31, which is stale |
| `DoseLevel.color` was dead | `rg` across app code **and** tests — the first pass missed two tests, which is why "dead" now means both |

---

## Corrections made during the work

Recorded because each was a real error that shipped into an intermediate
artifact, and the pattern is instructive.

1. **Contrast computed against white instead of the measured card.** Put a wrong
   number in the audit's own OFF-5 (`Theme.secondaryLabel` reported 4.25;
   actually **3.89**, which *fails* AA). The test suite's surface constants and
   doc comment now exist specifically to stop this recurring.
2. **A fabricated statistic.** A preview once displayed a uniform "+15% chroma"
   for every token because the sRGB comparison value was approximated as
   `p3 / 1.15` rather than computed. Real gains are 13/19/37/31%.
3. **A comparison that compared a thing to itself.** The sRGB-vs-P3 strip drew
   its "sRGB" half from the P3 value converted *down*, so the two halves were
   identical by construction. It now uses an independently sRGB-gated value.
4. **A max-chroma search that exited early** and returned grays (`success` came
   out `#6A6D6A`).
5. **A test heuristic that was wrong, not the code.** The catalog-resolution
   check asserted `text ≠ accent`; in dark mode `caution` and `success`
   legitimately converge, because against near-black the max-chroma color
   clearing the 3:1 accent gate also clears the 4.5:1 text gate.
6. **"Delete `WidgetColors.swift`"** was too aggressive — the file also holds
   `WidgetBackground` and gradient tokens that are not duplicates.

---

## Method notes

- **Pixel sampling** takes a ≥8×8 patch median, not a single pixel, to reject
  antialiasing and subpixel text. Pills use a color-cluster split with the
  capsule's corner triangles masked out — without that mask, corner bleed-through
  wins the "text" slot over the real, smaller text cluster.
- **Screenshots from `simctl` are sRGB-tagged**, verified with `sips -g profile`.
  Values in `sampled.json` are raw file values, not converted.
- **Contrast is a function of the (foreground, background) pair, not the call
  site.** 566 identical pairings collapse to one computation with no analytical
  loss — which is why `inventory.json` dedupes by pair and expands only outliers.

---

## Related, elsewhere in the repo

- Root [`CLAUDE.md`](../CLAUDE.md) — voice rules, US English, SwiftUI
  decomposition rules, localization workflow. Binding.
- `PiruTests/ColorContrastTests.swift` — the enforced gate.
- `Shared/Assets.xcassets/semantic/` — the generated P3 colorsets.
- Asset symbols — generated by Xcode from the catalog
  (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`), giving
  `Color.Semantic.Caution.text` with compile-time checking. Never hand-written.
- `Specs/KILLER-FEATURES.md` — product scope. Deliberately **not** duplicated
  here; this folder is about form, that one is about function.
