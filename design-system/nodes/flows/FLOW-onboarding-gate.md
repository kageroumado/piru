---
id: FLOW-onboarding-gate
type: flow
description: First-run onboarding is gated by an independent fullScreenCover + @AppStorage flag, entirely outside AppNavigator/SheetRoute.
edges:
  - {rel: part_of, target: SCR-onboarding}
metadata: {}
---

# Onboarding gate flow

1. App launches; `ContentView`'s `OnboardingGateModifier` (`:65-76`) checks
   `@AppStorage("hasCompletedOnboarding")`.
2. If `false`, presents `OnboardingView` via `fullScreenCover` — **not** `SheetRoute.onboarding`
   (that route case exists, dispatches, but has zero live call sites — see `DIV-010`-adjacent
   finding on `SCR-onboarding`).
3. `OnboardingView`'s `NavigationStack` walks 8 `OnboardingStep` cases with `OnboardingStepChrome`
   (progress bar + conditional Skip), `.interactiveDismissDisabled()`.
4. Completing or skipping flips the `@AppStorage` flag; `OnboardingGateModifier` stops presenting.

**QA note**: to replay onboarding on the simulator, use `-hasCompletedOnboarding NO` at launch
(see `Specs/design-system/README.md`'s dynamic-verification section) — there is no in-app deep
link or settings toggle to re-trigger it.
