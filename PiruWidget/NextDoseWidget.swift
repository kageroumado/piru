import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Next Dose Countdown Widget

struct NextDoseWidget: Widget {
    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDoseProvider()) { entry in
            NextDoseView(entry: entry)
                .containerBackground(for: .widget) {
                    NextDoseBackground()
                }
        }
        .configurationDisplayName("Next Dose")
        .description("Countdown to your next scheduled med.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct NextDoseBackground: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            WidgetBackground()
        default:
            Color.clear
        }
    }
}

// MARK: - Entry

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let nextSlot: NextSlotSnapshot?
    let takenCount: Int
    let totalCount: Int
}

struct NextSlotSnapshot {
    let name: String
    let doseText: String
    let dueDate: Date
    let isDueNow: Bool
}

// MARK: - Provider

struct NextDoseProvider: TimelineProvider {
    func placeholder(in _: Context) -> NextDoseEntry {
        let due = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now) ?? .now
        return NextDoseEntry(
            date: .now,
            nextSlot: NextSlotSnapshot(name: "Sertraline", doseText: "50 mg", dueDate: due, isDueNow: false),
            takenCount: 1,
            totalCount: 3,
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (NextDoseEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current

        var dates: [Date] = [now]
        let entry = makeEntry(at: now)
        if let dueDate = entry.nextSlot?.dueDate, dueDate > now {
            dates.append(dueDate)
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }

        let entries = dates.sorted().map { makeEntry(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date) -> NextDoseEntry {
        let calendar = Calendar.current
        guard let container = WidgetStoreAccess.makeContainer() else {
            return NextDoseEntry(date: date, nextSlot: nil, takenCount: 0, totalCount: 0)
        }
        let context = ModelContext(container)

        let items = (try? context.fetch(
            FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]),
        )) ?? []

        let dayStart = calendar.startOfDay(for: date)
        let todayEntries = (try? context.fetch(
            FetchDescriptor<DoseEntry>(
                predicate: #Predicate { $0.timestamp >= dayStart },
                sortBy: [SortDescriptor(\.timestamp)],
            ),
        )) ?? []

        let displayNames = (
            UserDefaults(suiteName: WidgetStoreAccess.appGroupID)?
                .dictionary(forKey: "piru.substanceDisplayNames.v1") as? [String: String],
        ) ?? [:]

        var slots: [(name: String, doseText: String, timeMinutes: Int?, taken: Bool)] = []
        for item in items where !item.isAsNeeded {
            guard MedSchedule.isDue(
                startDate: item.startDate, frequency: item.frequency,
                frequencyDays: item.frequencyDays, on: date,
            ) else { continue }

            let times = item.reminderTimesMinutes.sorted()
            let expected = max(1, times.count)
            let matched = todayEntries.count { entry in
                MedSchedule.matches(
                    entryKey: entry.identityKey, entryName: entry.substance, entryRoute: entry.route,
                    itemKey: item.identityKey, itemName: item.substance, itemRoute: item.route,
                )
            }
            let name = item.productName
                ?? displayNames[item.substance.lowercased()]
                ?? item.substance
            for index in 0 ..< expected {
                slots.append((
                    name: name,
                    doseText: "\(item.amount.doseFormatted) \(item.unit)",
                    timeMinutes: times.indices.contains(index) ? times[index] : nil,
                    taken: index < matched,
                ))
            }
        }

        let taken = slots.count(where: \.taken)
        let nowMinutes = TodayMedsEntry.minutesOfDay(date)

        let nextUntaken = slots
            .filter { !$0.taken && $0.timeMinutes != nil }
            .sorted { ($0.timeMinutes ?? 0) < ($1.timeMinutes ?? 0) }
            .first { ($0.timeMinutes ?? 0) >= nowMinutes }
            ?? slots.first { !$0.taken && $0.timeMinutes != nil }

        let snapshot: NextSlotSnapshot? = nextUntaken.flatMap { slot in
            guard let minutes = slot.timeMinutes,
                  let dueDate = calendar.date(
                      bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date,
                  )
            else { return nil }
            return NextSlotSnapshot(
                name: slot.name,
                doseText: slot.doseText,
                dueDate: dueDate,
                isDueNow: minutes <= nowMinutes,
            )
        }

        return NextDoseEntry(
            date: date,
            nextSlot: snapshot,
            takenCount: taken,
            totalCount: slots.count,
        )
    }
}

// MARK: - Views

private struct NextDoseView: View {
    let entry: NextDoseEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "timer")
                    .foregroundStyle(WidgetColors.accent)
                Text("Next Dose")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let slot = entry.nextSlot {
                Text(slot.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(slot.doseText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if slot.isDueNow {
                    Text("Due now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WidgetColors.accent)
                } else {
                    Text(timerInterval: entry.date ... slot.dueDate, countsDown: true)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WidgetColors.accent)
                }
            } else if entry.totalCount > 0 {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("All taken")
                    .font(.subheadline.weight(.medium))
                Spacer()
            } else {
                Spacer()
                Text("No meds today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var circularView: some View {
        if let slot = entry.nextSlot {
            if slot.isDueNow {
                VStack(spacing: 2) {
                    Image(systemName: "pill")
                    Text("Due")
                        .font(.caption.weight(.semibold))
                }
            } else {
                VStack(spacing: 2) {
                    Text(timerInterval: entry.date ... slot.dueDate, countsDown: true)
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                    Image(systemName: "pill")
                        .font(.caption2)
                }
            }
        } else if entry.totalCount > 0 {
            Image(systemName: "checkmark.circle")
                .font(.title2)
        } else {
            Image(systemName: "pill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if let slot = entry.nextSlot {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(slot.doseText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if slot.isDueNow {
                    Text("Due now")
                        .font(.caption.weight(.bold))
                } else {
                    Text(timerInterval: entry.date ... slot.dueDate, countsDown: true)
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                }
            }
        } else if entry.totalCount > 0 {
            Label("All taken", systemImage: "checkmark.circle")
                .font(.headline)
        } else {
            Label("No meds today", systemImage: "pill")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
