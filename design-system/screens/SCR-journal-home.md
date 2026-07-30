---
id: SCR-journal-home
type: screen
description: Journal tab root — timeline of logged doses/sessions, grouped 4 ways, plus My Meds and Active Now hero cards.
edges:
  - {rel: contains, target: CMP-glance-card}
  - {rel: contains, target: CMP-theme-card}
  - {rel: navigates_to, target: SCR-entry-detail}
  - {rel: navigates_to, target: SCR-session-detail}
  - {rel: navigates_to, target: SCR-my-meds-hub}
  - {rel: presents, target: SCR-quicklog}
  - {rel: diverges_from, target: SCR-session-detail}
  - {rel: uses_token, target: TOK-radius}
metadata:
  screenshot: screenshots/SCR-journal-home.png
  screenshot_dark: screenshots/SCR-journal-home-dark.png
---

# Journal home (`EntryListView`)

**Route**: tab root, not pushed/sheeted — embedded directly at `ContentView.swift:290-292` inside
the Journal `NavigationStack`. **Deep link**: `piru://journal` (tab switch only).
**File**: `Piru/Views/Journal/EntryListView.swift` (844 ln).

## States
- Empty/no-results: `ContentUnavailableView` at `:652-670`, 3 copy variants keyed on
  `searchText.isEmpty`/`hasActiveFilters` (`:654-663`), plus a "Search Library instead" action
  when `isSearchSurface` (`:665-668`).
- Hero "Active Now" card: gated `showActiveHero` (`:86-88`) → `ActiveNowCard` (`:263-282`), only
  when not the search surface and a session is active.
- "My Meds" plan card: `MyMedsCard()` (`:251-256`), self-omits when the user has no meds.
- 4 grouping modes (`.recent`/`.byDay`/`.bySubstance`/`.byCategory`, `:289-294`), independent
  collapse state per substance/category (`:132-133`).
- Pagination sentinel: `hasMoreSessions` (`:502-509`).

## Components
`MyMedsCard` (`Journal/DailyDose/MyMedsCard.swift`), `ActiveNowCard` (`Journal/ActiveNowCard.swift`),
`SessionCardView` (`Journal/Session/SessionCardView.swift:116`, `.equatable()`), a **private**
`SubstanceEntryRow` (`:787-824` — see `DIV-005`, NOT the shared `EntryRowView`), private
`SubstanceGroupHeader` (`:828-842`), `JournalFilterMenu`/`JournalOptionsButton`
(`Journal/JournalMenus.swift:166,10`), `JournalCalendarView` (local `.sheet`, not a `SheetRoute`
— see `DIV-010`).

## Interactions
Row tap → `navigator.push(.entry(...))` (`:479-488`); day-card tap → `navigator.push(.session(...))`
(`:530-533`); Active Now tap → push resolved session; toolbar filter `Menu` + options popover
(`:306-319`); options → Jump to Date local `.sheet` (`:361-365`) → `jump(to:proxy:)` (`:371-398`).

## Tokens
`.listSectionSpacing(.custom(2))` (`:298`); day-card insets `EdgeInsets(top:0,leading:16,bottom:12,trailing:16)`
(`:547`); flat-row insets `EdgeInsets(top:5,leading:16,bottom:5,trailing:16)` (`:485`);
`.themeCard()` on rows/day-container; filter chip `Capsule()` fill `Theme.accent` (`:455`);
`.animation(.smooth(duration:0.35))` on regroup (`:189`).

## Known divergences
`DIV-005` (private row vs. shared `EntryRowView`), `DIV-010` (Filter/Calendar bypass the
navigator entirely).
