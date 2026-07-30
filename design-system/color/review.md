---
id: color-audit-review
type: review
description: Adversarial review of color-system.md / palette-L1.json / semantic-roles.md / scales.md / component-sameness.md — three verdicts (palette quality, rules, verification), with corrected values and a priority list.
edges:
  - {rel: reviews, target: color-system.md}
  - {rel: reviews, target: palette-L1.json}
  - {rel: reviews, target: semantic-roles.md}
  - {rel: reviews, target: scales.md}
  - {rel: reviews, target: component-sameness.md}
---

# Adversarial review: Piru color system proposal

Read `color-system.md`, `colorimetry.py`, `palette-L1.json`, `inventory.json`, `sampled.json`,
`semantic-roles.md`, `scales.md`, `component-sameness.md`, and the app source for the three named
bugs and the `RouteOfAdministration`/`Theme` definitions. Rendered the proposed palette against the
app's real accent color and the app's *current* (de facto, pre-migration) colors in a local HTML
swatch, screenshotted at `/private/tmp/claude-501/-Users-kirie-Developer-piru/4d9db6ed-3473-4efa-a7b5-c6827bf6f425/scratchpad/keep-0001.png`
(source: `palette-review.html` in the same directory). Every number below was recomputed
independently with `colorimetry.py`, not copied from the audit's tables.

## Verdicts

| Axis | Verdict |
|---|---|
| A — Is the palette good design? | **NEEDS WORK** |
| B — Are the rules right? | **SOUND, with one real internal contradiction to resolve** |
| C — Is the analysis correct? | **SOUND**, with one methodological slip (§ C.1) and one overstated claim (§ C.2) |

**Should it ship as-is: no.** Ship after (1) the free per-hue chroma fix in §A.2, (2) an explicit
product decision on the warning/caution tradeoff in §A.1, and (3) resolving the L3-text
contradiction in §B.2. None of these are large — this is a "fix four things" verdict, not a
"redo it" verdict.

---

## A. Palette quality — NEEDS WORK

### A.1 The rendered swatch confirms the "muddy" risk, but only for two of five tokens

Rendering all five tokens as text-on-card and as pills-on-own-fill, next to the app's real
`AccentColor` (P3 `(0.898,0.497,0.591)` light / `(0.920,0.268,0.441)` dark, read straight from
`Piru/Assets.xcassets/AccentColor.colorset/Contents.json`) and next to what the app **actually
ships today** for these five roles (`systemRed`/`systemOrange`/raw `.yellow`+`legibleYellow`/
`systemGreen`/`route.oral` blue):

- `danger` (`#AC3227`) and `success` (`#00782D`) read as reasonable, if slightly dusty, brick-red
  and forest-green. Not a regression worth blocking on.
- `info` (`#0068A5`) is a clean, appropriately rich blue.
- `warning` (`#905200`, "dark tan") and `caution` (`#7A6000`, "olive-brown") **do** read as muddy,
  drab, and — the word the brief used — institutional, sitting next to the current cheerful
  `systemOrange`/`systemYellow` they replace and next to the app's own candy-pink accent. This is a
  real, visible product regression for an app whose entire written voice is anti-clinical
  ("nobody here thinks you need *reducing*"). A user who has seen both versions would notice the
  app got duller. Screenshot: swatch panel 1 vs. panel 2 in `keep-0001.png`.

**But it is not an under-tuned choice — it's a gamut ceiling, and this is verifiable, not
eyeballed.** Sweeping every hue at `L=0.50` for the *maximum* chroma sRGB can render at all:

```
h=20 maxC=0.201   h=50 maxC=0.132   h=80 maxC=0.104
h=30 maxC=0.200   h=60 maxC=0.117   h=90 maxC=0.102  ← caution
h=40 maxC=0.157   h=70 maxC=0.108   h=100 maxC=0.104
```
(full sweep + script in the swatch's panel 4). `#7A6000` is already **at** the gamut cusp for h=90
at L=0.50 — there is no more-vivid yellow-brown obtainable at this lightness in sRGB, full stop.
Yellow's own MacAdam limit sits near Oklab L≈0.97 (pure `#FFCC00` is L=0.865); asking for a
legible-on-white yellow at L=0.50 is asking for a color near the bottom of that hue's *entire*
usable chroma range. `color-system.md:76-77`'s own "physically impossible" framing is correct — my
disagreement is only that the write-up doesn't surface *how close to the floor* the chosen values
already sit, which matters for judging whether the muddiness is fixable within the current recipe.

**Independent corroboration that this isn't an implementation slip: Apple ships the identical
compromise, but only behind Increase Contrast.** The HIG `color` skill's Increased-Contrast system
table gives light-mode Yellow as **`#A16A00`** (R161,G106,B0) and Orange as **`#C55300`**
(R197,G83,B0) — both olive/rust-brown, both computed here at L≈0.57–0.58, C≈0.12–0.16, i.e. the
*same family* as the proposed `#7A6000`/`#905200`. Apple's own accessibility team hit this exact
wall and shipped an equally muddy answer — **but only as an opt-in fallback for users who turn on
Increase Contrast**, not as what every user sees by default (which stays the vivid `#FFCC00`/
`#FF9500`). The proposal makes the Increase-Contrast-grade compromise the *default* for 100% of
users, every day. That's the real objection, and it's a product decision, not a math error:
**decide explicitly whether Piru holds the line at 4.5:1 for all users (current proposal, drab
warning/caution) or accepts something closer to Apple's own ~4.2:1 Increase-Contrast bar as the
default** (see next paragraph for what that buys). Either is defensible; leaving it implicit is not.

If the latter, there's a concrete, HIG-precedented alternative for `warning` specifically (not
`caution` — h=90 stays capped regardless of L): shifting hue from 63°→~46° and raising L from
0.50→~0.55–0.58 (matching Apple's own IC Orange, h=46, C=0.163, ratio≈4.2 on the card) yields a
noticeably warmer "marmalade" orange instead of "dark tan," at a ratio just under the strict 4.5
line but still comfortably clearing WCAG's own 3:1 bold/large-text bar and matching what Apple's
most accessible mode ships. Flagging as an option, not a recommendation — trading exact-AA-at-any-
size for warmth is a brand call.

### A.2 A real, free, zero-risk fix the proposal is leaving on the table

`palette-L1.json`'s `_meta` states chroma is "0.16 gamut-fitted per hue" — but 0.16 is a **flat**
target, and at `L=0.50` it is nowhere near the ceiling for every hue. Measured:

| Token | flat C=0.16 (proposed) | max chroma available at same L | headroom |
|---|---|---|---|
| danger (light) | `#AC3227`, C=0.16 | C=0.205 | **+28%**, unused |
| warning (light) | `#905200`, C=0.16→clipped to 0.114 | C=0.117 (basically already capped) | ~0% |
| caution (light) | `#7A6000`, C=0.16→clipped to 0.102 | C=0.102 | 0% |
| success (light) | `#00782D`, C=0.16→clipped to 0.145 | C=0.145 | 0% |
| info (light) | `#0068A5`, C=0.16→clipped to 0.126 | C=0.126 | 0% |
| success (**dark**) | `#81ED93`, C=0.16 | **C=0.244** | **+53%**, unused |
| danger (dark) | `#FFBFB5`, C≈0.076 | C≈0.071 (already capped) | ~0% |

Warning/caution/info are already gamut-clipped by `fit_chroma()` regardless of the 0.16 target —
so the "flat 0.16" framing is misleading for those three (it just never binds), but it **does**
bind for light-mode danger and, dramatically, dark-mode success. A per-hue near-max chroma
(`fit_chroma((L, 0.30, h), "srgb")`, i.e. "give me the most sRGB can do at this L/h," not "give me
min(0.16, gamut)") would make danger a richer `#BA0C09` (ratio improves 5.97→6.10) and dark success
a vivid `#1DFA6A` (ratio 13.04→13.39) at **zero contrast cost** — verified with `colorimetry.py`,
shown in swatch panel 3. Whether `#1DFA6A` (near-neon) is the right *taste* call for a "success"
state is a separate, real judgment (it may read as a bit gamer-HUD rather than clinical-calm) —
but the current proposal isn't even offering the choice, because the derivation caps every hue at
the same number regardless of what's available. **Recommend: replace the flat `C_target: 0.16`
with a per-hue max-safe-chroma derivation, review the resulting danger/success values for taste,
keep warning/caution/info as computed (they don't change).**

### A.3 Accent-hue proximity, not flagged anywhere in the existing docs

`AccentColor` sits at Oklch h≈6.3° (light) / h≈9.9° (dark), C≈0.155–0.24 — computed directly from
the asset catalog's P3 components, not estimated. Proposed `danger` sits at h=29°, ~20–23° away,
in the same warm red-pink family and at comparable chroma. `semantic-roles.md`'s §4 collision
matrix carefully checks all 48 `PresetColor` L3 entries against L1/L2 anchors (flagging Rose,
Tangerine, Mustard, Green as near-twins) but never runs the same check the other direction — L1's
own new `danger` token against the app's one hard-coded brand color. Under the doc's own "form, not
hue" rule (§B.1 below) this is tolerable (danger is always a filled pill + triangle icon; accent is
a plain button/link tint), so I'm not blocking on it — but it's worth a name-check in the audit
before shipping, since "Danger" and "Accent" now live 20° apart in a system that otherwise treats
20–25° separations as worth flagging (see the Tangerine-vs-warning entry at 2.1°, or note that
Coral at "the single worst hue position on the wheel" is itself ~15-25° from multiple anchors).

---

## B. Are the rules right? — SOUND, with one contradiction

### B.1 "Form, not hue" — confirmed by HIG, not just internally consistent

The HIG `color` distilled reference (loaded fresh for this review, tier-1 file, not cached from a
prior pass) states, on Liquid Glass specifically: *"Apply color sparingly: reserve for status
indicators or primary actions,"* and — the stronger statement — *"To emphasize primary actions,
color the **background** (not the symbol/text)."* That is Apple's own design system independently
arriving at the same status=filled-background principle the audit proposes for L1. Combined with
`accessibility.md`'s *"Never rely on color alone... add distinct shapes, icons, or labels,"* the
rule is not just internally defensible, it's the platform's own recommendation. And it's cheap:
`component-sameness.md` (F1, F2) shows the filled-pill-with-icon chrome (`ConfidenceBadge`,
`capsuleChip`/`heroChip`) **already exists and is under-adopted** — 8 call sites need rewiring, not
a redesign. Adopt as specified.

One thing worth noting for the implementers: HIG's phrasing goes slightly further than the audit's
own OFF-2(a) fix. "Color the background, not the text" would suggest a **solid, saturated fill with
neutral (primary-label or white) text** — the Mail-flag/destructive-button pattern — rather than
"derive a legible *text* color and put it on a faint 10% tint," which is what OFF-2(a) proposes.
The solid-fill approach sidesteps all of this document's careful Oklab contrast math entirely
(white-on-`#AC3227` solid is trivially ≥4.5:1; no per-hue lightness tuning needed) at the cost of a
visibly bolder, less "whisper-tinted" look than the app has today. Not recommending it over
OFF-2(a) — it's a bigger visual departure from Piru's current soft aesthetic — but it's a real,
HIG-native third option that wasn't on the table, and worth a conscious "we're choosing the softer
look on purpose" note rather than leaving it undiscovered.

### B.2 "L3 never renders as small text" contradicts the document's own OFF-2(a) fix — needs resolving before implementation

`color-system.md:79-82` (rule 3) is unconditional: *"L3 never renders as small text, ever... where
a substance must be labelled, the label uses text/primary and the identity color appears beside it
as a mark."* But §8's OFF-2(a) — the *recommended* fix for "the self-tint pattern (21 failing
pairs)" — is *"Derived text variant... Preserves hue identity, guarantees contrast. Recommended."*

The failing chip list in §3 (`sampled.json`, reproduced independently below) **is** the L3
identity-chip population: Vitamin D3, Caffeine, Magnesium, Alcohol, L-Theanine, Creatine,
Methylphenidate "frequently used" chips are simultaneously (a) textbook self-tint failures and
(b) exactly the L3 chips rule 3 says must never carry colored text. The document recommends fixing
population (a) with a derived-lightness *colored* text variant, while rule 3 says population (b)
must drop colored text altogether. Since (a) and (b) are the same nine chips, an implementer
following OFF-2(a) literally would ship colored Vitamin-D3-yellow text on those chips — which rule
3 explicitly forbids two pages earlier. The document never states which rule wins for the
overlapping case.

**Resolution, not just a flag**: apply the two fixes by layer, which is consistent with everything
else in the doc (L1 is meaning-bearing and needs the color to reach the reader; L3 explicitly
isn't, per the layer table's own "Meaning-bearing? no" row for L3):
- **L1/L2** (danger/warning/caution/success/info, route/dose-tier/category): OFF-2(a), derived text
  variant. The color *is* the message here.
- **L3** (frequently-used chips, any per-substance identity render as text): OFF-2(c), neutral
  `text/primary` + identity as a mark — but not necessarily the "leading dot" the doc suggests as
  the only option. `CapsuleChip.swift:33-40` already ships a bordered-outline chip grammar for
  exactly this "quiet, non-competing" register (`component-sameness.md` F3), used today for
  alias/tag chips. Routing L3 identity chips through that **existing** outline treatment (hairline
  stroke in the identity hue, neutral fill, `text/primary` label) is a genuine third option beyond
  "derive a legible variant" vs. "reduce to a bare dot" — it keeps the identity color visibly
  present (as a ring, not a wash), costs no new component, and never needs contrast math because the
  stroke is thin enough to fall under WCAG 1.4.11's 3:1 non-text bar, not 1.4.3's 4.5:1 text bar.

### B.3 APCA thresholds — too strict to be a hard gate, right as a diagnostic

Reproduced `colorimetry.py`'s own claim: Apple's default (non-increased-contrast) `secondaryLabel`,
flattened over the measured cards, scores **APCA 40.8 (light) / -65.9 (dark)** against a 90/75/60
sliding floor — i.e. it fails at literally every Piru font size in light mode and needs the
*largest-bold* floor (60) to pass in dark mode. That's the color every default iOS app on every
device ships as secondary text, read by users constantly without complaint. Two conclusions:

1. The 90/75/60 floors are a legitimate, well-calibrated **diagnostic** — they correctly surface
   that thin, small, colored text is a harder readability problem than WCAG 2.1's coarser luminance
   ratio credits it for. Keep computing and reporting them.
2. They are **too strict to gate a binary PASS/FAIL** the way `colorimetry.py`'s `verdict()`
   currently does (`"PASS" if (w["AA"] and abs(lc) >= need) else "FAIL"`) — that formula would mark
   Apple's own default secondary-text color a FAIL in three of four size/appearance combinations,
   which isn't a useful signal if the goal is "does this ship." **Recommend: decouple — WCAG AA
   (4.5:1/3:1, matching HIG's own explicitly stated bar in `accessibility.md`) stays the hard gate;
   APCA stays reported alongside every ratio as an advisory second opinion**, flagged for human
   judgment rather than auto-failing. This preserves the diagnostic value without silently
   asserting a stricter spec than either WCAG or Apple's own HIG actually requires.

### B.4 Does splitting every token into `.text`/`.fill` double the count? — No, and the doc already shows why

Checked `palette-L1.json` directly: `semantic/danger/fill` is not an independently authored color —
its entry is `"derivation": "danger/text at 0.10 alpha over surface/card", "alpha": 0.1`. In Swift
terms that's `dangerText.opacity(0.10)`, not a second asset-catalog color. Same pattern already
lives in shipped code: `RouteOfAdministration.swift`'s doc comment states its tint is *"used... as
both the badge text and its 0.16 fill"* — one token, one opacity modifier, not two colors. So the
`.text`/`.fill` split the brief worried about doubling the token count is, in the asset catalog,
**one token per role** (5, not 10) plus a documented `.opacity()` convention at call sites. The
"doubling" framing in the brief doesn't match what `palette-L1.json` actually specifies — worth
saying explicitly in the shipped doc so a future implementer doesn't "helpfully" author 10 colorset
entries instead of 5.

---

## C. Verification — SOUND, with one real slip and one overstatement

Everything below was recomputed independently against `colorimetry.py`/`sampled.json`/
`inventory.json`, not copied from the audit's own tables.

**Reproduced exactly:**
- `inventory.json` layer histogram: L1 62 / L2 53 / chrome 45 / L3 13 / ambiguous 13, total 186 —
  exact match via direct `Counter` over `sites[*].layer`.
- `sampled.json` headline claim: reconstructing the population split (5 `chart.*`-surface pairs,
  7 of 8 low-confidence pairs excluded — the 8th, a low-confidence chart pair, correctly retained in
  the chart bucket rather than the excluded pile — leaving 33 text pairs) reproduces **21/33 text
  fails at 4.5:1** and **4/5 chart pairs fail 3:1** exactly.
- All five `palette-L1.json` `verified.on_card_light/dark` and `on_own_fill_light/dark` numbers,
  recomputed from the stated hexes and 0.10-alpha composite: within 0.02–0.05 of the published
  figures (danger 5.97/12.01/5.47/5.72 vs. my 5.95/12.02/5.45/5.72 — rounding-level agreement).
- The dark-mode self-tint asymptote claim ("cannot reach AA at 0.18 alpha, max 4.48"): swept L from
  0.70→0.99 at C=0.16, h=90 — ratio climbs monotonically and tops out at **4.451** at L=0.99 (the
  practical ceiling, since L can't exceed ~1). Confirmed; at 0.10 alpha the same sweep clears 6.7 at
  the same L. The 0.10 vs 0.18 alpha recommendation is real and load-bearing, not decorative.
- `RouteOfAdministration`'s 5 routes that miss their own ≥4.5 target against their actual 16% fill:
  recomputed all 11 routes' hex pairs from `RouteOfAdministration.swift:76-89` directly — sublingual
  **4.02**, buccal **4.18**, other **4.19**, inhalation **4.25**, transdermal **4.32**, matching the
  doc's figures to the hundredth. The other 6 routes pass. Confirmed exactly.
- The P3 reinterpretation trap: systemGreen dE=**0.0511** (worst), neutral `#111111` dE=**0.0**,
  systemRed dE=0.0442 — matches the published table.
- The three named contrast bugs are real, at the cited lines, and `.labelColor` is the correct
  existing fix: `DoseLevelIndicator.swift:22` uses `level.swiftUIColor` where every other of the 11
  consumers uses `.labelColor`; `InteractionCheckerView.swift:166` and
  `InteractionTimelineView.swift:693-695` both read `.severity.color` where `Interactions.swift:38`
  (`self == .caution ? Theme.legibleYellow : color`) is sitting right there, unused, on the same
  type. Confirmed by direct source read, not by trusting the audit's citation.

### C.1 One real methodological slip — OFF-5's own numbers violate the document's own rule

`color-system.md` §8 OFF-5 claims: *"Light override beats system (WCAG 4.25 vs 2.20); dark override
loses (8.66 vs 11.04)."* Recomputing `Theme.secondaryLabel`'s actual stored floats
(`(0.48,0.48,0.50)` light / `(0.65,0.65,0.68)` dark, `Theme.swift:19-25`) against pure `#FFFFFF`/
`#000000` reproduces those exact numbers (4.246 / 8.659). But **that's the wrong background** — the
whole point of §2's "the light card is `#f5f5f5`, not white" finding is that contrast must be
measured against the *actual rendered* surface, not the idealized one. Recomputed against the
document's own measured card:

```
Theme.secondaryLabel LIGHT vs #f5f5f5 card:  WCAG 3.89   (not 4.25 — FAILS AA's 4.5 floor)
Theme.secondaryLabel DARK  vs #111111 card:  WCAG 7.79   (not 8.66 — still comfortably passes)
```

This is the identical "source-only reasoning" error §2 explicitly warns against, now inside the
audit's own OFF-5 entry. It changes the recommendation: `Theme.secondaryLabel` in light mode is not
a clean "already correct, just adopt the system dark value" case — it's a **second, real contrast
bug** (3.89 < 4.5) at 566 call sites, most of which presumably render on a themed card rather than
the app's plain `.systemBackground`. Whether it actually fails in practice depends on which of the
566 sites sit on `Theme.background` (near-white, would pass) vs. a `themeCard()` (measured
`#f5f5f5`, fails) — a split the current OFF-5 entry doesn't make. **Recommend: re-run OFF-5 against
both real surfaces before treating it as settled**, and don't ship the "keep light, adopt dark"
recommendation as-is until that split is done.

### C.2 One overstated claim — the "L ≤ 0.54" ceiling is hue-dependent

§3 states: *"To clear 4.5:1 as 11pt text on its own 12% tint in light mode, a color needs Oklab
L ≤ ~0.54."* Sweeping L at fixed C=0.16 across the five status hues against a 12% self-tint:

```
h=29  (danger)   L=0.54 → ratio 4.54  (passes)
h=350 (pink)     L=0.54 → ratio 4.59  (passes)
h=63  (warning)  L=0.54 → ratio 4.35  (FAILS)
h=90  (caution)  L=0.54 → ratio 4.22  (FAILS)
h=148 (success)  L=0.50 → ratio 4.66  (passes; L=0.54 fails at 3.93)
h=245 (info)     L=0.50 → ratio 4.92  (passes; L=0.54 fails at 4.17)
```

`L≤0.54` only holds for the red/pink quadrant of the wheel; for orange/yellow/green/blue the real
ceiling is closer to **L≤0.50** — which is, reassuringly, exactly what `palette-L1.json` actually
used (its light `_meta.L_text_light` is 0.50, not 0.54). So the *chosen values* are unaffected —
this doesn't change any shipped number — but the **general rule as stated** would mislead someone
tuning a sixth hue later (e.g., a future `neutral` or a hue-shifted `warning`) into thinking 0.54 is
a safe ceiling everywhere. It isn't. Minor, but worth a one-line correction: state the ceiling as
hue-dependent, or just cite the 0.50 actually used and drop the generalization.

### C.3 Sampling-methodology note, not a defect

Of the 8 samples flagged `median_confidence: low`, 5 cluster in one failure mode: small,
anti-aliased dark-mode discs/pills (`PX-051/053/055` dose-tier discs, `PX-004/033` route pills) —
suggesting the clustering method is systematically less reliable on small, low-contrast,
anti-aliased shapes in dark mode specifically, not randomly distributed. This doesn't invalidate any
published number (the low-confidence ones are correctly excluded), but if a re-measure pass happens,
prioritize dark-mode dose-tier discs and route pills first — that's where the method is weakest.

---

## Priority list — what must change before implementation

1. **Decide the warning/caution tradeoff explicitly** (§A.1) — hold 4.5:1 for all users (current,
   drab) vs. accept an Apple-IC-grade ~4.2:1 default for a warmer amber/orange. Product/brand call,
   not an engineering one. Blocks nothing else; can be decided in parallel.
2. **Switch chroma derivation from a flat `C=0.16` target to per-hue near-gamut-max** (§A.2) — free,
   zero contrast cost, verified. Review the resulting richer `danger`/dark-`success` for taste
   before locking `palette-L1.json`.
3. **Resolve the L3-text contradiction** (§B.2) before any chip migrates — apply OFF-2(a)'s derived
   text variant to L1/L2 only; route L3 identity chips (Vitamin D3, Caffeine, etc.) through the
   existing `capsuleOutlineChip()` grammar instead, not a derived colored-text variant.
4. **Re-run OFF-5 against both real surfaces** (`Theme.background` vs. `themeCard()`) before
   shipping its "keep light, adopt dark" verdict — light mode may need its own fix, not just an
   adoption of the system dark value.
5. **Decouple APCA from the hard PASS/FAIL gate** (§B.3) — WCAG AA (matching HIG's stated bar)
   gates; APCA reports alongside as an advisory number, not an auto-fail.
6. Everything else in `color-system.md` §9's sequencing (OFF-1 label-color swap, the `Assets.xcassets`
   move, the L2 dedup work, high-contrast variants) is independently sound and can proceed as
   written — none of it depends on 1–5 above.

## Biggest single objection

The palette is contrast-rigorous but not yet a palette a designer would sign off on unreviewed:
**warning and caution read as muddy/institutional next to the app's own candy-pink brand accent**,
confirmed by direct rendering (not just eyeballing the hex codes), and — the sharper point —
this is the *exact* compromise Apple itself ships only behind an opt-in Increase Contrast toggle,
not as every user's default. Piru's whole voice is "you don't need reducing"; shipping every user
the Increase-Contrast-grade amber by default, with no attempt to claw back any of the free
chroma headroom that the flat 0.16 target is leaving unused elsewhere in the same file (§A.2), reads
as the audit optimizing the metric it measured (contrast) without checking the metric it didn't
(does this still look like Piru). Fixable in an afternoon; just not yet done.
