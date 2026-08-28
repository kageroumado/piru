import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Today's Meds Widget (interactive)

/// The ambient, never-buzzing reminder surface (Specs/meds-ux-review.md §8):
/// today's med slots on the Home Screen, each takeable in place via
/// ``TakeMedIntent`` — see the schedule and check a med off without opening
/// the app. Quiet meds collapse into one "Supplements" line (mirroring
/// MyMedsCard), and the Lock Screen accessories carry the taken/total ring
/// and the next slot.
struct TodayMedsWidget: Widget {
    let kind = "TodayMedsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayMedsProvider()) { entry in
            TodayMedsView(entry: entry)
                .containerBackground(for: .widget) {
                    TodayMedsBackground()
                }
        }
        .configurationDisplayName("Today's Meds")
        .description("See today's med schedule and take one right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// System families get the standard widget gradient; the Lock Screen
/// accessories render on the system's vibrant material and stay clear.
private struct TodayMedsBackground: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium:
            WidgetBackground()
        default:
            Color.clear
        }
    }
}

// MARK: - Entry

/// One checkable dose slot: a due med × one of its reminder times (or a
/// single "anytime" slot). Value snapshot of `MyMedsCard.MedSlot`, since a
/// timeline entry can't hold `@Model`s.
struct TodayMedSlot: Identifiable {
    let identityKey: String
    let name: String
    let doseText: String
    /// Minutes from midnight, or `nil` for an "anytime" slot.
    let timeMinutes: Int?
    let slotIndex: Int
    let taken: Bool
    let isQuiet: Bool

    var id: String {
        identityKey + "#" + String(slotIndex)
    }

    func isDueNow(at date: Date) -> Bool {
        guard !taken else { return false }
        guard let timeMinutes else { return true }
        return timeMinutes <= TodayMedsEntry.minutesOfDay(date)
    }
}

struct TodayMedsEntry: TimelineEntry {
    let date: Date
    let slots: [TodayMedSlot]
    let relevance: TimelineEntryRelevance?

    static func minutesOfDay(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // Derived, shared by every family view.

    var takenCount: Int {
        slots.count(where: \.taken)
    }

    /// The Supplements fold only pays for itself with 2+ quiet slots — same
    /// rule as MyMedsCard.
    var collapseQuiet: Bool {
        slots.count(where: \.isQuiet) >= 2
    }

    var loudSlots: [TodayMedSlot] {
        collapseQuiet ? slots.filter { !$0.isQuiet } : slots
    }

    var quietSlots: [TodayMedSlot] {
        collapseQuiet ? slots.filter(\.isQuiet) : []
    }

    /// The first untaken slot with a time still ahead of this entry's date.
    var nextUpcoming: TodayMedSlot? {
        let now = Self.minutesOfDay(date)
        return slots.first { !$0.taken && $0.timeMinutes != nil && $0.timeMinutes! > now }
    }

    /// The first untaken slot, due-now ones first — what the accessories lead with.
    var nextActionable: TodayMedSlot? {
        slots.first { $0.isDueNow(at: date) } ?? nextUpcoming ?? slots.first { !$0.taken }
    }

    var allTaken: Bool {
        !slots.isEmpty && takenCount == slots.count
    }

    static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Provider

struct TodayMedsProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayMedsEntry {
        TodayMedsEntry(date: .now, slots: [
            TodayMedSlot(identityKey: "vyvanse", name: "Vyvanse", doseText: "40 mg", timeMinutes: 480, slotIndex: 0, taken: true, isQuiet: false),
            TodayMedSlot(identityKey: "sertraline", name: "Sertraline", doseText: "50 mg", timeMinutes: 540, slotIndex: 0, taken: false, isQuiet: false),
            TodayMedSlot(identityKey: "magnesium", name: "Magnesium", doseText: "200 mg", timeMinutes: 1_260, slotIndex: 0, taken: false, isQuiet: true),
            TodayMedSlot(identityKey: "vitamin d", name: "Vitamin D", doseText: "2000 IU", timeMinutes: 1_260, slotIndex: 0, taken: false, isQuiet: true),
        ], relevance: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (TodayMedsEntry) -> Void) {
        completion(fetchEntries().first ?? TodayMedsEntry(date: .now, slots: [], relevance: nil))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayMedsEntry>) -> Void) {
        // Entries at now + each remaining slot time (so "due"/"next" states
        // roll over on time) + next midnight (so tomorrow starts with a fresh,
        // unchecked list). Taken states only change through logging, and every
        // log path — in-app or the widget's own intents — reloads timelines.
        completion(Timeline(entries: fetchEntries(), policy: .atEnd))
    }

    private func fetchEntries() -> [TodayMedsEntry] {
        let now = Date.now
        let calendar = Calendar.current
        guard let container = WidgetStoreAccess.makeContainer() else {
            return [TodayMedsEntry(date: now, slots: [], relevance: nil)]
        }
        let context = ModelContext(container)

        let items = (try? context.fetch(
            FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]),
        )) ?? []

        let dayStart = calendar.startOfDay(for: now)
        let todayEntries = (try? context.fetch(
            FetchDescriptor<DoseEntry>(
                predicate: #Predicate { $0.timestamp >= dayStart },
                sortBy: [SortDescriptor(\.timestamp)],
            ),
        )) ?? []

        // The personal display-name override the app mirrors into the app group
        // (same source TodaySummaryWidget reads).
        let displayNames = (
            UserDefaults(suiteName: WidgetStoreAccess.appGroupID)?
                .dictionary(forKey: "piru.substanceDisplayNames.v1") as? [String: String],
        ) ?? [:]

        var dates: [Date] = [now]
        for slot in slots(on: now, items: items, entries: todayEntries, displayNames: displayNames) {
            guard let minutes = slot.timeMinutes,
                  let slotDate = calendar.date(
                      bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now,
                  ),
                  slotDate > now else { continue }
            dates.append(slotDate)
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            dates.append(midnight)
        }

        return dates.sorted().map { date in
            let slots = slots(on: date, items: items, entries: todayEntries, displayNames: displayNames)
            let dueNow = slots.contains { $0.isDueNow(at: date) }
            return TodayMedsEntry(
                date: date,
                slots: slots,
                // Smart Stack hint: surface the widget while something is due.
                relevance: TimelineEntryRelevance(score: dueNow ? 70 : 10),
            )
        }
    }

    /// Mirrors `MyMedsCard.allSlots` for an arbitrary day: due, non-PRN meds
    /// expanded into per-reminder-time slots, with the day's matched doses
    /// absorbed by the earliest slots first.
    private func slots(
        on date: Date,
        items: [DailyDoseItem],
        entries: [DoseEntry],
        displayNames: [String: String],
    ) -> [TodayMedSlot] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayEntries = entries.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }

        var slots: [(slot: TodayMedSlot, order: Int)] = []
        for item in items where !item.isAsNeeded {
            guard MedSchedule.isDue(
                startDate: item.startDate, frequency: item.frequency,
                frequencyDays: item.frequencyDays, on: date,
            ) else { continue }

            let times = item.reminderTimesMinutes.sorted()
            let expected = max(1, times.count)
            let matched = dayEntries.count { entry in
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
                    slot: TodayMedSlot(
                        identityKey: item.identityKey,
                        name: name,
                        doseText: "\(item.amount.doseFormatted) \(item.unit)",
                        timeMinutes: times.indices.contains(index) ? times[index] : nil,
                        slotIndex: index,
                        taken: index < matched,
                        isQuiet: item.isQuiet,
                    ),
                    order: item.sortOrder,
                ))
            }
        }
        return slots
            .sorted { ($0.slot.timeMinutes ?? .max, $0.order) < ($1.slot.timeMinutes ?? .max, $1.order) }
            .map(\.slot)
    }
}

// MARK: - Views

struct TodayMedsView: View {
    let entry: TodayMedsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            MedsCircularView(entry: entry)
        case .accessoryRectangular:
            MedsRectangularView(entry: entry)
        case .systemSmall:
            if entry.slots.isEmpty {
                MedsEmptyView()
            } else {
                MedsSmallView(entry: entry)
            }
        default:
            if entry.slots.isEmpty {
                MedsEmptyView()
            } else {
                MedsMediumView(entry: entry)
            }
        }
    }
}

private struct MedsEmptyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pills")
                .font(.title2)
                .foregroundStyle(WidgetColors.accent)
                .accessibilityHidden(true)
            Text("No meds today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Small

private struct MedsSmallView: View {
    let entry: TodayMedsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                MedsProgressRing(taken: entry.takenCount, total: entry.slots.count)
                    .frame(width: 52, height: 52)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            if entry.allTaken {
                Text("That's everything today.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            } else if let next = entry.nextActionable {
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let minutes = next.timeMinutes {
                        Text(verbatim: TodayMedsEntry.timeText(minutes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(
                                next.isDueNow(at: entry.date) ? AnyShapeStyle(WidgetColors.accent) : AnyShapeStyle(.secondary),
                            )
                    }
                }
            }
        }
        .padding(2)
    }
}

/// The taken/total ring, green like the app's My Meds header ring.
private struct MedsProgressRing: View {
    let taken: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: total == 0 ? 0 : CGFloat(taken) / CGFloat(total))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(taken)/\(total)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .accessibilityHidden(true)
    }
}

// MARK: Medium

private struct MedsMediumView: View {
    let entry: TodayMedsEntry

    private static let maxRows = 4

    /// A row is one loud slot or the collapsed Supplements line.
    private enum Row: Identifiable {
        case slot(TodayMedSlot)
        case supplements(taken: Int, total: Int)

        var id: String {
            switch self {
            case let .slot(slot): slot.id
            case .supplements: "supplements"
            }
        }

        var isTaken: Bool {
            switch self {
            case let .slot(slot): slot.taken
            case let .supplements(taken, total): taken == total
            }
        }
    }

    /// All rows in display order (loud slots by time, then the Supplements
    /// fold), trimmed to the widget's capacity by dropping *taken* rows first
    /// so an actionable med is never hidden behind a checked one.
    private var visibleRows: (rows: [Row], overflow: Int) {
        var rows: [Row] = entry.loudSlots.map(Row.slot)
        if !entry.quietSlots.isEmpty {
            rows.append(.supplements(
                taken: entry.quietSlots.count(where: \.taken),
                total: entry.quietSlots.count,
            ))
        }
        guard rows.count > Self.maxRows else { return (rows, 0) }

        var keep = Set(rows.filter { !$0.isTaken }.prefix(Self.maxRows).map(\.id))
        for row in rows where keep.count < Self.maxRows {
            keep.insert(row.id)
        }
        let visible = rows.filter { keep.contains($0.id) }.prefix(Self.maxRows)
        return (Array(visible), rows.count - visible.count)
    }

    var body: some View {
        let (rows, overflow) = visibleRows

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Meds")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.allTaken {
                    Text("That's everything today.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(verbatim: "\(entry.takenCount)/\(entry.slots.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WidgetColors.accent)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows) { row in
                    switch row {
                    case let .slot(slot):
                        MedSlotRow(slot: slot, entryDate: entry.date)
                    case let .supplements(taken, total):
                        SupplementsRow(taken: taken, total: total)
                    }
                }
            }

            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(2)
    }
}

/// One takeable slot row: check-circle button, name + dose, time.
private struct MedSlotRow: View {
    let slot: TodayMedSlot
    let entryDate: Date

    var body: some View {
        HStack(spacing: 8) {
            if slot.taken {
                WidgetCheckCircle(done: true, due: false)
            } else {
                Button(intent: TakeMedIntent(identityKey: slot.identityKey)) {
                    WidgetCheckCircle(done: false, due: slot.isDueNow(at: entryDate))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Take \(slot.name)"))
            }

            Text(slot.name)
                .font(.caption.weight(slot.taken ? .regular : .medium))
                .foregroundStyle(slot.taken ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .strikethrough(slot.taken)
                .lineLimit(1)

            Text(slot.doseText)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let minutes = slot.timeMinutes {
                Text(verbatim: TodayMedsEntry.timeText(minutes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(
                        slot.isDueNow(at: entryDate) ? AnyShapeStyle(WidgetColors.accent) : AnyShapeStyle(.secondary),
                    )
            }
        }
    }
}

/// The collapsed quiet-meds line; its check circle takes every remaining
/// supplement in one tap (the widget's Take All).
private struct SupplementsRow: View {
    let taken: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            if taken == total {
                WidgetCheckCircle(done: true, due: false)
            } else {
                Button(intent: TakeQuietMedsIntent()) {
                    WidgetCheckCircle(done: false, due: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Take all supplements"))
            }

            Text("Supplements")
                .font(.caption.weight(taken == total ? .regular : .medium))
                .foregroundStyle(taken == total ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .strikethrough(taken == total)

            Spacer(minLength: 4)

            Text(verbatim: "\(taken)/\(total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// The checked/unchecked circle, sized for widget rows.
private struct WidgetCheckCircle: View {
    let done: Bool
    let due: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(done ? Color.green : Color.clear)
            Circle()
                .strokeBorder(
                    done ? Color.green : (due ? WidgetColors.accent : Color.primary.opacity(0.25)),
                    lineWidth: 1.5,
                )
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
    }
}

// MARK: Lock Screen accessories

private struct MedsCircularView: View {
    let entry: TodayMedsEntry

    var body: some View {
        Gauge(value: Double(entry.takenCount), in: 0 ... Double(max(1, entry.slots.count))) {
            Image(systemName: "pills.fill")
                .accessibilityHidden(true)
        } currentValueLabel: {
            Text(verbatim: "\(entry.takenCount)/\(entry.slots.count)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.green)
    }
}

private struct MedsRectangularView: View {
    let entry: TodayMedsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "pills.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text("Meds")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                Text(verbatim: "\(entry.takenCount)/\(entry.slots.count)")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            if entry.slots.isEmpty {
                Text("No meds today")
                    .font(.headline)
            } else if entry.allTaken {
                Text("All taken")
                    .font(.headline)
            } else if let next = entry.nextActionable {
                Text(next.name)
                    .font(.headline)
                    .lineLimit(1)
                if let minutes = next.timeMinutes {
                    let time = TodayMedsEntry.timeText(minutes)
                    if next.isDueNow(at: entry.date) {
                        Text("Due · \(time)")
                            .font(.caption2)
                    } else {
                        Text(verbatim: time)
                            .font(.caption2)
                    }
                } else {
                    Text("Anytime")
                        .font(.caption2)
                }
            }
        }
    }
}
