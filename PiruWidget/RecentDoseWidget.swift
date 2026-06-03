import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Recent Dose Widget

struct RecentDoseWidget: Widget {
    let kind = "RecentDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentDoseProvider()) { entry in
            RecentDoseView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Last Dose")
        .description("See your most recent dose and how long ago it was.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Entry

struct RecentDoseEntry: TimelineEntry {
    let date: Date
    let substance: String?
    let amount: Double
    let unit: String
    let route: String
    let doseTime: Date?
    let colorHex: String
}

// MARK: - Provider

struct RecentDoseProvider: TimelineProvider {
    func placeholder(in _: Context) -> RecentDoseEntry {
        RecentDoseEntry(date: .now, substance: "Caffeine", amount: 200, unit: "mg", route: "Oral", doseTime: .now.addingTimeInterval(-3_600), colorHex: "F57878")
    }

    func getSnapshot(in _: Context, completion: @escaping (RecentDoseEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RecentDoseEntry>) -> Void) {
        let entry = fetchEntry()
        // Update every 15 minutes so the "ago" text stays fresh
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static let appGroupID = "group.dev.yumeji.piru"

    private func fetchEntry() -> RecentDoseEntry {
        let container: ModelContainer
        do {
            guard let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupID,
            ) else {
                return RecentDoseEntry(date: .now, substance: nil, amount: 0, unit: "mg", route: "Oral", doseTime: nil, colorHex: "F56297")
            }
            let storeURL = groupURL.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: storeURL)
            container = try ModelContainer(
                for: DoseEntry.self, SubstanceColor.self, UserColor.self,
                DailyDoseItem.self, FavoriteSubstance.self, QuickLogDose.self,
                configurations: config,
            )
        } catch {
            return RecentDoseEntry(date: .now, substance: nil, amount: 0, unit: "mg", route: "Oral", doseTime: nil, colorHex: "F56297")
        }
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<DoseEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        )
        descriptor.fetchLimit = 1

        let colorDescriptor = FetchDescriptor<SubstanceColor>()

        guard let entries = try? context.fetch(descriptor), let entry = entries.first else {
            return RecentDoseEntry(date: .now, substance: nil, amount: 0, unit: "mg", route: "Oral", doseTime: nil, colorHex: "F56297")
        }

        let colors = (try? context.fetch(colorDescriptor)) ?? []
        let hex = colors.first { $0.substance.lowercased() == entry.substance.lowercased() }?.hexColor ?? "F56297"

        // Apply a personal display-name override (e.g. THC → "joint") from the
        // lightweight app-group map the main app maintains.
        let displayNames = (
            UserDefaults(suiteName: Self.appGroupID)?
                .dictionary(forKey: "piru.substanceDisplayNames.v1") as? [String: String],
        ) ?? [:]
        let shownSubstance = displayNames[entry.substance.lowercased()] ?? entry.substance

        return RecentDoseEntry(
            date: .now,
            substance: shownSubstance,
            amount: entry.amount,
            unit: entry.unit,
            route: entry.route.displayName,
            doseTime: entry.timestamp,
            colorHex: hex,
        )
    }
}

// MARK: - View

struct RecentDoseView: View {
    let entry: RecentDoseEntry

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

    private var timeAgo: String {
        guard let doseTime = entry.doseTime else { return "" }
        let interval = Date.now.timeIntervalSince(doseTime)
        let minutes = Int(interval / 60)
        let hours = minutes / 60

        if hours > 0 {
            let remainingMin = minutes % 60
            return remainingMin > 0
                ? String(localized: "\(hours)h \(remainingMin)m ago")
                : String(localized: "\(hours)h ago")
        }
        return String(localized: "\(minutes)m ago")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last Dose")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(Color(hex: entry.colorHex))
                    .frame(width: 8, height: 8)
            }

            Spacer(minLength: 0)

            if let substance = entry.substance {
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(entry.amount.doseFormatted) \(entry.unit)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WidgetColors.accent)
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No doses yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(2)
    }

    private var circularView: some View {
        VStack(spacing: 2) {
            if let substance = entry.substance {
                Image(systemName: "pill.fill")
                    .font(.caption)
                    .foregroundStyle(WidgetColors.accent)
                Text(shortTimeAgo)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(String(substance.prefix(5)))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "pill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            if let substance = entry.substance {
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(entry.amount.doseFormatted) \(entry.unit) · \(timeAgo)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No recent doses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var shortTimeAgo: String {
        guard let doseTime = entry.doseTime else { return "--" }
        let minutes = Int(Date.now.timeIntervalSince(doseTime) / 60)
        let hours = minutes / 60
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
