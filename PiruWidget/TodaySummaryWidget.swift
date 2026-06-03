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
        .configurationDisplayName("Today's Doses")
        .description("See what you've taken today at a glance.")
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

    private static let appGroupID = "group.dev.yumeji.piru"

    private func fetchEntry() -> TodaySummaryEntry {
        let container: ModelContainer
        do {
            guard let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupID,
            ) else {
                return TodaySummaryEntry(date: .now, doses: [], totalCount: 0)
            }
            let storeURL = groupURL.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: storeURL)
            container = try ModelContainer(
                for: DoseEntry.self, SubstanceColor.self, UserColor.self,
                DailyDoseItem.self, FavoriteSubstance.self, QuickLogDose.self,
                configurations: config,
            )
        } catch {
            return TodaySummaryEntry(date: .now, doses: [], totalCount: 0)
        }
        let context = ModelContext(container)

        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = #Predicate<DoseEntry> { $0.timestamp >= startOfDay }
        let descriptor = FetchDescriptor<DoseEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)],
        )

        let colorDescriptor = FetchDescriptor<SubstanceColor>()

        guard let entries = try? context.fetch(descriptor) else {
            return TodaySummaryEntry(date: .now, doses: [], totalCount: 0)
        }

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

        let doses = grouped.map { name, data in
            DoseSummary(
                substance: name,
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
            Text("No doses today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
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
                Text("Today")
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
