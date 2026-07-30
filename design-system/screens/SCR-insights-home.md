---
id: SCR-insights-home
type: screen
description: Insights tab root — 4 GlanceCard glances (Usage/In-System/Adherence/Tolerance), each independently empty/populated.
edges:
  - {rel: contains, target: CMP-glance-card}
  - {rel: navigates_to, target: SCR-insight-adherence}
  - {rel: navigates_to, target: SCR-insight-usage}
  - {rel: navigates_to, target: SCR-insight-tolerance}
  - {rel: navigates_to, target: SCR-insight-insystem}
metadata:
  screenshot: screenshots/SCR-insights-home.png
---

# Insights home (`InsightsView`)

**Route**: tab root. **Deep link**: `piru://insights`. **File**: `Piru/Views/Insights/InsightsView.swift` (417 ln).

## States (brand-new user sees all 4 empty simultaneously)
Usage: `emptyContent("No doses logged yet")` (`:75`). In-system: `emptyContent("Nothing active
right now")` (`:101-102`). Adherence: `emptyContent("Add your meds to see adherence")` (`:130-131`,
plain caption, **no CTA** — contrast with the richer CTA on the detail screen, `SCR-insight-adherence`).
Tolerance: a **positive** "Receptors rested" state (`:204-217`) that collapses "never logged
anything" and "logged but nothing tolerant right now" into one visual.

## Components
`usageChart` (Swift Charts `BarMark`, `:81-89`); `inSystemCard` (shared `GlanceRow`/`GlanceMoreRow`);
`miniCalendar` (custom `LazyVGrid`, not Charts); `toleranceBar` (custom `Capsule`-in-`GeometryReader`).

## Known divergences
`DIV-004` (4 different empty-state chrome idioms across this one hub), `DIV-008` (`usageChart`
sets accessibility label/value directly on a `Chart` without the shared collapsing helper every
other chart in Usage/Tolerance uses), `DIV-030` (streak font size disagrees with the detail
screen).
