# Piru color system — the three layers, and where they collide

Companion to `inventory.json` (now carries a `layer` field per site: `L1`/`L2`/`L3`/`chrome`/`ambiguous`).
Read-only pass over app code; this file and the `inventory.json` update are the only writes.

## 0. The reframe

Piru's color usage isn't one system with bugs — it's **three systems sharing one namespace**:

- **L1 — Semantic status.** A closed set of meanings: danger / warning / caution / success / info / neutral.
- **L2 — Encoding scales.** Multi-valued, still meaning-bearing: 11 routes (nominal), 6 dose levels (ordered),
  5 experience phases (ordered — two *conflicting* value sets exist for this), 3 interaction severities
  (ordered), 23 substance categories, 14 library families, 11 tolerance mechanism classes, 5 effect
  domains, 5 effect lenses.
- **L3 — Identity.** Per-substance color, carrying **no** meaning — user-picked, or auto-assigned via
  `PresetColor.deterministic` (`SubstanceColor.swift:72-78`, FNV-1a hash of the lowercased name mod
  palette size).

**Correction to the brief**: the L3 palette (`PresetColor.all`, `Shared/Models/SubstanceColor.swift:80-145`)
has **48 entries** (16 named families × Light/base/Dark), not 31 — confirmed by `grep -c 'PresetColor(hex:'`.
The collision matrix below uses the real 48.

The structural bug, restated: **L3 draws arbitrarily from a palette that overlaps L1's and L2's hues.**
A substance dyed "Mustard" by an FNV-1a hash renders in the exact hue of a caution badge. Nothing about
the render — no shape, no icon, no position — distinguishes "this happens to be Mustard-colored" from
"this is a caution." Sections 3 and 4 below make this demonstrable, not just asserted.

---

## 1. Layer histogram

Computed over the 186 individually-detailed sites in `inventory.json` (bulk-rolled `Theme.secondaryLabel`/
`Theme.accent` pairs excluded from this count — they're tagged `chrome` in `observations.theme_token_pairs`
as a block, since they're overwhelmingly generic text/icon tint, not status-bearing):

| Layer | Count | What's in it |
|---|---|---|
| **L1** (semantic status) | 62 | Severity, confidence tiers, safety banners, success/error text, destructive actions, adherence ladder, "due now" badges |
| **L2** (encoding scales) | 53 | Routes, dose levels, phases, categories, families, mechanism classes, effect domains/lenses, chart-series comparisons |
| **L3** (identity) | 13 | PresetColor/UserColor definitions + render sites, per-substance curve/marker/chip colors |
| **chrome** | 45 | Backgrounds, materials, brand accent (as brand, not status), PDF layout ink, decorative icon tints, third-party brand marks |
| **ambiguous** | 13 | Sites that genuinely straddle two layers — see §2 |

L1 (62) and L2 (53) are both far bigger than L3 (13) in raw site count — most of the app's color *usage* is
status/encoding, not identity. But L3's 48-entry palette is what actually collides with the other two,
because it's the only layer whose color is chosen **without regard to meaning at all**.

## 2. The 13 `ambiguous` sites — cross-layer collisions, not gaps in classification

Every `ambiguous` site is ambiguous because the **code itself** blurs the boundary, not because I couldn't
decide. Six distinct patterns:

1. **One token serving both L1 and L2** — `Theme.legibleYellow` (`Piru/Theme.swift:12`) is applied to
   `InteractionSeverity.labelColor` (`Piru/Data/Services/Interactions.swift:37-39`, L1 caution) **and**
   `DoseLevel.labelColor` (`Piru/Views/Components/DoseLevelIndicator.swift:183-186`, L2 dose tier) — the
   identical color definition crosses the layer boundary by design. Screenshot-confirmed collision, §3.
2. **An L2 color reused for an L1-shaped meaning** — `PharmacologyHero.swift:282`'s "agonist" green
   (`rgb(0.11,0.48,0.20)`) is reused at `PharmacologyHero.swift:240` and `PharmacologyRows.swift:116` to mean
   "this data point is human, not animal" — a trust/provenance signal, which is an L1 concept, wearing an
   L2 taxonomy color.
3. **A UI convention masquerading as L1** — the favorite-star `.yellow`
   (`SubstanceLibraryView.swift:79,399`, `SubstanceSearchField.swift:118`) isn't part of the
   danger/warning/caution/success/info/neutral set at all; it's the OS-wide "favorite = yellow star"
   convention (Mail, Files, Reminders). It collides with L1 caution-yellow by coincidence, not design.
4. **Functional action tint wearing warning orange** — swipe-action "Edit" tints
   (`DayEntryRow.swift:58`, `SessionDetailView.swift:427`) use plain `.orange`, indistinguishable in code
   from every genuine caution/warning site.
5. **Brand accent pressed into L1 service** — `Theme.accent` used as a "this is due now" status signal
   (`MyMedsCard.swift:488,548-549`), and `WidgetColors.accent` doing the identical job independently in the
   widget target (`TodayMedsWidget.swift:330,485,535`) — brand identity color moonlighting as status,
   in two unrelated codebases that solved the same problem differently.
6. **A 3-way mix in one ternary** — `TodayMedsWidget.swift:535`'s check-circle stroke is
   `done ? .green : (due ? WidgetColors.accent : .primary.opacity(0.25))` — L1 status, brand chrome, and
   generic system gray, three different color *mechanisms*, one state indicator.

## 3. Screenshot join

Two evidence sources, both cited per row: my own direct reads of the PNGs in `screenshots/`, and
`sampled.json` / `sampled-contactsheet.png` (produced by the sibling `pixel-sampler` agent — 145 patch
samples + 45 fg/bg pairs, real per-channel medians off the actual screenshots, sRGB raw). I did not
recompute their pixel data; I cross-referenced it against the code-level inventory and read what a user
would take the color to mean. Where I opened a screenshot directly, that's noted as "direct read"; where I
relied on a pixel-sampler ID, that's cited as `PX-NNN`.

I checked the `screenshots/` directory for new files before writing this — still 37 PNGs, unchanged from
what `README.md`'s screen nodes map; nothing new landed from `pixel-sampler` since my last check.

### 3a. Confirmed alignment (code meaning = what a user reads)

| # | Screenshot | Region | Code says (layer.semantic) | User reads | Verdict |
|---|---|---|---|---|---|
| 1 | `SCR-journal-home-dark-v2.png` (`PX-003/004`) | "oral" pill, Active Now card | L2 `route.oral`, `RouteOfAdministration.swift:78` | "this dose was taken orally" — neutral, informational | Aligned |
| 2 | `SCR-session-detail-dark.png` (`PX-032/033`) | "oral" pill next to Methylphenidate | L2 `route.oral` | Same reading, same screen family | Aligned — text hex `#0a84ff` sampled matches my code-derived dark value exactly |
| 3 | `SCR-insight-adherence.png`, direct read | Calendar heatmap: green ✓ / orange half-circle / red ✗ | L1 `adherence.day.complete/partial/missed`, `AdherenceView.swift:425-433` | Unambiguous pass/partial/fail ladder | Aligned — the one place in the app where an ordered L1 ladder reads exactly as intended |
| 4 | `SCR-tool-interactions.png` (`PX-118-129`) | "Frequently used" chips: Caffeine/Vitamin D3/Magnesium/Alcohol/L-Theanine/Creatine | L3 identity, `PresetColor`/deterministic hash | "these are the substances I log often" — no severity implied | Aligned in *intent*, but see 3b — Vitamin D3's chip is nearly unreadable |
| 5 | `SCR-substance-detail-caffeine.png`, direct read | "STIMULANT" badge | L2 `substance.category-color`, `Substance.swift:2071` (`.orange`) | "this is in the stimulant family" | Aligned, but see 3b for the collision this sets up |
| 6 | `SCR-library-home.png` / `-dark.png` (`PX-008-012,140-144`) | Family gradient cards (Common/Stimulants/Empathogens/Hallucinogens/Cannabinoids) | L2 `family.*`, `LibraryTaxonomy.swift:160-306` | "these are effect-family groupings" | Aligned |
| 7 | `SCR-session-detail-dark.png` (`PX-041/042`) | PK curve stroke, blue | L3 `substance.curve-stroke` | "this is Methylphenidate's curve" | Aligned — pixel-sampler's own note confirms the stroke is the app's Azure preset (`#2ca2f5`), not raw systemBlue |

### 3b. Screenshot-verified collisions (the finding, not the assertion)

| # | Screenshot | Region | Code says | User reads / collides with | Verdict |
|---|---|---|---|---|---|
| 8 | `SCR-entry-detail.png`, direct read | "common" dose-tier pill AND the "Alcohol + Caffeine … caution" pill, **one row apart on the same screen** | `DoseLevel.labelColor` (`DoseLevelIndicator.swift:183-186`) and `InteractionSeverity.labelColor` (`Interactions.swift:37-39`) both resolve through `Theme.legibleYellow` | Both pills render in the **same** muted tan/olive — a user cannot tell "this dose is in the common range" (L2, purely descriptive) from "this combination needs caution" (L1, a safety signal) by color alone | **Smoking gun** — the exact ambiguous case #1 in §2, now visible on one screen |
| 9 | `SCR-tool-interactions.png` (`PX-118/119`) + `SCR-substance-detail-caffeine.png` direct read + any orange safety banner (e.g. `AcetaldehydeCard.swift:55`, screenshot not captured but code-confirmed identical `.orange`) | "Caffeine" identity chip (orange), "STIMULANT" category badge (orange), and the app's ~20 warning-banner icons (orange) | L3 identity (arbitrary hash landed on orange) / L2 category (`.stimulant` = `.orange`) / L1 warning | Three unrelated meanings, one hue, demonstrable across two real screens plus a confirmed code path for the third | Three-way collision, the clearest case for the whole audit |
| 10 | `SCR-substance-detail-caffeine.png`, direct read | Route **picker** pills ("Oral" selected = solid brand-pink fill/white text; "Insufflation"/"Inhalation" unselected = plain gray) | Confirmed via `PX-046-049`: fill `#ff2d6f` (dark) / route picker uses `Theme.accent`, **not** `RouteOfAdministration.tintColor` at all | A route rendered as a read-only badge elsewhere (finding #1 above) uses its L2 route-blue; the *same* route rendered in the picker uses generic accent-pink with zero route-color signal | L2 identity is silently dropped in one of its two render contexts — internal L2 inconsistency, not just an L1/L2/L3 boundary issue |
| 11 | `SCR-substance-detail-caffeine-dark.png` (`PX-050-059`), cross-checked against `DoseDurationCard.swift:331-333` | Dose-tier discs (threshold/light/common/strong/heavy) | `DoseDurationCard.colors = [B7BCC4, 34C759, E0A021, F0803A, E8503A]` (`DoseDurationCard.swift:331-333`) — a **different, continuous** 5-stop gradient than `DoseLevel.swiftUIColor`'s discrete gray/blue/green/yellow/orange/red (`DoseLevelIndicator.swift:169-177`) | The tier disc a user actually sees on the substance detail page is the DoseDurationCard gradient, not the "canonical" DoseLevel enum used elsewhere (dose-level badges in Journal/EntryDetail) | Two competing L2 encodings for the identical 5/6-tier dose-level concept, and the screenshot shows which one actually ships |
| 12 | `SCR-library-home.png`, direct read, cross-checked against `LibraryBrowseView.swift:356` | Favorites card gradient (rose/raspberry) | `LibraryFavoritesCard.accent = rgb(0.85,0.26,0.47)` (`#D9427B`) — comment says "distinct from the warm Stimulants orange … and the cool Common blue" | Visually near-identical to `WidgetColors.accent` light (`#F57896`) and the app's own `AccentColor` asset, and to the `Rose`/`Magenta` L3 presets and the empathogen family pink | The code comment proves the author *thought about* two collisions (orange, blue) and missed the third (brand accent itself) |
| 13 | `SCR-insight-adherence.png`, direct read | Streak flame icon (orange) + "65%" stat (orange) + the SAME screen's adherence-ladder "partial" square (orange) | `AdherenceView.swift:142` (decorative streak icon, chrome) vs `AdherenceView.swift:429` (L1 `adherence.day.partial`) | One screen, orange meaning "here's a fun stat" right next to orange meaning "you partially missed a dose" | Chrome/L1 collision on a single screen |

### 3c. Not visible in any current screenshot — flagged, not guessed

- `ConfidenceBadge`/`ProvenanceBadge` (confidence-tier green/amber/orange/gray, `ConfidenceBadge.swift:27-33`)
  — the Pharmacology screens captured (`SCR-substance-data-pharmacology.png`) show the MOA card and
  Receptor Literature rows, but the confidence/provenance pills themselves scroll further down than the
  capture. `PharmacologyHero.swift`'s receptor-action orange/rust *is* visible there (see below) but the
  dedicated badge components are not.
- `SITE-0095`'s "antagonist" color (`rgb(0.75,0.22,0.17)`, nominally a brick-red) — visible in
  `SCR-substance-data-pharmacology.png`'s "Non-Selective Adenosine Receptor Antagonist" headline and the
  "ACTS ON" pill fills, but it **renders as a warm rust-orange in practice**, not a distinguishable red —
  worth flagging on its own: the code's red/green/amber three-way split for agonist/antagonist/partial is
  less visually distinct than the enum suggests, because the antagonist "red" is desaturated toward orange.
- The Benzo/Opioid Equivalence "Safety" disclaimer headers (`BenzoEquivalenceToolView.swift:284`,
  `OpioidEquivalenceToolView.swift:255`) — `SCR-tool-benzo-equivalence.png`'s capture ends above the fold;
  the visible content (hero icon, "Cited equivalence" quote) is all `Theme.accent`/`Theme.secondaryLabel`
  chrome, not the safety banner. Not asserting a screenshot match I don't have.
- QuickLog's crisis-support banner (`QuickLogHelpBanner.swift`, blue-tinted, ambiguous §2 item) — no
  screenshot captures the distress-keyword search state; QuickLog captures show the normal dock only.

---

## 4. Collision matrix — all 48 `PresetColor` entries

Grouped by the 16 named families (Light/base/Dark share a family verdict; I flag when a specific variant is
notably worse). Candidates only — I did the naming/eyeball pass; the Oklch hue-distance math is yours.

| Family (base hex) | Hue-family | Adjacent L1/L2 meanings | Verdict |
|---|---|---|---|
| **Mustard** (`bb9900`) | dark yellow-olive | `Theme.legibleYellow` (`#856300`/`#FFD60A`), raw caution `.yellow` | **Worst offender #1** — this preset sits *inside* the caution-amber hue family, not merely near it |
| **Rose** (`f17395`) | pink | `WidgetColors.accent` light (`#F57896`) — near-identical hex neighbor; empathogen `.pink`; Favorites gradient `#D9427B` | **Worst offender #2** — a substance dyed Rose can read as the app's own brand accent |
| **Tangerine** (`e08600`) | deep orange | `systemOrange` (warning), `substance.category.stimulant` `.orange`, Stimulants family card | **Worst offender #3** — near-twin of warning-orange |
| **Green** (`21b26a`) | true green | `systemGreen` success/checkmark, adherence "complete", cannabinoid category | **Worst offender #4** — reads as a success/complete state |
| **Magenta** (`dd79c9`) | pink-magenta | Brand `AccentColor` (soft pink light / hot pink dark), empathogen `.pink`, Favorites gradient | High — three-way overlap with brand + L2 + another L3 collision (Favorites card) |
| **Coral** (`f27859`) | salmon/orange-red | Sits *between* `systemRed` (danger/opioid) and `systemOrange` (warning/inhalation) | High — the single worst hue position on the wheel, ambiguous even between two L1 tiers |
| **Azure** (`2ca2f5`) | clear blue | `route.oral` tint (`#0A84FF` dark), benzodiazepine category `.blue`, sedative family, crisis-banner info-blue | High |
| **Ocean** (`00A4E8`) | blue | Same bucket as Azure | High |
| **Orchid** (`CB7FDD`) | purple-pink | Psychedelic `.purple`, hallucinogen family, insufflation route, drifts toward empathogen pink | Moderate-high |
| **Lilac** (`b885ef`) | light purple | Psychedelic `.purple`, hallucinogen family, insufflation route | High |
| **Teal** (`00b3a2`) | teal | Sublingual route tint, nootropic category `.teal` | Moderate-high |
| **Pear** (`83a926`) | yellow-green/olive | Straddles caution-yellow and success-green — ambiguous even to itself | Moderate |
| **Sky** (`00add3`) | cyan-blue | Dissociative category `.cyan`, sublingual teal | Moderate |
| **Aqua** (`00BFC8`) | cyan-teal | Same bucket as Sky/Teal | Moderate |
| **Lavender** (`8394ff`) | blue-violet | Gabapentinoid `.indigo`, subcutaneous route indigo | Moderate |
| **Violet** (`9B8DF7`) | blue-violet | Same bucket as Lavender | Moderate |

**Not flagged as meaningful collisions**: none of the 16 — every family lands near *some* L1/L2 meaning,
because L1+L2 between them already cover most of the usable hue wheel (red/orange/yellow/green/blue/
purple/pink/teal/indigo/brown/gray all carry a status or encoding meaning somewhere in this app). This
itself is worth stating plainly: **there is no "safe" region left in hue space for L3 to live in**, given
how much of the wheel L1+L2 already claim. That fact alone is the strongest argument for separating layers
by form rather than hue (§6) — hue-band reservation would require *removing* meanings from L1/L2, not just
picking better L3 colors.

---

## 5. Proposed closed L1 set

Six roles, each with a `.text` / `.fill` / `.icon` split — matching the pattern `ConfidenceBadge.swift`
already uses internally (`color` for text+icon, `color.opacity(0.15)` for the self-tinted capsule fill),
formalized as the house rule rather than left as one component's private convention:

| Role | Color (proposed single definition) | Replaces |
|---|---|---|
| `danger.text/fill/icon` | `systemRed`, adaptive | `InteractionSeverity.color` `.dangerous` (`Interactions.swift:28`), `DoseTrayViews.swift:493` delete-affordance, `StagedDoseEditor.swift:286` remove-dose, `AdherenceView.swift:433` missed-day, `PDFReportGenerator.dangerousRed/dangerousBg` (`PDFReportGenerator.swift:46,49`) |
| `warning.text/fill/icon` | `systemOrange`, adaptive | `InteractionSeverity.color` `.unsafe` (`Interactions.swift:29`), **~20 raw `.orange` safety-banner sites** (`AcetaldehydeCard.swift:55`, `ContraceptionCautionBanner.swift:17`, `CombinationMetaboliteBanner.swift:14`, `ElevenHydroxyTHCCard.swift:17`, `DataStorageView.swift:223,788,815`, `ToleranceSections.swift:20`, `OpioidEquivalenceToolView.swift:221`, `DoseTrayViews.swift:593`, `UsageStatsView.swift:751`, `RampDownView.swift:130,140`, `EffectEstimatesView.swift:200`, `AdherenceView.swift:429`, `SubstanceDBUpdateRow.swift:144`), `PDFReportGenerator.unsafeOrange/unsafeBg` |
| `caution.text/fill/icon` | **One** adaptive amber (`Theme.legibleYellow`'s existing light/dark values are a good starting point — light `#856300`, dark `#FFD60A`) | `InteractionSeverity.color`/`labelColor` `.caution` (`Interactions.swift:30,38`), `ConfidenceBadge`/`ProvenanceBadge` `.medium` tier, `DoseLevel.color`/`labelColor` `.common` (**but see the recommendation below** — this specific reuse is the §3b #8 collision and should probably NOT share the token with severity-caution even after consolidation), raw unswapped `.yellow` sites (`BenzoEquivalenceToolView.swift:284`, `VolumetricDosingView.swift:194`, `OpioidEquivalenceToolView.swift:255`), `PDFReportGenerator.cautionYellow/cautionBg` (`PDFReportGenerator.swift:48,51`) |
| `success.text/fill/icon` | `systemGreen`, adaptive | The ~15 checkmark/success sites (`OnboardingImportStep.swift:27`, `InsightsView.swift:208`, `NotificationSettingsView.swift:264`, `SubstanceDBUpdateRow.swift:72,127`, `StagedDoseEditor.swift:251`, `InteractionTimelineView.swift:527`, `InteractionCheckerView.swift:146`, `RampDownView.swift:115`, `AdherenceView.swift:425`, `MyMedsCard.swift:182,221,301`, `DataStorageView.swift:819`, `EntryReadContent.swift:105`), `PDFReportGenerator.goodAttr` (`PDFReportGenerator.swift:375`) |
| `info.text/fill/icon` | `systemBlue`, adaptive | **Currently unused as a true status role** — the app's blue sites are either L2 (route.oral) or chrome (decorative icon tint, crisis-banner theming). Reserved for genuine "FYI, no action needed" status if one is ever needed, so a future engineer doesn't reach for `.blue` and accidentally collide with route.oral again |
| `neutral.text/fill/icon` | `Theme.secondaryLabel` or `systemGray`, adaptive | `ConfidenceBadge`/`ProvenanceBadge`/`labelColor` `.unverified` tier |

**Answer to "how many distinct color definitions remain for warning/caution after this": 2** (one
`warning` orange, one `caution` amber) — down from at least **5 independently-authored ambers/oranges
doing overlapping duty today**: `Theme.legibleYellow`, raw `.yellow` (unswapped), `PDFReportGenerator.
cautionYellow`, `systemOrange`-as-warning, `PDFReportGenerator.unsafeOrange`. Across the full L1 ladder
(danger/warning/caution/success/info/neutral), that's **6 canonical tokens total**, replacing at least
**11 independently-invented color definitions** found in this audit (2 ambers beyond legibleYellow, 2 PDF
severity oranges/reds, the PDF success green, plus the raw-hue sites that never got a named token at all).

**One explicit non-recommendation**: don't fold `DoseLevel.common`'s legibleYellow reuse into the new
`caution` token just because they'd share a hex value — §3b #8 shows this is an *active* collision, not a
harmless coincidence. If L2 dose levels need a "this is the common/moderate tier" amber, it should be a
**named L2 token** (e.g. `doseLevel.common`) that happens to start from the same base hue family but is
kept as a distinct definition — so retuning `caution` (an L1 severity color) can never silently retune a
dose-level badge, and vice versa.

## 6. Separation rule recommendation: **form, not hue**

**Recommendation: separate L1/L2/L3 by rendering FORM, not by reserved hue bands.**

Concretely: **status (L1) is always a filled capsule/pill with a leading SF Symbol icon** (the
`ConfidenceBadge`/`ProvenanceBadge` shape, already the majority pattern for severity/confidence); **identity
(L3) is always a bare dot, ring, or unadorned curve/chip fill with no icon** (the existing substance-color
dot/curve pattern); **encoding (L2) keeps its current pill-with-text-label form** (route/dose-tier/category
badges already read as labeled pills, distinct from both).

Why this over reserved hue bands:

- **Hue bands can't fix the bugs already found.** The worst confirmed collision in this audit (§3b #8,
  `DoseLevel.common` vs `InteractionSeverity.caution`) is an **L1-vs-L2** collision, not L3-vs-anything — no
  amount of reserving hues away from L3 touches it, because both colliding sites are already inside the
  "reserved" status band.
- **Hue bands break a live migration.** L3 colors are persisted (`SubstanceColor.hexColor`,
  `UserColor.hex`) and partly user-chosen. Reserving bands means re-coloring already-assigned substances
  out from under users who picked those colors deliberately, or silently reassigning
  `PresetColor.deterministic` hashes for everyone (which also breaks the "same substance, same color
  everywhere" guarantee the deterministic hash exists to provide, per `SubstancePalette`'s own doc comment).
- **There's no hue room left to reserve.** §4 shows all 16 L3 families already land near some L1/L2 meaning
  — L1+L2 between them have claimed nearly the entire usable hue wheel. A "reserved band" scheme would
  have to shrink the 48-entry L3 palette to whatever hue sliver survives, likely under a dozen usable
  colors for hundreds of substances.
- **Form survives color vision deficiency; hue bands don't.** A form-based rule (filled pill vs bare dot)
  reads correctly for a colorblind user even if two colors are indistinguishable to them — a benefit hue
  separation can never provide, since it's still asking the user to distinguish colors, just fewer of them.
- **Form is cheap and largely already in place.** The dominant existing patterns already split close to
  this line (badges are pills-with-icons, substance identity is dots/curves) — formalizing it is mostly
  documentation plus fixing the outliers (§2's list is the fix-it list: the swipe-action orange, the
  brand-accent-as-status sites, the favorite star).

**Tradeoff being accepted**: form separation doesn't stop a *new* L1 site from being coded as a bare
colored dot by an engineer who doesn't know the rule — it's a convention, not a compiler-enforced
constraint. Reserved hue bands, if a type system enforced them (e.g. distinct `StatusColor`/`RouteColor`/
`IdentityColor` Swift types that don't implicitly convert), would be harder to violate accidentally. If
Piru wants that stronger guarantee later, the two approaches aren't mutually exclusive — form separation
now, with wrapper types enforcing L1 vs L2 vs L3 provenance as a follow-up hardening pass once the six L1
tokens in §5 exist to wrap.

---

## Appendix: methodology notes

- Layer assignment lives in `inventory.json` as `"layer"` (+ `"layer_note"` where non-obvious) on all 186
  individual sites, and as a block-level `"layer": "chrome"` tag on each of the 7 `theme_token_pairs`
  objects from the previous pass.
- The `pixel-sampler` sibling agent's `sampled.json`/`sampled-contactsheet.png`/`colorimetry.py` in this
  same directory were read but not modified; their 145 samples and 45 pairs are cited by `PX-NNN` ID above
  where used as evidence.
- `component-sameness.md` and `asset-catalog-migration.md`, also present in this directory from other
  agents, were not read for this pass — out of scope for the layer/screenshot task as assigned.
