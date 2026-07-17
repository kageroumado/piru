import SwiftData
import SwiftUI
import TipKit

struct JournalCalendarView: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]
    let onSelectDate: (Date) -> Void

    @State private var selectedMonth: Date = .now

    /// Per-day entry counts keyed by day start, bucketed once per change to
    /// `entries` so each of the ~31 day cells does an O(1) lookup instead of
    /// scanning every entry.
    @State private var dayCounts: [Date: Int] = [:]

    private var calendar: Calendar {
        Calendar.current
    }

    /// Content fingerprint of the fields the day buckets depend on — the
    /// rebuild task's identity, mirroring `EntryListView.entriesSignature`.
    private var entriesSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.timestamp)
        }
        return hasher.finalize()
    }

    private func rebuildDayCounts() {
        dayCounts = entries.reduce(into: [:]) { counts, entry in
            counts[calendar.startOfDay(for: entry.timestamp), default: 0] += 1
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth)!
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(Text("Previous month"))
                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth)!
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel(Text("Next month"))
            }
            .padding(.horizontal)

            // Day-of-week header
            let weekdays = calendar.shortWeekdaySymbols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }

                // Calendar days
                ForEach(daysInMonth()) { item in
                    if item.day == 0 {
                        Color.clear.frame(height: 40)
                    } else {
                        let date = calendar.date(from: DateComponents(year: item.year, month: item.month, day: item.day))!
                        let count = dayCounts[date, default: 0]
                        Button {
                            onSelectDate(date)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(item.day)")
                                    .font(.subheadline)
                                    .foregroundStyle(count > 0 ? .primary : Theme.secondaryLabel)
                                    .fontWeight(count > 0 ? .semibold : .regular)
                                if count > 0 {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 5, height: 5)
                                } else {
                                    Color.clear.frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background {
                                if calendar.isDateInToday(date) {
                                    Circle().fill(Theme.accent.opacity(0.15))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(dayAccessibilityLabel(for: date))
                        .accessibilityValue(count > 0 ? Text("^[\(count) dose](inflect: true)") : Text(verbatim: ""))
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .task(id: entriesSignature) {
            rebuildDayCounts()
        }
    }

    /// "July 15" — plus "Today", the accent halo's only spoken equivalent.
    private func dayAccessibilityLabel(for date: Date) -> Text {
        let name = date.formatted(.dateTime.month(.wide).day())
        return calendar.isDateInToday(date) ? Text("\(name), Today") : Text(verbatim: name)
    }

    private struct CalendarDay: Identifiable, Hashable {
        let id: Int // unique within the grid (slot index); negative for leading placeholders
        let year: Int
        let month: Int
        let day: Int // 0 = placeholder
    }

    private func daysInMonth() -> [CalendarDay] {
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [CalendarDay] = []
        for blank in 0 ..< leadingBlanks {
            days.append(CalendarDay(id: -(blank + 1), year: comps.year!, month: comps.month!, day: 0))
        }
        for day in range {
            days.append(CalendarDay(id: day, year: comps.year!, month: comps.month!, day: day))
        }
        return days
    }
}
