---
id: divergences
type: index
description: Every place the design forks — ranked, cited, with a recommended convergence for each.
---

# Divergences

Each entry is a `divergence`-type graph node (`DIV-NNN`). Severity: **P0** = user-visible
inconsistency touching a core, frequently-seen flow; **P1** = visible but narrow-flow or
consistency-only; **P2** = code-hygiene/architectural, not currently user-visible. All citations
are `file:line` as reported by the five static-analysis passes (2026-07-29); re-verify line
numbers before editing since the codebase moves fast.

## Cross-tab / systemic

### DIV-001 — Card corner radius has no single source of truth
**Severity**: P1. **Majority**: `Theme.themeCard()` defaults to `22` (`Theme.swift:93`, 60 bare call sites) or `16` for nested cards (`Theme.swift:101`, 6 call sites). **Outliers**: `10`(19 sites: Calculator's dose field, Volumetric's numeric field, Benzo/Opioid input chips, `InventorySupport`), `12`(14 sites: QuickLog help/suggestion cards, `EducationCard` row pill, Ceiling's info box), `8`(6, mini-graph clips), `18`(4, `SessionNoteEditor.swift:16`), `20`(4 + 2 `themeCard(cornerRadius:20)`, Search's `SubstanceRowsCard`), plus one-offs at 9/5/4/6/15/17/36/3/14/2/1/1.5. QuickLog additionally has its own fourth system, `DoseTrayMetrics.cardCornerRadius = 26` (`DoseTray.swift:31`). **Fix**: promote `22`/`16`/`10`/`8` to named `Theme.Radius` cases (see `tokens.md#TOK-radius`); migrate the one-offs on next touch, don't do a big-bang pass.

### DIV-002 — No semantic success/warning/danger color tokens
**Severity**: P0. 345 bare system-hue literals (`.red`/`.green`/`.orange`/`.yellow`/etc.) with zero `Theme.success`/`Theme.warning`/`Theme.danger`. Concrete same-concept forks: interaction-clear state uses raw `.green` (`InteractionCheckerView.swift:146`, `InteractionTimelineView.swift:527`); adherence complete/partial/missed uses `.green`/`.orange`/`.red` at hand-picked opacities (`AdherenceView.swift:182-188` vs `AdherenceDayDetailSheet` 512-527 — same 3-color vocabulary, independently re-declared); "Safety" card icons use raw `.yellow` in three unrelated files (`VolumetricDosingView.swift:194`, Benzo/Opioid equivalence tools). **Fix**: add `Theme.success`/`Theme.warning`/`Theme.danger` (dark/light-aware like every other `Theme` color) and migrate the ~8 highest-traffic sites first (Adherence, Interactions, the three equivalence/safety cards).

### DIV-003 — Capsule chip reimplemented instead of reused
**Severity**: P1. `CapsuleChip.swift` already exports `capsuleChip(tint:)`/`heroChip(tint:)` (`:7-13`, `:20-26`), but at least 6 sites hand-roll the identical visual with drifted values: `SubstanceLibraryView.swift:490-493` (opacity 0.12), `:511-517` (0.15, `.medium` not `.semibold`), `InventoryMenus.swift:218-228` (0.16, `.footnote`), `ToleranceCard.swift:60-64,76-82`, `MyMedsCard.swift:296-301`. **Fix**: replace these call sites with the existing modifier; no new API needed.

### DIV-004 — Empty-state idiom inconsistent
**Severity**: P1. `ContentUnavailableView` is the majority idiom (15 files/18 sites) but at least 5 screens diverge: category/tag/favorites browse renders nothing for an empty list (`SubstanceLibraryView.swift:383-429`, no placeholder at all — the sharpest gap, since Search's sibling screens *do* show one); Search's `focusedEmpty` phase shows a blank scroll view for a brand-new user (`ContentView.swift`, `RecentlySearchedGroup`/`RecentDosesGroup` self-hide with no fallback message); `InYourSystemView` uses a custom icon+text block instead (`InYourSystemView.swift:53-70`); Insights-hub's 4 glance cards each use a plain inline caption (`InsightsView.swift:75,101-102,130-131`, plus Tolerance's positive-framed "Receptors rested" which isn't really an empty state, `:204-217`). **Fix**: give category/tag/favorites browse a `ContentUnavailableView` (cheapest, highest-visibility fix in this set); consider a shared `InsightsEmptyState` component for the hub's 4 near-identical inline captions.

### DIV-005 — Two incompatible "one dose" row visual languages
**Severity**: P0. `EntryListView.swift:787-824` defines and uses its own private `SubstanceEntryRow` for the flat Journal list, while `EntryRowView.swift:101` (shared, also used by `DayEntryRow.swift:42` and `SessionShareImage.swift:250`) is the row Session detail and the share-image renderer use. Same underlying `DoseEntry`, two different row layouts (no ROA pill/strength chip/elimination rail parity on the flat-list row). **Fix**: this is the single highest-value convergence in the whole audit — migrate `EntryListView`'s flat rows onto `EntryRowView`/`DayEntryCore`.

### DIV-006 — Chip metrics disagree for "strength/severity badge"
**Severity**: P1. `heroChip` (`.caption`, 10h/5v padding, `CapsuleChip.swift:20-26`) vs `capsuleChip` (`.caption2`, 8h/3v, `:7-13`) both encode "one badge on a card," used interchangeably by screen rather than by semantic (hero context vs. row context) — `EntryReadContent.swift:256` uses `heroChip` while `EntryRowView.swift:225`/`EntrySessionSection.swift:156` use `capsuleChip` for the same "strength" concept at different screen depths. Likely intentional (hero vs. row) but undocumented as a rule — worth a one-line comment on each, or renaming to make the hierarchy explicit.

### DIV-007 — Curve-fill (area-under-PK-curve) convention disagrees three ways
**Severity**: P1. `MechanisticChartView` gradient `0.34→0.05` (`:353-354`); `EffectThumbnail` gradient `0.32→0.04` (`EffectEstimatesView.swift:101-104`, near-duplicate constant, not shared); `ActiveNowWindowGraph` flat `color.opacity(0.16)` (`:215`), no gradient. Dose-tick idiom also diverges (dashed guide+baseline dot vs. short solid tick). **Fix**: extract one `PKCurveFillStyle` (gradient stops as named constants) shared by all three renderers.

### DIV-008 — Accessibility narration disagrees for sibling PK/PD charts
**Severity**: P0 (accessibility). `MechanisticChartView` narrates itself in full (`.accessibilityLabel`+`.accessibilityValue` synthesizing a sentence, `:146-161`) — directly resolves the historical "silent charts" defect. Its sibling in the same tab, `ActiveNowWindowGraph`, explicitly opts OUT: `.accessibilityHidden(true)` (`:82`, rationale: "the hosting card's phase bar / header speak the graph's story"). Whether that rationale holds needs a VoiceOver pass — flagging as the sharpest a11y divergence found. Separately, `InsightsView.usageChart` sets label/value directly on a `Chart` (`:93-94`) **without** the shared `chartSummaryAccessibility(children:.ignore)` helper (`AccessibilityPrimitives.swift:17-21`) that every other Swift-Charts chart in Usage/Tolerance uses — one inconsistent call site out of ~8.

### DIV-009 — Navigation-push mechanism is inconsistent
**Severity**: P2. Majority: imperative `navigator.push(...)`. Outliers: value-based `NavigationLink(value: PushRoute...)` (`SessionRecoverySection.swift:16-27`, `EntryAboutSection`); a second, parallel `sessionEditingService` environment channel for Session detail's delete/split/move/recolor/adjust-time actions, coexisting with `AppNavigator` in the same row (`DayEntryRow.swift:60-84` mixes both in one context menu). **Fix**: no urgent bug, but new code should default to imperative `navigator.push`; the `sessionEditingService` channel should get a comment explaining why it's separate (likely: these actions need a callback/confirmation the pure-value `AppNavigator` doesn't carry).

### DIV-010 — Three `SheetRoute` cases are declared but permanently dead
**Severity**: P1 (misleading to future readers/agents). `.journalFilters`, `.journalCalendar`, `.dayShare` all resolve to `UnmigratedRoutePlaceholder` (`SheetRouteView.swift:107-113,328-350`) and are excluded from deep-link encoding (`DeepLink.swift:304-321`). The **real** Filter UI is `JournalFilterMenu` (`JournalMenus.swift:166-319`, a `Menu` toggling `@Binding` sets owned by `EntryListView`) and the real Calendar is `JournalCalendarView` (`JournalCalendarView.swift:5`) presented via a **local** `.sheet` in `EntryListView.swift:361-365` — neither goes through the navigator at all. Day-share has **no implementation** — only session-share (`SessionShareSheet`) exists. **Fix**: either wire the real UIs through their intended `SheetRoute` (so deep links/`graph.json` edges are truthful) or delete the three dead cases and update this doc + `DeepLink.swift` comments accordingly. Same pattern in Library: `.customSubstancesList`/`.customSubstanceForm` are real `Codable` cases with dispatch stubs that are never triggered — the shipped UI is a bare `NavigationLink` from `SettingsView.swift:32-34` + a local `.sheet` in `CustomSubstancesListView.swift:71-76`.

### DIV-011 — Four distinct "flow complete" dismissal strategies
**Severity**: P2. Environment `dismiss()` (MedFormView, LocationPickerView, MedDetailView-delete), `navigator.dismiss()` (LogMedicationsView cancel), `navigator.dismissAll()` (LogMedicationsView success, QuickLog's `commitTray()`), and no dismissal at all (embedded views like MyMedsCard). Not a bug per se — each is locally correct — but no written rule for when a flow should use which, so new sheets pick arbitrarily.

### DIV-016 — Shared `CancellationCloseButton` applied inconsistently
**Severity**: P2. The modifier (`SheetRouteView.swift:121-136`) is applied to `.sessionDetail`, `.entryDetail`, `.sourcePriority`, `.advancedSearch`, `.dailyDoseSettings` (all at the dispatch site). `.settings` and `.help` explicitly opt out and hand-roll a visually-identical xmark button inside the view itself (`SettingsView.swift:151-161`, `HelpView.swift:85-90`) — same pixels, duplicated code. `TimeAdjustHost` also hand-rolls its own (`SheetRouteView.swift:275-284`) even though it's defined two screens away in the same file. **Fix**: move Settings'/Help's own close button to the shared modifier at the dispatch site; fold `TimeAdjustHost`'s local button into the same helper.

### DIV-017 — Voice-rule violation: "harm-reduction" wording in shipped copy (4 sites)
**Severity**: P0 (violates `CLAUDE.md` directly). Four confirmed user-facing occurrences of "harm reduction"/"harm-reduction," against the repo's explicit house-style ban on that phrase in consumer copy (`CLAUDE.md` → Voice section: "Nobody here thinks you need *reducing*"):

1. `Piru/Views/Settings/SubstanceDatabaseView.swift:28` — says it **twice** in one footer: "community harm-reduction databases" and "Provided for harm-reduction and educational purposes only." Catalog key is live (`Localizable.xcstrings:33088`, zh-Hans/zh-Hant both translated) — fixing this needs a `translate_catalog.py` pass after the Swift edit, not just the source change.
2. `Piru/Utilities/PDFReportGenerator.swift:930` — `"This report was generated by Piru for informational and harm reduction purposes."` in the exported PDF's footer disclaimer. **Highest stakes of the four**: this is a document a user may hand to a clinician. This string is a plain Swift `String` literal drawn directly via `NSAttributedString`, never routed through `String(localized:)` — it isn't in `Localizable.xcstrings` at all, so this fix is Swift-only (a separate, unrelated gap this implies: the exported PDF disclaimer ships English-only regardless of device locale).
3. `Piru/Views/Search/SearchLandingView.swift:192` — `"Crisis resources, harm-reduction basics, and how Piru works."` (the Help card subtitle on Search landing). Catalog key is live (`Localizable.xcstrings:13806`, zh-Hans/zh-Hant both translated) — needs the same `translate_catalog.py` pass.
4. `Piru/Localizable.xcstrings` carries the two catalog entries above forward to zh-Hans/zh-Hant. A Swift-only fix leaves stale/wrong translated strings behind — remediation order: edit the English source strings in (1) and (3), add the new copy to `translate_catalog.py`'s `T` dict, run it (updates existing keys in place + re-collates), verify the diff is clean.

**Not violations — confirmed, don't "fix" these**:
- `Piru/Data/Services/UserProfile.swift:25` — `case harmReduction = "harm-reduction"` is an internal enum raw value; its user-facing `displayName` is already `"Curious"` (`UserProfile.swift:34`). The raw value never reaches the UI.
- `Piru/Data/SubstanceDB/AppSources.swift:20,32,39` — descriptions of what TripSit/PsychonautWiki/FreeOD Wiki actually are ("Harm reduction community providing factsheets...," etc.) — `CLAUDE.md`'s scholarship exception explicitly covers naming a real field or organization; these are that.
- Doc comments and internal identifiers elsewhere (`DoseLogService`, `RampDownScheduler`, `ReceptorClasses`, `PKModel`, `EffectLens`, etc.) — the rule governs consumer voice, not code comments/identifiers.
- Two `Localizable.xcstrings` entries (`"Harm Reduction"` at line 22060, and the longer "Pharmacological data in this app is compiled..." string at line 33071) are both marked `extractionState: stale` — orphaned from an earlier copy revision, zero current Swift call sites for either. Leave them; a future clean build re-evaluates stale entries per `CLAUDE.md`'s localization workflow, and hand-pruning risks the reformatting trap that workflow warns about.

**Durable check** (generalizing this to a class — "house-voice rule violations in shipped copy"): `rg -i 'harm.?reduction' --include='*.swift' Piru Shared` filtered to string literals (skip `//`/`///` doc comments and non-UI identifiers) is the repeatable audit; run it before each release rather than relying on this one-time finding staying complete.

### DIV-018 — Bespoke non-scaling `.system(size:)` fonts vs. semantic text styles
**Severity**: P1 (accessibility/Dynamic Type). See `tokens.md#TOK-font-scale`. Concentrated in `MechanisticChartView`'s `Canvas` axis labels (`:283,308,326,468`, sizes 8-11, legitimately can't use `Text`-style scaling since it's a `Canvas`) and ~15 other `.system(size:)` sites outside any `Canvas` context that could trivially move to a semantic style. `ActiveNowWindowGraph`'s labels, by contrast, correctly use `.caption2`/`.caption2.weight(.semibold)` (scales). **Fix**: audit the non-`Canvas` `.system(size:)` sites (see tokens.md) and move each to the nearest semantic style.

### DIV-019 — Charting approach mixed within one tab, no documented rule
**Severity**: P2. Swift Charts (`Chart`/`BarMark`/`LineMark`/`SectorMark`) dominates Usage/Tolerance/Insights-hub; hand-rolled `Canvas`+`Path` appears in `HalfLifeCalculatorView`'s decay curve, `SubstanceEliminationCurve` (shared by In Your System + Session detail), and `ToleranceOptionsMenu`'s phone-thumbnail sketches. No comment anywhere states when to reach for which — the `Canvas` instances read as pre-dating a later Swift-Charts-first convention. **Fix**: not urgent to rewrite, but a one-paragraph ADR-style comment (or a note in this doc) stating "Swift Charts for anything with real axes/legends/selection; Canvas only for bespoke non-chart illustrations" would stop the next screen from picking arbitrarily.

### DIV-020 — Dose-tier iconography duplicated with different visual grammar
**Severity**: P1. Live `DoseTierStrip` (`DoseDurationCard.swift:318-385`, growing-diameter colored discs, diameters `[7,10,13,15,18]`) vs. share-card `DoseTierMark` (`SubstanceShareCard.swift:716-736`, escalating SF Symbols: dotted circle → filled circle → exclamation circle → exclamation triangle) encode the identical 5-tier concept with unrelated grammar — a screenshot of the share card doesn't visually match what the user saw in-app. **Fix**: share one tier→visual mapping function; the share card can still render it monochrome/dark-forced, but the *shape* vocabulary should match.

### DIV-021 — "Show All" affordance implemented three different ways on one screen
**Severity**: P2. On `SubstanceDetailView` alone: Effects' "Show All" is a `Button` driving `navigationDestination(isPresented:)` (`SubstanceDetailSections.swift:160-171`, justified — "a header NavigationLink isn't reliably hittable"); Inventory's "Show All" uses the same pattern but a *different* bound `@State` flag; the reference sections (Pharmacology/Chemistry/Sources) use `ShowAllRow` calling `navigator.push(.substanceData(...))` directly. Three call patterns for one recurring gesture on a single screen. **Fix**: at minimum, extract the isPresented-driven pattern into one reusable helper instead of two independent `@State` flags.

### DIV-022 — Disclaimer ("not medical advice") has three visual-weight tiers, and is missing on some dosing screens
**Severity**: P1. Tier (a): hand-copied "Estimate Only" card (`Label`+`.caption`/secondaryLabel+`themeCard()`) in Interactions-via-Timeline (`InteractionTimelineView.swift:745-758`) and Calculator (`HalfLifeCalculatorView.swift:392-405`) — byte-for-byte the same pattern, not componentized. Tier (b): plain `Section` footer, no styling override, in EffectSandbox/EffectPipelineExplainer. Tier (c): **absent entirely** in Pharma Search, Ceiling Effect, ToleranceExplainer, Volumetric Dosing (a yellow "Safety" card exists but isn't a medical-advice disclaimer), and all of Inventory. Ceiling/ToleranceExplainer instead use softer epistemic-humility phrasing without the "not medical advice" words at all. **Fix**: extract tier (a) into a shared `EstimateOnlyDisclaimer` component; decide deliberately (not by omission) whether Pharma/Ceiling need one.

### DIV-023 — Unsupported-substance handling differs in visual weight between sibling equivalence tools
**Severity**: P1. Benzo Equivalence silently demotes an unconvertible substance to `"--"` + small caption (`unconvertibleReason`, `BenzoEquivalenceToolView.swift:199-204`); Opioid Equivalence promotes methadone/fentanyl/buprenorphine to a full first-class orange-icon `specialCard` ("Not a simple conversion," `OpioidEquivalenceToolView.swift:217-230`) for the conceptually identical "can't convert this one" state. **Fix**: pick one treatment (the Opioid `specialCard` is more honest about the limitation) and apply to both.

### DIV-025 — Screens filed outside the folder their route/tab implies
**Severity**: P2 (navigability for future agents, not user-visible). `HalfLifeCalculatorView.swift` (a `Tool`) lives in `Views/Insights/`; `PharmaTableView.swift` (a `Tool`) and `SubstanceCardView.swift`/`InteractionsSummaryCard.swift` (Tools/QuickLog components) live in `Views/Library/SubstanceDetail/`; `ToleranceToolView.swift` (an `Insight` route) lives in `Views/Tools/Tolerance/`; `SourcePriorityView.swift` lives in `Views/Settings/` and `AdvancedSearchView.swift` in `Views/Search/` despite both being Library-adjacent. No functional impact (routing is centralized in `AppDestinations.swift`), but any folder-based navigation (including this graph's screenshot-to-file mapping) must go through the route table, not the directory tree.

### DIV-026 — Dead code confirmed via grep (zero call sites)
**Severity**: P2. `StatusBanner`/`JokeBanner` (`SubstanceContentSections.swift:144-207`), `CombinedDepressionBanner`, `MonoamineProfileCard` (the View — its data model is still alive), `DoseRangeRows`, `DurationInfoView`, `SubstanceDot` (`InventorySupport.swift:314-324`), and the entire `AdvancedSearchView.swift` screen (wired to `SheetRoute.advancedSearch`, excluded from deep links, doc-comment claims a tier-gated entry point that does not exist anywhere in the codebase). **Fix**: delete, or if intentionally kept for a near-future feature, add a `// TODO` explaining why.

### DIV-027 — "Superview" `@State` anti-pattern, ranked
**Severity**: P1 (violates `CLAUDE.md`'s explicit rule). Ranked worst-first: `StagedDoseEditor.swift` (1063 ln, 21 state properties — 3 genuinely different sub-modes, natural split candidates); `EntryFormView.swift` (633 ln, 21 `@State`, duplicating logic the sibling `@Observable EntryDraft` already solved — this one is reachable only from `DayEntryRow`'s swipe/context menu, so it's a live, user-facing duplicate flow, not dead code); `QuickLogDock.swift` (1024 ln, 12 state properties, partially mitigated by deliberate non-`@Observable` boxing to avoid per-frame invalidation); `SessionDetailView.swift` (675 ln, passes the strict count but has an inline un-extracted "Note" `Section` breaking its own per-file-section pattern). Counter-examples worth citing as the target pattern: `MedFormView.swift` (`@Observable MedFormDraft`), `QuickLogModels.swift` (0 `@State`), `SessionDetailModel.swift`/`SessionEntryListSection.swift` (textbook narrow-input/derived-state split).

### DIV-028 — Hero/summary row anatomy hand-duplicated instead of shared
**Severity**: P2. `EntryReadHero` (`EntryReadContent.swift:155-246`) and `BodyLoadRowLabel` (`SessionBodyLoadSection.swift:17-118`) independently implement the same "dot·name·trailing measurement·status line" anatomy (the latter's own comment acknowledges this is deliberate, not accidental). Same for `EntryInteractionEchoRow` (`EntrySessionSection.swift:141-166`) vs. `SessionSafetySection.interactionRow` (`:35-71`) — the former's comment literally says "mirrors the session-safety anatomy." **Fix**: low urgency (each is individually well-factored), but a shared `AnatomyRow` primitive would remove ~150 lines of parallel maintenance.

### DIV-029 — Mixed foldable/non-foldable section-header idiom on one screen
**Severity**: P2. Substance Detail's reference sections mostly use `CollapsibleSection` (`DisclosureGroup`+optional info-button+count badge, `SubstanceDetailSupport.swift:28-96`) — Mechanism, Receptor Literature, Pharmacokinetics, Metabolism, Info, Chemistry. But "Also Active" metabolite cards, "Metabolism Interactions," and "Common misconceptions" use a plain `Section`+`Label` header instead (deliberately non-collapsible per in-code rationale) — with no shared visual cue (e.g. a chevron) telling the user which header type they're looking at until they tap it.

### DIV-030 — Font-scale divergence for the same data point (hub vs. detail)
**Severity**: P2. Adherence streak count: `.system(.largeTitle, design: .rounded, weight: .bold)` in the detail screen (`AdherenceView.swift:145`) vs. `.title2` for the identical number in the Insights-hub glance card (`InsightsView.swift:136-137`). Likely an intentional hero-vs-glance hierarchy, but undocumented as such.

### DIV-031 — `InventorySupplyBar` color philosophy split across reuse sites
**Severity**: P2. Inventory's own screens tint the shared bar via substance-palette color at 0.5 opacity (`InventorySupport.swift:74-80`); the two external reuse sites (`InventoryStockSection.swift:81` in Substance Detail's Track/Restock, `SubstanceCardView.swift:175`) use the flatter `StockStatus.barTint` (primary/orange/red at 0.35) instead — same component, two color philosophies depending on the caller.

### DIV-032 — `ComedownGuideView` has two different navigation-title behaviors depending on entry route
**Severity**: P2. Reached via `PushRoute.tool(.recovery)`, the title "Recovery Guide" is set at the dispatch switch (`AppDestinations.swift:107`). Reached via the second route resolving to the same view, `PushRoute.comedownGuide` (from `RampDownView`'s "Full recovery guide" link, `RampDownView.swift:186-189`), **no title is set at all** — `ComedownGuideView` itself declares none. **Fix**: move the title into `ComedownGuideView` itself so it's correct regardless of entry route.

## Meds / DailyDose-specific

### DIV-012 — Three logging metaphors for the same `DailyDoseItem` concept
**Severity**: P0 (core, frequently-used flow). Check-circle log/unlog (`MyMedsCard`'s `SlotRowView`, `:520-527`); no logging control at all, navigation-only (`MyMedsHubView`'s `MedRow`, `:209-289` — the whole row is one `Button` that pushes `.medDetail`); pre-log exclude-toggle (`LogMedicationsView`'s per-item `Toggle`, `LogDailyDoseView.swift:51-59`). Three genuinely different mental models for "did I take this" spread across three screens that all touch `DailyDoseItem`. **Fix**: pick one primary metaphor (check-circle reads best for the common case) and make Hub rows support it directly instead of requiring a detail-screen or log-sheet round-trip.

### DIV-013 — Med avatar/icon tile size disagrees between two screens showing the same med
**Severity**: P2. 30×30 in `MyMedsHubView.swift:220` vs. 44×44 in `MedDetailView.swift:127`. See also 3 different circular-control stroke weights in `MyMedsCard.swift` alone (`lineWidth: 2` check-circle at `:479-498`, `lineWidth: 4` progress ring at `:207-212`, `lineWidth: 2.5` supplements circle at `:328-331`).

### DIV-014 — QuickLog's internal card chrome bypasses `Theme.themeCard()` entirely
**Severity**: P1. Every card *inside* the dock (`DockGroupedCard`, `QuickLogSupport.swift:8-18`; `TrayStagedListCard`, `DoseTrayViews.swift:52-55`) hardcodes flat `Color(.secondarySystemGroupedBackground)` with no light/dark branch and no material — while the **cover screen's own** cards one layer up call `.themeCard()` normally (`QuickLogSupport.swift:573,314`). This is likely deliberate (the dock rides the native sheet's own glass platter, documented via `.presentationBackground { Color.clear }` in `QuickLogSupport.swift:81`), but it means QuickLog's internal cards will not pick up any future `Theme.cardBackground` retheme the rest of the app gets. `DockGroupedCard` itself carries a self-flagged TODO: `// TODO(integrator): promote to Components/ if reused outside QuickLog` (`QuickLogDockCards.swift:5`).

### DIV-015 — Destructive-action confirmation is inconsistent
**Severity**: P1. `DataStorageView` gates every destructive action behind `.confirmationDialog`/`.alert` (restore-merge-or-replace, delete-everything, restore-recoverable, `:137-165`); `SourcePriorityView`'s "Reset" toolbar button resets to defaults with **no confirmation** (`:33-37`); `SubstanceColorsListView`'s `.onDelete` swipe deletes with no confirmation (`:50-54`). Similarly, `EntryDetailView` confirms dose deletion via `.confirmationDialog` (`:115-125`) but `SessionDetailView`'s per-row swipe/context delete (`DayEntryRow.swift:48,81`) and note delete (`SessionDetailView.swift:614-616`) have none. **Fix**: audit which of these are genuinely low-stakes (a color reset is reversible; a full data delete is not) and apply `.confirmationDialog` consistently to the irreversible ones — Reset-to-defaults and swipe-delete-a-color are the cheapest fixes.

## Full DIV index (quick lookup)

| ID | One-line | Severity |
|---|---|---|
| DIV-001 | Card corner radius has no single source of truth | P1 |
| DIV-002 | No semantic success/warning/danger color tokens | P0 |
| DIV-003 | Capsule chip reimplemented instead of reused | P1 |
| DIV-004 | Empty-state idiom inconsistent | P1 |
| DIV-005 | Two incompatible "one dose" row visual languages | P0 |
| DIV-006 | Chip metrics disagree (hero vs. row) | P1 |
| DIV-007 | Curve-fill convention disagrees three ways | P1 |
| DIV-008 | Chart accessibility narration disagrees | P0 |
| DIV-009 | Navigation-push mechanism inconsistent | P2 |
| DIV-010 | Three dead `SheetRoute` cases + bypassed Custom Substances route | P1 |
| DIV-011 | Four dismissal strategies for "flow complete" | P2 |
| DIV-012 | Three logging metaphors for `DailyDoseItem` | P0 |
| DIV-013 | Med avatar tile size disagrees 30×30 vs 44×44 | P2 |
| DIV-014 | QuickLog card chrome bypasses `Theme.themeCard()` | P1 |
| DIV-015 | Destructive-action confirmation inconsistent | P1 |
| DIV-016 | Shared `CancellationCloseButton` applied inconsistently | P2 |
| DIV-017 | "harm-reduction" wording violates house voice rule (4 sites incl. exported PDF) | P0 |
| DIV-018 | Non-scaling bespoke fonts vs. semantic text styles | P1 |
| DIV-019 | Charting approach (Swift Charts vs. Canvas) mixed, undocumented | P2 |
| DIV-020 | Dose-tier iconography duplicated with different grammar | P1 |
| DIV-021 | "Show All" affordance implemented 3 ways on one screen | P2 |
| DIV-022 | Disclaimer visual weight has 3 tiers, missing on some screens | P1 |
| DIV-023 | Unsupported-substance handling differs Benzo vs. Opioid | P1 |
| DIV-024 | Dead `SheetRoute` cases for Custom Substances (see DIV-010) | P1 |
| DIV-025 | Screens filed outside their route's implied folder | P2 |
| DIV-026 | Dead code confirmed via grep (zero call sites) | P2 |
| DIV-027 | "Superview" `@State` anti-pattern, ranked | P1 |
| DIV-028 | Hero/summary row anatomy hand-duplicated | P2 |
| DIV-029 | Mixed foldable/non-foldable section-header idiom | P2 |
| DIV-030 | Font-scale divergence for same data point (hub vs detail) | P2 |
| DIV-031 | `InventorySupplyBar` color philosophy split | P2 |
| DIV-032 | `ComedownGuideView` nav-title depends on entry route | P2 |
