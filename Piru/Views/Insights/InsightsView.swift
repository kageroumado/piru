import Charts
import SwiftData
import SwiftUI

// MARK: - Model

@Observable
@MainActor
final class InsightsModel {
    struct DailyCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date {
            date
        }
    }

    struct AdherenceSummary {
        /// Scheduled doses taken so far this month, and how many were due.
        let taken: Int
        let due: Int
        let hasData: Bool
    }

    /// The Usage card's figures, over the same days its bars draw.
    struct UsageSummary {
        let total: Int
        let perDay: Double
        /// Whether the journal holds any entry at all, in or out of the window.
        let hasEntries: Bool
        var perDayText: String {
            perDay.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// The days the Usage card's bars and figures cover, ending today.
    static let usageWindowDays = 14

    private(set) var adherence: AdherenceSummary?
    private(set) var usage: UsageSummary?
    private(set) var active: [ActiveSubstance] = []
    private(set) var dailyCounts: [DailyCount] = []
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

        let cells = computeMonthCells(cal: cal, entriesByDay: entriesByDay, dailyItems: dailyItems)
        monthCells = cells
        adherence = Self.monthAdherence(fromCells: cells)
        active = ActiveSubstanceCalculator.compute(from: entries, colorMap: substanceColors.colorMap)
        activeComputedAt = .now
        let counts = computeDailyCounts(cal: cal, entriesByDay: entriesByDay)
        dailyCounts = counts
        let windowTotal = counts.reduce(0) { $0 + $1.count }
        usage = UsageSummary(
            total: windowTotal,
            perDay: Double(windowTotal) / Double(Self.usageWindowDays),
            hasEntries: !entries.isEmpty,
        )
        computedToken = token
    }

    private func computeDailyCounts(cal: Calendar, entriesByDay: [Date: [DoseEntry]]) -> [DailyCount] {
        let today = cal.journalDay(for: .now)
        return (0 ..< Self.usageWindowDays).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyCount(date: day, count: entriesByDay[day]?.count ?? 0)
        }
    }

    private func computeMonthCells(cal: Calendar, entriesByDay: [Date: [DoseEntry]], dailyItems: [DailyDoseItem]) -> [DayAdherence?] {
        guard !dailyItems.isEmpty,
              let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = cal.component(.weekday, from: start) - cal.firstWeekday
        let leadingBlanks = (firstWeekday + 7) % 7
        var cells: [DayAdherence?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in range {
            guard let date = cal.date(byAdding: .day, value: dayOffset - 1, to: start) else { continue }
            let dayStart = cal.startOfDay(for: date)
            cells.append(AdherenceCalculator.adherence(for: dayStart, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems))
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

                LazyVGrid(columns: compactColumns, spacing: Spacing.xl) {
                    CompactLinkCard(
                        icon: "list.clipboard",
                        tint: .brown,
                        title: Text("Patterns"),
                        subtitle: Text("Trends, exposure, and overlap"),
                        route: .insight(.patterns),
                    )
                    if hasRatedNotes {
                        CompactLinkCard(
                            icon: "checkmark.bubble",
                            tint: .teal,
                            title: Text("Did it work?"),
                            subtitle: Text("Compare your dose ratings"),
                            route: .insight(.feltPatterns),
                        )
                    }
                    CompactLinkCard(
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
            if let u = model.usage, u.hasEntries {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                            usageFigures(u)
                            Spacer(minLength: Spacing.sm)
                            usageWindowLabel
                        }
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            usageFigures(u)
                            usageWindowLabel
                        }
                    }
                    usageChart
                }
            } else {
                emptyContent("No entries recorded yet")
            }
        }
    }

    private func usageFigures(_ u: InsightsModel.UsageSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(u.total)")
                .font(.piru(.title2, design: .rounded, weight: .bold))
            Text("entries")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            Text("\(u.perDayText)")
                .font(.piru(.title2, design: .rounded, weight: .bold))
                .padding(.leading, Spacing.lg)
            Text("/day")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var usageWindowLabel: some View {
        Text("Last \(InsightsModel.usageWindowDays) days")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
    }

    private var usageChart: some View {
        Chart(model.dailyCounts) { item in
            BarMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Entries", item.count),
                width: .fixed(7),
            )
            .foregroundStyle(Color.blue.gradient)
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 76)
        .accessibilityLabel(Text("Entries recorded per day over the past two weeks"))
        .accessibilityValue(Text("\(model.usage?.total ?? 0) in the last 14 days"))
    }

    // MARK: - In Your Body

    private var inYourBodyCard: some View {
        largeCard(icon: "waveform.path.ecg", tint: .teal, title: "Modeled Levels", route: .insightGroup(.inYourBody), isEstimation: true) {
            if model.active.isEmpty {
                emptyContent("Nothing active right now")
            } else {
                VStack(spacing: Spacing.lg) {
                    ForEach(model.active.prefix(3)) { sub in
                        GlanceRow(dotColor: sub.color, title: Text(CustomSubstanceStore.shared.displayName(for: sub.name))) {
                            Text("\(sub.totalRemaining.doseFormatted) \(sub.unit)")
                                .sectionLabel()
                                .foregroundStyle(sub.color)
                            RemainingBar(fraction: 1 - sub.eliminatedFraction, color: sub.color)
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

// MARK: - Remaining bar

/// A small capsule progress bar showing the remaining fraction of a substance,
/// matching the compact `DosePhaseProgressBar` style from timeline dose pills.
private struct RemainingBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(Theme.Opacity.tint))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(width: 40, height: 3)
        .accessibilityLabel(Text("\(Int(fraction * 100))% remaining"))
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
    isEstimation: Bool = false,
    @ViewBuilder content: @escaping () -> some View,
) -> some View {
    GlanceCard(icon: icon, tint: tint, title: Text(title), route: route, isEstimation: isEstimation, content: content)
}

/// Tolerance states worth surfacing on a glance card, worst first.
private var notableToleranceStates: [ClassTolerance] {
    ToleranceStore.shared.states.values
        .filter { $0.severity > 0.10 }
        .sorted { $0.severity > $1.severity }
}

// MARK: - Tolerance card

/// Modeled Tolerance and Receptor Load in one card: both screens read the same
/// per-class states, so the card draws those bars once and links to each
/// screen. Receptor Load's own data is a history (load over weeks), which
/// costs a full replay per class and stays on its screen.
private struct InsightsToleranceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteLink(.insight(.tolerance)) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    GlanceCardHeader(icon: "chart.line.downtrend.xyaxis", iconTint: .purple, title: Text("Modeled Tolerance")) {
                        EstimationTag()
                        GlanceCardChevron()
                    }
                    ToleranceBars(states: Array(notableToleranceStates.prefix(4)))
                }
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, Spacing.xxl)

            RouteLink(.insight(.receptorLoad)) {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "chart.xyaxis.line")
                        .cardTitle()
                        .foregroundStyle(.pink)
                        .frame(width: GlanceCardHeader<EmptyView>.iconWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Receptor Load")
                            .font(.subheadline.weight(.semibold))
                        Text("How hard each mechanism has been driven over time")
                            .captionSecondary()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.md)
                    GlanceCardChevron()
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .themeCard()
        .skinFrameCorners()
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
