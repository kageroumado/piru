import SwiftData
import SwiftUI

/// Insights overview — an App-Store "Today"-style intro that surfaces a glance
/// of each insight as a summary card, tapping into the full screen for detail.
struct InsightsView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var dailyItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]

    @State private var adherence: AdherenceSummary?
    @State private var usage: UsageSummary?
    @State private var active: [ActiveSubstance] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                adherenceCard
                usageCard
                inSystemCard
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

    // MARK: - Cards

    private var adherenceCard: some View {
        card(
            icon: "flame.fill",
            title: "Adherence",
            route: .insight(.adherence),
            detail: {
                if let a = adherence, a.hasData {
                    Text("\(a.streak)-day streak · \(a.monthText) this month")
                } else {
                    Text("No adherence data yet")
                }
            },
        )
    }

    private var usageCard: some View {
        card(
            icon: "chart.bar.fill",
            title: "Usage",
            route: .insight(.usage),
            detail: {
                if let u = usage, u.hasData {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(u.total) entries · \(u.perDayText)/day")
                        if let most = u.mostLogged {
                            Text("Most logged: \(most)")
                        }
                    }
                } else {
                    Text("No doses logged yet")
                }
            },
        )
    }

    private var inSystemCard: some View {
        card(
            icon: "hourglass",
            title: "In your system",
            route: .tool(.calculator),
            detail: {
                if active.isEmpty {
                    Text("Nothing active right now")
                } else {
                    Text("\(active.count) active right now")
                }
            },
        )
    }

    // MARK: - Card chrome

    private func card(
        icon: String,
        title: LocalizedStringKey,
        route: PushRoute,
        @ViewBuilder detail: @escaping () -> some View,
    ) -> some View {
        NavigationLink(value: route) {
            NavCardLabel(icon: icon, title: Text(title), detail: detail)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summaries

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
        let cal = Calendar.current
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in allEntries {
            entriesByDay[cal.startOfDay(for: entry.timestamp), default: []].append(entry)
        }

        // Instant on-main readout: this month's adherence rate + the other cards.
        adherence = computeMonthAdherence(cal: cal, entriesByDay: entriesByDay)
        usage = computeUsage()
        active = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)

        // The 365-day streak scan is the heavy part — run it off-main over
        // Sendable snapshots, then merge it into the (already-shown) summary.
        await refreshStreak()
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
