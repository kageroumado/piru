# Piru

Substance and medication tracking iOS app. Users log doses, browse a 680+ substance library, check drug interactions, and monitor adherence to daily medications. Live Activities show active dose timelines on the lock screen and Dynamic Island.

## Workflow

- **Commit after every change** — After completing any feature, fix, or modification, always create a git commit with a descriptive message before moving on. Do not batch unrelated changes into a single commit.

## Build & Test

```bash
# Build
xcodebuild build -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run tests (uses modern Swift Testing framework, not XCTest)
xcodebuild test -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Validate substance data
cd Tools/SubstanceValidator && swift run SubstanceValidator
```

## Project Structure

```
Piru/
├── PiruApp.swift              # @main entry, SwiftData ModelContainer setup
├── Theme.swift                # Global accent color
├── Models/                    # Data models
│   ├── Substance.swift        # Core struct + DoseRange, DurationProfile, TimeRange, etc.
│   ├── DoseEntry.swift        # @Model — logged dose (SwiftData)
│   ├── DailyDoseItem.swift    # @Model — recurring daily medication
│   ├── SubstanceColor.swift   # @Model — user-assigned substance colors
│   ├── UserColor.swift        # @Model — custom color palette entries
│   └── RouteOfAdministration.swift
├── Data/                      # Static substance definitions (one file per category)
│   ├── SubstanceLibrary.swift # Central registry, search, O(1) name lookup
│   ├── Interactions.swift     # Drug interaction rules and checker
│   ├── AppSources.swift       # Citation sources
│   └── [17 category files]    # Stimulants.swift, Opioids.swift, etc.
├── Views/                     # SwiftUI views
│   ├── ContentView.swift      # Tab navigation (Journal, Quick Log, Library, Insights, Settings)
│   ├── Insights/              # Adherence, usage stats, half-life calculator
│   └── [view files]
├── Utilities/
│   ├── LiveActivityManager.swift   # @Observable singleton for Live Activities
│   ├── DataExportImport.swift      # CSV/JSON export, PsyLog import
│   └── AdherenceCalculator.swift   # Daily dose streak tracking
Shared/                        # Code shared between app and Live Activity extension
├── PiruActivityAttributes.swift
├── ColorHex.swift
└── TimelineGraphView.swift
PiruLiveActivity/              # Live Activity widget extension
PiruTests/                     # 8 test files using Swift Testing (@Suite/@Test)
Tools/SubstanceValidator/      # SPM CLI tool for data validation
```

## Architecture

- **SwiftUI + SwiftData** — reactive views with `@Query`, `@Environment(\.modelContext)` for persistence
- **No third-party dependencies** — Apple frameworks only (SwiftUI, SwiftData, ActivityKit, WidgetKit)
- **Minimum deployment**: iOS 17
- **Schema versioning**: `PiruSchemaV2` in PiruApp.swift; add new versions + lightweight migration stages there
- **SwiftData models**: `DoseEntry`, `SubstanceColor`, `UserColor`, `DailyDoseItem`, `FavoriteSubstance` — all `@Model final class`
- **Substance data**: Plain Swift structs defined statically in `Data/` files, aggregated by `SubstanceLibrary.all`
- **Live Activities**: Managed by `LiveActivityManager.shared` singleton; auto-resumes on launch, auto-prunes completed entries

## Conventions

- **4-space indentation**
- **`// MARK: -` sections** to organize code within files
- **Enums as namespaces** for static collections (`SubstanceLibrary`, `InteractionChecker`, `AdherenceCalculator`)
- **Substance data files** are extensions on `SubstanceLibrary` exposing a static array (e.g., `static let stimulants: [Substance]`)
- **Search ranking**: exact name > exact alias > prefix match > contains match
- **Tests use Swift Testing** (`@Suite`, `@Test`, `#expect`) — not XCTest
- Substances reference each other by name string, not by ID — `DoseEntry.substance` stores the display name
- View composition: large views extract sections as private computed properties or `@ViewBuilder` methods

## Substance Data Format

Each substance requires: `name`, `aliases`, `category`, `defaultRoute`, `routes` (with `DoseRange` + `DurationProfile`), `effects`. Optional: `subjectiveEffects`, `toleranceInfo`, `halfLifeMinutes`, `sources`. All dose/duration values use **milligrams** and **minutes** as base units. Data is verified against authoritative pharmacological sources (see RESEARCH.md).

## Interaction System

`InteractionChecker` in `Interactions.swift` maps substances to drug classes, then checks class-pair rules with severity levels: **Dangerous** > **Unsafe** > **Caution**. Specific substance overrides exist for multi-class compounds (e.g., Tramadol = opioid + SNRI).
