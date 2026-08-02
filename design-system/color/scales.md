---
id: scales
type: analysis
description: Every ordered/nominal color scale (L2) in Piru — complete ordered values, light/dark, role, font, and file:line. Raw material for the colorimetry (Oklch/contrast) pass; no Oklch or contrast computed here.
---

# Color scales (L2) — raw material

Companion machine-readable file: `Specs/design-system/color-audit/scales.json` (12 scales, fully
enumerated, no truncation). This file is the narrative walkthrough plus the three flag categories
requested. **No Oklch or contrast math below** — every "flag" that depends on perceived lightness
or contrast ratio is explicitly marked as an eyeballed candidate for you to verify, not a
computed result.

Framing: L1 (closed semantic set) and L3 (per-substance identity) are out of scope here — owned
elsewhere. Where an L2 scale collides with an L3 identity color at the same call site (found once,
in Inventory — see §7), it's flagged as a boundary issue, not resolved.

---

## 1. Route of administration — `route_tint` (nominal, 11)

`Shared/RouteOfAdministration.swift:76-89`, consumed via `:69-74`. The reference case in this
whole audit: 11 routes, each with a **hand-tuned, separately-authored light/dark hex pair**, and a
doc comment (`:65-68`) stating exactly why: *"as ~11pt text on a near-white card several hues fail
small-text contrast (orange/green worst), so light mode darkens each toward ≥4.5:1 while keeping
the hue identity."* Full 11×2 table is in `scales.json#route_tint` — oral/sublingual/buccal/
insufflation/inhalation/intravenous/intramuscular/subcutaneous/transdermal/rectal/other. Role: text
+ 16% fill (`ROAPill`, `.caption2`/`.caption.weight(.semibold)` depending on density).

---

## 2. Dose level — `dose_level` (ordered, 6) — **three coexisting encodings**

`Sub-threshold → Threshold → Light → Common → Strong → Heavy`. Found **three independent
encodings** of this one scale:

1. `Substance.swift:171-188` — `DoseLevel.color: String`, returning raw words (`"gray"`, `"blue"`,
   …). Grepped for consumers app-wide: **zero found** outside its own declaration. Flagging as
   likely-dead rather than asserting — worth a quick confirm before deleting.
2. `DoseLevelIndicator.swift:167-177` — `swiftUIColor`, the fill/dot color. Bare system colors
   (`.gray/.blue/.green/.yellow/.orange/.red`), one value per step, no custom light/dark tuning
   (relies on iOS's own dynamism).
3. `DoseLevelIndicator.swift:183-186` — `labelColor`, the "legible text variant." **Identical to
   `swiftUIColor` for 5 of 6 steps** — only `.common` diverges, swapping bare `.yellow` for
   `Theme.legibleYellow` (a real, hand-tuned light/dark pair: amber `(0.52, 0.39, 0.0)` in light,
   system yellow in dark).

**Bug found during extraction**: `DoseLevelIndicator.swift:18-23`'s own level-name text —
`Text(level.displayName).foregroundStyle(level.swiftUIColor)` — uses `swiftUIColor`, **not**
`labelColor`. I checked all 11 other places `DoseLevel`'s color reaches a view (`scales.json`'s
`consumers` array) and every other one correctly reads `labelColor`. This one, rendered at
`.subheadline.weight(.semibold)`, is the ladder header on the **Edit**-dose screens (`DoseInfoView`
via `EntryFormView.swift:264` / `EntryEditContent.swift:136`) — exactly the failure
`Theme.legibleYellow`'s own doc comment says it exists to prevent, just not wired to this one call
site.

---

## 3. Experience phase — **two conflicting definitions**

**Definition A**, `experience_phase_hex_ramp` (5 steps, hex): `onset #9B9BA1 → comeup #3A8DEF →
peak #34C759 → offset #FF9F0A → after #9B9BA1`. Verbatim-identical across
`SessionReportPDF.swift:10-14` and `DosePhaseProgressBar.swift:24-28` — confirmed intentional, not
drift (`SessionReportPDF.swift:8`: *"matches DosePhaseProgressBar so the export reads like the
app"*). `TimelineGraphView.swift:1942-1945` wires the same 4 leading hex literals as background
bands on the main graph (`:1975`, `.opacity(0.12)`). Screens: Journal home's "Active Now" card,
dose detail read view, the exported PDF, the main timeline graph.

**Definition B**, `experience_phase_system_ramp` (5 steps, system colors):
`onset .blue → comeup .teal → peak .orange → offset .purple → afterglow .systemGray3` —
`DoseLevelIndicator.swift:127-163`. Screens: the substance-detail "Duration" card and
`DurationTimelineBar`/`DurationPhaseRows` (`DurationViews.swift`), both reached from the Edit-dose
flow (`EntryFormView.swift`, `EntryEditContent.swift`).

**These conflict directly**: `peak` is green in A, orange in B; `comeup` is blue in A, teal in B.
They don't render on literally the same screen at the same instant, but they trace back to the
**same dose entry** — edit it (B's colors) then view it (A's colors) and "peak" visibly flips hue.
Both scales are internally **non-monotonic by design** — they're a narrative arc (quiet → build →
crest → cool → quiet-again), not a magnitude ramp, and definition A's first/last steps are
literally the same gray on purpose. Flagging this so it isn't miscategorized as a broken intensity
scale during the lightness pass.

---

## 4. Interaction severity — `interaction_severity` (ordered, 3)

`caution (yellow) → unsafe (orange) → dangerous (red)`, `Interactions.swift:9-38`. Same `color`/
`labelColor` split as dose level, same asymmetry: only `caution` gets the `Theme.legibleYellow`
swap in `labelColor`; the other two steps are identical between the two accessors.

**Two more contrast bugs found**, same shape as §2's:
- `InteractionCheckerView.swift:166` — the *"N Interaction(s) Found"* results header —
  `.foregroundStyle((results.first?.severity ?? .caution).color)`. Font: `.caption.weight(.semibold)`
  plus `.textCase(.uppercase)` — the smallest, boldest, most compressed text in this whole set,
  raw system yellow when the top result is `.caution`.
- `InteractionTimelineView.swift:693-695` — the warning-card title (`"{severity.label}:
  {substanceA} + {substanceB}"`) — `.foregroundStyle(severity.color)` at `.subheadline.weight(.semibold)`.

Six confirmed-correct consumers (using `labelColor`) are listed in `scales.json`; a seventh
possible site at `InteractionTimelineView.swift:512` is flagged low-confidence — I didn't get to
confirm whether it's text or icon-only, worth a quick re-check before acting on it.

---

## 5. Adherence status — `adherence_status` (nominal-ish, 4)

Raw values: `complete (green) / partial (orange) /
missed (red) / noData (secondary)`, hand-declared **three times** in `AdherenceView.swift` with
agreeing hues but disagreeing icon glyphs (bare vs. circle-composited) and one path (the monthly
rate percentage, `:152-155`, `.system(.title2, design: .rounded, weight: .semibold)`) that isn't
even keyed off the shared enum — it's a separately-invented `rate >= 0.8/0.5` threshold.

---

## 6. Dose-tier / dose-intensity — **a third scale for the same "how strong" question**

Beyond §2's `dose_level`, there are two *more* independent 5-/6-step dose-intensity color scales:

- `dose_tier_strip` (5 steps: Threshold/Light/Common/Strong/Heavy) —
  `DoseDurationCard.swift:328-334` — `#B7BCC4 → #34C759 → #E0A021 → #F0803A → #E8503A`, rendered as
  growing filled discs (diameters 7/10/13/15/18).
- `dose_intensity_dial` (6 steps: **Threshold/Light/Common/Strong/Heavy/Overdose** — the only one
  of the three with a top-end "Overdose" label) — `DoseIntensityCard.swift:26-29` —
  `#34C759 → #8ED04A → #E0B93A → #E8940C → #E5613D → #E5484D`, rendered on a circular arc gauge.
  Text-bearing: the big center readout is `.system(size: 27, weight: .heavy, design: .rounded)`
  (colored only for the Overdose step, else `.primary`); the band-name label under it is
  `.subheadline.weight(.semibold)`, colored by the scale on every step.

Three scales, three step counts (6 / 5 / 6), three different greens for "Light"
(system `.green` / `#34C759` / `#8ED04A`) — none of them the same value.

---

## 7. Inventory — `stock_status` vs. a colliding L3 identity tint

`StockStatus` (`InventorySupport.swift:8-64`) is a deliberate **3-step, mostly-neutral** scale —
its own comment states the house rule: *"color carries meaning only for Low/Out; a healthy supply
reads neutral."* `ok → .primary (35% for the bar)`, `low → .orange`, `out → .red`. Both its
`numberColor` and `barTint` accessors agree exactly (unusual among these scales).

Flagging the boundary case explicitly since it's an L2/L3 collision, not a pure L2 issue: a
**second**, unrelated bar-tint path exists for the exact same `InventoryItem` —
`InventoryItem.supplyBarTint` (`InventorySupport.swift:74-80`) uses the **substance's own identity
color** (L3, at 0.5 opacity) instead. `SubstanceCardView.swift:175` and
`InventoryStockSection.swift:81` use `StockStatus.barTint`; `supplyBarTint` is a separate,
independently-called accessor on the same type — two color systems (status vs. identity) both
competing for one visual slot.

---

## 8. Tolerance bar bands — **not a 5th ramp; correcting an assumption**

`ToleranceRow.swift:44-59`. Worth stating plainly since the brief expected a green→red ramp here:
**this is not one.** Each of the three bands (Tachyphylaxis/Tolerance/Deep) is the **same**
receptor-family identity color (`familyColor`, an L3-style per-mechanism hue) at three fixed
alphas — 0.5, 0.82, 1.0 — ordered fast-timescale-to-slow. It's an alpha-ordered scale built on top
of one identity color, not a semantic hue ramp. `ToleranceBucket` (`ToleranceRow.swift:257-285`,
5 word-only cases: rested/mild/moderate/high/veryHigh) supplies the spoken word only — I found no
`.color` property on it; the rendered color always comes from `familyColor`.

---

## 9. Substance category — `substance_category` (nominal, 29)

`Substance.swift:774-803` (cases), `:2069-2101` (color). 29 cases, no ordering. The systemic finding:
**9 of 29** (`dysdelic`, `deliriant`, `ampakine`, `eugeroic`, `depressant`, `orexinAntagonist`,
`antihistamine`, `peptide`, `anticonvulsant`) are plain `Color(red:green:blue:)` literals with
**zero** light/dark tuning — the identical pixel renders in both appearances. The other 20 use bare
system color names (some `.opacity()`'d), which get free system-level light/dark adaptation, but
that's Apple's default curve, not anything Piru chose — unlike §1's route scale, which is the one
place in the app where every step got deliberate per-appearance attention.

---

## 10. Chart structural chrome (`TimelineGraphView.swift`)

Not per-substance identity (that's L3, out of scope) — the fixed alpha vocabulary layered under
whichever identity color a given curve uses. Full table in `scales.json#chart_structural`; headline
entries: fill-under-curve `0.16`, curve stroke `0.9`, emphasis-fade gradient `0.2→0.85`, phase
background bands `0.12` (reusing §3 Definition A's hex ramp), gridlines ranging `0.08–0.55` depending
on role, now-line `0.7`. Two fixed vitals lanes: HR `rgb(0.898, 0.290, 0.310)`
(`VitalsPalette.heart`, `SessionVitals.swift:7`), BP `rgb(0.231, 0.490, 0.847)`
(`VitalsPalette.bloodPressure`, `:8`) — both single literals, no dark-mode variant.

**The smallest text-bearing scale entry found in the entire audit**: axis label text,
`.system(size: 10, weight: .medium, design: .rounded)` at `primary.opacity(0.6)`
(`TimelineGraphView.swift:2323,2387`) — 10pt, well under the 13pt threshold you asked me to flag.

---

## Flags (per your three categories)

### Non-monotonic in perceived lightness (eyeballed, not computed — needs your Oklab pass)
- `dose_level.swiftUIColor` — yellow sits at position 3 of 6, reading as the single brightest step
  sandwiched between darker neighbors on both sides. Classic non-monotonic shape by eye.
- `experience_phase_hex_ramp` / `experience_phase_system_ramp` — **both intentionally
  non-monotonic** (a narrative arc returning toward its starting neutral, not a magnitude ramp).
  Don't flag these as broken — flagging the *interpretation* risk instead, so the lightness pass
  doesn't miscategorize a deliberately-arced scale as a defective ramp.
- `dose_tier_strip` / `dose_intensity_dial` — both look like plausible monotonic-decreasing-L
  ramps by eye, but disagree with each other and with `dose_level` on the exact green used for
  "Light" (§6) — worth checking whether the three are at least mutually consistent, not just each
  internally monotonic.

### Scales overlapping L1 status meanings
- `dose_level.common` and `interaction_severity.caution` terminate on the literal same two-value
  pair (`Theme.legibleYellow`) — a confirmed shared reference, not coincidence.
- `adherence_status.missed`, `interaction_severity.dangerous`, `stock_status.out`, and
  `substance_category.opioid` all use bare system `.red` — plausibly fine (red-for-danger is a
  defensible universal) but worth confirming none of these will collide unexpectedly once a
  `semantic/danger` asset-catalog token exists and some of these move onto it while others don't.

### Light and dark are not the same scale
- `substance_category` — 9 of 29 cases are single literals with no dark variant at all (§9).
- `dose_level.swiftUIColor` — every step is a single system-color declaration (implicitly
  system-dynamic) **except** `.common`'s `labelColor`, the one step with an explicit, Piru-authored
  light/dark pair — an inconsistency inside an otherwise-uniform scale.
- `experience_phase_hex_ramp`, `dose_tier_strip`, `dose_intensity_dial` — all `Color(hex:)`
  literals, and because `Color(hex:)` constructs in sRGB only, every step in these three scales is
  unambiguously one fixed value for both appearances today.

---

## Summary

| Scale | Cardinality | Steps | Text-bearing entries found | Notes |
|---|---|---|---|---|
| Route tint | nominal | 11 | `.caption2`/`.caption` (11pt/12pt) | Reference case — fully tuned |
| Dose level | ordered | 6 (×3 encodings) | `.subheadline` (15pt) **BUG**, `.caption2` (11pt), `.caption` (12pt) | 1 dead encoding, 1 contrast bug |
| Experience phase (hex) | ordered/arc | 5 | none scale-colored | Conflicts with system-ramp variant |
| Experience phase (system) | ordered/arc | 5 | not fully captured, re-verify | Conflicts with hex variant |
| Interaction severity | ordered | 3 | `.caption` (12pt) **BUG**, `.subheadline` (15pt) **BUG** | 2 contrast bugs found |
| Adherence status | nominal | 4 | `.headline`, `.title2` | 3× duplicated declaration |
| Dose tier strip | ordered | 5 | none scale-colored | 3rd dose-intensity scale |
| Dose intensity dial | ordered | 6 | `.subheadline` (15pt), 27pt display number | 3rd dose-intensity scale |
| Stock status | ordered | 3 | not separately fonted, re-verify | Deliberately mostly-neutral |
| Tolerance bands | ordered (alpha) | 3 | n/a (fill only) | NOT a hue ramp — alpha of one identity color |
| Substance category | nominal | 29 | n/a (fill/icon only) | 9/29 have no dark variant |
| Chart structural | n/a | — | `.system(size: 10)` **smallest found** | Axis labels under 13pt threshold |

**3 genuine contrast bugs found during extraction** (raw `.color` used where `.labelColor` exists
and every sibling consumer uses it): `DoseLevelIndicator.swift:18-23`,
`InteractionCheckerView.swift:166`, `InteractionTimelineView.swift:693-695`. All three are
text-bearing at ≤15pt, all three render pure system yellow when their respective scale is at its
"caution"/"common" step in light mode — precisely the failure mode `Theme.legibleYellow` exists to
prevent, just not wired to these particular call sites.
