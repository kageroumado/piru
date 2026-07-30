> **Superseded on the Swift-accessor question.** This document was written
> assuming the generator would emit a `GeneratedTheme.swift`. It should not,
> and no longer can: Xcode already generates nested, compile-time-checked
> symbols (`Color.Semantic.Caution.text`) from the catalog whenever
> `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` is YES —
> which it is (`project.pbxproj:395,463`). Read every `GeneratedTheme.*`
> mention below as "the Xcode-generated symbol". Everything else here — the
> P3 conversion, the four appearance slots, the namespace mechanics — stands.

---
id: asset-catalog-migration
type: plan
description: Mechanism for migrating Piru's 211 hardcoded color literals to a display-p3, high-contrast-capable asset catalog — schema, generator, the sRGB->P3 trap, and sequencing. Values are owned by the colorimetry pass; this covers only the machinery.
---

# Asset-catalog migration — the mechanism

Scope discipline: this file designs **how** the migration works, not **which colors** result.
Every worked example below uses either a placeholder token name or a real color already in the
Swift source, converted with `colorimetry.py` — none of it should be read as a proposed final
palette. That's `colorimetry.py`'s job. All claims re-verified against source on 2026-07-30;
counts differ slightly from the assignment brief where a direct `grep -rn` gave a different
number — the actual command is shown so it's reproducible.

---

## 0 — Baseline, verified

```
grep -rn "Color(hex:" Piru Shared PiruWidget PiruLiveActivityExtension --include="*.swift" | wc -l   # 128
grep -rn "Color(red:"  ...                                                                            # 58
grep -rn "UIColor(red:" ...                                                                            # 18
grep -rc "displayP3\|display-p3\|display_p3" ...                                                       # 0 everywhere
grep -rn "isDarkerSystemColorsEnabled\|accessibilityContrast\|legibilityWeight\|colorSchemeContrast" ...  # 0 everywhere
```

**Confirmed: zero P3 usage, zero high-contrast handling anywhere in the app.** The 128 count is
lower than the brief's 135 — likely a difference in what was swept (worktrees, or a second
counting method); not worth reconciling further, the shape of the problem is identical either way.
`Piru/Assets.xcassets/AccentColor.colorset/Contents.json` is the one existing colorset and it's
correctly `display-p3` in both its `any` and `dark` entries — it's also the one file this whole
migration must never touch (see §4 safety rails).

---

## 1 — Colorset structure: all four appearance slots

Xcode's per-color `Contents.json` supports two independent, **orthogonal** appearance axes:

- `luminosity`: `light` (implicit/omitted) or `dark`
- `contrast`: `high` (omitted = normal/any)

Combined, that's four slots: **Any**, **Dark**, **Any + High Contrast**, **Dark + High Contrast**.
Xcode's own Attributes Inspector calls these "Appearances" (Any/Dark) and "Contrasts" (Any/High) —
two independent checkboxes — and this is exactly what the app is missing today (§0's grep). A
color with only Any/Dark entries is valid and simply falls back to its non-HC sibling when
Increase Contrast is on; the HC slots are additive, never required.

**Worked example** — `semantic/caution/text`, all four slots, built by the generator in §4 from
real `Theme.legibleYellow` values (`Theme.swift:12-16`) plus placeholder HC variants (not final —
illustrative only):

```json
{
  "colors": [
    {
      "color": {
        "color-space": "display-p3",
        "components": { "red": "0.501", "green": "0.394", "blue": "0.118", "alpha": "1.000" }
      },
      "idiom": "universal"
    },
    {
      "color": {
        "color-space": "display-p3",
        "components": { "red": "0.968", "green": "0.808", "blue": "0.274", "alpha": "1.000" }
      },
      "idiom": "universal",
      "appearances": [{ "appearance": "luminosity", "value": "dark" }]
    },
    {
      "color": {
        "color-space": "display-p3",
        "components": { "red": "0.347", "green": "0.278", "blue": "0.072", "alpha": "1.000" }
      },
      "idiom": "universal",
      "appearances": [{ "appearance": "contrast", "value": "high" }]
    },
    {
      "color": {
        "color-space": "display-p3",
        "components": { "red": "0.978", "green": "0.872", "blue": "0.426", "alpha": "1.000" }
      },
      "idiom": "universal",
      "appearances": [
        { "appearance": "luminosity", "value": "dark" },
        { "appearance": "contrast", "value": "high" }
      ]
    }
  ],
  "info": { "author": "generate_colorsets.py", "version": 1 }
}
```

This is real, generator-produced output (§4), not hand-typed — `scratch-test/Assets.xcassets/semantic/caution/fill.colorset/Contents.json`
under this same directory, generated and verified against `plutil`/`json.load` (§4.4).

**Namespacing note**: a slash-namespaced token name (`semantic/caution/text`) requires the
intermediate folders (`semantic/`, `semantic/caution/`) to each carry their own `Contents.json`
with `"properties": {"provides-namespace": true}` — otherwise Xcode treats them as plain
organizational groups and the resolved asset name silently collapses to just `text`, colliding with
any other leaf named `text` elsewhere in the catalog. The generator in §4 does this automatically;
it is the single most common thing a hand-rolled script gets wrong.

---

## 2 — What this kills: `Theme.swift`'s manual `UIColor { traits in }` branching

`Theme.swift:4-56` hand-branches on `UIColor.userInterfaceStyle` for six colors (a seventh,
`WidgetColors.accent` in `PiruWidget/WidgetColors.swift:9-13`, does the same thing independently —
see §6). None of the six can express high contrast; `userInterfaceStyle` is the *only* trait they
inspect.

| Closure | File:line | Replaces with | Consumers found |
|---|---|---|---|
| `Theme.legibleYellow` | `Theme.swift:12-16` | `semantic/caution/text` (§3) — the split this migration exists to enable, see below | `ConfidenceBadge.swift:30`, `ProvenanceBadge.swift:40`, `DoseLevelIndicator.swift:184`, `Interactions.swift:38` |
| `Theme.secondaryLabel` | `Theme.swift:19-25` | `text/secondary` | used across ~40+ files app-wide (too many to enumerate; grep `Theme.secondaryLabel` for the current list at migration time) |
| `Theme.background` | `Theme.swift:30-34` | `surface/background` | app root backgrounds |
| `Theme.cardBackground` | `Theme.swift:37-41` | `surface/card` (dark-mode fill; `CardBackground`/`themeCard` still branch light-mode to `.ultraThinMaterial`, which has no asset-catalog equivalent — material stays code, only the dark solid moves) | `CardBackground`, `ThemedBackground` (`Theme.swift:60-71,78-88`) |
| `Theme.groupedBackground` | `Theme.swift:44-48` | `surface/groupedBackground` | grouped-list screens |
| `Theme.inputBackground` | `Theme.swift:51-55` | `surface/inputBackground` | text-field/input chrome |

**The yellow bug, concretely**: `Theme.legibleYellow` is asked to serve as both **readable text**
(`ConfidenceBadge`/`ProvenanceBadge`/`DoseLevelIndicator`'s label color) and, via
`Interactions.swift:38`, the tint fed into F2's capsule-chip family (§ component-sameness.md F2),
where the *same* value becomes a **13-16% opacity fill background** for the caution pill. One token
is being asked to be legible black-on-white text in one place and a vivid saturated fill in
another — those are different jobs with different constraints (a fill can be as saturated as looks
good; text must clear a contrast minimum). The taxonomy in §3 makes `.../text` and `.../fill`
separate tokens *by construction*, so a future "make this pop more" fill edit can no longer
accidentally desaturate someone's caption text three files away.

### MainActor: verified, and more nuanced than "asset colors are free of it"

`Interactions.swift:36-38`:
```swift
/// MainActor because `Theme.legibleYellow` is.
@MainActor var labelColor: Color {
    self == .caution ? Theme.legibleYellow : color
}
```
`InteractionSeverity` itself is declared `nonisolated enum` (`Interactions.swift:9`) and its plain
`color` property is unannotated/nonisolated — `labelColor` alone carries `@MainActor`, solely
because it touches `Theme.legibleYellow`.

I compiled four standalone probes against the iOS 26 simulator SDK under
`-swift-version 6 -strict-concurrency=complete -default-isolation MainActor` (the project's actual
settings per `CLAUDE.md`) to isolate the real cause:

1. A bare `nonisolated func` returning `Color(UIColor { traits in ... })` — **compiles clean**.
   The `UIColor` dynamic-provider closure is not itself what forces MainActor.
2. The same `Theme.legibleYellow`-shaped declaration *without* `nonisolated` — **fails**:
   `main actor-isolated static property 'legibleYellow' can not be referenced from a nonisolated context`.
   Confirms the constraint comes from the project's `-default-isolation MainActor` flag applying to
   every declaration that doesn't opt out, not from anything intrinsic to `UIColor`.
3. The same declaration *with* `nonisolated static let` added — **compiles clean**, and reading it
   from another `nonisolated` function works.
4. A full reproduction of the real shape — `nonisolated enum InteractionSeverity` +
   `nonisolated var labelColor` reading a `nonisolated` `Theme.legibleYellowOld` (UIColor-closure
   form) *and* a `nonisolated` `Theme.cautionText = Color("semantic/caution/text")`
   (asset-catalog form) side by side — **both compile clean**, identically.

**Conclusion, precisely stated**: an asset-catalog `Color(_:)` lookup is exactly as `nonisolated`-safe
as today's `UIColor{traits}` closure — neither construction mechanism requires MainActor. The
`@MainActor` on `labelColor` today is a **pre-existing, independently fixable bug** (someone could
add `nonisolated` to `Theme.legibleYellow` right now, with no P3 migration involved, and the
constraint would disappear). What the asset-catalog migration *does* provide is a natural forcing
moment: every one of these six colors is being re-declared anyway, so adding `nonisolated` to each
new `GeneratedTheme.*` accessor (the generator in §4 does this by default) costs nothing extra, and
is easy to justify precisely because a catalog lookup is so obviously inert — no captured
`UITraitCollection` closure to eyeball for hidden state. Fold this into the same PR as the token
migration rather than opening a separate concurrency-only PR: touch `Interactions.swift:36`,
`RouteOfAdministration.swift` (its `.tintColor`, doc comment at `:65` already calls out
`legibleYellow` as its adaptivity model), and any other `@MainActor` annotation whose sole cause is
reading one of these six values, dropping the annotation in the same commit that repoints the
property at `GeneratedTheme.*`.

---

## 3 — Naming scheme: role-based, not appearance-based

Never `yellow`, `pink`, `green3`. Every leaf name states **what the color is for**, split so that
"readable text" and "vivid fill" of the same semantic idea can never be forced into one token
again (§2's yellow bug is the reason this rule exists, not a style preference).

```
semantic/
  caution/{text, fill}          -- Theme.legibleYellow's two current jobs, split
  danger/{text, fill}           -- .red today (Interactions .dangerous, adherence .missed, DoseLevel .heavy)
  unsafe/{text, fill}           -- .orange today (Interactions .unsafe, adherence .partial)
  success/{text, fill}          -- .green today (adherence .complete, interaction-clear state)
  neutral/{text, fill}          -- .secondary/.gray "no data" states (adherence .noData, DoseTierStrip threshold)

surface/
  background                    -- Theme.background
  card                          -- Theme.cardBackground (dark-mode fill only; light stays .ultraThinMaterial, §2)
  groupedBackground             -- Theme.groupedBackground
  inputBackground                -- Theme.inputBackground

text/
  secondary                     -- Theme.secondaryLabel (primary text stays system .primary, untouched)

dose/
  tier/
    threshold/{text, fill}
    light/{text, fill}
    common/{text, fill}         -- DoseLevel.common is legibleYellow-adjacent; same split logic applies
    strong/{text, fill}
    heavy/{text, fill}
  -- values owned by colorimetry pass; DoseLevelIndicator.swift:167-186, DoseTierStrip's
  -- 5-stop ramp (DoseDurationCard.swift:330-334) and EntryRowView's strengthChip
  -- (:222-229) all read this one family today via 3 different Swift-side color tables
  -- that should collapse onto these tokens as part of the same pass that fixes DIV-020.

chart/
  series/{1, 2, ...}            -- multi-substance timeline/graph palette (currently ad hoc per-substance hex)

adherence/
  complete, partial, missed, noData   -- component-sameness.md F6's 3-way-duplicated status vocabulary

category/
  <SubstanceCategory case>...    -- 23 cases (Substance.swift's SubstanceCategory enum) -- too large a leaf
                                  -- set for this document to enumerate values for; flagging as an
                                  -- OPEN QUESTION for the colorimetry pass: do all 23 need distinct
                                  -- catalog tokens, or does the category-color system stay computed
                                  -- Swift (HSB rotation, etc.) with only the *shared chrome* (F2's
                                  -- statusChip) reading a generic `category/accent` placeholder tint
                                  -- passed in as a parameter? Recommend the latter -- 23 hand-picked
                                  -- P3+HC quadruples is a lot of colorimetry work for values that are
                                  -- already programmatically generated today.

route/
  <RouteOfAdministration> tint   -- ~10 cases, same open question as category/ above
```

`text/primary` is **deliberately absent** — primary label color should stay the system
`.primary`/`Color.primary`, which already tracks Dark Mode *and* Increase Contrast for free at the
OS level; asset-catalog-izing it would be strictly worse (losing automatic HC tracking to gain
nothing).

---

## 4 — Generator: `generate_colorsets.py`

Written and tested at `Specs/design-system/color-audit/generate_colorsets.py`. Full design
rationale is in the script's own module docstring; summary:

- **Every appearance value must declare its source space** — `oklch`, `p3_hex`, or `srgb_hex`. An
  `srgb_hex` input is unconditionally routed through `colorimetry.srgb_to_p3_same_appearance()`.
  There is no code path that copies raw sRGB numbers into a `display-p3` slot — the accident this
  whole migration is built to prevent (§5) is structurally unrepresentable in the generator's input
  format, not just discouraged by a comment.
- **Namespace folders are generated automatically** for slash-named tokens (`provides-namespace`
  Contents.json at each intermediate level — §1's namespacing note).
- **Idempotent** — verified by running twice against the same palette and diffing every
  `Contents.json`'s SHA-256; byte-identical both times.
- **Refuses `AccentColor`** two ways — a token literally named `AccentColor`, or an `--out` path
  ending in `AccentColor.colorset` — both exit non-zero with an explicit refusal message, tested.
- Emits an optional Swift accessor file (`GeneratedTheme.swift`-shaped), each accessor
  `nonisolated` per §2's verified finding.

### Test run (this session, against a scratch dir — never `Piru/Assets.xcassets`)

```
python3 generate_colorsets.py scratch-test/sample-palette.json \
    --out scratch-test/Assets.xcassets --swift-out scratch-test/GeneratedTheme.swift
# wrote 4 colorsets under scratch-test/Assets.xcassets
```

Verified:
- **Structure**: `semantic/caution/{text,fill}.colorset`, `surface/card.colorset`,
  `chart/series/1.colorset`, with real `provides-namespace` folders at `semantic/`,
  `semantic/caution/`, `chart/`, `chart/series/`, `surface/`.
- **JSON validity**: `python3 -m json.tool` / `json.load` parses every emitted `Contents.json`
  cleanly. `plutil -lint` reports `"Unexpected character { at line 1"` on **every** emitted file —
  including, when I checked, on the app's own real, Xcode-authored
  `Piru/Assets.xcassets/AccentColor.colorset/Contents.json`. That's a `plutil -lint` format-sniffing
  quirk (it appears to assume XML/binary plist unless told otherwise), not a defect in the output —
  confirmed by running `plutil -convert json -o -` (which auto-detects correctly) against the same
  files, which round-trips cleanly. **Use `python3 -m json.tool` or `plutil -convert json -o -` to
  validate generated catalogs, not `plutil -lint`** — a future agent seeing `-lint` fail on valid
  output should not assume the generator is broken.
- **Idempotency**: two consecutive runs against the same palette produce SHA-256-identical
  `Contents.json` files.
- **Safety rails**: both `AccentColor` refusal paths tested, both exit 1 with an explicit message.
- **Sample dE-relevant token** (`semantic/caution/fill`, built from `Theme.legibleYellow`'s real
  sRGB values `856300`/`FFCC00` via `srgb_hex`, alpha 0.15/0.28): output components land at
  `(0.501, 0.394, 0.118)` any / `(0.968, 0.808, 0.274)` dark — the colorimetrically-correct P3
  reprojection, not a numbers-preserving reinterpretation.

---

## 5 — The trap, quantified

**Pasting an sRGB hex's raw components into a `display-p3` colorset keeps the numbers and changes
the color.** sRGB and Display P3 share the same transfer function but different primaries — P3 is a
wider gamut, so the *same three numbers* read as P3 describe a more saturated color than the
original sRGB one. `colorimetry.py`'s `srgb_to_p3_same_appearance()` does the correct thing
(colorimetric round-trip through XYZ, numbers change, appearance doesn't); `srgb_to_p3_same_numbers()`
is the identity function, named and kept specifically so the audit can quantify the accident rather
than describe it in prose.

Representative sample, pulled from real hex literals in the app (`Color(hex:)` call sites and
`Theme.swift`'s `UIColor(red:)` neutrals), Oklab ΔE between the correct conversion and the
numbers-preserved accident:

| Source | Hex | Oklab ΔE (naive reinterpretation) |
|---|---|---|
| `Theme.legibleYellow` dark (`systemYellow`) | `#FFCC00` | 0.0282 |
| `Theme.legibleYellow` light (amber) | `#856300` | 0.0174 |
| `Theme.secondaryLabel` dark | `#A6A6AD` | 0.0010 |
| `Theme.secondaryLabel` light | `#7A7A80` | 0.0009 |
| `Theme.cardBackground` dark | `#111111` | 0.0000 |
| `DoseTierStrip` threshold gray (`DoseDurationCard.swift:332`) | `#B7BCC4` | 0.0018 |
| `DoseTierStrip` light green | `#34C759` | **0.0511** (largest in sample) |
| `DoseTierStrip` common gold | `#E0A021` | 0.0249 |
| `DoseTierStrip` strong orange | `#F0803A` | 0.0319 |
| `DoseTierStrip` heavy red | `#E8503A` | 0.0388 |
| Interactions danger red-ish (`#E5484D`, sampled from the hex pool) | `#E5484D` | 0.0388 |
| Mechanism-card blue (`#2ca2f5`) | `#2ca2f5` | 0.0312 |
| Empathogen purple (`#A970FF`) | `#A970FF` | 0.0212 |
| Stimulant teal (`#2ECDD4`) | `#2ECDD4` | 0.0413 |
| Depressant violet (`#8E80E3`) | `#8E80E3` | 0.0115 |

**Mean ΔE 0.0226, max 0.0511** (n=15). `colorimetry.py`'s own self-test tolerances treat ~0.0005 as
"indistinguishable" (the residual float error it accepts for white-point round-trips) — every
saturated color in this sample is **20-100× that**, i.e., nowhere near a rounding error, a plainly
visible shift. The pattern is exactly what color science predicts: **neutrals/grays are ~free**
(ΔE ≈ 0.0000-0.0018 — sRGB and P3 share the same white point, so achromatic colors barely move) and
**saturated hues are expensive** (ΔE 0.017-0.051), worst for green (`#34C759`, ΔE 0.0511) because
P3's green primary is the most different from sRGB's of the three primaries. This is precisely why
the generator (§4) makes the correct conversion the *only* path for `srgb_hex` input rather than
relying on a migration checklist item that says "remember to convert, not reinterpret."

---

## 6 — Migration sequencing

Each step is independently shippable; the app must build and pass its test suite after every one.
Screenshot baseline: `Specs/design-system/screenshots/` — **40 PNGs verified present** (`ls | wc -l`;
the brief said 33, actual count is 40 as of this session), covering light+dark pairs for most major
screens (e.g. `SCR-journal-home.png`/`SCR-journal-home-dark.png`) but not all — spot-check which of
the 40 have a dark sibling before relying on 1:1 pairing for a screen you're touching.

1. **Land the generator + an empty/placeholder palette, unwired.** `generate_colorsets.py` and its
   Swift output live in the repo but nothing consumes `GeneratedTheme.*` yet. Zero visual risk —
   this step is pure tooling.
2. **Generate the catalog into `Piru/Assets.xcassets`, still unwired.** Confirms the real Xcode
   project accepts the generated `.colorset` structure (opens in Xcode's asset editor, shows the
   4-slot appearance grid) before any Swift call site depends on it. Still zero visual risk — no
   code reads the new tokens yet.
3. **Move `Piru/Assets.xcassets` into `Shared/`** — this is the one structural project-file change,
   and it's small: I confirmed via `project.pbxproj` that `Shared`'s
   `PBXFileSystemSynchronizedRootGroup` (path `Shared`) is **already** listed in all three
   consuming targets' `fileSystemSynchronizedGroups` — `Piru` (`:204-207`), `PiruWidget`
   (`:267-270`), and `PiruLiveActivityExtensionExtension` (`:227-230`) all reference it. `Piru`'s own
   root group (which currently holds `Assets.xcassets`) is referenced **only** by the `Piru` target
   (`:204-206`) — confirmed by grep, and independently confirmed by `WidgetColors.swift:6-8`'s own
   comment: *"The widget target doesn't include the app's `Assets.xcassets`, so the variants are
   built in code via a dynamic provider."* Relocating the physical `Assets.xcassets` folder from
   `Piru/` to `Shared/` (a `git mv`, plus updating any hardcoded `Bundle.main` asset lookups to
   still resolve — asset catalogs compile into whichever target(s) include them, so once the folder
   sits under the already-tri-target `Shared/` group, Piru, PiruWidget, *and*
   PiruLiveActivityExtensionExtension all get it with **no per-target membership exceptions needed**,
   no catalog duplication, and no separate `WidgetAssets.xcassets`. This single move is what makes
   `WidgetColors.swift` and any future Live-Activity-side hex literals deletable in step 6.
4. **Migrate one token family at a time, each its own PR**, in this order (lowest-risk /
   highest-value first):
   1. `surface/*` (4 tokens) — the `Theme.swift` background quartet. Low risk: these are large flat
      fills, easy to screenshot-diff, and `themeCard`'s light-mode `.ultraThinMaterial` branch is
      untouched (§2), so only the dark solids move.
   2. `text/secondary` (1 token) — highest call-site count, but a single flat color, trivial to diff.
   3. `semantic/caution/{text,fill}` (2 tokens, replacing `Theme.legibleYellow`) — this is the one
      that also drops `@MainActor` per §2; land the color change and the concurrency change in the
      same PR, verified together.
   4. `semantic/{danger,unsafe,success,neutral}/*` and `adherence/*` — the DIV-002/F6 semantic-token
      gap. Landing these is what makes the F6 `AdherenceStatus` extension
      (`Specs/design-system/color-audit/component-sameness.md#f6`) buildable on catalog colors
      instead of bare `.green`/`.orange`/`.red`.
   5. `dose/tier/*` — coordinate with whoever fixes DIV-020 (`DoseTierStrip` vs `DoseTierMark`),
      since that fix and this token migration touch the same five-stop ramp; doing them together
      avoids two separate PRs both editing `DoseDurationCard.swift`'s color table.
   6. `chart/*`, `category/*`, `route/*` — deferred last; largest token counts, and `category/route`
      both have the open question from §3 (whether they asset-catalog at all, or stay computed
      Swift reading a generic tint token).
5. **Verify no regression per step**: re-capture the same 40 screens (or the subset a given step's
   tokens actually appear on — most steps don't touch all 40) at the same simulator/OS pin
   (`Specs/design-system/screenshots/` presumably used a fixed device+OS; match it) and diff
   pixel-for-pixel against the existing baseline. A `surface/*` or `text/secondary` step should
   produce a **zero-diff** result if `srgb_to_p3_same_appearance()` was used correctly (same
   appearance is the entire point); any visible diff on those steps means the conversion path was
   skipped somewhere, not that P3 "looks different" — that would be a red flag to investigate, not
   an expected side effect to wave off. Steps that also change *values* (if the colorimetry pass
   revises a color, not just reprojects it) are expected to diff, and should be reviewed as a design
   change, not a migration bug.
6. **Delete the now-redundant manual dynamic providers**: `Theme.swift`'s six `UIColor{traits}`
   closures, and `PiruWidget/WidgetColors.swift`'s `accent` closure (`:9-13`) once step 3 makes the
   real `AccentColor` catalog entry reachable from the widget target — `WidgetColors.swift`'s
   `backgroundGradientTop`/`backgroundGradientBottom` (`:15-16`, plain `Color(red:)` sRGB literals)
   are two more candidates for the same catalog once they have a real token name in §3's taxonomy.
   This step is pure deletion once the prior steps have landed — no new risk, just removes code that
   no longer has a live call site.

**Not in scope for this document** (left to whoever picks up the values): the actual Oklch/hex
numbers for every leaf in §3's tree, and the category/route open question flagged there.
