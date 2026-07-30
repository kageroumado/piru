---
id: SCR-onboarding
type: screen
description: First-run welcome flow — a genuine thin coordinator over 8 steps; its own SheetRoute is dead code, the real path is a separate fullScreenCover gate.
edges:
  - {rel: contains, target: CMP-glass-pill-button}
metadata:
  screenshot: screenshots/SCR-onboarding.png
---

# Onboarding (`OnboardingView`)

**Declared route**: `SheetRoute.onboarding` — dispatches (`SheetRouteView.swift:36-37`) but
`navigator.present(.onboarding)` has **zero call sites** anywhere in the repo (dead, `DIV-010`-style).
**Real path**: `OnboardingGateModifier` (`ContentView.swift:65-76`), an independent
`fullScreenCover` + `@AppStorage("hasCompletedOnboarding")`, entirely outside `AppNavigator`. No
deep link. **Files**: `Piru/Views/Onboarding/` (5 files, 1377 ln).

## Structure
`NavigationStack` over `[OnboardingStep]` (8 cases), `OnboardingStepChrome` wraps every step with
a progress bar + conditional Skip, `.interactiveDismissDisabled()`.

## Components
`OnboardingFeatureTour.swift` reuses **real** app components for its device-mock screenshots
(`TimelineGraphView`, `FamilyGradientCard`, `MoleculeView`) via a private `MockPalette` (7 literal
`Color(red:green:blue:)` — the one deliberate raw-hex exception, justified since these mimic
substance-specific colors). Every step's CTA uses `GlassPillButton` (9 call sites) — the cleanest
single-component reuse story in the audit.

## Known divergence
`OnboardingImportStep.swift:27,47` uses raw `.foregroundStyle(.green)`/`.red` instead of a
`Theme.success`/`Theme.danger` token (`DIV-002`).
