---
id: SCR-insight-adherence
type: screen
description: Med-adherence calendar + streak + day-detail sheet — the richest empty-state CTA in the Insights tab.
edges:
  - {rel: variant_of, target: SCR-insights-home}
  - {rel: navigates_to, target: SCR-my-meds-hub}
  - {rel: diverges_from, target: SCR-insights-home}
metadata:
  screenshot: screenshots/SCR-insight-adherence.png
---

# Adherence (`AdherenceView`)

**Route**: `PushRoute.insight(.adherence)`. **Deep link**: `piru://insight/adherence`. **File**:
`Piru/Views/Insights/AdherenceView.swift` (538 ln).

## States
Empty: full `ContentUnavailableView("No Meds Yet")` **plus an actionable CTA** `Button {
navigator.push(.myMeds) }` (`:25-45`) — richer than the hub's plain-caption empty state (`DIV-004`).
`todayCard` renders only `if today.status != .noData`. Day-detail opens via `.sheet(item:)` on a
non-future, non-`.noData` calendar tap.

## Components
`todayCard`, `streakCard`, `calendarSection` (`monthHeader`+`weekdayHeader`+`calendarGrid`,
`AdherenceCalendarCell`), `remindersLink`. **No Swift Charts anywhere** — custom
`LazyVGrid`/`Circle`/`RoundedRectangle` chrome throughout, unlike Usage/Tolerance.

## Tokens
Complete/partial/missed status colors: `.green`/`.orange`/`.red` at hand-picked opacities
(`:182-188`, reused in `AdherenceDayDetailSheet:512-527` — independently re-declared, `DIV-002`).
Streak number `.system(.largeTitle, design:.rounded, weight:.bold)` (`:145`) vs. `.title2` for the
same data point in the hub glance (`InsightsView.swift:136-137` — `DIV-030`).
