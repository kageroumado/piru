---
id: SCR-insight-usage
type: screen
description: The app's chart-heaviest screen — 5 distinct Swift Charts visualizations plus one custom capsule-bar chart, fully accessibility-instrumented.
edges:
  - {rel: variant_of, target: SCR-insights-home}
  - {rel: contains, target: CMP-accessibility-primitives}
metadata:
  screenshot: screenshots/SCR-insight-usage.png
---

# Usage (`UsageStatsView` + `UsageStatsModel` + `ActivityExpandedChart`)

**Route**: `PushRoute.insight(.usage)`. **Deep link**: `piru://insight/usage`. **Files**:
`Piru/Views/Insights/UsageStatsView.swift` (921 ln), `UsageStatsModel.swift` (338 ln, `@Observable`
derived-state model — async data correctly parked off the view), `ActivityExpandedChart.swift` (147 ln).

## States
`allEntries.isEmpty` → `ContentUnavailableView`; time-range picker hidden while empty. Filtered-empty
(entries exist but none in range) silently suppresses chart sections — a minor gap vs. the
top-level empty state (no explicit "no data in this range" message).

## Components (all private nested structs, one `body` each — correct decomposition)
`frequencyChart`→`FrequencyChartContent` (custom capsule bars, not Charts); `timelineChart` (Swift
Charts `BarMark` compact / `ActivityExpandedChart` expanded with pinch-zoom + category filter
chips); `DoseTrendSection` (Swift Charts `AreaMark`+`LineMark`+`PointMark`, gradient fill, dashed
moving-average line, pinch-zoom — **independently reimplements** the same pinch-zoom gesture code
as `ActivityExpandedChart`, not shared); `TimeOfDayChartContent` (Swift Charts `BarMark`,
per-bucket `.orange`/`.yellow`/`.indigo`/`.blue`); `CategoryBreakdownContent` (Swift Charts
`SectorMark` donut, drill-down into a second donut).

## Accessibility (best-in-class in this audit)
Every Swift-Charts chart uses the shared `chartSummaryAccessibility` helper — fully consistent.
One header-trait gap: `timelineChart`'s "Activity" header lacks `.accessibilityAddTraits(.isHeader)`
while Frequency/TimeOfDay/Categories headers all have it (`:167` vs `:401-403`).

## Tokens
Dashed gridlines everywhere as `StrokeStyle(lineWidth:0.5, dash:[3,3])` — one consistent grid-line
token reused across every chart in this file (a genuine positive convergence, worth citing as the
house grid-line standard).
