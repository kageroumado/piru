# Piru

Substance dose tracking iOS app built with SwiftUI and SwiftData. Logs doses, browses 1,900+ substances from a bundled SQLite database (sourced from TripSit/PsychonautWiki/DailyMed and curated data), checks interactions, and provides pharmacokinetic insights.

## Voice (read before writing any user-facing copy)

**Anti-guilt, assumes competence. Do NOT use the phrase "harm reduction" in app or marketing copy** — it implies the user is guilty of something needing reduction. The established house lines (already on the site and in the README — keep them, and write in this register):

- "This is not harm reduction. Nobody here thinks you need *reducing*."
- "a dose is not a confession."
- "it's not a question of goodness — it's a question of dose."
- "Most tracking apps are built to make you take less. Piru isn't."

Piru presents as a **reference, a record, and a model** — what is known about a substance, what you logged, how the pharmacology behaves. Never advice to use, never a dosing recommendation. "Not medical advice" stays prominent.

(The rule is about *consumer* voice, not scholarship: in a peer-reviewed paper "harm reduction" is a legitimate field name.)

## Working Style

- **Use sub-agents** for research, exploration, and parallel tasks. Spawn agents for codebase searches, multi-file reads, and independent investigations rather than doing everything sequentially in the main context.
- Prefer editing existing files over creating new ones.
- Keep changes minimal and focused — no over-engineering.

## Build & Test

**Prefer the Xcode MCP over raw `xcodebuild`.** Use `mcp__xcode__BuildProject` to build and `mcp__xcode__RunAllTests` / `mcp__xcode__RunSomeTests` to test. The MCP surfaces compiler errors and warnings far more legibly than parsing `xcodebuild` output, and it drives the one shared Xcode/DerivedData instance — so it won't race a build another agent (or the IDE) already has in flight. Raw `xcodebuild` is a fallback for CI or when the MCP is unavailable; two concurrent `xcodebuild` invocations against the same DerivedData clobber each other.

```bash
# Fallback only (prefer the Xcode MCP above):
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test

# Build & run the SubstanceValidator CLI tool
cd Tools/SubstanceValidator && swift build
cd Tools/SubstanceValidator && swift run SubstanceValidator validate
```

## Releases & schema versioning

- **Each shipped build is git-tagged** (`vMAJOR.MINOR-bBUILD`). Run `git tag --sort=-creatordate | head` to find the current shipped baseline; everything after the newest tag is **unreleased**. Tag every release going forward so this stays true.
- **Never bump a persisted schema version that hasn't shipped.** Many schema/data changes land between releases and never reach a user, so the "current" version is often itself unshipped — amend it *in place* rather than minting `n+1`. Check the newest release tag before assuming a version is live in the wild.
  - **SwiftData store:** uses additive automatic lightweight migration with **no version ladder** (see `StoreRecovery`'s schema-migration policy). Additive `@Model` changes (new entity, new optional/defaulted field) need **no** version bump and no migration plan at all. Only a genuinely non-additive change reintroduces a scoped `VersionedSchema` + `MigrationStage`.
  - **Bundled substance SQLite** (`manifest.schema_version`, currently `6`): the DB ships as a wholesale-replaced bundle artifact, so its version can be edited in place pre-release — only bump it for a change that an *already-shipped* app must read.

## Rebuilding the bundled substance DB

`pipeline/build.sh` (default `fast`) is **quick, offline, and reproducible** — it rebuilds the whole `Piru/Data/piru-substances.sqlite` from committed inputs (cached web snapshots in `data/sources/` + the curated layer in `data/curated/`) plus external extracts in `/tmp/piru-extract`. `pipeline/build.sh full` additionally re-runs the upstream scrape (network).

- **Always rebuild the WHOLE DB through the pipeline — never hand-edit the bundled `.sqlite`.** A surgical/manual edit hides build-pipeline bugs (they only surface on a full rebuild) and is silently clobbered on the next run. Because the full rebuild is fast and offline, there is never a reason to avoid it.
- To change pharmacology/MOA data, edit the curated source (`data/curated/`), then `pipeline/build.sh fast`, then commit the rebuilt `piru-substances.sqlite` + `manifest.json` + `data/snapshots/*`.
- Some datasources are private (not in this open-source repo); the build **warns loudly** when an external extract is missing and produces a clearly-partial DB rather than failing silently (set `PIRU_REQUIRE_EXTERNAL=1` to hard-fail instead).

## Architecture

**Pattern**: SwiftUI + SwiftData with @Observable singletons — no formal MVVM ViewModels.

```
Piru/
├── Domain/          # value-type domain models (NOT SwiftData): Substance struct, DoseRange, DurationProfile, DoseUnit, JournalModel, PSID
├── Views/           # SwiftUI views (ContentView has 4 tabs: Journal, Library, Tools, Insights)
│   ├── Insights/    # Adherence, half-life calc, activity charts, usage stats
│   └── Components/
├── Data/            # per-concern subfolders (all filesystem-synchronized groups):
│   ├── SubstanceDB/     # SubstanceStore (GRDB over bundled SQLite) + extensions, SubstanceLibrary façade, AppSources, DB updater/manifest, search history
│   ├── Persistence/     # SwiftData store lifecycle: StoreRecovery, StoreHealth, StoreDiagnostics, backfill migrations
│   ├── Backup/          # BackupManager, BackupCrypto (AES-256-GCM encrypted backups)
│   ├── Pharmacology/    # the science: HalfLifeDatabase, MechanismOfActionDatabase, receptor/metabolism/effect models
│   ├── Tolerance/       # ToleranceStore, ToleranceModulation
│   └── Services/        # Interactions, Benzo/OpioidEquivalence, InventoryService, UserProfile(+Store)
├── Utilities/       # ActiveSubstanceCalculator, RampDownScheduler, LiveActivityManager, etc.
├── Navigation/      # AppNavigator + route enums + deep link codec — single source of truth for tab/sheet/path state
Shared/              # Code shared across all targets (widget + Live Activity):
│   ├── Models/         # the 15 SwiftData @Model (DoseEntry, Session, DailyDoseItem, …)
│   ├── Engines/        # PKModel, PDModel, EffectEngine, TimelineCurveModel, SessionClustering
│   ├── Formatting/     # DoseFormatting, ColorHex, ConfidenceTier
│   └── (root)          # value types: RouteOfAdministration, ByVolumeDosing, SessionVitals, TimelineGraphView, PiruActivityAttributes
PiruLiveActivityExtension/  # Lock Screen Live Activity widget
PiruWidget/          # Home Screen widgets (Today's Summary, Recent Dose)
PiruTests/           # 105 test files, ~1,300 tests using Apple Testing framework (@Suite, @Test)
Tools/SubstanceValidator/   # SPM CLI tool for validating substance data against APIs
pipeline/            # Python data pipeline that builds the bundled substance SQLite DB
```

## Key Files

| File | Purpose |
|------|---------|
| `Domain/Substance.swift` | Core `Substance` struct, `DoseRange`, `DurationProfile`, `SubstanceCategory` enum (23 categories) |
| `Shared/Models/DoseEntry.swift` | SwiftData `@Model` for logged doses (shared with widget) |
| `Shared/Models/DailyDoseItem.swift` | SwiftData `@Model` for daily medication tracking (shared with widget) |
| `Shared/Models/SubstanceColor.swift` | SwiftData `@Model` + 31 preset colors (shared with widget) |
| `Shared/RouteOfAdministration.swift` | 10 routes enum (shared with widget) |
| `Shared/Formatting/DoseFormatting.swift` | `Double.doseFormatted` extension (shared with widget) |
| `Data/SubstanceDB/SubstanceStore.swift` | `@Observable @MainActor` singleton — GRDB queries over the bundled SQLite DB with per-field source-priority resolution, ranked search, caches. Also hosts the `SubstanceLibrary` static façade (overlay-aware lookups) at the bottom of the file |
| `Data/SubstanceDB/SubstanceDBUpdater.swift` | Opt-in over-the-air updates for the bundled substance DB (manifest + checksum) |
| `Data/Persistence/StoreRecovery.swift` | Never-delete SwiftData store recovery: versioned migration plan + data-aware fallback |
| `Data/Pharmacology/HalfLifeDatabase.swift` | 530+ hardcoded half-life values (minutes) |
| `Data/Services/Interactions.swift` | Drug class mapping + 76 interaction severity rules |
| `Shared/Engines/PKModel.swift` | One-compartment oral PK model (concentration, Tmax, Cmax, ka estimation) |
| `Utilities/RampDownScheduler.swift` | Harm-reduction notifications with session-based grouping |
| `Views/InteractionTimelineView.swift` | PK curve overlay with interaction danger window visualization |
| `Views/DoseSuggestionCard.swift` | Smart dose suggestion card shown during quick-log |
| `Views/ContentView.swift` | Main TabView (Journal, Library, Tools, Insights) |
| `Views/QuickLogView.swift` | Modal for quick dose logging (plus per-type `QuickLog*.swift` files split out alongside it) |
| `Navigation/AppNavigator.swift` | `@Observable @MainActor` singleton owning `selectedTab`, per-tab push paths, and the sheet stack |
| `Navigation/Routes.swift` | `AppTab`, `PushRoute`, `SheetRoute` enums + `NavigatorSnapshot` (all Codable for deep links) |
| `Navigation/DeepLink.swift` | `piru://` URL ↔ `NavigatorSnapshot` codec |
| `Navigation/SheetRouteView.swift` | Dispatches a `SheetRoute` to its underlying view |
| `Theme.swift` | Accent color + secondary label styling |

## Data Layer

- **Persistence**: SwiftData for user data (DoseEntry, DailyDoseItem, SubstanceColor, FavoriteSubstance, UserColor)
- **Substance data**: Ships as a bundled SQLite DB (`Piru/Data/piru-substances.sqlite`) built by `pipeline/build.sh` from TripSit/PsychonautWiki/DailyMed + curated data — editing pipeline JSON does nothing without a rebuild. `SubstanceStore` resolves each field by per-source priority (user-reorderable); `SubstanceDBUpdater` handles opt-in DB updates
- **Queries**: Use `@Query` macro in views for SwiftData, `SubstanceLibrary.all` for substance lookups
- **Substance lookups go through the `SubstanceLibrary` façade** (bottom of `SubstanceStore.swift`), never raw `SubstanceStore.shared.lookup*` — the façade overlays `CustomSubstanceStore` user edits (duration overrides, relabels); bypassing it silently drops those overrides
- **Search**: Ranked cascade (exact → alias → prefix → contains → fuzzy via Levenshtein distance)
- **Export**: PsyLog-compatible JSON format via `DataExportImport`; PDF reports with PK charts via `PDFReportGenerator`
- **Shared code**: SwiftData models + formatting live in `Shared/` with multi-target membership (Piru, PiruWidget, PiruLiveActivityExtension)

## Navigation

Navigation state is centralised in `AppNavigator` (`Piru/Navigation/`). Views read tab/sheet state through `@Environment(\.appNavigator)` rather than holding their own `@State` flags. The key rules:

- **Present a sheet**: `navigator.present(.someRoute)`. To atomically swap the current sheet for another (e.g. Save → ColorPicker), use `replacingTop: true`.
- **Dismiss a sheet**: `navigator.dismiss()`. Direct state mutation, not the env `dismiss()` round-trip — that's why Done/Cancel feel instant now.
- **`@Environment(\.dismiss)` is fine** in views that can be either pushed or presented (e.g. `EntryDetailView`) — the system routes it correctly. For dedicated sheet roots, prefer `navigator.dismiss()` for explicitness.
- **New screens**: add a case to `SheetRoute` (or `PushRoute`) and a dispatch arm in `SheetRouteView`. Update `DeepLink.encode/decode` if the route should be deep-linkable.

`piru://` URLs route through `DeepLink.decode` → `navigator.snapshot = decoded`. URL scheme is registered in `Piru/Info.plist`.

## Testing

Uses **Apple Testing framework** (Swift Testing), not XCTest:
```swift
@Suite("DoseEntry")
struct DoseEntryTests {
    @Test("Initializes with correct default values")
    func defaults() { ... }
}
```

**Coverage areas**: Models (Substance, DoseEntry, DoseRange, DurationProfile, RouteOfAdministration, etc.), Data (BundledDatabase, SourcePriorityResolution, SubstanceLibrary, SubstanceCustomOverlay, Interactions, HalfLifeDatabase, AppSources, StoreRecovery, BackupCrypto/BackupManager, SubstanceDBUpdater), Utilities (AdherenceCalculator, DataExportImport, PKModel, RampDownScheduler, TagExtractor, ColorHex, SessionClustering, SessionService), Features (FuzzySearch, NotificationGrouping, Navigation/DeepLink).

## Conventions

- **Spelling**: Use **US English** everywhere — code, comments, and user-facing strings (`color` not `colour`, `behavior` not `behaviour`, `-ize`/`-ization` not `-ise`/`-isation`, `gray`, `center`, `modeled`, `signaling`). The lone exception is proper nouns and official names, which keep their real spelling (e.g. the poison-control "Centre Antipoison", the "European Monitoring Centre for Drugs and Drug Addiction").
- **Localization**: The app ships **English, Simplified Chinese (`zh-Hans`), and Traditional Chinese (`zh-Hant`)** via `Piru/Localizable.xcstrings`. **Every user-facing string must be localized** — use `Text("...")`, `LocalizedStringKey`, or `String(localized:)`; never hardcode a bare `String` into UI. Strings passed to non-localizing APIs (e.g. accessibility labels taking `String`) still need `String(localized:)`.
  - **NEVER hand-edit `Localizable.xcstrings` with a generic JSON writer.** Xcode owns its format — `" : "` key separators (spaces around the colon), empty entries written `"key" : {\n\n    }` (not `{}`), CJK stored literally (no `\uXXXX`), no trailing newline, and keys ordered by Unicode collation Python can't reproduce. A naïve `json.dump` reformats all ~20k lines and the diff becomes unreviewable.
  - **Workflow for new strings:** add the English `Text("…")` in code, then add `"English": ("简体", "繁體")` to the `T` dict in **`translate_catalog.py`** and run `python3 translate_catalog.py`. It updates existing keys in place with a byte-identical serializer (see `serialize_catalog`). For a string Xcode hasn't extracted yet (CLI-only change, project not opened), add it to the `NEW_KEYS` allow-list in `__main__` so it gets inserted — keep that set to just the handful you added (don't bulk-insert all of `T`, or a catalog inherits strings its target never uses; the widget catalog is intentionally a small subset). The script leaves a no-op run as an empty `git diff`.
  - **The script canonicalizes order itself — no build-first dance needed.** After filling translations, `translate_catalog.py` runs `canonicalize_catalogs()`: an `xcodebuild -exportLocalizations` → `-importLocalizations` round-trip that hands every project `.xcstrings` back to Xcode to re-collate into its canonical (ICU-collated) key order. This is the *only* reliable headless way to get Xcode's ordering — verified facts: (1) Python can't reproduce the collation; (2) `xcodebuild build`/`clean build` (CLI **or** IDE-via-AppleScript) never writes the source catalog back, so a build can't reorder it; (3) standalone `xcstringstool sync` mangles the catalog (stales hundreds of live strings, drops keys like `Substance Info` that are present in the `.stringsdata`) — that's the trap the old "build first" note danced around. The export/import round-trip is **idempotent** (second pass = byte-identical) and **non-destructive** (no keys dropped, stale marks and untranslated entries preserved); it also cross-fills a catalog's untranslated keys from project-wide translations (e.g. the widget's `Onset`/`Peak` pick up the main catalog's zh values), matching what Xcode does on its own. So the durable workflow is just **add to `T` → run the script → commit** — the script owns both translations *and* ordering. It still appends `NEW_KEYS` to the end first, but the round-trip then relocates them canonically, which is exactly what stops the IDE from re-ordering the file on the next build. Falls back gracefully (leaves the unsorted Python output) if `xcodebuild` is unavailable.
  - **Don't auto-prune stale entries.** `extractionState: stale` is a *candidate* signal, not proof of death — the lightweight extractor false-flags strings resolved via `String(localized:)` in helpers (e.g. `MechanismOfActionDatabase.moa()` summaries) or used only from another target. Deleting those ships English to zh users at runtime. Leave orphans in place (harmless unused entries); a future clean build re-evaluates them. We do **not** use a TMS (SimpleLocalize/Localazy) — translations are authored directly in `translate_catalog.py`.
- **Decompose views eagerly — never grow a "superview" holding piles of state.** A SwiftUI `View` is one *invalidation boundary*: any `@State` change re-evaluates the **entire** `body`, every section, every modifier. A view with 15–30 pieces of `@State` is both a performance problem (everything re-renders on any change) and a correctness hazard (tangled interdependencies, stale values, effects firing on the wrong change — the hard-to-trace bugs live here). Split a view **as soon as it grows past a few hundred lines or takes on more than one role** — don't defer it to a later refactor pass. The rules:
  1. **Each section → its own `View` `struct` with narrow inputs** — only the fields it reads (value types by `let`, shared mutable state by `@Binding`, its own `@Environment`, actions as closures). **Not** a `private var section: some View` and **not** a `@ViewBuilder` helper — those share the parent's invalidation boundary and buy nothing.
  2. **More than ~6 `@State` is a smell.** Async-loaded data belongs in an `@Observable @MainActor` model filled in `.task`; a multi-field edit draft belongs in **one** `@Observable` draft model. Keep only genuine UI toggles as `@State`.
  3. Reference example: the giant-view decomposition of `SubstanceDetailView`/`SessionDetailView`/`EntryDetailView`/`QuickLogDock`/`ToleranceToolView` (each 1200–1600 lines → a thin coordinator + narrow-input subviews + an `@Observable` model). Follow the `swiftui-specialist` skill (`structure.md`, `dataflow.md`) when doing this.
- **iOS 26+** minimum deployment target (Liquid Glass UI throughout)
- **Swift 6** strict concurrency (`default-isolation=MainActor`)
- **No `Text + Text` concatenation.** The SwiftUI `+` operator on `Text` is deprecated in iOS 26 and trips a build warning (`'+' was deprecated in iOS 26.0: Use string interpolation on Text`). Build the value in one shot instead: a single `Text("… \(value) …")`, or — when several **independently localized** pieces must join (e.g. an `accessibilityValue`) — compose a plain `String` from `String(localized:)` pieces and pass that (`"\(status), \(position)"` assigned to a `let`, so it resolves to the `StringProtocol` overload rather than minting a `"%@, %@"` catalog key). Keep the build warning-clean; don't leave these to accumulate.
- Colors: accent from `Assets.xcassets` (soft pink light / hot pink dark), substances get user-assignable `PresetColor`s
- **Define colors in Oklab/Oklch, never hex.** Hex is confusing and encodes nothing perceptual; Oklab is the best perceptual representation — lightness, chroma, and hue mean what a human sees, and equal numeric distance ≈ equal perceived difference, so you don't have to guess how a color reads or how far apart two colors are (measure Oklab dE with `design-system/color/colorimetry.py`; distinct UI colors want ≥ ~0.08–0.10). Since Apple panels are Display P3, convert Oklch → P3 components at the catalog boundary (`generate_colorsets.py` emits display-p3 only); sRGB is not a gamut we target or notate. Legacy hex still in the design-system sources is historical — new colors get Oklch seeds or P3 components, not hex.
- All singleton managers use `@Observable @MainActor`
- Route parsing is case-insensitive with abbreviation support
- Substance names are normalized for dedup (lowercased, stripped of prefixes/suffixes)
- Interaction rules are class-based (e.g., "stimulant + MAOI"), not per-substance
- Notifications use `threadIdentifier` for session-based grouping (6-hour windows)
- `nonisolated(unsafe)` in LiveActivityManager is intentional (Apple's Activity API not Sendable)
