# Delete candidates

Looks dead; scope or origin unverified. Kiri confirms → it goes.

## `Piru/Navigation/Routes.swift` — `SheetRoute.timeAdjust`, with `TimeAdjustHost` in `Piru/Navigation/SheetRouteView.swift`
- **What**: the route case, its dispatch arm and the ~50-line host view that resolves the entry
- **Looks dead because**: no code presents it; `SessionDetailView` shows `TimeAdjustSheet` from a local `.sheet(item:)`. `DeepLink` encodes it as `nil` and has no decode arm
- **Not deleted because**: `SheetRoute` is `Codable` inside `NavigatorSnapshot`, and two tests exercise the case; unknown whether a stored snapshot can carry it
- **To confirm**: `grep -rnE '\.timeAdjust\b' Piru Shared PiruTests`, then check where `NavigatorSnapshot` is persisted
- **Found**: 2026-11-20

## `Piru/Navigation/Routes.swift` — `SheetRoute.advancedSearch`, with `Piru/Views/Search/AdvancedSearchView.swift`
- **What**: the route case and the whole advanced-search screen, reachable only through it
- **Looks dead because**: no code presents the route and no test names it
- **Not deleted because**: the screen is a finished feature (query syntax, examples); it may be parked on purpose
- **To confirm**: `grep -rnE '\.advancedSearch\b' Piru Shared PiruTests`, or ask Kiri whether advanced search is coming back
- **Found**: 2026-11-20

## `Piru/Navigation/Routes.swift` — `SheetRoute.onboarding`
- **What**: the route case and its dispatch arm
- **Looks dead because**: onboarding is shown by `OnboardingGateModifier`'s cover in `ContentView.swift`; nothing presents the route, and one test names it
- **Not deleted because**: same `Codable` snapshot question as `.timeAdjust`
- **To confirm**: `grep -rnE 'present\(\.onboarding|\.onboarding\b' Piru Shared PiruTests`
- **Found**: 2026-11-20

## `Piru/Navigation/AppNavigator.swift` — `pop()`, `popToRoot(in:)`, `dismiss(_ sheet:)`
- **What**: three navigator methods
- **Looks dead because**: only `PiruTests` calls them; app code uses `dismiss()`, `setPath` and `resetAllPaths`
- **Not deleted because**: they read as the navigator's intended public surface, and the tests assert their behavior
- **To confirm**: `grep -rnE '\.pop\(|popToRoot|\.dismiss\(\.' Piru Shared`
- **Found**: 2026-11-20
