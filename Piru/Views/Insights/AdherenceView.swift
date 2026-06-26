import SwiftData
import SwiftUI

struct AdherenceView: View {
    @Query(sort: \DoseEntry.timestamp) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]

    @State private var displayedMonth: Date = .now
    @State private var monthAdherence: [DayAdherence] = []
    /// Same data keyed by `startOfDay` so each calendar cell is an O(1) lookup
    /// instead of a linear `first { isDate(...) }` scan — the grid did O(days²)
    /// per body pass.
    @State private var monthAdherenceByDay: [Date: DayAdherence] = [:]
    @State private var streak: Int = 0
    @State private var selectedDay: DayAdherence?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        if dailyItems.isEmpty {
            ContentUnavailableView(
                "No Prescriptions",
                systemImage: "pills",
                description: Text("Add prescriptions in Settings to start tracking adherence."),
            )
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    streakCard
                    calendarSection
                }
                .padding()
            }
            .background(Theme.background)
            .task(id: EntriesFingerprint.make(allEntries)) { await recompute() }
            .onChange(of: displayedMonth) { recomputeMonth() }
            .sheet(item: $selectedDay) { day in
                AdherenceDayDetailSheet(day: day)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(streak == 1 ? "day streak" : "days streak")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let rate = adherenceRate
                Text("\(Int(rate * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(rate >= 0.8 ? .green : rate >= 0.5 ? .orange : .red)
                Text("this month")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            calendarGrid
        }
        .padding()
        .themeCard()
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(Text("Previous Month"))
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                withAnimation {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(Text("Next Month"))
            .disabled(calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        return LazyVGrid(columns: columns, spacing: 4) {
            // Use the slot index as the identity, not the date itself —
            // the leading blanks at the start of the month are all `nil`
            // and would otherwise collide on `id: \.self`.
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    let adherence = monthAdherenceByDay[calendar.startOfDay(for: date)]
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > .now

                    Button {
                        if !isFuture, let adherence, adherence.status != .noData {
                            selectedDay = adherence
                        }
                    } label: {
                        AdherenceCalendarCell(
                            day: calendar.component(.day, from: date),
                            status: isFuture ? .noData : (adherence?.status ?? .missed),
                            isToday: isToday,
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(height: 36)
                }
            }
        }
    }

    // MARK: - Computation

    private var adherenceRate: Double {
        let actionable = monthAdherence.filter { $0.status != .noData && $0.date <= .now }
        let totalDue = actionable.reduce(0) { $0 + $1.totalCount }
        guard totalDue > 0 else { return 0 }
        let totalTaken = actionable.reduce(0) { $0 + $1.takenCount }
        return Double(totalTaken) / Double(totalDue)
    }

    /// Recompute the visible month (instant, ~30 days on main) then the streak
    /// (the heavy 365-day scan, off-main). Mirrors `InsightsView`'s pattern.
    private func recompute() async {
        recomputeMonth()
        await refreshStreak()
    }

    /// The displayed month's per-day adherence — cheap (~30 days), so it stays
    /// synchronous for an instant calendar on month-nav. Publishes both the
    /// ordered array (for the rate) and the by-day dict (for O(1) cells).
    private func recomputeMonth() {
        // Pre-group entries by day — O(N) once instead of O(N) per day
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in allEntries {
            let day = calendar.startOfDay(for: entry.timestamp)
            entriesByDay[day, default: []].append(entry)
        }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let range = calendar.range(of: .day, in: .month, for: start)!

        var data: [DayAdherence] = []
        var byDay: [Date: DayAdherence] = [:]
        for dayOffset in range {
            let date = calendar.date(byAdding: .day, value: dayOffset - 1, to: start)!
            let dayStart = calendar.startOfDay(for: date)
            let adherence = AdherenceCalculator.adherence(for: date, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems)
            data.append(adherence)
            byDay[dayStart] = adherence
        }

        monthAdherence = data
        monthAdherenceByDay = byDay
    }

    /// The 365-day streak scan, run off the main actor over `Sendable`
    /// snapshots — it used to block the first paint and every month-nav.
    private func refreshStreak() async {
        guard !dailyItems.isEmpty else {
            streak = 0
            return
        }
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
        streak = await Task.detached(priority: .utility) {
            AdherenceCalculator.currentStreak(spanningDays: 365, endingAt: now, entries: entrySnaps, items: itemSnaps)
        }.value
    }

    private func daysInMonth() -> [Date?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let range = calendar.range(of: .day, in: .month, for: start)!

        let firstWeekday = calendar.component(.weekday, from: start) - calendar.firstWeekday
        let leadingBlanks = (firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in range {
            days.append(calendar.date(byAdding: .day, value: dayOffset - 1, to: start))
        }
        return days
    }
}

// MARK: - Calendar Cell

struct AdherenceCalendarCell: View {
    let day: Int
    let status: AdherenceStatus
    let isToday: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            if isToday {
                Circle()
                    .stroke(Theme.accent, lineWidth: 2)
            }
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.caption2.weight(isToday ? .bold : .medium).monospacedDigit())
                statusIcon
                    .frame(height: 10)
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(day)"))
        .accessibilityValue(Text(statusDescription))
    }

    /// Status wording matching `AdherenceDayDetailSheet`'s badge.
    private var statusDescription: LocalizedStringResource {
        switch status {
        case .complete: "All taken"
        case .partial: "Partially taken"
        case .missed: "All missed"
        case .noData: "Nothing due"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.green)
        case .partial:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
        case .missed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.red)
        case .noData:
            Color.clear
                .frame(height: 8)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .complete: .green.opacity(0.1)
        case .partial: .orange.opacity(0.1)
        case .missed: .red.opacity(0.1)
        case .noData: Color(.secondarySystemBackground).opacity(0.5)
        }
    }
}

// MARK: - Day Detail Sheet

struct AdherenceDayDetailSheet: View {
    let day: DayAdherence
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        statusBadge
                        Spacer()
                        Text("\(day.takenCount)/\(day.totalCount) taken")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Section("Prescriptions due") {
                    ForEach(day.items) { itemAdherence in
                        HStack(spacing: 12) {
                            Image(systemName: itemAdherence.taken ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(itemAdherence.taken ? .green : .red)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    itemAdherence.taken
                                        ? "Taken \(itemAdherence.item.substance)"
                                        : "Missed \(String(localized: itemAdherence.item.route.localizedName).lowercased()) of \(itemAdherence.item.substance)",
                                )
                                .font(.body)

                                Text("\(itemAdherence.item.amount.doseFormatted) \(itemAdherence.item.unit) \u{2014} \(String(localized: itemAdherence.item.frequency.shortLabel))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusLabel)
                .font(.headline)
        }
    }

    private var statusIcon: String {
        switch day.status {
        case .complete: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missed: "xmark.circle.fill"
        case .noData: "minus.circle"
        }
    }

    private var statusColor: Color {
        switch day.status {
        case .complete: .green
        case .partial: .orange
        case .missed: .red
        case .noData: .secondary
        }
    }

    private var statusLabel: LocalizedStringResource {
        switch day.status {
        case .complete: "All taken"
        case .partial: "Partially taken"
        case .missed: "All missed"
        case .noData: "Nothing due"
        }
    }
}
