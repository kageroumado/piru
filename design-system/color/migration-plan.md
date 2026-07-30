---
id: PLAN-color-migration
type: plan
status: draft
depends_on: [SYS-color, review.md]
edges:
  - {rel: implements, target: color-system.md}
  - {rel: gated_by, target: review.md}
  - {rel: uses, target: generate_colorsets.py}
---

# Progressive migration to the color system

**Contingency note.** Phases 0, 1, 3, and the mechanics of 4–6 are independent
of the final palette *values*. Only Phase 2 consumes `palette-L1.json`, which is
under adversarial review (`review.md`). If the review changes the values, only
Phase 2's inputs change — the sequence does not.

## Design constraints this plan respects

1. **Every phase ships independently.** No phase leaves the app in a state that
   must be finished before release.
2. **Risk ascends.** Phase 1 has zero visual change; Phase 5 has the most. The
   verification apparatus is built in Phase 0, before anything moves.
3. **`CLAUDE.md` says keep the build warning-clean.** That rules out the usual
   "deprecate everything and burn down hundreds of warnings" approach — see
   Phase 3 for the adaptation.
4. **Never bump a persisted schema version that hasn't shipped**, and no
   migration is needed here: colors are presentation, not persistence. The one
   exception is `SubstanceColor` / `UserColor` rows, which this plan **does not
   touch** — that is why "form, not hue" was chosen over hue banding.

---

## Phase 0 — Safety net (no color changes at all)

Nothing in this phase alters a single rendered pixel. It exists so every later
phase is verifiable and regressions cannot silently land.

1. **Contrast unit test over the token table** — `PiruTests/ColorContrastTests.swift`.
   Pure computation: resolves each colour against a `UITraitCollection` and does
   arithmetic, never renders a view, so it is fast and cannot flake. It gates
   route tints (both modes, plus mutual distinctness), `InteractionSeverity` and
   `DoseLevel` label colours, and pins `Theme.secondaryLabel`'s known gap so it
   can only improve. `InteractionSeverity` gained `CaseIterable` so a new
   severity cannot escape the gate by not being in a hardcoded list.

   Surfaces are the **measured** `#f5f5f5` / `#111111`, not white/black — using
   white is precisely the mistake that put a wrong number in the audit's own
   OFF-5, and the suite's doc comment says so to stop it recurring.
2. **Screenshot baseline.** Re-capture all 43 light+dark PNGs from a known
   persona (`-piruPersona dailyMeds`) and commit them as the before-state.
3. **A `scripts/` entry point** so re-running the audit is one command.

**Ships:** nothing user-visible. **Reverts:** trivially.

---

## Phase 1 — Free wins (independent, no system dependency)

Each item is separately revertible and needs nothing from later phases.

**STATUS: DONE.** Build clean, 1440/1443 tests pass (3 pre-existing skips).

| # | Change | Outcome |
|---|---|---|
| 1.1 | `.color` → `.labelColor` at **5** sites | WCAG **1.39 → 5.08**. The audit named 3; two more were found in the same `InteractionTimelineView` warning card (`:512`, `:689`) where the *icons* also used the raw fill colour and failed even the 3:1 non-text gate. |
| 1.2 | Deleted `DoseLevel.color: String` | **Correction:** it was not fully dead. No production consumer, but `DoseRangeTests.swift:121-135` had two tests asserting its strings. Those were tests *of* dead code — nothing rendered those words — so they were removed with it. |
| 1.3 | `git mv Piru/Assets.xcassets Shared/` | **Correction:** "delete `WidgetColors.swift`" was too aggressive — the file also holds `WidgetBackground` and gradient tokens that are not duplicates. Only `WidgetColors.accent` was redundant; it now reads `Color("AccentColor")`, keeping all 12 call sites unchanged. The project references the catalog by *name* (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`), not path, so the move needed no project edit. |
| 1.4 | 5 route tints corrected | sublingual 4.02→4.53, buccal 4.18→4.57, inhalation 4.25→4.56, transdermal 4.32→4.51, other 4.19→4.50. Hue held constant to 0.1°; only Oklab lightness moved. |

**Visual change:** five previously-invisible caution labels/icons become
readable; five route pills darken slightly. The widget accent is unchanged (the
old literals were colorimetrically correct) but now resolves from the P3
colorset rather than an sRGB copy.

---

## Phase 2 — Introduce the system, consume nothing

Generate the tokens and let them sit unused. **Zero visual change** — this is
the point. It de-risks everything after it.

0. **Regenerate `palette-L1.json` first**, per the review: per-hue chroma
   ceilings instead of the flat 0.16 (free saturation for `danger` light →0.205
   and `success` dark →0.250), and role-split gates — `*/text` at WCAG AA 4.5:1,
   `*/fill` and `*/icon` at the non-text 3:1, which is what recovers warmth in
   the gamut-capped `warning`/`caution` hues.
1. Run `generate_colorsets.py` against `palette-L1.json` → `.colorset`
   directories in `Shared/Assets.xcassets` (P3, Any/Dark slots; high-contrast
   slots deferred to Phase 6).
2. Accessors need no step — Xcode emits `Color.Semantic.Caution.text` from the
   catalog itself (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`,
   already YES). Compile-time checked, per-target bundle, nothing to maintain.
   A hand-written accessor file was tried and deleted: string lookup means a
   typo compiles and silently falls back at runtime.
3. Point the Phase 0 contrast test at the generated table. It should pass on
   first run — if it doesn't, the palette is wrong, not the app.
4. Verify Xcode live previews resolve the new colorsets.

**Ships:** yes (dead code, but harmless and reviewable). **Reverts:** delete the
generated directories.

---

## Phase 3 — Burndown migration, one token at a time

The standard move — deprecate the old token and let the compiler enumerate call
sites — **conflicts with this repo's warning-clean rule** if applied to all
tokens at once. Adaptation: **migrate exactly one token per change-set**, so
deprecation warnings exist only *within* a single working session and the branch
is clean when it lands.

Per token:
1. Mark the old token `@available(*, deprecated, message: "use semantic/…")`.
2. The compiler now lists every remaining call site. That list is the worklist,
   and its length is the progress bar.
3. Migrate all of them, verify the warning count reaches zero.
4. Delete the old token. Build is clean again.

**Corrected order.** The original list treated `Theme.legibleYellow` as one
6-site token to migrate and delete. It is not: only **one** of its consumers is
genuinely L1 status (`InteractionSeverity.caution`). The other three —
`DoseLevel.common`, `ConfidenceBadge.medium`, `ProvenanceBadge.medium` — are L2
*encoding scales* that happen to share the amber. Pointing them at
`semantic/caution` would be exactly the L1/L2 merge the color spec forbids, so
they stay on `Theme.legibleYellow` until phase 4 gives their scales real tokens,
and the token cannot be deleted in phase 3.

`Theme.legibleYellow` (1 of 6 sites migrated) → `PDFReportGenerator.cautionYellow` (1) →
`LibraryTaxonomy` teal (1) → `Theme.secondaryLabel` (566) → `Theme.accent` (223).

`Theme.secondaryLabel` carries a **corrected** action: measured against the real
card rather than white/black, the light value is **3.89 and fails AA**, so it
must be *darkened*, not merely retained; the dark value loses to system (7.79 vs
9.97) and should adopt it. This is the largest single-token visual change in
Phase 3 — 566 sites — so it goes last in the burndown, after the mechanism is
proven on the cheap tokens.

**Ships:** after each token. **Visual change:** small and intentional per token.

---

## Phase 4 — L2 scales

Now the encoding scales, which are structural rather than cosmetic.

1. **Dedupe the experience-phase ramp.** Two definitions exist; editing a dose
   and reading it flip "peak" from orange to green. This is a **user-visible
   bug fix**, not a refactor. Keep the arc non-monotonic — that is deliberate.
2. **Unify the three dose-intensity scales** (6 / 5 / 6 steps, three different
   greens for "Light") onto one, with `.text` variants.
3. **Generate `route/*` tokens** from the existing hex pairs, folding in 1.4.
4. **Resolve the route-picker divergence** — the picker discards route color
   entirely while the read-only badge uses it.
5. **Give the 9 dark-blind `substance_category` cases** a dark variant.
6. **Resolve `StockStatus.barTint` vs `InventoryItem.supplyBarTint`** competing
   for one bar-fill role.

**Ships:** per item. **Visual change:** moderate, and mostly corrective.

---

## Phase 5 — L3 enforcement (largest visual change — do it last)

1. **Derived text variants** for tinted pills: text on a tinted chip comes from
   a fixed-L derivative of the identity color, not the raw color. This is the
   fix for 21 of the 33 failing pairs.
2. **Lower tinted-fill alpha to ≤0.10** — required for dark mode to be
   reachable at all.
3. **Identity out of chart chrome** — `#2ca2f5` (the `Azure` preset) currently
   draws PK curve strokes; route to `chart/series/*` or `semantic/info`.

**Gate:** re-capture the 43 screenshots and diff against Phase 0's baseline.
This is the phase most likely to be judged "the app looks different now," so it
should land on its own, with the diff reviewed by a human.

---

## Phase 6 — Hardening

1. **High-contrast colorset slots** (Any+HC, Dark+HC) — now expressible for the
   first time; the app currently has zero response to Increase Contrast.
2. **Wrapper types** — `StatusColor` / `RouteColor` / `IdentityColor` so passing
   an identity color where a status is expected fails to compile. Converts the
   "form, not hue" convention into an enforced invariant.
3. **Component unification** per `component-sameness.md`: 19 instances
   mergeable, **7 must stay separate** with reasons recorded. Includes deleting
   `SubstanceEntryRow` (`EntryListView.swift:787`, private, one consumer) so the
   Journal list stops showing strictly less than Session detail.

---

## What could go wrong

| Risk | Mitigation |
|---|---|
| The palette is contrast-correct but ugly | That is exactly what `review.md` is for. Phase 2 ships it *unused*, so it can be swapped before anything consumes it. |
| Phase 3 warnings breach the warning-clean rule | One token per change-set; branch lands clean. |
| Phase 5 visibly changes the app's character | Isolated to its own phase, gated on a human-reviewed screenshot diff. |
| Contrast test becomes a nuisance that gets disabled | Keep it pure-computation and fast. It asserts on the token *table*, not on rendered views, so it cannot flake. |
| Widget/Live Activity drift again | Phase 1.3 deletes the duplicate outright rather than syncing it. |
