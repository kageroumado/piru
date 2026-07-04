import Charts
import SwiftData
import SwiftUI

/// Insights overview — Apple Health–style large cards that surface each
/// insight's headline graph (or calendar) inline, tapping through to the full
/// detail screen.
struct InsightsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]

    @State private var adherence: AdherenceSummary?
    @State private var usage: UsageSummary?
    @State private var active: [ActiveSubstance] = []
    /// Zero-filled dose counts for the trailing two weeks (oldest → newest).
    @State private var dailyCounts: [DailyCount] = []
    /// Current month's per-day adherence, with leading `nil` weekday blanks so
    /// the mini grid aligns to the week — mirrors ``AdherenceView``'s layout.
    @State private var monthCells: [DayAdherence?] = []

    private let calendar = Calendar.current
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                usageCard
                inSystemCard
                adherenceCard
                toleranceCard
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .appNavigationBar("Insights")
        .task(id: changeToken) { await recompute() }
    }

    /// Re-derive summaries when the underlying data changes. Keyed on a content
    /// fingerprint (not counts) so in-place edits refresh the cards too, while
    /// the streak scan still doesn't recompute on every redraw.
    private var changeToken: Int {
        var hasher = Hasher()
        hasher.combine(EntriesFingerprint.make(allEntries, colors: substanceColors))
        hasher.combine(dailyItems.count)
        return hasher.finalize()
    }

    // MARK: - Usage

    private var usageCard: some View {
        largeCard(icon: "chart.bar.fill", tint: .blue, title: "Usage", route: .insight(.usage)) {
            if let u = usage, u.hasData {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(u.total)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("entries")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                        Spacer()
                        Text("\(u.perDayText)/day")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    usageChart
                    Text("Past 2 weeks")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            } else {
                emptyContent("No doses logged yet")
            }
        }
    }

    private var usageChart: some View {
        Chart(dailyCounts) { item in
            BarMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Doses", item.count),
                width: .fixed(7),
            )
            .foregroundStyle(Color.blue.gradient)
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 76)
        .accessibilityLabel(Text("Doses logged per day over the past two weeks"))
        .accessibilityValue(Text("\(dailyCounts.reduce(0) { $0 + $1.count }) in the last 14 days"))
    }

    // MARK: - In Your System

    private var inSystemCard: some View {
        largeCard(icon: "hourglass", tint: .teal, title: "In your system", route: .insight(.inSystem)) {
            if active.isEmpty {
                emptyContent("Nothing active right now")
            } else {
                VStack(spacing: 10) {
                    ForEach(active.prefix(3)) { sub in
                        GlanceRow(dotColor: sub.color, title: Text(sub.name)) {
                            Text("\(sub.totalRemaining.doseFormatted) \(sub.unit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(sub.color)
                            Text("\(Int((1 - sub.eliminatedFraction) * 100))%")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    if active.count > 3 {
                        GlanceMoreRow(count: active.count - 3)
                    }
                }
            }
        }
    }

    // MARK: - Adherence

    private var adherenceCard: some View {
        largeCard(icon: "flame.fill", tint: .orange, title: "Adherence", route: .insight(.adherence)) {
            if dailyItems.isEmpty {
                emptyContent("Track prescriptions in Settings to see adherence")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let a = adherence {
                            Text("\(a.streak)")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(a.streak == 1 ? "day streak" : "day streak")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                            Text("\(a.monthText) this month")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    miniCalendar
                }
            }
        }
    }

    private var miniCalendar: some View {
        VStack(spacing: 5) {
            Text(Date.now.formatted(.dateTime.month(.wide)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: calendarColumns, spacing: 3) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(adherenceDotColor(cell))
                            .frame(height: 15)
                            .overlay {
                                if calendar.isDateInToday(cell.date) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Theme.accent, lineWidth: 1.5)
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

    private func adherenceDotColor(_ day: DayAdherence) -> Color {
        if day.date > .now { return Color(.tertiarySystemFill) }
        switch day.status {
        case .complete: return .green.opacity(0.85)
        case .partial: return .orange.opacity(0.85)
        case .missed: return .red.opacity(0.8)
        case .noData: return Color(.secondarySystemFill)
        }
    }

    // MARK: - Tolerance

    /// Tolerance is usage statistics — a summary of the user's own logged history — so it lives in
    /// Insights (§7). The glance reads the warm ``ToleranceStore/states`` snapshot the background refresh
    /// keeps current, so the card is free (no compute here). Renders the top mechanism classes as a
    /// color-coded horizontal bar chart (family colour = the same class colours used in the Library).
    private var toleranceCard: some View {
        // Non-rested = responseFraction < 0.90 ⇒ severity > 0.10 (matches the tool's rested bucket).
        let notable = ToleranceStore.shared.states.values
            .filter { $0.severity > 0.10 }
            .sorted { $0.severity > $1.severity }
        return largeCard(icon: "chart.line.downtrend.xyaxis", tint: .purple, title: "Tolerance", route: .insight(.tolerance)) {
            if notable.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receptors rested")
                            .font(.subheadline.weight(.semibold))
                        Text("No notable predicted tolerance right now")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 9) {
                    ForEach(notable.prefix(4)) { state in
                        toleranceBar(state)
                    }
                }
            }
        }
    }

    /// One color-coded mechanism row: family-colour dot + class name + a bar
    /// whose fill length tracks the predicted tolerance level.
    private func toleranceBar(_ state: ClassTolerance) -> some View {
        let color = state.receptorClass.familyColor
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
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

    // MARK: - Card chrome

    /// An Apple Health–style large card — the shared ``GlanceCard``.
    private func largeCard(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        route: PushRoute,
        @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        GlanceCard(icon: icon, tint: tint, titleColor: tint, title: Text(title), route: route, content: content)
    }

    private func emptyContent(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summaries

    private struct DailyCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date {
            date
        }
    }

    private struct AdherenceSummary {
        let streak: Int
        let monthPct: Int
        let hasData: Bool
        var monthText: String {
            "\(monthPct)%"
        }
    }

    private struct UsageSummary {
        let total: Int
        let perDay: Double
        let mostLogged: String?
        var hasData: Bool {
            total > 0
        }
        var perDayText: String {
            String(format: "%.1f", perDay)
        }
    }

    private func recompute() async {
        let cal = calendar
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in allEntries {
            entriesByDay[cal.startOfDay(for: entry.timestamp), default: []].append(entry)
        }

        // Instant on-main readout: this month's adherence rate + the other cards.
        adherence = computeMonthAdherence(cal: cal, entriesByDay: entriesByDay)
        usage = computeUsage()
        active = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)
        dailyCounts = computeDailyCounts(cal: cal, entriesByDay: entriesByDay)
        monthCells = computeMonthCells(cal: cal, entriesByDay: entriesByDay)

        // The 365-day streak scan is the heavy part — run it off-main over
        // Sendable snapshots, then merge it into the (already-shown) summary.
        await refreshStreak()
    }

    /// Trailing 14 days of dose counts, zero-filled and ordered oldest → newest.
    private func computeDailyCounts(cal: Calendar, entriesByDay: [Date: [DoseEntry]]) -> [DailyCount] {
        let today = cal.startOfDay(for: .now)
        return (0 ..< 14).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyCount(date: day, count: entriesByDay[day]?.count ?? 0)
        }
    }

    /// Current month's per-day adherence with leading weekday blanks, for the
    /// mini calendar grid. Cheap (~30 days) so it stays on main.
    private func computeMonthCells(cal: Calendar, entriesByDay: [Date: [DoseEntry]]) -> [DayAdherence?] {
        guard !dailyItems.isEmpty,
              let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = cal.component(.weekday, from: start) - cal.firstWeekday
        let leadingBlanks = (firstWeekday + 7) % 7
        var cells: [DayAdherence?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in range {
            guard let date = cal.date(byAdding: .day, value: dayOffset - 1, to: start) else { continue }
            let dayStart = cal.startOfDay(for: date)
            cells.append(AdherenceCalculator.adherence(for: date, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems))
        }
        return cells
    }

    /// This-month adherence rate only — the instant readout. The streak is filled
    /// in afterward by ``refreshStreak()`` (off-main), so this returns `streak: 0`.
    private func computeMonthAdherence(cal: Calendar, entriesByDay: [Date: [DoseEntry]]) -> AdherenceSummary {
        guard !dailyItems.isEmpty else {
            return AdherenceSummary(streak: 0, monthPct: 0, hasData: false)
        }

        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1 ..< 2
        var month: [DayAdherence] = []
        for offset in range {
            guard let date = cal.date(byAdding: .day, value: offset - 1, to: monthStart) else { continue }
            let dayEntries = entriesByDay[cal.startOfDay(for: date)] ?? []
            month.append(AdherenceCalculator.adherence(for: date, entries: dayEntries, dailyItems: dailyItems))
        }
        let actionable = month.filter { $0.status != .noData && $0.date <= .now }
        let due = actionable.reduce(0) { $0 + $1.totalCount }
        let taken = actionable.reduce(0) { $0 + $1.takenCount }
        let pct = due > 0 ? Int((Double(taken) / Double(due)) * 100) : 0

        return AdherenceSummary(streak: 0, monthPct: pct, hasData: due > 0)
    }

    /// Compute the past-year streak off the main actor over `Sendable` snapshots
    /// and merge it into the current month summary.
    private func refreshStreak() async {
        guard !dailyItems.isEmpty else { return }
        let entrySnaps = allEntries.map {
            AdherenceCalculator.EntrySnapshot(substance: $0.substance, timestamp: $0.timestamp)
        }
        let itemSnaps = dailyItems.map {
            AdherenceCalculator.DailyItemSnapshot(
                substance: $0.substance, startDate: $0.startDate,
                frequency: $0.frequency, frequencyDays: $0.frequencyDays,
            )
        }
        let now = Date.now
        let streak = await Task.detached(priority: .utility) {
            AdherenceCalculator.currentStreak(spanningDays: 365, endingAt: now, entries: entrySnaps, items: itemSnaps)
        }.value
        guard let current = adherence else { return }
        adherence = AdherenceSummary(streak: streak, monthPct: current.monthPct, hasData: current.hasData || streak > 0)
    }

    private func computeUsage() -> UsageSummary {
        guard !allEntries.isEmpty,
              let newest = allEntries.first?.timestamp,
              let oldest = allEntries.last?.timestamp else {
            return UsageSummary(total: 0, perDay: 0, mostLogged: nil)
        }
        let days = max(1, newest.timeIntervalSince(oldest) / 86_400 + 1)
        var counts: [String: Int] = [:]
        for entry in allEntries {
            counts[entry.substance, default: 0] += 1
        }
        let most = counts.max { $0.value < $1.value }?.key
        return UsageSummary(total: allEntries.count, perDay: Double(allEntries.count) / days, mostLogged: most)
    }
}
