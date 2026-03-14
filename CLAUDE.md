# Piru

Substance dose tracking iOS app built with SwiftUI and SwiftData. Logs doses, browses 1100+ substances from TripSit/PsychonautWiki/DailyMed APIs, checks interactions, and provides pharmacokinetic insights.

## Working Style

- **Use sub-agents** for research, exploration, and parallel tasks. Spawn agents for codebase searches, multi-file reads, and independent investigations rather than doing everything sequentially in the main context.
- Prefer editing existing files over creating new ones.
- Keep changes minimal and focused — no over-engineering.

## Build & Test

```bash
# Build
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests (uses Apple Testing framework, not XCTest)
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

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
├── Data/            # SubstanceLibrary (singleton), HalfLifeDatabase, Interactions, AppSources
├── Services/        # TripSitAPI, PsychonautWikiAPI, DailyMedAPI
├── Utilities/       # ActiveSubstanceCalculator, PKModel, RampDownScheduler, etc.
Shared/              # Code shared across all targets: models, ColorHex, DoseFormatting, timeline graph
PiruLiveActivityExtension/  # iOS 18 Lock Screen widget
PiruWidget/          # Home Screen widgets (Today's Summary, Recent Dose)
PiruTests/           # 31 test files, 387 tests using Apple Testing framework (@Suite, @Test)
Tools/SubstanceValidator/   # SPM CLI tool for validating substance data against APIs
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
| `Data/SubstanceLibrary.swift` | `@Observable @MainActor` singleton — fetches/caches/merges API data, fuzzy search |
| `Data/HalfLifeDatabase.swift` | 1100+ hardcoded half-life values (minutes) |
| `Data/Interactions.swift` | Drug class mapping + 59 interaction severity rules |
| `Utilities/PKModel.swift` | One-compartment oral PK model (concentration, Tmax, Cmax, ka estimation) |
| `Utilities/RampDownScheduler.swift` | Harm-reduction notifications with session-based grouping |
| `Views/InteractionTimelineView.swift` | PK curve overlay with interaction danger window visualization |
| `Views/DoseSuggestionCard.swift` | Smart dose suggestion card shown during quick-log |
| `Views/ContentView.swift` | Main TabView (Journal, Library, Tools, Insights) |
| `Views/QuickLogView.swift` | Modal for quick dose logging (~880 LOC) |
| `Theme.swift` | Accent color + secondary label styling |

## Data Layer

- **Persistence**: SwiftData for user data (DoseEntry, DailyDoseItem, SubstanceColor, FavoriteSubstance, UserColor)
- **Substance data**: Fetched from 3 APIs (TripSit, PsychonautWiki, DailyMed), merged with deduplication, cached to `substances_cache.json` with 7-day TTL
- **Queries**: Use `@Query` macro in views for SwiftData, `SubstanceLibrary.all` for substance lookups
- **Search**: Ranked cascade (exact → alias → prefix → contains → fuzzy via Levenshtein distance)
- **Export**: PsyLog-compatible JSON format via `DataExportImport`; PDF reports with PK charts via `PDFReportGenerator`
- **Shared code**: SwiftData models + formatting live in `Shared/` with multi-target membership (Piru, PiruWidget, PiruLiveActivityExtension)

## Testing

Uses **Apple Testing framework** (Swift Testing), not XCTest:
```swift
@Suite("DoseEntry")
struct DoseEntryTests {
    @Test("Initializes with correct default values")
    func defaults() { ... }
}
```

**Coverage areas**: Models (Substance, DoseEntry, DoseRange, DurationProfile, RouteOfAdministration, etc.), Data (SubstanceLibrary, Interactions, HalfLifeDatabase, AppSources), Services (TripSitAPI parsing), Utilities (AdherenceCalculator, DataExportImport, PKModel, SubstanceDeduplicator, RampDownScheduler, TagExtractor, ColorHex), Features (FuzzySearch, NotificationGrouping).

## Conventions

- **iOS 18+** target with `iOS 26` feature gates (`.liquidGlassBody`, etc.)
- **Swift 6** strict concurrency (`default-isolation=MainActor`)
- Colors: accent from `Assets.xcassets` (soft pink light / hot pink dark), substances get user-assignable `PresetColor`s
- All singleton managers use `@Observable @MainActor`
- Route parsing is case-insensitive with abbreviation support
- Substance names are normalized for dedup (lowercased, stripped of prefixes/suffixes)
- Interaction rules are class-based (e.g., "stimulant + MAOI"), not per-substance
- Notifications use `threadIdentifier` for session-based grouping (6-hour windows)
- `nonisolated(unsafe)` in LiveActivityManager is intentional (Apple's Activity API not Sendable)
