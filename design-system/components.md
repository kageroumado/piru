---
id: components
type: index
description: De-facto component inventory — what exists, its API, and where it's reimplemented inline instead of reused.
---

# Components

`Piru/Views/Components/` (37 files, 5495 lines) is the app's explicit shared-component folder,
but it is **partly** a genuine reuse library and **partly** an overflow bin for splitting large
files under the ~2500-line budget (`CLAUDE.md` → Lint/format tooling). This file separates the
two. Each heading is a `component`-type graph node (`CMP-<name>`); `edges: [{rel: "used_by", target: "SCR-..."}]`
in `graph.json` links each component to the screens that construct it.

## Genuinely cross-feature (real reuse — treat as the stable API surface)

### CMP-theme-card — `Theme.themeCard(cornerRadius:)` / `Theme.themeCapsule()`
`Piru/Theme.swift:78-108`. The app's single most-used surface treatment: `.ultraThinMaterial` in light mode, a solid near-black (`Theme.cardBackground`) in dark mode. Default radius `22`; a `16` overload exists for cards nested inside another grouped container. 60+ bare-default call sites, 6 at `cornerRadius:16`. See `tokens.md#TOK-radius`, `divergences.md#DIV-001`.

### CMP-glance-card — `GlanceCard` family
`Piru/Views/Components/GlanceCard.swift` (124 ln): `GlanceCard`, `GlanceCardHeader` (fixed 26pt icon column + `.headline` title), `GlanceCardChevron`, `GlanceRow`, `GlanceMoreRow`. The canonical "dashboard tile" — one `NavigationLink` wrapping icon+title+chevron+optional live-data rows. Used by: Insights hub (all 4 cards), Tools hub (`InteractionsSummaryCard`, `InventorySummaryCard`), `HalfLifeCalculatorView`↔`InYourSystemView` cross-links, `ToolsView`'s 6 plain-row tools. This is the best-reused family in the app — no known reimplementation.

### CMP-capsule-chip — `CapsuleChip.swift`
`capsuleChip(tint:)` (`.caption2`, 8h/3v padding, `:7-13`) and `heroChip(tint:)` (`.caption`, 10h/5v, `:20-26`). **Under-adopted**: at least 6 sites hand-roll the same visual with drifted opacity/padding instead of calling these modifiers — see `divergences.md#DIV-003`.

### CMP-app-chrome — `AppChrome.swift`
`Piru/Views/AppChrome.swift` (111 ln): `.appNavigationBar(title:)` (the shared tab-root nav-bar treatment) + `AppOverflowMenu` (the ••• Settings/Help menu present on every tab root) + `NavCardLabel`. Applied to every Tools screen and all 4 tab roots.

### CMP-flow-layout — `FlowLayout.swift`
`Piru/Views/Components/FlowLayout.swift`. Custom `Layout` for wrapping chip/tag rows. Used by Interactions' capsule selector, Search's category legend, alias-chip rows.

### CMP-salt-isomer-picker — `SaltPicker.swift` / `IsomerPicker.swift`
Shared route/salt/isomer selection controls. Genuinely reused across `EntryFormView`, `EntryEditContent`, QuickLog's `StagedDoseEditor` — confirmed via grep, not duplicated.

### CMP-substance-search-field — `SubstanceSearchField.swift`
Debounced substance-name search field with clear button. Reused by Calculator, Inventory forms, Journal/Med forms, `LocationPickerView`'s parent flows. **Not** reused by `PharmaTableView`, which hand-rolls its own search `TextField`+clear-button despite identical intent (`divergences.md`'s Tools findings).

### CMP-elimination-curve — `SubstanceEliminationCurve.swift`
`Piru/Views/Components/SubstanceEliminationCurve.swift` (173 ln). `Canvas`-based multi-dose decay curve with 50%/25% dashed milestones + "now" dot. Explicitly shared, per its own header comment, between `InYourSystemView` and `SessionDetailView`'s "In Your Body" section — a good example of the intended extraction pattern.

### CMP-accessibility-primitives — `AccessibilityPrimitives.swift`
`chartSummaryAccessibility(label:value:)` — collapses a Swift-Charts `Chart`'s children and sets a synthesized label+value. Used consistently across Usage's and Tolerance's every chart (`divergences.md#DIV-008` notes the one exception, `InsightsView.usageChart`).

### CMP-cancellation-close-button — `CancellationCloseButton` (private `ViewModifier`)
`Piru/Navigation/SheetRouteView.swift:121-136`, applied via `.withCancellationCloseButton()`. The shared sheet-root xmark/`.cancellationAction` Close button. Applied to `.sessionDetail`/`.entryDetail`/`.sourcePriority`/`.advancedSearch`/`.dailyDoseSettings`; **not** applied (hand-duplicated instead) by `.settings`/`.help`/`TimeAdjustHost` — see `divergences.md#DIV-016`. Worth promoting out of `SheetRouteView.swift` (currently `private`) into `Components/` so those three call sites can adopt it directly.

### CMP-glass-pill-button — `GlassPillButton.swift`
Used by every Onboarding step's CTA (9 call sites) — the cleanest single-component reuse story found in the whole audit.

### CMP-content-card — `CardBackground` (`Theme.swift`)
A standalone `View` wrapping the same scheme-adaptive fill as `themeCard`, for `.listRowBackground` call sites — used 28+ times across Session/Tools/Inventory/Settings/Help.

## Component, but single-purpose (extracted for file-length budget, not cross-feature reuse)

These live in `Views/Components/` or a feature folder but have exactly one call site — they are
legitimate splits under the ~2500-line file-length rule, not shared design-system vocabulary.
Don't propose "reuse this more," just don't mistake the folder location for reuse:
`ContraceptionCautionBanner`, `ElevenHydroxyTHCCard`, `AcetaldehydeCard`, `PharmacologyCard`,
`DosingNotes` (has a stale orphaned `// MARK:` at line 51 with no following content — cheap
cleanup), `MythBustSection`, `SubstancePeptideSection`.

## Reimplemented instead of reused (the actual "divergence" cases)

| Concept | Shared component that exists | Sites that reimplement it instead |
|---|---|---|
| Capsule chip | `CapsuleChip.swift` (`capsuleChip`/`heroChip`) | `SubstanceLibraryView.swift:490-517`, `InventoryMenus.swift:218-228`, `ToleranceCard.swift:60-82`, `MyMedsCard.swift:296-301` |
| Substance search field | `SubstanceSearchField.swift` | `PharmaTableView.swift:86-110` |
| Dose-tier visual | `DoseTierStrip` (`DoseDurationCard.swift:318-385`) | `DoseTierMark` (`SubstanceShareCard.swift:716-736`) — different SF-Symbol grammar, see `DIV-020` |
| "Estimate only" disclaimer card | (none extracted yet, but copy-pasted identically twice) | `InteractionTimelineView.swift:745-758` ≈ `HalfLifeCalculatorView.swift:392-405` — candidate for a new `EstimateOnlyDisclaimer` component |
| `safetyPoint(_:)` bullet helper | (none) | duplicated verbatim in `BenzoEquivalenceToolView.swift:297-308` and `OpioidEquivalenceToolView.swift:269-280` |
| Weekday-circle button row | (none) | duplicated verbatim `MedFormView.swift:276-304` vs `MedDetailView.swift:281-303` |
| "Row = icon + title + detail" anatomy | (none) | hand-duplicated 3+ times: `DataStorageView`'s `optionRow`/`dataRow`, `HelpView`'s `groundingTip` |
| Hero/summary row anatomy | (none) | `EntryReadHero` vs `BodyLoadRowLabel` vs `EntryInteractionEchoRow` vs `SessionSafetySection.interactionRow` — see `DIV-028` |

## Confirmed dead components (zero construction sites, grep-verified)

`StatusBanner`/`JokeBanner` (`SubstanceContentSections.swift:144-207`), `CombinedDepressionBanner`,
`MonoamineProfileCard` (the View only — its data model + `DopamineSerotoninLeanBar` subview are
still alive), `DoseRangeRows`, `DurationInfoView`, `SubstanceDot` (`InventorySupport.swift:314-324`).
See `divergences.md#DIV-026`.
