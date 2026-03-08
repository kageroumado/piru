import SwiftUI
import SwiftData

struct AdherenceView: View {
    @Query(sort: \DoseEntry.timestamp) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]

    @State private var displayedMonth: Date = .now
    @State private var monthAdherence: [DayAdherence] = []
    @State private var streak: Int = 0

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        if dailyItems.isEmpty {
            ContentUnavailableView(
                "No Daily Medications",
                systemImage: "pills",
                description: Text("Set up your daily dose items in Settings to start tracking adherence.")
            )
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    streakCard
                    calendarSection
                }
                .padding()
            }
            .task { recompute() }
            .onChange(of: allEntries.count) { recompute() }
            .onChange(of: displayedMonth) { recompute() }
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
            ForEach(days, id: \.self) { date in
                if let date {
                    let adherence = monthAdherence.first { calendar.isDate($0.date, inSameDayAs: date) }
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > .now

                    NavigationLink(value: date) {
                        AdherenceCalendarCell(
                            day: calendar.component(.day, from: date),
                            status: isFuture ? .noData : (adherence?.status ?? .missed),
                            isToday: isToday
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
        let completed = monthAdherence.filter { $0.status == .complete }.count
        let total = monthAdherence.filter { $0.status != .noData && $0.date <= .now }.count
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    private func recompute() {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let range = calendar.range(of: .day, in: .month, for: start)!

        var data: [DayAdherence] = []
        for dayOffset in range {
            let date = calendar.date(byAdding: .day, value: dayOffset - 1, to: start)!
            data.append(AdherenceCalculator.adherence(for: date, entries: allEntries, dailyItems: dailyItems))
        }

        monthAdherence = data

        // Compute streak across all time (last 365 days)
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: .now)!
        var allData: [DayAdherence] = []
        var d = yearAgo
        while d <= .now {
            allData.append(AdherenceCalculator.adherence(for: d, entries: allEntries, dailyItems: dailyItems))
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        streak = AdherenceCalculator.currentStreak(adherenceData: allData)
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
