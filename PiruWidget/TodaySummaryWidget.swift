import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Today Summary Widget

struct TodaySummaryWidget: Widget {
    let kind = "TodaySummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaySummaryProvider()) { entry in
            TodaySummaryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Current Session")
        .description("See your current session's doses at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry

struct TodaySummaryEntry: TimelineEntry {
    let date: Date
    let doses: [DoseSummary]
    let totalCount: Int
}

struct DoseSummary: Identifiable {
    let id = UUID()
    let substance: String
    let totalAmount: Double
    let unit: String
    let count: Int
    let colorHex: String
    let lastTime: Date
}

// MARK: - Provider

struct TodaySummaryProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodaySummaryEntry {
        TodaySummaryEntry(date: .now, doses: [
            DoseSummary(substance: "Caffeine", totalAmount: 200, unit: "mg", count: 2, colorHex: "F57878", lastTime: .now),
            DoseSummary(substance: "Vyvanse", totalAmount: 40, unit: "mg", count: 1, colorHex: "F57896", lastTime: .now),
        ], totalCount: 3)
    }

    func getSnapshot(in _: Context, completion: @escaping (TodaySummaryEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodaySummaryEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> TodaySummaryEntry {
        guard let container = WidgetStoreAccess.makeContainer() else {
            return TodaySummaryEntry(date: .now, doses: [], totalCount: 0)
        }
        let context = ModelContext(container)

        // Show the *current session* — the most recent one — rather than a
        // calendar day. Empty (no sessions yet) falls through to the empty state.
        var sessionDescriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)],
        )
        sessionDescriptor.fetchLimit = 1
        let entries = (try? context.fetch(sessionDescriptor))?.first?.orderedDoses ?? []

        let colorDescriptor = FetchDescriptor<SubstanceColor>()

        let colors = (try? context.fetch(colorDescriptor)) ?? []
        let colorMap = Dictionary(uniqueKeysWithValues: colors.compactMap { color -> (String, String)? in
            let hex = color.hexColor; guard !hex.isEmpty else { return nil }
            return (color.substance.lowercased(), hex)
        })

        // Group by substance
        var grouped: [String: (total: Double, unit: String, count: Int, lastTime: Date)] = [:]
        for entry in entries {
            let key = entry.substance
            var existing = grouped[key] ?? (total: 0, unit: entry.unit, count: 0, lastTime: entry.timestamp)
            existing.total += entry.amount
            existing.count += 1
            if entry.timestamp > existing.lastTime { existing.lastTime = entry.timestamp }
            grouped[key] = existing
        }

        // The personal display-name override (THC → "joint") the app mirrors into
        // the app group. This widget had none, so a relabel reached every surface
        // except this one.
        //
        // Only the relabel: these rows are per-*substance* totals, so the title
        // must stay canonical. A Concerta 36 mg and a Ritalin 10 mg sum to
        // "Methylphenidate 46 mg", which is the honest answer for a total — while
        // titling the group from either dose's product or snapshot would name the
        // whole group after one of the forms in it.
        let displayNames = (
            UserDefaults(suiteName: WidgetStoreAccess.appGroupID)?
                .dictionary(forKey: "piru.substanceDisplayNames.v1") as? [String: String],
        ) ?? [:]

        let doses = grouped.map { name, data in
            DoseSummary(
                substance: displayNames[name.lowercased()] ?? name,
                totalAmount: data.total,
                unit: data.unit,
                count: data.count,
                colorHex: colorMap[name.lowercased()] ?? "F56297",
                lastTime: data.lastTime,
            )
        }.sorted { $0.lastTime > $1.lastTime }

        return TodaySummaryEntry(date: .now, doses: doses, totalCount: entries.count)
    }
}

// MARK: - View

struct TodaySummaryView: View {
    let entry: TodaySummaryEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.doses.isEmpty {
            emptyState
        } else {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "pill")
                .font(.title2)
                .foregroundStyle(WidgetColors.accent)
            Text("No active session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.totalCount)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WidgetColors.accent)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.doses.prefix(3)) { dose in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: dose.colorHex))
                            .frame(width: 6, height: 6)
                        Text(dose.substance)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(dose.totalAmount.doseFormatted)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetColors.accent)
                    }
                }
            }

            if entry.doses.count > 3 {
                Text("+\(entry.doses.count - 3) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(2)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.totalCount) dose\(entry.totalCount == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetColors.accent)
            }

            Spacer(minLength: 0)

            let columns = entry.doses.count > 3
                ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                : [GridItem(.flexible())]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(entry.doses.prefix(6)) { dose in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: dose.colorHex))
                            .frame(width: 3, height: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(dose.substance)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Text("\(dose.totalAmount.doseFormatted) \(dose.unit)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WidgetColors.accent)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(2)
    }
}
