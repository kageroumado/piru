# Piru

Substance dose tracking iOS app built with SwiftUI and SwiftData. Logs doses, browses 1100+ substances from a bundled SQLite database (sourced from TripSit/PsychonautWiki/DailyMed and curated data), checks interactions, and provides pharmacokinetic insights.

## Working Style

- **Use sub-agents** for research, exploration, and parallel tasks. Spawn agents for codebase searches, multi-file reads, and independent investigations rather than doing everything sequentially in the main context.
- Prefer editing existing files over creating new ones.
- Keep changes minimal and focused — no over-engineering.

## Build & Test

```bash
# Build
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build

# Run tests (uses Apple Testing framework, not XCTest)
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test

# Build SubstanceValidator CLI tool
cd Tools/SubstanceValidator && swift build

# Run SubstanceValidator
cd Tools/SubstanceValidator && swift run SubstanceValidator validate
```

## Architecture

**Pattern**: SwiftUI + SwiftData with @Observable singletons — no formal MVVM ViewModels.

```
Piru/
├── Models/          # Substance struct, DoseRange, DurationProfile, DoseUnit
├── Views/           # SwiftUI views (ContentView has 4 tabs: Journal, Library, Tools, Insights)
│   ├── Insights/    # Adherence, half-life calc, activity charts, usage stats
│   └── Components/
├── Data/            # SubstanceStore (GRDB over bundled SQLite), HalfLifeDatabase, Interactions, AppSources, StoreRecovery, BackupManager
├── Utilities/       # ActiveSubstanceCalculator, RampDownScheduler, LiveActivityManager, etc.
├── Navigation/      # AppNavigator + route enums + deep link codec — single source of truth for tab/sheet/path state
Shared/              # Code shared across all targets: SwiftData models, PKModel, DoseFormatting, timeline graph
PiruLiveActivityExtension/  # Lock Screen Live Activity widget
PiruWidget/          # Home Screen widgets (Today's Summary, Recent Dose)
PiruTests/           # 48 test files, ~620 tests using Apple Testing framework (@Suite, @Test)
Tools/SubstanceValidator/   # SPM CLI tool for validating substance data against APIs
pipeline/            # Python data pipeline that builds the bundled substance SQLite DB
```

## Key Files

| File | Purpose |
|------|---------|
| `Models/Substance.swift` | Core `Substance` struct, `DoseRange`, `DurationProfile`, `SubstanceCategory` enum (23 categories) |
| `Shared/DoseEntry.swift` | SwiftData `@Model` for logged doses (shared with widget) |
| `Shared/DailyDoseItem.swift` | SwiftData `@Model` for daily medication tracking (shared with widget) |
| `Shared/SubstanceColor.swift` | SwiftData `@Model` + 31 preset colors (shared with widget) |
| `Shared/RouteOfAdministration.swift` | 10 routes enum (shared with widget) |
| `Shared/DoseFormatting.swift` | `Double.doseFormatted` extension (shared with widget) |
| `Data/SubstanceStore.swift` | `@Observable @MainActor` singleton — GRDB queries over the bundled SQLite DB with per-field source-priority resolution, ranked search, caches. Also hosts the `SubstanceLibrary` static façade (overlay-aware lookups) at the bottom of the file |
| `Data/SubstanceDBUpdater.swift` | Opt-in over-the-air updates for the bundled substance DB (manifest + checksum) |
| `Data/StoreRecovery.swift` | Never-delete SwiftData store recovery: versioned migration plan + data-aware fallback |
| `Data/HalfLifeDatabase.swift` | 1100+ hardcoded half-life values (minutes) |
| `Data/Interactions.swift` | Drug class mapping + 59 interaction severity rules |
| `Shared/PKModel.swift` | One-compartment oral PK model (concentration, Tmax, Cmax, ka estimation) |
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
- **Substance data**: Ships as a bundled SQLite DB (`Piru/Data/piru-substances.sqlite`) built by `python3 pipeline/build/sqlite.py` from TripSit/PsychonautWiki/DailyMed + curated data — editing pipeline JSON does nothing without a rebuild. `SubstanceStore` resolves each field by per-source priority (user-reorderable); `SubstanceDBUpdater` handles opt-in DB updates
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

- **Localization**: The app ships **English, Simplified Chinese (`zh-Hans`), and Traditional Chinese (`zh-Hant`)** via `Piru/Localizable.xcstrings`. **Every user-facing string must be localized** — use `Text("...")`, `LocalizedStringKey`, or `String(localized:)`; never hardcode a bare `String` into UI. Strings passed to non-localizing APIs (e.g. accessibility labels taking `String`) still need `String(localized:)`.
  - **NEVER hand-edit `Localizable.xcstrings` with a generic JSON writer.** Xcode owns its format — `" : "` key separators (spaces around the colon), empty entries written `"key" : {\n\n    }` (not `{}`), CJK stored literally (no `\uXXXX`), no trailing newline, and keys ordered by Unicode collation Python can't reproduce. A naïve `json.dump` reformats all ~20k lines and the diff becomes unreviewable.
  - **Workflow for new strings:** add the English `Text("…")` in code, then add `"English": ("简体", "繁體")` to the `T` dict in **`translate_catalog.py`** and run `python3 translate_catalog.py`. It updates existing keys in place with a byte-identical serializer (see `serialize_catalog`). For a string Xcode hasn't extracted yet (CLI-only change, project not opened), add it to the `NEW_KEYS` allow-list in `__main__` so it gets inserted — keep that set to just the handful you added (don't bulk-insert all of `T`, or a catalog inherits strings its target never uses; the widget catalog is intentionally a small subset). The script leaves a no-op run as an empty `git diff`.
  - **Xcode owns structure; the script only fills values.** A real `xcodebuild` runs `xcstringstool` (`extract` → `.stringsdata`, then `sync` → merges into `.xcstrings`) to add new keys, mark removed ones `extractionState: stale`, and impose Apple's canonical key order. `translate_catalog.py` round-trips that canonical form **byte-identically** (verified: a no-op run is a 0-line diff), so the durable workflow is **build first → run the script → commit**; the build owns ordering/staleness, the script owns zh translations. Don't hand-author ordering. Caveat: Xcode's incremental sync silently *skips* re-syncing once the `.xcstrings` is edited out-of-band (mtime newer), and a manual `xcstringstool sync` needs the *complete* `.stringsdata` set (a partial set false-marks live strings stale) — so reach for `NEW_KEYS` to insert a one-off, and let the next clean build canonicalize its position.
  - **Don't auto-prune stale entries.** `extractionState: stale` is a *candidate* signal, not proof of death — the lightweight extractor false-flags strings resolved via `String(localized:)` in helpers (e.g. `MechanismOfActionDatabase.moa()` summaries) or used only from another target. Deleting those ships English to zh users at runtime. Leave orphans in place (harmless unused entries); a future clean build re-evaluates them. We do **not** use a TMS (SimpleLocalize/Localazy) — translations are authored directly in `translate_catalog.py`.
- **iOS 26+** minimum deployment target (Liquid Glass UI throughout)
- **Swift 6** strict concurrency (`default-isolation=MainActor`)
- Colors: accent from `Assets.xcassets` (soft pink light / hot pink dark), substances get user-assignable `PresetColor`s
- All singleton managers use `@Observable @MainActor`
- Route parsing is case-insensitive with abbreviation support
- Substance names are normalized for dedup (lowercased, stripped of prefixes/suffixes)
- Interaction rules are class-based (e.g., "stimulant + MAOI"), not per-substance
- Notifications use `threadIdentifier` for session-based grouping (6-hour windows)
- `nonisolated(unsafe)` in LiveActivityManager is intentional (Apple's Activity API not Sendable)
