---
id: component-sameness
type: analysis
description: Difference matrices + classification for every pill/badge/chip/meter/card/row family — verifies which look-alikes are genuinely the same thing before any unification.
---

# Component sameness audit

Companion to `Specs/design-system/components.md` and `divergences.md`. Those two answer *what
exists* and *where it forks*; this file answers the harder question for each look-alike cluster —
**genuinely the same thing, or different things that happen to look alike?** Every claim below is
`file.swift:line`, re-read from source on 2026-07-30, not carried over from the earlier docs
without verification.

Classification key:
- **IDENTICAL** — byte-equivalent behavior, straight dedup.
- **SAME + PARAMETRIC** — one concept; differences are genuine parameters (tint, label, icon, density).
- **SUPERFICIALLY SIMILAR** — looks alike, encodes different meaning or interaction. Stays separate.
- **DIVERGENT BUG** — same intent, unintentional drift. Converges.

Design constraint applied throughout: **no widened initializers.** Where a family unifies, the
fix is a shared `View`/`ViewModifier` plus `@Environment` for whatever a whole subtree sets once
(tint context, density) — explicit arguments stay explicit for anything that's per-instance and
required (a substance's own color, a status enum case). See `swiftui-specialist` skill
(`structure.md`, `dataflow.md`, `environment.md`) for the underlying model.

---

## F1 — Evidence badges: `ConfidenceBadge` vs `ProvenanceBadge`

| Axis | `ConfidenceBadge` (`Piru/Views/Components/ConfidenceBadge.swift:9-44`) | `ProvenanceBadge` (`Piru/Views/Components/ProvenanceBadge.swift:15-99`) |
|---|---|---|
| Shape | Capsule | Capsule |
| Padding h/v | 8 / 3 (`:20-21`) | 7 / 2 (`:28-29`) |
| Font | `.caption2.weight(.semibold)` (`:18`) | `.caption2.weight(.semibold)` (`:26`) |
| Icon | SF Symbol, `.imageScale(.small)`, leading, 4pt gap (`:14-15`) | SF Symbol, `.imageScale(.small)`, leading, 3pt gap (`:22-23`) |
| Fill | `color.opacity(0.15)` (`:22`) | `color.opacity(0.15)` (`:30`) |
| Color source | `ConfidenceTier` → green/yellow/orange/secondaryLabel (`:27-34`) | Same `ConfidenceTier` ramp, identical 4-way switch (`:37-44`) |
| What it encodes | **Trust grade alone** — one of 4 tiers | **Assay method** (human/rat/mouse/animal/in-vitro/aggregated) **colored by** trust grade — 6 kinds × the same 4-color ramp |
| Icon vocabulary | `checkmark.seal.fill` → `exclamationmark.triangle`, 4 icons (`:37-42`) | `person.fill`/`pawprint.fill`/`testtube.2`/`tray.full`, 4 icons for 6 kinds (`:76-83`) |
| Accessibility | `.accessibilityLabel(tier.label)` only (`:24`) | Combines method + tier into one sentence (`:32`) |
| Call sites | `ToleranceExplainerView.swift:130`, `EffectSandboxView.swift:1130`, `MetabolicModulationBanner.swift:26`, `CeilingEffectToolView.swift:121,144` (5) | `EffectSandboxView.swift:1226` (1) |
| Used together? | Yes — `EffectSandboxView.swift:1130` and `:1226` are both reachable in the same screen; `ProvenanceBadge`'s own doc comment (`:5-7`) says it "complements `ConfidenceBadge` (which states the grade alone)" | — |

**Classification: SUPERFICIALLY SIMILAR at the data layer, IDENTICAL at the chrome layer.**

They are not the same *fact* — one says "how much to trust this," the other says "where this came
from" — and the codebase deliberately shows both side by side in `EffectSandboxView`, so collapsing
them into one badge would delete information the screen is designed to carry twice. **Do not
merge the views.** But the pill chrome itself (icon + `.caption2.weight(.semibold)` text on a
`color.opacity(0.15)` capsule) is genuinely one idiom with a 1pt-off padding drift (8·3 vs 7·2,
no comment justifies the difference) — that part is a **DIVERGENT BUG**, cheap to fix by extracting
the chrome:

```swift
/// Shared pill chrome for the two evidence badges — icon + label on a tinted
/// capsule. Each badge still owns its own icon/label/accessibility logic;
/// only the shape, padding, and font are pulled out so they can't drift again.
struct EvidenceBadgeChrome<Label: View>: View {
    let systemImage: String
    let color: Color
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).imageScale(.small)
            label()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }
}
```

`ConfidenceBadge.body` becomes `EvidenceBadgeChrome(systemImage: symbol, color: color) { Text(tier.label) }`
plus its own `.accessibilityElement`/`.accessibilityLabel` wrapper; `ProvenanceBadge.body` the same
with its icon+label+combined accessibility string. No environment needed here — both fields
(`color`, `systemImage`) are per-instance and required, exactly the case that stays an explicit
argument.

---

## F2 — Status/tier capsule chip (route · strength · category · severity)

The largest family. All of these render **one classifying word about a dose or substance** as a
tinted, filled capsule — and the app already has a shared idiom for it
(`Text.capsuleChip(tint:)` / `Text.heroChip(tint:)`, `Piru/Views/Components/CapsuleChip.swift:7-27`).
The question is which call sites actually use it.

| Instance | File:line | Font | Padding h/v | Fill opacity | Uppercase/tracking | Uses shared modifier? |
|---|---|---|---|---|---|---|
| Route pill (`ROAPill`) | `Piru/Views/Components/ROAPill.swift:13-48` | `.caption2`/`.caption` (size-dependent) | 8/3 (compact) or 10/5 (regular) | 0.16 | no | No — hand-builds identical grammar, doc comment (`:9-12`) explains it was extracted **from** the same drift this file catalogs |
| Strength/dose-level chip (`strengthChip` in `EntryRowView`) | `EntryRowView.swift:222-229` | `.caption2.weight(.semibold)` via modifier | 8/3 | 0.16 | no | **Yes** — `.capsuleChip(tint:)` (`:225`) |
| Interaction-severity chip, row context | `EntrySessionSection.swift:155-156`, `SessionSafetySection.swift:56-57` | via modifier | 8/3 | 0.16 | no (lowercased) | **Yes** — `.capsuleChip(tint:)` |
| Interaction-severity chip, Checker/Timeline context | `InteractionTimelineView.swift:464,568,667`, `InteractionCheckerView.swift` (band legend `:464`) | `.caption`/`.caption.weight(.semibold)` (varies) | 8/3 | **0.15** (not 0.16) | no | No — hand-rolled `Text(...).font(...).padding(8,3).background(color.opacity(0.15), in: Capsule())` repeated 3× in one file |
| Category chip, hero (`CategoryChip`) | `SubstanceDetailLayout.swift:387-401` | `.caption2.weight(.bold)` | 9/4 | 0.14 | **yes**, tracking 0.6 | No |
| Category badge, row (`SubstanceLibraryView`) | `SubstanceLibraryView.swift:487-493` | `.caption2.weight(.medium)` | 8/3 | 0.12 | no | No |
| "Predicted" badge | `ToleranceCard.swift:58-63` | `.caption2.weight(.semibold)` | 9/4 | 0.14 (fixed `Color.secondary`, not tint) | yes, tracking-less uppercase | No |
| "Limited data" badge | `SubstanceLibraryView.swift:481-486` | `.caption2` (no weight) | 8/3 | `.fill.tertiary` (not opacity-tint) | no | No |

**Classification: SAME + PARAMETRIC — genuinely one concept (a classifying capsule, tint-driven),
already has the right API, under-adopted.** This restates `divergences.md#DIV-003` and `#DIV-006`
with the exact drift measured: opacity forks at 0.12/0.14/0.15/0.16 and padding forks at 8·3/9·4/10·5
across what should be 2 states (row density, hero density).

`ROAPill` is the interesting case: its own doc comment says it was extracted *to stop* casing/padding
drift between call sites, but it re-implements the capsule instead of calling `capsuleChip`/`heroChip`
— it should be the reference consumer of the shared modifier, not a fourth parallel implementation.

**Proposed API** — an environment-driven density, matching `DIV-006`'s observation that hero-vs-row
is currently chosen per-screen with no rule:

```swift
/// Row (dense, inline with other chips) vs Hero (standalone, detail-header scale).
/// Set once by the container; individual chips don't need to know their context.
enum ChipDensity { case row, hero }

private struct ChipDensityKey: EnvironmentKey {
    static let defaultValue: ChipDensity = .row
}
extension EnvironmentValues {
    var chipDensity: ChipDensity {
        get { self[ChipDensityKey.self] }
        set { self[ChipDensityKey.self] = newValue }
    }
}
extension View {
    /// Apply once to a section — e.g. the detail header — so every classifying
    /// chip inside picks up the hero size without a per-call-site parameter.
    func chipDensity(_ density: ChipDensity) -> some View {
        environment(\.chipDensity, density)
    }
}

/// Reads `chipDensity` so `Text` doesn't need its own `@Environment` (extensions
/// on non-View types can't declare property wrappers).
private struct StatusChip: View {
    @Environment(\.chipDensity) private var density
    let text: Text
    let tint: Color
    var body: some View {
        switch density {
        case .row: text.capsuleChip(tint: tint)
        case .hero: text.heroChip(tint: tint)
        }
    }
}
extension Text {
    /// The one classifying-capsule call every route/strength/category/severity
    /// chip should route through. Density comes from environment; tint is the
    /// one thing that's genuinely per-instance (the substance/level/category's
    /// own color) and stays an explicit argument.
    func statusChip(tint: Color) -> some View { StatusChip(text: self, tint: tint) }
}
```

Before (today, 3 different call sites, 3 different constants):
```swift
// InteractionTimelineView.swift:464
Text(level).font(.caption.weight(.semibold))
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(color.opacity(0.15), in: Capsule())
    .foregroundStyle(color)

// SubstanceDetailLayout.swift:391-399 (CategoryChip)
Text(category.displayName).font(.caption2.weight(.bold)).textCase(.uppercase).tracking(0.6)
    .foregroundStyle(category.color).padding(.horizontal, 9).padding(.vertical, 4)
    .background(category.color.opacity(0.14), in: Capsule())

// SubstanceLibraryView.swift:487-493 (row category badge)
Text(substance.category.displayName).font(.caption2.weight(.medium))
    .foregroundStyle(substance.category.color)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(substance.category.color.opacity(0.12), in: Capsule())
```

After:
```swift
// Detail header sets density once:
VStack { ... }.chipDensity(.hero)
// then inside:
Text(category.displayName).textCase(.uppercase).tracking(0.6)
    .statusChip(tint: category.color)          // hero

// Library row (default .row density, no wrapper needed):
Text(substance.category.displayName).statusChip(tint: substance.category.color)

// Interactions band legend:
Text(level).statusChip(tint: color)
```

The uppercase/tracking on the hero `CategoryChip` is a real, distinct fact (it's the one chip in the
app treated as a section-eyebrow, not an inline tag) — kept as an explicit modifier the caller adds,
not folded into `statusChip` itself.

"Limited data" (`.fill.tertiary`, no tint) is arguably a fifth, genuinely different case — it has no
color to carry (a stub substance has no category-accent story to tell) — so it's the one instance in
this table that should probably **stay** a plain neutral capsule rather than being forced through
`statusChip(tint:)` with a fake gray tint. Flagging it rather than merging it.

---

## F3 — Freeform tag chip (aliases, class tags) — DO NOT MERGE with F2

| Instance | File:line | Fill | Font | Interactive? |
|---|---|---|---|---|
| `Text.capsuleOutlineChip()` (shared) | `CapsuleChip.swift:33-40` | **unfilled**, hairline stroke `Color.secondary.opacity(0.3)` | `.caption2.weight(.medium)` | no |
| Entry tag row | `EntryRowView.swift:174-181` | via `.capsuleOutlineChip()` | via modifier | no |
| Alias chip | `SubstanceIdentitySections.swift` (`InfoDisclosureSection`) `:99-106` | **filled**, `Color(.tertiarySystemFill)` (or `Theme.accent.opacity(0.12)` for the "+N more" overflow chip) | `.caption.weight(.medium)` | "+N more" chip is a `Button` |
| Class/mechanism tag (`SubstanceTagFlow`) | `SubstanceLibraryView.swift:472-483` | filled, `accent.opacity(0.15)` | `.caption2.weight(.medium)` | no |

**Classification: SUPERFICIALLY SIMILAR to F2, genuinely distinct — the code says so explicitly.**
`CapsuleChip.swift:29-32`'s own doc comment: *"a bordered, unfilled capsule for freeform tags —
deliberately a different grammar from the filled `capsuleChip`... so a rarely-used tag reads as a
quiet annotation rather than competing with the dose's categorical badges."* This is an intentional,
documented visual hierarchy (classifying badge = filled/loud, freeform tag = outline/quiet) — do not
collapse it into F2's `statusChip`.

*Within* this family, though, there's a real **DIVERGENT BUG**: the alias chip and `SubstanceTagFlow`
each hand-roll their own filled-capsule variant instead of using `capsuleOutlineChip()` (or a filled
sibling of it), and use three different fill treatments (`.tertiarySystemFill`, `accent.opacity(0.12)`,
`accent.opacity(0.15)`) for what reads as the same "quiet filled tag" intent. Converge these two by
adding one parameter to the existing modifier — a real per-instance value, not environment:

```swift
/// Filled variant of the quiet-tag grammar, for tags that need a hint of
/// color (aliases, mechanism tags) rather than pure outline (Journal tags).
func capsuleFillChip(tint: Color = Theme.secondaryLabel, opacity: Double = 0.15) -> some View {
    font(.caption2.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(opacity), in: Capsule())
        .foregroundStyle(tint)
}
```

---

## F4 — Removable filter/selection chip (`InventoryMenus.chip` vs `InteractionCheckerView.substanceCapsule`)

| Axis | `InventoryMenus.chip` (`InventoryMenus.swift:216-232`) | `InteractionCheckerView.substanceCapsule` (`InteractionCheckerView.swift:301-320`) |
|---|---|---|
| Wrapper | `Button(action: remove)` | `Button(action: action)` |
| Icon | `xmark`, **trailing**, `.caption2.weight(.bold)` | `xmark`, **leading**, `.caption.weight(.bold)`, conditional on `removable` |
| Font | `.footnote.weight(.medium)` | `.subheadline.weight(.medium)` (one step larger) |
| Padding h/v | 10 / 5 | 12 / 7 |
| Tint | fixed `Theme.accent` always | per-substance `colorMap[name]`, falls back to `Theme.accent` |
| Fill opacity | 0.16 | 0.15 |
| Non-removable mode | none — always a remove action | supported (`removable: Bool`) — used to show an already-staged, non-removable substance |
| Accessibility | `"Remove filter"` + value = filter name | conditional: `"Remove \(name)"` or bare name |
| Call sites | 2 (status filter, category filter) | 2 (`:115` new-substance-added, `:219` staged list) |

**Classification: SAME concept, DIVERGENT in execution — but one real capability difference.**
Both are "tap this capsule to remove/toggle a selection," and nothing documents *why* the icon sits
on opposite sides, or why one is a full font-size step larger — that reads as organic drift, not
intent, and is worth converging (pick one icon side — trailing reads as the more common "tag ×"
convention and matches `InventoryMenus`). The **tint source is not drift** — Interactions ties each
capsule to the substance's own color (matching that screen's color-coded curves elsewhere);
Inventory's filters have no substance to color by. Keep `tint` as a required per-instance argument.
The **`removable` toggle is not drift** — Interactions genuinely needs to show a non-removable staged
item; Inventory never does. Keep it as a real parameter, not environment (it changes what the view
*renders*, not a passive style choice a whole subtree shares).

```swift
struct SelectableChip: View {
    let label: Text
    var tint: Color = Theme.accent
    var removable: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                label
                if removable {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(removable ? Text("Remove \(label)") : label)
    }
}
```

Flagging, not resolving: whether Interactions' larger 12·7 tap target is deliberate (a wider
horizontal-scroll pill row wants a bigger touch target) needs a human call before the size folds in —
don't silently shrink it during a mechanical merge.

---

## F5 — Tier/strength meters (`DoseLevelIndicator`, `StrengthMeter`, `AffinityDots`, `DoseTierStrip`/`DoseTierMark`, `ToleranceBar`)

| Instance | File:line | Segments | Shape | Data model | Purpose |
|---|---|---|---|---|---|
| `DoseLevelIndicator` | `DoseLevelIndicator.swift:3-104` | 3–5, source-dependent | `Rectangle` bar row + per-segment label text + position dot | discrete dose-range ladder (threshold…heavy), **with an exact-position marker** | QuickLog/detail: "where does this dose sit" |
| `StrengthMeter` | `PharmacologyRows.swift:234-252` | fixed 3 | `Capsule`, 15×7 | discrete binding-strength tier (1–3) | Receptor pills + share card binding table |
| `AffinityDots` | `PharmacologyRows.swift:210-226` | fixed 3 | `Circle`, 6×6 | **same** binding-strength tier (1–3), same `affinityTier(forNm:)` source (`:202-206`) | Mechanism/Receptor card compact rows |
| `DoseTierStrip` | `DoseDurationCard.swift:318-385` | fixed 5 | growing `Circle`, diameters `[7,10,13,15,18]`, green→gold→red | discrete dose tier (0–4) | in-app dose ladder disclosure |
| `DoseTierMark` | `SubstanceShareCard.swift:716-736` | fixed 5 | escalating SF Symbol (`circle.dotted`→`exclamationmark.triangle.fill`), monochrome white | **same** discrete dose tier (0–4) | share-card export of the same ladder |
| `ToleranceBar` | `ToleranceCard.swift:90+` | 1–3, variable | segmented bar with legend | **continuous** occupancy fraction, not a discrete tier | tolerance-percent readout |

**Three separate findings here, not one:**

1. **`StrengthMeter` vs `AffinityDots` — SAME + PARAMETRIC, and already correctly factored.**
   `PharmacologyRows.swift:228-233`'s own doc comment states the intent directly: dots for dense
   Mechanism-card rows, segmented capsules where "three dots blur together." Both consume the same
   `affinityTier(forNm:)` (`:202-206`), so the two glyph families can't drift on *which* tier is
   shown, only *how* it's drawn — that's a deliberate, documented style choice already living in one
   file. **No action needed**; low risk either way, not worth forcing into one view with a style enum.

2. **`DoseTierStrip` vs `DoseTierMark` — DIVERGENT BUG (this is `divergences.md#DIV-020`,
   re-verified).** Same 0–4 tier, same intent ("this dose is heavy"), but the in-app ladder uses
   growing colored discs and the share-card export uses an escalating SF-Symbol vocabulary
   (dotted circle → triangle). Unlike `StrengthMeter`/`AffinityDots`, **nothing documents this as
   intentional** — the effect is a share-card screenshot that doesn't visually match what the user
   saw in-app for the same dose. Converge on one tier→visual mapping function (e.g.
   `DoseTierVisual.diameter(for:)`/`.color(for:)` shared by both call sites); the share card can
   still force monochrome/white for its dark plate, but the *shape* (disc, not symbol) should agree.

3. **`ToleranceBar` — SUPERFICIALLY SIMILAR to the discrete-tier meters, DO NOT MERGE.** It renders
   a continuous 0–1 occupancy fraction with a variable 1–3 band count and a legend, not a fixed
   discrete tier. Visually "a horizontal bar with colored segments" like `DoseLevelIndicator`, but the
   data model (continuous vs discrete) and configurability (variable bands vs fixed) are different
   enough that a shared view would need to abstract away the one thing that makes each legible.

`DoseLevelIndicator` itself has no real sibling to merge with in this set — it's the only one
carrying per-segment labels *and* an exact-position marker dot, a strictly richer widget than the
other five. Leave it standalone.

---

## F6 — Adherence status vocabulary (3 independent encodings of the same 4-case status)

| Instance | File:line | Icon set | Fill/color |
|---|---|---|---|
| `AdherenceCalendarCell.statusIcon` | `AdherenceView.swift:419-436` | `checkmark` / `circle.lefthalf.filled` / `xmark` / (blank), bare glyphs, size 8 | `backgroundColor` separately declared (`:438-445`): `.green/.orange/.red.opacity(0.1)` / secondarySystemBackground |
| `AdherenceDayDetailSheet.statusIcon` | `AdherenceView.swift:503-510` | `checkmark.circle.fill` / `circle.lefthalf.filled` / `xmark.circle.fill` / `minus.circle` — **circle-composited**, not bare | no background at all — plain `Image` + `Text`, no capsule (`:494-500`) |
| `AdherenceDayDetailSheet.statusColor` | `AdherenceView.swift:512-519` | — | `.green`/`.orange`/`.red`/`.secondary` |
| Adherence-rate percentage | `AdherenceView.swift:152-155` | none | bare threshold: `rate >= 0.8 ? .green : rate >= 0.5 ? .orange : .red` — not driven by the same `AdherenceStatus` enum at all, a separately-invented threshold |

**Classification: DIVERGENT BUG.** This is `divergences.md#DIV-002`'s "no semantic success/warning/
danger token" finding made concrete: the same four-state vocabulary (complete/partial/missed/no-data,
green/orange/red/secondary) is hand-declared **three separate times** in one file — two icon tables
that agree on color but disagree on whether the glyph is a bare shape or a filled circle, plus a
percentage-threshold color rule that isn't even keyed off the `AdherenceStatus` enum the other two
use, so a future adherence-threshold change (say, redefining "partial") would have to be hunted down
in three places. None of the three differences (bare vs circled glyph, badge vs plain-text, separate
threshold logic) reads as intentional — no comment justifies any of them.

**Converge** onto one `AdherenceStatus` extension owning color/icon/label, consumed by all three
sites:

```swift
extension AdherenceStatus {
    var color: Color {
        switch self {
        case .complete: .green
        case .partial: .orange
        case .missed: .red
        case .noData: .secondary
        }
    }
    /// Circle-composited glyph — used wherever the icon stands alone (detail
    /// sheet). The calendar cell's bare-glyph variant was undocumented drift,
    /// not a deliberate density choice, and folds into this one.
    var icon: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missed: "xmark.circle.fill"
        case .noData: "minus.circle"
        }
    }
    var label: LocalizedStringResource {
        switch self {
        case .complete: "All taken"
        case .partial: "Partially taken"
        case .missed: "All missed"
        case .noData: "Nothing due"
        }
    }
}
```

The rate-percentage threshold (`rate >= 0.8`/`0.5`) should be re-derived from `AdherenceStatus`
rather than re-invented, or explicitly documented as a *different*, continuous-scale judgment
(a month's aggregate rate isn't the same statement as one day's discrete status) if that's the
intended reading — right now it just looks uncoordinated with its neighbors two structs away in the
same file.

---

## F7 — Card/surface treatment (`themeCard` / `CardBackground` / `themeCapsule`)

| Instance | File:line | Radius | Fill (light) | Fill (dark) |
|---|---|---|---|---|
| `Theme.themeCard(cornerRadius:)` | `Theme.swift:93-95` | default 22, override any value | `.ultraThinMaterial` | `Theme.cardBackground` solid |
| `Theme.themeCard(enabled:cornerRadius:)` | `Theme.swift:100-107` | default 16 | same as above, conditional | same |
| `CardBackground` (standalone view) | `Theme.swift:78-88` | n/a (caller supplies shape) | `.ultraThinMaterial` | `Theme.cardBackground` |
| `Theme.themeCapsule()` | `Theme.swift:109-111` | n/a (Capsule) | `.ultraThinMaterial` | `Theme.cardBackground` |
| QuickLog `DockGroupedCard`/`TrayStagedListCard` | `QuickLogSupport.swift:8-18`, `DoseTrayViews.swift:52-55` | own constant (`DoseTrayMetrics.cardCornerRadius = 26`, `DoseTray.swift:31`) | flat `Color(.secondarySystemGroupedBackground)`, **no light/dark branch, no material** | same flat color |

**Classification: SAME + PARAMETRIC for the three `Theme.swift` entries — they are one
`ThemedBackground` `ViewModifier` (`Theme.swift:60-71`) underneath all of them, just applied to
different shapes/call conventions. No action needed there; that part of the system already follows
the "shared modifier, not widened initializer" pattern correctly.** The corner-radius proliferation
across call sites (`divergences.md#DIV-001`: 22/16/10/12/8/18/20 + one-offs) is a real, separately-
tracked issue but is about *call-site choices*, not the shared primitive being wrong.

QuickLog's dock cards are the one **SUPERFICIALLY SIMILAR, DO NOT MERGE** case here: they visually
resemble a themed card but are deliberately flat, with a self-documented rationale
(`.presentationBackground { Color.clear }`, `QuickLogSupport.swift:81` — the dock rides the native
sheet's own glass platter, so a second material layer underneath would double-blur) and a `// TODO
(integrator): promote to Components/ if reused outside QuickLog` marker at `QuickLogDockCards.swift:5`
acknowledging the split is deliberate, not yet-generalized. Do not fold this into `themeCard` — doing
so would put a second frosted layer on top of the sheet's own, which is exactly the bug the
`.presentationBackground` comment is guarding against.

---

## F8 — Dose-entry row: `EntryRowView` vs `SubstanceEntryRow`

| Axis | `EntryRowView` (shared) — `EntryRowView.swift:101-260+` | `SubstanceEntryRow` (private) — `EntryListView.swift:787-824` |
|---|---|---|
| Input | `DayEntryDisplay` (pre-resolved `DayEntryCore` + color + optional HR), built once upstream by `DayEntryCore.make`/`DayEntryDisplay.make` (`DayEntryCore` doc comment, `EntryRowView.swift:1-96`) | raw `DoseEntry` + a `colorMap`, resolves display name inline via `CustomSubstanceStore.shared.displayName(for:)` at render time |
| Name resolution | Pre-resolved title (`DoseTitle.resolve`), memoized | Resolved in `body`, on every re-render |
| ROA | `ROAPill(route:size:.compact)` (`:213-215`) | plain `Text` interpolation, no pill (`:803`) |
| Strength/dose-level | `capsuleChip(tint:)` chip (`:222-229`) | **none** — no dose-tier indicator at all |
| Elimination rail | Live `TimelineView`-driven countdown + progress rail (`:236-260+`) | **none** |
| Tags | Wrapping `capsuleOutlineChip()` row (`:174-181`) | **none** — `DoseEntry.tags` never rendered |
| Accessibility size handling | Explicit `dynamicTypeSize.isAccessibilitySize` branch, restacks layout (`:132-155`) | none — single fixed `HStack` |
| Layout | Multi-line `VStack` (name/pill row, dose+chevron, elimination footer, tag row) | Single `HStack`, fixed 14pt padding, `themeCard()` |
| Used by | `DayEntryRow.swift:42` (Session detail), `SessionShareImage.swift:250` (share-image renderer) | `EntryListView.swift` flat Journal list only |

**Classification: DIVERGENT BUG — restates `divergences.md#DIV-005`, confirmed at the field level.**
This is not a cosmetic fork: `SubstanceEntryRow` is missing the ROA pill, the strength chip, the
elimination rail, and tags entirely — a user scrolling the flat Journal list sees strictly less
information about the exact same `DoseEntry` than they'd see on the Session-detail screen or in a
shared session image, for no stated reason. It is also less accessible (no Dynamic-Type restack) and
does a live substance-name lookup per row per render instead of using the already-memoized
`DayEntryCore`/`DayEntryDisplay` pipeline the other two consumers share.

**Not a same-vs-parametric question** — there's no legitimate reason for two dose-row anatomies here,
so this isn't a candidate for an environment/modifier sketch; it's a migration (as `divergences.md`
already recommends): route `EntryListView`'s flat list through `DayEntryDisplay.make` +
`EntryRowView`, delete `SubstanceEntryRow`. Flagging it in this audit because it's the single
highest-value item in the whole set — worth prioritizing over any of the badge/chip work above.

---

## Summary table

| Family | Classification | Call sites touched by a fix | Risk |
|---|---|---|---|
| F1 Evidence badges (Confidence/Provenance) | Chrome: DIVERGENT BUG · Content: SUPERFICIALLY SIMILAR (keep 2 views) | 2 (padding fix only; views stay separate) | Low — cosmetic 1pt padding, no behavior change |
| F2 Status/tier capsule chip | SAME + PARAMETRIC (API exists, under-adopted) | 8 (`ROAPill`, 3× interaction-severity hand-rolls, `CategoryChip`, library row badge, "Predicted" badge; "Limited data" excluded, kept separate) | Medium — touches visible chrome on Library/Detail/Interactions; needs visual diff review per site |
| F3 Freeform tag chip | Internally DIVERGENT BUG · vs F2: SUPERFICIALLY SIMILAR (do not merge) | 2 (alias chip, `SubstanceTagFlow`) | Low |
| F4 Removable filter/selection chip | DIVERGENT BUG (icon side, size) + 2 genuine params (tint, `removable`) kept | 2, size change flagged for human confirmation first | Medium — one axis (12·7 padding) may be intentional; don't merge blind |
| F5a `StrengthMeter`/`AffinityDots` | SAME + PARAMETRIC, already correct | 0 — no action | None |
| F5b `DoseTierStrip`/`DoseTierMark` | DIVERGENT BUG (DIV-020) | 2 | Medium — share-card export is user-facing, screenshot-diff before/after needed |
| F5c `ToleranceBar` | SUPERFICIALLY SIMILAR, DO NOT MERGE | 0 | N/A |
| F6 Adherence status vocabulary | DIVERGENT BUG (DIV-002 concrete instance) | 3 (calendar cell, detail sheet, rate-percentage — the last needs a judgment call on whether it's a distinct continuous-scale concept) | Low–Medium — the rate-percentage merge needs a product decision, not just a refactor |
| F7 Card/surface treatment | Theme.swift trio: SAME + PARAMETRIC (correct) · QuickLog dock: SUPERFICIALLY SIMILAR, DO NOT MERGE | 0 | None |
| F8 `EntryRowView`/`SubstanceEntryRow` | DIVERGENT BUG (DIV-005), highest priority | 1 (delete `SubstanceEntryRow`, wire `EntryListView` to `DayEntryDisplay`/`EntryRowView`) | Medium-High — touches the most-viewed screen in the app; needs a full regression pass on the flat Journal list, not just a screenshot |

**Totals**: 8 families examined, 26 individual component instances cited. **Genuinely mergeable**
(DIVERGENT BUG, safe to converge): F1-chrome, F2 (7 of 8 sites), F3-internal, F4 (partial), F5b, F6
(2 of 3 sites cleanly, 1 needs a product call), F8 — **19 instances**. **Must stay separate**
(SUPERFICIALLY SIMILAR, do-not-merge): F1-content, F3-vs-F2, F5c, F7-QuickLog — **7 instances**.
