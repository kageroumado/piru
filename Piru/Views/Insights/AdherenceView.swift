import SwiftData
import SwiftUI

struct AdherenceView: View {
    @Environment(\.appNavigator) private var navigator
    @Query(sort: \DoseEntry.timestamp) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]
    @Environment(\.modelContext) private var modelContext

    @State private var model = AdherenceModel()
    @State private var displayedMonth: Date = .now
    @State private var selectedDay: DayAdherence?

    var body: some View {
        if dailyItems.isEmpty {
            AdherenceEmptyState { navigator.push(.myMeds) }
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    AdherenceTodayCard(today: model.today) {
                        navigator.present(.quickLog(routine: nil))
                    }
                    AdherenceStreakCard(streak: model.streak, adherenceRate: model.adherenceRate)
                    AdherenceCalendar(
                        displayedMonth: $displayedMonth,
                        monthAdherenceByDay: model.monthAdherenceByDay,
                        selectedDay: $selectedDay,
                        calendar: model.calendar,
                    )
                    AdherenceRemindersLink()
                }
                .padding()
            }
            .background(Theme.background)
            .task(id: DoseLogService.shared.revision) {
                await model.recompute(
                    entries: allEntries,
                    dailyItems: dailyItems,
                    month: displayedMonth,
                    container: modelContext.container,
                )
            }
            .onChange(of: displayedMonth) {
                model.recomputeMonth(entries: allEntries, dailyItems: dailyItems, month: displayedMonth)
            }
            .sheet(item: $selectedDay) { day in
                AdherenceDayDetailSheet(day: day)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Empty state

private struct AdherenceEmptyState: View {
    let onAddMeds: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            ContentUnavailableView(
                "No Meds Yet",
                systemImage: "pills",
                description: Text("Adherence tracks how consistently you take your scheduled meds. Add one and this screen starts working."),
            )
            Button(action: onAddMeds) {
                Label("Add Your Meds", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, Spacing.xxxl)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

// MARK: - Reminders link

private struct AdherenceRemindersLink: View {
    var body: some View {
        NavigationLink {
            NotificationSettingsView()
        } label: {
            HStack(spacing: Spacing.xl) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(Theme.accent)
                Text("Reminders")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .themeCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today Card

private struct AdherenceTodayCard: View {
    let today: DayAdherence?
    let onLogDose: () -> Void

    var body: some View {
        if let today, today.status != .noData {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    Text("Today")
                        .cardTitle()
                    Spacer()
                    Text("\(today.takenCount)/\(today.totalCount) taken")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                VStack(spacing: 0) {
                    ForEach(today.items) { itemAdherence in
                        TodayAdherenceRow(
                            title: itemAdherence.item.productName
                                ?? CustomSubstanceStore.shared.displayName(for: itemAdherence.item.substance),
                            doseText: "\(itemAdherence.item.amount.doseFormatted) \(itemAdherence.item.unit)",
                            takenCount: itemAdherence.takenCount,
                            totalCount: itemAdherence.totalCount,
                        )
                    }
                }
                if today.takenCount < today.totalCount {
                    Button(action: onLogDose) {
                        Label("Log a Dose", systemImage: "plus")
                            .sectionLabel()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.accent)
                }
            }
            .padding(14)
            .themeCard()
        }
    }
}

// MARK: - Today Row

private struct TodayAdherenceRow: View {
    let title: String
    let doseText: String
    let takenCount: Int
    let totalCount: Int

    private var done: Bool {
        takenCount >= totalCount
    }

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.Semantic.Success.accent : Color(.tertiaryLabel))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(doseText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            if totalCount > 1 {
                Text(verbatim: "\(takenCount)/\(totalCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(doseText)"))
        .accessibilityValue(
            done ? Text("Taken") : Text("\(takenCount) of \(totalCount) taken"),
        )
    }
}

// MARK: - Streak Card

private struct AdherenceStreakCard: View {
    let streak: Int
    let adherenceRate: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(streak)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(streak == 1 ? "day streak" : "days streak")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text("\(Int(adherenceRate * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(adherenceRate >= 0.8 ? Color.Semantic.Success.text : adherenceRate >= 0.5 ? Color.Semantic.Caution.text : Color.Semantic.Danger.text)
                Text("this month")
                    .captionSecondary()
            }
        }
        .padding()
        .themeCard()
    }
}

// MARK: - Calendar

private struct AdherenceCalendar: View {
    @Binding var displayedMonth: Date
    let monthAdherenceByDay: [Date: DayAdherence]
    @Binding var selectedDay: DayAdherence?
    let calendar: Calendar

    @State private var showMonthPicker = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 7)

    var body: some View {
        VStack(spacing: Spacing.xl) {
            AdherenceMonthHeader(displayedMonth: $displayedMonth, calendar: calendar) {
                showMonthPicker = true
            }
            AdherenceWeekdayHeader(columns: columns, calendar: calendar)
            AdherenceCalendarGrid(
                columns: columns,
                displayedMonth: displayedMonth,
                monthAdherenceByDay: monthAdherenceByDay,
                selectedDay: $selectedDay,
                calendar: calendar,
            )
        }
        .padding()
        .themeCard()
        .sheet(isPresented: $showMonthPicker) {
            AdherenceMonthPicker(displayedMonth: $displayedMonth, calendar: calendar)
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
        }
    }
}

private struct AdherenceMonthHeader: View {
    @Binding var displayedMonth: Date
    let calendar: Calendar
    let onPickMonth: () -> Void

    var body: some View {
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
            Button(action: onPickMonth) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .cardTitle()
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens month picker"))
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
}

private struct AdherenceWeekdayHeader: View {
    let columns: [GridItem]
    let calendar: Calendar

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(Array(calendar.orderedShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct AdherenceCalendarGrid: View {
    let columns: [GridItem]
    let displayedMonth: Date
    let monthAdherenceByDay: [Date: DayAdherence]
    @Binding var selectedDay: DayAdherence?
    let calendar: Calendar

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, date in
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
                .foregroundStyle(Color.Semantic.Success.text)
                .accessibilityHidden(true)
        case .partial:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 8))
                .foregroundStyle(Color.Semantic.Caution.text)
                .accessibilityHidden(true)
        case .missed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.Semantic.Danger.text)
                .accessibilityHidden(true)
        case .noData:
            Color.clear
                .frame(height: 8)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .complete: Color.Semantic.Success.accent.opacity(Theme.Opacity.tint)
        case .partial: Color.Semantic.Caution.accent.opacity(Theme.Opacity.tint)
        case .missed: Color.Semantic.Danger.accent.opacity(Theme.Opacity.tint)
        case .noData: Color(.secondarySystemBackground).opacity(Theme.Opacity.dimmed)
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

                Section("Meds due") {
                    ForEach(day.items) { itemAdherence in
                        HStack(spacing: Spacing.xl) {
                            Image(systemName: itemAdherence.taken ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(itemAdherence.taken ? Color.Semantic.Success.accent : Color.Semantic.Danger.accent)
                                .font(.title3)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(
                                    itemAdherence.taken
                                        ? "Taken \(itemAdherence.item.substance)"
                                        : "Missed \(String(localized: itemAdherence.item.route.localizedName).lowercased()) of \(itemAdherence.item.substance)",
                                )
                                .font(.body)

                                Text("\(itemAdherence.item.amount.doseFormatted) \(itemAdherence.item.unit) \u{2014} \(String(localized: itemAdherence.item.frequency.shortLabel))")
                                    .captionSecondary()
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
            }
            .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            Text(statusLabel)
                .cardTitle()
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
        case .complete: Color.Semantic.Success.accent
        case .partial: Color.Semantic.Caution.accent
        case .missed: Color.Semantic.Danger.accent
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

// MARK: - Month Picker

private struct AdherenceMonthPicker: View {
    @Binding var displayedMonth: Date
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss

    @State private var pickerYear: Int
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3)

    init(displayedMonth: Binding<Date>, calendar: Calendar) {
        _displayedMonth = displayedMonth
        self.calendar = calendar
        _pickerYear = State(initialValue: calendar.component(.year, from: displayedMonth.wrappedValue))
    }

    private var currentYear: Int {
        calendar.component(.year, from: Date.now)
    }
    private var currentMonth: Int {
        calendar.component(.month, from: Date.now)
    }
    private var selectedMonth: Int {
        calendar.component(.month, from: displayedMonth)
    }
    private var selectedYear: Int {
        calendar.component(.year, from: displayedMonth)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Button {
                        withAnimation(.snappy) { pickerYear -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Previous Year"))
                    Spacer()
                    Text(verbatim: "\(pickerYear)")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button {
                        withAnimation(.snappy) { pickerYear += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Next Year"))
                    .disabled(pickerYear >= currentYear)
                }
                .padding(.horizontal)

                LazyVGrid(columns: monthColumns, spacing: Spacing.lg) {
                    ForEach(1 ... 12, id: \.self) { month in
                        let isFuture = pickerYear > currentYear || (pickerYear == currentYear && month > currentMonth)
                        let isSelected = pickerYear == selectedYear && month == selectedMonth
                        Button {
                            select(month: month)
                        } label: {
                            Text(calendar.monthSymbols[month - 1])
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.xl)
                                .background(isSelected ? Theme.accent.opacity(Theme.Opacity.tint) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.inner))
                                .foregroundStyle(isFuture ? Theme.secondaryLabel.opacity(Theme.Opacity.muted) : isSelected ? Theme.accent : .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isFuture)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, Spacing.md)
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    private func select(month: Int) {
        var comps = DateComponents()
        comps.year = pickerYear
        comps.month = month
        comps.day = 1
        if let date = calendar.date(from: comps) {
            withAnimation { displayedMonth = date }
        }
        dismiss()
    }
}
