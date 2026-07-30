---
id: SCR-comedown-guide
type: screen
description: Recovery-tips reference, reachable both as a Tools-tab tool and as a push route from RampDownView — with two different nav-title outcomes.
edges: []
metadata:
  screenshot: screenshots/SCR-tool-recovery.png
---

# Recovery Guide / Comedown Guide (`ComedownGuideView`)

**Routes**: `PushRoute.tool(.recovery)` **and** `PushRoute.comedownGuide` both resolve to the same
view (`AppDestinations.swift:66-67,107,145`) — this is one screen with two entry routes, not two
screens. **Deep link**: `piru://tool/recovery`. **File**: `Piru/Views/Tools/ComedownGuideView.swift` (394 ln).

## Known divergence — `DIV-032`
Reached via `.tool(.recovery)`: title "Recovery Guide" set at the dispatch switch
(`AppDestinations.swift:107`). Reached via `.comedownGuide` (from `RampDownView`'s "Full recovery
guide" link, `RampDownView.swift:186-189`): **no title at all** — the view itself sets none.

## States
"Relevant to you" section only if `!recentCategories.isEmpty` within a 48h window (`:32-38`);
always-present "All categories" + "Universal recovery basics" fallback (`:40-46`) — no explicit
empty-state placeholder for "no recent activity" (section silently omits).

## Components
`ComedownCategoryDisclosure` (shared with `SessionDetailView`'s Recovery section per its own doc
comment). No disclaimer text is visually distinguished from ordinary bullets (`DIV-022`).

## Adjacent, NOT the same screen: `RampDownView`
`Piru/Views/Tools/RampDownView.swift` (214 ln), `PushRoute.rampDown`. Shares `CardBackground`+
`Theme.background` chrome but adds a 4-branch active/past/disabled/CTA state machine, an alert +
confirmation dialog, and semantic status colors (`.red`/`.orange`/`.green`) entirely absent from
`ComedownGuideView`. Consumes `ComedownGuideView.guide(for:)` **data** only, not its view.
