import SwiftData
import SwiftUI

// MARK: - Shortcut Slots

/// The idle dock's leading area: the user's shortcut slots, in order. Empty
/// slots take no room. Lives in the accessory's overlay row (beside the "+")
/// because every slot is its own button over the full-width body button.
struct DockShortcutSlots: View {
    let currentTime: Date
    let compact: Bool
    let controlSide: CGFloat

    @State private var preferences = DockPreferences.shared
    @Query private var substanceColors: [SubstanceColor]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(preferences.shortcuts.prefix(Self.visibleCount(of: preferences.shortcuts.count, compact: compact))) { shortcut in
                DockShortcutButton(
                    shortcut: shortcut,
                    compact: compact,
                    controlSide: controlSide,
                    colorHex: shortcut.favoriteSubstance.flatMap { colorHex(for: $0) },
                    sessionActive: sessionActive,
                )
            }
        }
    }

    /// Re-read per accessory minute-tick: "active" is a time-dependent read of
    /// the session manager, so the `currentTime` input keeps it fresh.
    private var sessionActive: Bool {
        _ = currentTime
        return ActiveSessionManager.shared.hasActiveSession
    }

    private func colorHex(for substance: String) -> String? {
        Array(substanceColors).hexColorMap[substance.lowercased()]
    }
}

extension DockShortcutSlots {
    /// How many slots show: all of them in the full bar; only the first when
    /// the tab bar is folded, where three slots would leave the label a few
    /// characters ("Vita…").
    static func visibleCount(of total: Int, compact: Bool) -> Int {
        compact ? min(total, 1) : total
    }

    /// The width the body content must leave free for the slots, so the center
    /// label lands on true center.
    static func reservedWidth(slots: Int, controlSide: CGFloat) -> CGFloat {
        CGFloat(slots) * controlSide
    }
}

/// One slot. Fixed kinds show their symbol; a favorite shows its substance's
/// color with its initial, the same identity the Log sheet's cards carry.
private struct DockShortcutButton: View {
    let shortcut: DockShortcut
    let compact: Bool
    let controlSide: CGFloat
    let colorHex: String?
    let sessionActive: Bool

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    /// A favorite's display name, resolved once the substance cache is warm
    /// (the accessory mounts before the launch prewarm lands).
    @State private var favoriteTitle: String?

    private var isEnabled: Bool {
        !shortcut.requiresActiveSession || sessionActive
    }

    var body: some View {
        Button(action: perform) {
            glyph
                .frame(width: controlSide, height: controlSide)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .task(id: shortcut) {
            guard let substance = shortcut.favoriteSubstance else { return }
            await SubstanceStore.shared.ensureAllLoaded()
            guard !Task.isCancelled else { return }
            favoriteTitle = CustomSubstanceStore.shared.displayName(for: substance)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let substance = shortcut.favoriteSubstance {
            Text(substance.prefix(1).uppercased())
                .font((compact ? Font.caption2 : Font.caption).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                .background(colorHex.map { Color(hex: $0) } ?? .gray, in: Circle())
        } else {
            Image(systemName: shortcut.systemImage)
                .font((compact ? Font.subheadline : Font.title3).weight(.medium))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        }
    }

    private var title: String {
        if let substance = shortcut.favoriteSubstance {
            return favoriteTitle ?? substance
        }
        return shortcut.fixedTitle.map { String(localized: $0) } ?? ""
    }

    private func perform() {
        switch shortcut {
        case .inventory:
            navigator.selectedTab = .tools
            navigator.push(.tool(.inventory), in: .tools)
        case .interactions:
            navigator.selectedTab = .tools
            navigator.push(.tool(.interactions), in: .tools)
        case .timeline:
            navigator.selectedTab = .journal
            navigator.push(.timeline, in: .journal)
        case .myMeds:
            navigator.selectedTab = .journal
            navigator.push(.myMeds, in: .journal)
        case .addNote:
            guard navigator.sheetStack.isEmpty, let id = mostRecentSessionID() else { return }
            navigator.present(.sessionNoteEditor(sessionID: id))
        case let .favorite(substance):
            // Stages the substance at its reference dose; the user still commits.
            OnboardingTips.logDoseInvoked()
            guard navigator.sheetStack.isEmpty else { return }
            navigator.present(.quickLog(routine: nil, prefillSubstance: substance))
        }
    }

    /// The current session — most recent by start date, the same resolution
    /// the accessory's session tap uses.
    private func mostRecentSessionID() -> UUID? {
        var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.id
    }
}

// MARK: - Center Label

/// The idle dock's center text: the first applicable label from the user's
/// list. Owns the context derivation (due meds, last dose, next med) and
/// reports the due count out for the "+" badge. Recomputes once per accessory
/// minute-tick, plus whenever the meds list changes or a dose commits.
struct DockLabelText: View {
    let currentTime: Date
    let compact: Bool
    @Binding var dueCount: Int

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @State private var preferences = DockPreferences.shared
    @State private var context = DockLabelContext()

    var body: some View {
        Text(verbatim: DockLabel.resolve(preferences.labels, in: context))
            .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .task(id: recomputeKey) { await recompute() }
    }

    private var recomputeKey: String {
        "\(Int(currentTime.timeIntervalSinceReferenceDate / 60))|\(items.count)|\(DoseLogService.shared.revision)"
    }

    /// Display names resolve through the substance batch cache, which is cold
    /// at launch — the accessory mounts before the prewarm lands, so wait for it.
    private func recompute() async {
        await SubstanceStore.shared.ensureAllLoaded()
        guard !Task.isCancelled else { return }
        context = DockLabelContext.derive(items: items, in: modelContext, now: currentTime)
        dueCount = context.dueMedNames.count
    }
}

extension DockLabelContext {
    /// Gathers the label inputs off today's doses (one indexed fetch) and the
    /// most recent dose (one limit-1 fetch). "Due" is the same derivation as
    /// the quick-log due strip, so the dock and the Log sheet never disagree.
    @MainActor
    static func derive(items: [DailyDoseItem], in modelContext: ModelContext, now: Date) -> DockLabelContext {
        var context = DockLabelContext(now: now)
        context.lastDose = lastDose(in: modelContext)

        let scheduled = items.filter { !$0.isAsNeeded }
        guard !scheduled.isEmpty else { return context }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.timestamp >= dayStart })
        let todays = (try? modelContext.fetch(descriptor)) ?? []

        context.dueMedNames = DueNowSlot.derive(items: items, todayEntries: todays, now: now)
            .map { displayName(for: $0.item) }
        context.nextMed = nextMed(items: scheduled, todayEntries: todays, now: now, calendar: calendar)
        return context
    }

    private static func lastDose(in modelContext: ModelContext) -> DockDoseRef? {
        var descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let entry = try? modelContext.fetch(descriptor).first else { return nil }
        return DockDoseRef(
            name: entry.productName ?? CustomSubstanceStore.shared.displayName(for: entry.substance),
            timestamp: entry.timestamp,
        )
    }

    /// The earliest untaken timed slot still ahead today; failing that, the
    /// earliest slot of any med due tomorrow.
    private static func nextMed(items: [DailyDoseItem], todayEntries: [DoseEntry], now: Date, calendar: Calendar) -> DockMedRef? {
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var today: [(item: DailyDoseItem, minutes: Int)] = []
        for item in items where AdherenceCalculator.isDue(item, on: now) {
            let taken = todayEntries.count { AdherenceCalculator.entryMatches(entry: $0, item: item) }
            let times = item.reminderTimesMinutes.sorted()
            guard taken < times.count else { continue }
            if let slot = times[taken...].first(where: { $0 > nowMinutes }) {
                today.append((item, slot))
            }
        }
        if let soonest = today.min(by: { $0.minutes < $1.minutes }),
           let at = date(minutes: soonest.minutes, of: now, calendar: calendar) {
            return DockMedRef(name: displayName(for: soonest.item), at: at)
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        let first = items
            .filter { AdherenceCalculator.isDue($0, on: tomorrow) }
            .compactMap { item in item.reminderTimesMinutes.min().map { (item: item, minutes: $0) } }
            .min { $0.minutes < $1.minutes }
        guard let first, let at = date(minutes: first.minutes, of: tomorrow, calendar: calendar) else { return nil }
        return DockMedRef(name: displayName(for: first.item), at: at)
    }

    private static func date(minutes: Int, of day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    private static func displayName(for item: DailyDoseItem) -> String {
        item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
    }
}

// MARK: - Due Badge

/// The meds-due count on the "+", the app-icon badge idiom: it says there is
/// something to do in the Log sheet, where the due strip is first on screen.
struct DockDueBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(verbatim: "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(.red, in: Capsule())
                .accessibilityLabel(Text("\(count) meds due"))
        }
    }
}
