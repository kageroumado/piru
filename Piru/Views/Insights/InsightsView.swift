import Charts
import SwiftData
import SwiftUI

// MARK: - Model

@Observable
@MainActor
final class InsightsModel {
    struct AdherenceSummary {
        /// Scheduled doses taken so far this month, and how many were due.
        let taken: Int
        let due: Int
        let hasData: Bool
    }

    /// The Usage card's window: the range the Usage screen opens on, counted
    /// by the screen's own rule, one bar per day of it.
    static let usageRange = UsageTimeRange.opening

    private(set) var adherence: AdherenceSummary?
    /// The Usage card's count, or `nil` while the journal holds no entry at all.
    private(set) var usage: UsageWindowCount?
    private(set) var active: [ActiveSubstance] = []
    private(set) var monthCells: [DayAdherence?] = []

    private let calendar = Calendar.current

    /// The change token the published values were computed from. The view's
    /// `.task(id:)` also fires on re-appearance with the id unchanged; the
    /// whole-log recompute below is main-actor work, so it runs only when
    /// something it reads has changed.
    @ObservationIgnored private var computedToken: Int?
    /// When ``active`` was last computed; it decays with the clock, so it is
    /// refreshed on re-appearance once it is a minute old even when the log
    /// has not changed.
    @ObservationIgnored private var activeComputedAt: Date = .distantPast
    private static let activeStaleAfter: TimeInterval = 60

    func changeToken(substanceColors: [SubstanceColor], dailyItemCount: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        for color in substanceColors {
            hasher.combine(color.substance)
            hasher.combine(color.tint)
        }
        hasher.combine(dailyItemCount)
        return hasher.finalize()
    }

    func recompute(
        entries: [DoseEntry],
        dailyItems: [DailyDoseItem],
        substanceColors: [SubstanceColor],
    ) async {
        let token = changeToken(substanceColors: substanceColors, dailyItemCount: dailyItems.count)
        if computedToken == token {
            // The In Your Body card decays with the clock even when nothing was
            // logged, so it alone is refreshed once it has gone stale.
            if Date.now.timeIntervalSince(activeComputedAt) > Self.activeStaleAfter {
                active = ActiveSubstanceCalculator.compute(from: entries, colorMap: substanceColors.colorMap)
                activeComputedAt = .now
            }
            return
        }
        await SubstanceStore.shared.ensureAllLoaded()
        let cal = calendar
        // Journal days, each dose on the clock of the zone it was logged in.
        let boundaryHour = Calendar.sessionDayBoundaryHour
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in entries {
            entriesByDay[entry.journalDay(in: cal, boundaryHour: boundaryHour), default: []].append(entry)
        }

        let cells = computeMonthCells(
            cal: cal, entriesByDay: entriesByDay, dailyItems: dailyItems,
            scheduleOpens: AdherenceCalculator.scheduleOpens(for: dailyItems, entries: entries, boundaryHour: boundaryHour),
        )
        monthCells = cells
        adherence = Self.monthAdherence(fromCells: cells)
        active = ActiveSubstanceCalculator.compute(from: entries, colorMap: substanceColors.colorMap)
        activeComputedAt = .now
        usage = entries.isEmpty ? nil : UsageAnalytics.windowCount(
            entries.map(\.timestamp), range: Self.usageRange, now: .now, buckets: Self.usageRange.days ?? 30,
        )
        computedToken = token
    }

    private func computeMonthCells(
        cal: Calendar, entriesByDay: [Date: [DoseEntry]], dailyItems: [DailyDoseItem],
        scheduleOpens: [ObjectIdentifier: Date],
    ) -> [DayAdherence?] {
        guard !dailyItems.isEmpty,
              let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = cal.component(.weekday, from: start) - cal.firstWeekday
        let leadingBlanks = (firstWeekday + 7) % 7
        var cells: [DayAdherence?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in range {
            guard let date = cal.date(byAdding: .day, value: dayOffset - 1, to: start) else { continue }
            let dayStart = cal.startOfDay(for: date)
            cells.append(AdherenceCalculator.adherence(
                for: dayStart, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems, scheduleOpens: scheduleOpens,
            ))
        }
        return cells
    }

    /// The month summary read off the calendar cells — the same per-day
    /// adherence the mini calendar draws, computed once for both.
    private static func monthAdherence(fromCells cells: [DayAdherence?]) -> AdherenceSummary {
        let month = cells.compactMap(\.self)
        guard !month.isEmpty else {
            return AdherenceSummary(taken: 0, due: 0, hasData: false)
        }
        let today = Calendar.current.journalDay(for: .now)
        let actionable = month.filter { $0.status != .noData && $0.date <= today }
        let due = actionable.reduce(0) { $0 + $1.totalCount }
        let taken = actionable.reduce(0) { $0 + $1.takenCount }

        return AdherenceSummary(taken: taken, due: due, hasData: due > 0)
    }
}

// MARK: - View

/// Insights overview — Apple Health–style large cards that surface each
/// insight's headline graph (or calendar) inline, tapping through to the full
/// detail screen.
struct InsightsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]
    /// Any note carrying a "did it work?" answer. The card appears once there
    /// is something for it to read; nobody who never rates a dose sees it.
    @Query(filter: #Predicate<SessionNote> { $0.worked != nil }) private var ratedNotes: [SessionNote]

    @State private var model = InsightsModel()
    /// Whether the log holds an injectable hormone, read in `.task` rather
    /// than `body`: it scans the whole log.
    @State private var hasInjectableHormone = false

    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let compactColumns = [
        GridItem(.flexible(), spacing: Spacing.xl),
        GridItem(.flexible(), spacing: Spacing.xl),
    ]

    private var hasRatedNotes: Bool {
        !ratedNotes.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                usageCard
                adherenceCard
                if hasInjectableHormone {
                    HormoneLevelsInsightCard()
                }
                inYourBodyCard
                InsightsToleranceCard()
                largeCard(icon: "chart.xyaxis.line", tint: .pink, title: "Receptor Load", route: .insight(.receptorLoad)) {
                    Text("How hard each mechanism has been driven over time")
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: compactColumns, spacing: Spacing.xl) {
                    CompactRouteCard(
                        icon: "list.clipboard",
                        tint: .brown,
                        title: Text("Patterns"),
                        subtitle: Text("Trends, exposure, and overlap"),
                        route: .insight(.patterns),
                    )
                    if hasRatedNotes {
                        CompactRouteCard(
                            icon: "checkmark.bubble",
                            tint: .teal,
                            title: Text("Did it work?"),
                            subtitle: Text("Compare your dose ratings"),
                            route: .insight(.feltPatterns),
                        )
                    }
                    CompactRouteCard(
                        icon: "square.and.arrow.up.on.square",
                        tint: .indigo,
                        title: Text("Reports"),
                        subtitle: Text("Export sessions and journal summaries"),
                        route: .insight(.reports),
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 80)
        }
        .skinBackdrop()
        .appNavigationBar("Insights")
        .task(id: model.changeToken(substanceColors: substanceColors, dailyItemCount: dailyItems.count)) {
            await model.recompute(
                entries: allEntries,
                dailyItems: dailyItems,
                substanceColors: substanceColors,
            )
        }
        .task(id: DoseLogService.shared.revision) {
            hasInjectableHormone = HormoneLevelsLog.hasInjectableHormone(in: allEntries)
        }
    }

    // MARK: - Usage

    private var usageCard: some View {
        largeCard(icon: "chart.bar.fill", tint: .blue, title: "Usage", route: .insight(.usage)) {
            if let usage = model.usage {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                            UsageCardFigures(usage: usage)
                            Spacer(minLength: Spacing.sm)
                            usageWindowLabel
                        }
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            UsageCardFigures(usage: usage)
                            usageWindowLabel
                        }
                    }
                    UsageCardBars(usage: usage)
                }
            } else {
                emptyContent("No entries recorded yet")
            }
        }
    }

    private var usageWindowLabel: some View {
        Text(InsightsModel.usageRange.windowName)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
    }

    // MARK: - In Your Body

    private var inYourBodyCard: some View {
        largeCard(icon: "waveform.path.ecg", tint: .teal, title: "In Your Body", route: .insightGroup(.inYourBody)) {
            if model.active.isEmpty {
                emptyContent("Nothing active right now")
            } else {
                VStack(spacing: Spacing.lg) {
                    ForEach(model.active.prefix(3)) { sub in
                        GlanceRow(dotColor: sub.color, title: Text(CustomSubstanceStore.shared.displayName(for: sub.name))) {
                            Text("\(sub.totalRemaining.doseFormatted) \(sub.unit)")
                                .sectionLabel()
                                .foregroundStyle(sub.color)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if model.active.count > 3 {
                        GlanceMoreRow(count: model.active.count - 3)
                    }
                }
            }
        }
    }

    // MARK: - Adherence

    /// The count and the month on one line, the month's shape under it — the
    /// layout every card on this tab uses: figures first, picture second.
    ///
    /// No streak counter here, and no flame: a streak a single missed day
    /// resets to zero is a scoreboard, and this card is read by people for whom
    /// a scoreboard is a shame vector rather than a nudge. The calendar says
    /// which days; the count only ever goes up.
    private var adherenceCard: some View {
        largeCard(icon: "calendar", tint: Theme.accent, title: "Adherence", route: .insight(.adherence)) {
            if dailyItems.isEmpty {
                emptyContent("Add your meds to see adherence")
            } else {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let a = model.adherence, a.hasData {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(verbatim: "\(a.taken)/\(a.due)")
                                .font(.piru(.title2, design: .rounded, weight: .bold))
                            Text("scheduled")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                            Text(Date.now, format: .dateTime.month(.wide))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(a.taken) of \(a.due) scheduled doses"))
                    }
                    miniCalendar
                }
            }
        }
    }

    private var miniCalendar: some View {
        VStack(spacing: 5) {
            LazyVGrid(columns: calendarColumns, spacing: 3) {
                ForEach(Array(model.monthCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                            .fill(adherenceDotColor(cell))
                            .frame(height: 15)
                            .overlay {
                                if Calendar.current.isDateInToday(cell.date) {
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                                        .stroke(Theme.accent, lineWidth: 1.5)
                                } else if isMissed(cell) {
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.tiny)
                                        .strokeBorder(Theme.tertiaryLabel, lineWidth: 1)
                                }
                            }
                    } else {
                        Color.clear.frame(height: 15)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("This month's adherence calendar"))
    }

    /// The Adherence calendar's code: taken in the success color, partly
    /// taken a lighter step of it. An unlogged day is an empty outline, never
    /// a warning color: in a thin month those are most of the grid, and a
    /// dose is not a confession. The three read apart by lightness alone.
    private func adherenceDotColor(_ day: DayAdherence) -> Color {
        if day.date > .now { return Color.platformTertiarySystemFill }
        switch day.status {
        case .complete: return .successAccent.opacity(Theme.Opacity.dimmed)
        case .partial: return .successAccent.opacity(Theme.Opacity.tintActive)
        case .missed: return .clear
        case .noData: return Color.platformSecondarySystemFill
        }
    }

    private func isMissed(_ day: DayAdherence) -> Bool {
        day.date <= .now && day.status == .missed
    }

    private func emptyContent(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Usage card

private struct UsageCardFigures: View {
    let usage: UsageWindowCount

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(usage.entryCount)")
                .font(.piru(.title2, design: .rounded, weight: .bold))
            Text("entries")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            Text(usage.averagePerDayText)
                .font(.piru(.title2, design: .rounded, weight: .bold))
                .padding(.leading, Spacing.lg)
            Text("/day")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

/// One bar per day-long slice of the window, across the card's full width, in
/// the accent the Usage screen draws its entry counts in.
private struct UsageCardBars: View {
    let usage: UsageWindowCount

    private struct Bar: Identifiable {
        let id: Int
        let count: Int
    }

    var body: some View {
        let bars = usage.buckets.enumerated().map { Bar(id: $0.offset, count: $0.element) }
        Chart {
            // A categorical x, so the bars share the width out evenly.
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Day", String(bar.id)),
                    y: .value("Entries", bar.count),
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(2)
            }
            // The baseline spans the whole window, so a quiet stretch reads as
            // days with nothing logged.
            RuleMark(y: .value("Entries", 0))
                .foregroundStyle(Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 76)
        .accessibilityLabel(Text("Entries recorded per day"))
        .accessibilityValue(Text("\(usage.entryCount) entries"))
    }
}

// MARK: - Card chrome

/// Card chrome shared by every Insights glance card: the tint colors the icon,
/// the title keeps the label color.
private func largeCard(
    icon: String,
    tint: Color,
    title: LocalizedStringKey,
    route: PushRoute,
    @ViewBuilder content: @escaping () -> some View,
) -> some View {
    GlanceCard(icon: icon, tint: tint, title: Text(title), route: route, content: content)
}

/// Tolerance states worth surfacing on a glance card, worst first.
private var notableToleranceStates: [ClassTolerance] {
    ToleranceStore.shared.states.values
        .filter { $0.severity > 0.10 }
        .sorted { $0.severity > $1.severity }
}

// MARK: - Tolerance card

/// The Modeled Tolerance card: the per-class states the screen draws, worst
/// first.
private struct InsightsToleranceCard: View {
    var body: some View {
        GlanceCard(
            icon: "chart.line.downtrend.xyaxis", tint: .purple,
            title: Text("Modeled Tolerance"), route: .insight(.tolerance),
        ) {
            ToleranceBars(states: Array(notableToleranceStates.prefix(4)))
        }
    }
}

/// The per-class tolerance bars, worst first, or the line saying there are none.
private struct ToleranceBars: View {
    let states: [ClassTolerance]

    var body: some View {
        if states.isEmpty {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "chart.line.flattrend.xyaxis")
                    .font(.piru(.title))
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Nothing notable in the model")
                        .sectionLabel()
                    Text("Based only on the entries in your journal.")
                        .captionSecondary()
                }
                Spacer()
            }
        } else {
            VStack(spacing: Spacing.lg) {
                ForEach(states) { state in
                    ToleranceBarRow(state: state)
                }
            }
        }
    }
}

private struct ToleranceBarRow: View {
    let state: ClassTolerance

    var body: some View {
        let color = state.receptorClass.familyColor
        HStack(spacing: Spacing.lg) {
            LegendDot(color: color)
            Text(state.receptorClass.casualName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * state.severity), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 96, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.receptorClass.casualName))
        .accessibilityValue(Text("\(Int(state.severity * 100))% tolerance"))
    }
}
