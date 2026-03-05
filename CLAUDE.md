# Piru

Substance dose tracking iOS app built with SwiftUI and SwiftData. Logs doses, browses 1100+ substances from TripSit/PsychonautWiki/DailyMed APIs, checks interactions, and provides pharmacokinetic insights.

## Working Style

- **Use sub-agents** for research, exploration, and parallel tasks. Spawn agents for codebase searches, multi-file reads, and independent investigations rather than doing everything sequentially in the main context.
- Prefer editing existing files over creating new ones.
- Keep changes minimal and focused — no over-engineering.

## Build & Test

```bash
# Build
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests (uses Apple Testing framework, not XCTest)
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Build SubstanceValidator CLI tool
cd Tools/SubstanceValidator && swift build

# Run SubstanceValidator
cd Tools/SubstanceValidator && swift run SubstanceValidator validate
```

## Architecture

**Pattern**: SwiftUI + SwiftData with @Observable singletons — no formal MVVM ViewModels.

```
Piru/
├── Models/          # SwiftData @Model classes + plain Codable structs
├── Views/           # SwiftUI views (ContentView has 4 tabs: Journal, Library, Tools, Insights)
│   ├── Insights/    # Adherence, half-life calc, activity charts, usage stats
│   └── Components/
├── Data/            # SubstanceLibrary (singleton), HalfLifeDatabase, Interactions, AppSources
├── Services/        # TripSitAPI, PsychonautWikiAPI, DailyMedAPI
├── Utilities/       # AdherenceCalculator, DataExportImport, LiveActivityManager
Shared/              # Code shared with Live Activity widget (ColorHex, timeline graph)
PiruLiveActivityExtension/  # iOS 18 Lock Screen widget
PiruTests/           # 24 test files using Apple Testing framework (@Suite, @Test)
Tools/SubstanceValidator/   # SPM CLI tool for validating substance data against APIs
```

## Key Files

| File | Purpose |
|------|---------|
| `Models/Substance.swift` | Core `Substance` struct, `DoseRange`, `DurationProfile`, `SubstanceCategory` enum (23 categories) |
| `Models/DoseEntry.swift` | SwiftData `@Model` for logged doses |
| `Models/DailyDoseItem.swift` | SwiftData `@Model` for daily medication tracking |
| `Models/SubstanceColor.swift` | SwiftData `@Model` + 31 preset colors |
| `Models/RouteOfAdministration.swift` | 10 routes enum (oral, sublingual, insufflation, etc.) |
| `Data/SubstanceLibrary.swift` | `@Observable @MainActor` singleton — fetches/caches/merges API data |
| `Data/HalfLifeDatabase.swift` | 1100+ hardcoded half-life values (minutes) |
| `Data/Interactions.swift` | Drug class mapping + interaction severity rules |
| `Views/ContentView.swift` | Main TabView (Journal, Library, Tools, Insights) |
| `Views/QuickLogView.swift` | Modal for quick dose logging (largest view, ~550 LOC) |
| `Theme.swift` | Accent color + secondary label styling |

## Data Layer

- **Persistence**: SwiftData for user data (DoseEntry, DailyDoseItem, SubstanceColor, FavoriteSubstance, UserColor)
- **Substance data**: Fetched from 3 APIs (TripSit, PsychonautWiki, DailyMed), merged with deduplication, cached to `substances_cache.json` with 7-day TTL
- **Queries**: Use `@Query` macro in views for SwiftData, `SubstanceLibrary.all` for substance lookups
- **Export**: PsyLog-compatible JSON format via `DataExportImport`

## Testing

Uses **Apple Testing framework** (Swift Testing), not XCTest:
```swift
@Suite("DoseEntry")
struct DoseEntryTests {
    @Test("Initializes with correct default values")
    func defaults() { ... }
}
```

## Conventions

- **iOS 18+** target with `iOS 26` feature gates (`.liquidGlassBody`, etc.)
- Colors: accent from `Assets.xcassets` (soft pink light / hot pink dark), substances get user-assignable `PresetColor`s
- All singleton managers use `@Observable @MainActor`
- Route parsing is case-insensitive with abbreviation support
- Substance names are normalized for dedup (lowercased, stripped of prefixes/suffixes)
- Interaction rules are class-based (e.g., "stimulant + MAOI"), not per-substance
