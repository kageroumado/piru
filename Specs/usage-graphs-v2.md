# Usage Graphs V2 — Spec

> Redesign of the Insights → Usage tab to surface actionable patterns, not just counts.

## Design Principles

1. **Answer questions, not just show data.** Every chart should answer a specific question a user would ask about their usage.
2. **Time is the primary axis.** Most insights are meaningless without temporal context.
3. **Layered detail.** Summary → trend → drill-down. Don't front-load complexity.
4. **Respect the data model.** We have: `substance`, `amount`, `unit`, `route`, `timestamp`, `tags`, `notes`, plus resolved `category`, `halfLifeMinutes`, and `DoseRange` (threshold/light/common/strong/heavy) from the substance library.

---

## Section 1: Overview Cards (replaces current summary row)

**Question answered:** "What does my usage look like right now compared to recently?"

### Cards (horizontal scroll, 2×2 grid or scrollable row):

| Card | Value | Subtext | Trend |
|------|-------|---------|-------|
| **This Period** | Entry count for selected range | vs. previous period (e.g. "↑12% vs last 7d") | Sparkline (7 points) |
| **Unique Substances** | Count | "N new this period" if any | — |
| **Avg per Day** | Entries/day | "Most active: Wednesday" (mode weekday) | — |
| **Dose Intensity** | % of entries at common+ dose level | "N heavy doses" as warning | Colored dot (green/yellow/red) |

**Computation notes:**
- "Previous period" = same-length window immediately before the selected range.
- Sparkline: divide selected range into 7 equal buckets, count entries per bucket.
- Dose intensity requires resolving each entry's `DoseRange` from `SubstanceLibrary` — skip entries where substance has no dose data.
- Most active weekday: `Calendar.current.component(.weekday, from: entry.timestamp)`, find mode.

### Time Range Selector
Keep existing: **7D · 30D · 90D · 1Y · All** (add 1Y).

---

## Section 2: Activity Heatmap

**Question answered:** "When do I tend to use substances — which days and hours?"

### Design
- GitHub-style contribution heatmap: **columns = weeks, rows = days of week** (Mon–Sun).
- Cell color intensity = entry count for that day (0 = empty, 1 = lightest, max = darkest).
- Color: use the app's accent color ramp (pink), or per-category color if a category filter is active.
- Below the heatmap: **hour-of-day histogram** (24 bins, not 4 buckets) showing entry distribution across clock hours.

### Interactions
- Tap a heatmap cell → highlight that day's entries in the hour histogram below.
- Long-press → navigate to that day's `DayDetailView`.
- Category filter pills above the heatmap (same as current, but also filter the histogram).

### Computation
```
for entry in filteredEntries {
    let weekIndex = calendar.component(.weekOfYear, from: entry.timestamp)
    let dayOfWeek = calendar.component(.weekday, from: entry.timestamp)
    let hour = calendar.component(.hour, from: entry.timestamp)
    heatmap[weekIndex][dayOfWeek] += 1
    hourHistogram[hour] += 1
}
```

### Implementation Notes
- Use `Grid` or `LazyHGrid` with colored `RoundedRectangle` cells (not Charts — it's a grid, not a chart).
- Hour histogram: `Chart { BarMark }` with 24 bins, x-axis labels at 0, 6, 12, 18.
- Heatmap cell size: ~14pt with 2pt spacing (fits ~13 weeks = 90 days naturally).
- For 1Y/All ranges: horizontally scrollable, default scroll position = trailing (most recent).

---

## Section 3: Substance Trends (replaces current "Dose Trends" + "Frequency" sections)

**Question answered:** "How has my usage of each substance changed over time?"

### Design
- **Multi-substance line chart** showing rolling frequency (entries per week) for top N substances.
- Each substance gets its own colored line (from `SubstanceColor`).
- Y-axis: entries per week (rolling 7-day window).
- X-axis: dates across selected range.
- Legend below with colored dots + substance names (tappable to toggle visibility).

### Aggregation Strategy
| Range | Bucket Size | Rolling Window |
|-------|------------|----------------|
| 7D | 1 day | 7 days |
| 30D | 1 day | 7 days |
| 90D | 1 week | 4 weeks |
| 1Y | 1 week | 4 weeks |
| All | 1 week | 4 weeks |

### Interactions
- Tap legend item to solo/unsolo a substance line.
- `chartXSelection` to show vertical rule + tooltip with exact counts.
- Pinch-to-zoom (reuse existing 0.5×–4× gesture pattern).

### Implementation Notes
- Use `Chart { ForEach(substances) { LineMark } }` with `.interpolationMethod(.catmullRom)` for smooth curves.
- Limit to top 5 substances by default; "Show all" toggle expands.
- Rolling average: `entries.filter { $0.timestamp in (date-window)...date }.count`.
- When a substance has zero entries for an extended period, draw the line at 0 (don't break the line).

---

## Section 4: Dose Level Distribution (new)

**Question answered:** "Am I dosing responsibly? Are my doses escalating?"

### Design
- **Stacked area chart** over time showing the proportion of entries at each dose level.
- Dose levels (bottom to top): sub-threshold, threshold, light, common, strong, heavy.
- Colors: gray, blue, green, yellow, orange, red (matches existing `DoseLevel.color`).
- Y-axis: percentage (0–100%) — normalized so each time bucket = 100%.
- X-axis: time (bucketed same as Section 3).

### Fallback
- Many entries won't have resolvable dose levels (substance not in library, or no `DoseRange` data for that route). Show a small footnote: "Based on N of M entries with dose data."
- If <30% of entries have dose data, demote this section to a collapsed disclosure group.

### Interactions
- `chartXSelection` for tooltip: "Week of Mar 1: 2 light, 3 common, 1 strong".
- Tap a dose level in the legend to highlight just that band.

### Computation
```
for entry in filteredEntries {
    guard let substance = library.substance(named: entry.substance),
          let routeData = substance.route(for: entry.route),
          let doseRange = routeData.doseRange else { continue }
    let level = doseRange.level(for: entry.amount)
    let bucket = bucketDate(entry.timestamp)
    distribution[bucket][level] += 1
}
// Normalize each bucket to percentages
```

### Implementation Notes
- `Chart { ForEach(buckets) { AreaMark } }` with `.foregroundStyle(by: .value("Level", level))`.
- This chart is most valuable for single-substance analysis — add a substance selector at the top (default: "All").
- When viewing a single substance, show absolute counts instead of percentages on the y-axis.

---

## Section 5: Route Breakdown (new)

**Question answered:** "How do my administration routes vary?"

### Design
- **Horizontal stacked bar chart**: one bar per substance (top 10 by count), segmented by route.
- Route colors: assign a fixed color per route (oral = blue, sublingual = teal, insufflation = purple, inhalation = gray, IV = red, IM = orange, transdermal = green, etc.).
- Bar width proportional to total count.

### When to Show
- Only show if the user has logged entries with ≥2 distinct routes. Otherwise, hide the section entirely.

### Implementation Notes
- `Chart { BarMark(.horizontal) }` with `.foregroundStyle(by: .value("Route", route))`.
- Sort substances by total count descending.
- Keep it compact — this is a secondary insight.

---

## Section 6: Combinations & Co-use (new)

**Question answered:** "Which substances do I tend to use together?"

### Design
- **Co-occurrence matrix / list view** showing substances frequently logged on the same day.
- Display as a ranked list of pairs:
  ```
  Caffeine + L-Theanine          23 days
  Magnesium + Melatonin          18 days
  Adderall + Caffeine            12 days
  ```
- Each pair shows: frequency (days where both appear), and a subtle bar showing what % of days either substance was used that both were used together.

### Filtering
- Minimum co-occurrence threshold: 2 days (don't show one-off coincidences).
- Category filter: "Show only recreational" / "Show only supplements" / "All".

### Computation
```
let dayGroups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
var pairCounts: [Set<String>: Int] = [:]
for (_, dayEntries) in dayGroups {
    let substances = Set(dayEntries.map(\.substance))
    for pair in substances.combinations(ofCount: 2) {
        pairCounts[Set(pair), default: 0] += 1
    }
}
// Sort by count descending, take top 10
```

### Implementation Notes
- Use a simple `List` or `ForEach` with `HStack` — no chart needed.
- The `.combinations(ofCount:)` is from Swift Algorithms; if we don't want the dependency, a nested loop over the set works fine for small N.
- Show the pair's substance colors as two dots next to each pair name.

---

## Section 7: Periodicity / Regularity (new)

**Question answered:** "Do I use on a regular schedule, or sporadically?"

### Design
- **Per-substance regularity score** with a visual indicator.
- For each substance with ≥5 entries in the selected range, compute:
  - **Mean interval** (avg days between consecutive doses)
  - **CV (coefficient of variation)** = stddev / mean — lower = more regular
  - **Regularity label**: CV < 0.3 → "Very regular", < 0.6 → "Somewhat regular", < 1.0 → "Irregular", ≥ 1.0 → "Sporadic"
- Display as a list sorted by regularity (most regular first):
  ```
  ● Magnesium         Every 1.0 days    ████████████ Very regular
  ● Caffeine          Every 1.2 days    ████████░░░░ Somewhat regular
  ● Ibuprofen         Every 8.3 days    ████░░░░░░░░ Irregular
  ```

### Visual
- Progress bar filled proportional to regularity (1 - min(CV, 1.5) / 1.5).
- Color: green → yellow → orange → red based on CV buckets.

### Computation
```
let sorted = substanceEntries.sorted(by: \.timestamp)
let intervals = zip(sorted, sorted.dropFirst()).map { $1.timestamp.timeIntervalSince($0.timestamp) / 86400 }
let mean = intervals.mean
let stddev = intervals.standardDeviation
let cv = stddev / mean
```

### Implementation Notes
- No chart library needed — use `GeometryReader` bars or `ProgressView` with tint.
- Only compute for substances with ≥5 entries to avoid noisy stats.
- This section naturally answers "am I building a habit?" for supplements/medications and "how often am I using?" for recreational substances.

---

## Section 8: Day-of-Week Patterns (replaces current "Time of Day")

**Question answered:** "Which days of the week am I most active, and what do I use on each day?"

### Design
- **Grouped bar chart**: x-axis = days of week (Mon–Sun), bars = entry count.
- Each bar is stacked by substance category (using category colors).
- Below: **average entries per weekday** as a simple stat row.

### Enhancement over Current
The current "Time of Day" chart uses only 4 coarse buckets. This replaces it with a 7-day view while the hour-of-day detail moves to the heatmap (Section 2). The time-of-day data is *not lost* — it becomes the 24-bin histogram under the heatmap.

### Implementation Notes
- `Chart { BarMark }` with `.foregroundStyle(by: .value("Category", category))`.
- Day labels: abbreviated (Mon, Tue, ...).
- Show count annotation above each bar.

---

## Layout & Order

The sections appear in this order in a `ScrollView`:

1. **Time range selector** (sticky, top)
2. **Overview cards** (always visible)
3. **Activity heatmap** + hour histogram
4. **Substance trends** (multi-line)
5. **Day-of-week patterns** (grouped bars)
6. **Dose level distribution** (stacked area)
7. **Combinations & co-use** (list)
8. **Periodicity / regularity** (list with bars)
9. **Route breakdown** (conditional, stacked horizontal bars)

Sections 6–9 are in collapsible `DisclosureGroup`s (expanded by default on first visit, remembers state via `@AppStorage`).

---

## Data Requirements

All charts read from `[DoseEntry]` fetched via `@Query` with a date predicate based on the selected time range. Additional lookups:

| Data | Source | Used By |
|------|--------|---------|
| Substance category | `SubstanceLibrary.substance(named:)?.category` | Sections 2, 5, 8 |
| Dose level | `SubstanceLibrary` → `DoseRange.level(for:)` | Section 4 |
| Substance color | `SubstanceColor` SwiftData model | Sections 3, 6, 7 |
| Half-life | `HalfLifeDatabase` / `Substance.halfLifeMinutes` | (not directly used, but available for future "active time" charts) |

### Performance Considerations
- Pre-compute all derived data (buckets, rolling averages, co-occurrence) in a single pass in a `task {}` modifier when the time range changes.
- Cache the computed stats in an `@Observable` helper class (e.g., `UsageStatsComputer`) to avoid recomputing on every scroll frame.
- For "All" time range with thousands of entries, use wider buckets (weekly) and cap co-occurrence pairs at top 15.
- Heatmap rendering: use `drawingGroup()` modifier for Metal-accelerated compositing if cell count > 365.

---

## What's Removed

| Current Section | Disposition |
|----------------|-------------|
| Summary row (4 cards) | **Replaced** by Overview Cards (Section 1) with trends + sparklines |
| Frequency chart (top 10 bars) | **Removed** — redundant with Substance Trends (Section 3) which shows the same ranking with temporal context |
| Activity timeline (stacked bars/day) | **Removed** — the heatmap (Section 2) + substance trends (Section 3) together cover this more effectively |
| Dose trends (single substance) | **Evolved** into multi-substance trends (Section 3) + dose level distribution (Section 4) |
| Time of day (4 buckets) | **Replaced** by 24-bin hour histogram in Section 2 and day-of-week chart in Section 8 |
| Category donut | **Removed as standalone** — category info is now embedded as stacked colors in Sections 5 and 8; a dedicated category view added less value than the new analytical sections |

---

## Future Considerations (out of scope for v2)

- **Tolerance estimation**: plot estimated tolerance curve based on receptor pharmacology + dosing frequency.
- **Interaction timeline**: overlay known interaction warnings on the activity heatmap when two interacting substances appear on the same day.
- **Sleep/wellness correlation**: if the app adds mood/sleep tracking, correlate substance use with outcomes.
- **Export to CSV**: let users export the computed statistics.
