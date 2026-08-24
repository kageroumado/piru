import SwiftData
import SwiftUI

/// The Journal tab's "My Meds" card — the daily front door of the Meds
/// redesign (Specs/meds-reminders-redesign.md): today's checklist at a
/// glance, tap a circle to log, quiet meds folded into one "Supplements"
/// row with a one-tap Take All. Hidden entirely while nothing is due today
/// (no meds at all, only PRN meds, or only off-cycle schedules) — so a
/// recreational-only journal never carries it.
struct MyMedsCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]
    @Query private var todayEntries: [DoseEntry]
    @Query private var recentEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var todayOccurrences: [RoutineOccurrence]

    @State private var supplementsExpanded = false
    @State private var streak: Int?
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var pendingSlots: [MedSlot] = []
    @State private var showInteractionSheet = false

    init() {
        let dayStart = Calendar.current.startOfDay(for: .now)
        _todayEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= dayStart },
            sort: \DoseEntry.timestamp,
        )
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= cutoff },
            sort: \DoseEntry.timestamp,
        )
        _todayOccurrences = Query(
            filter: #Predicate<RoutineOccurrence> { $0.dueDay >= dayStart },
        )
    }

    // MARK: Slot derivation

    /// One checkable dose slot: a due med × one of its reminder times (or a
    /// single "anytime" slot). Earliest slots absorb today's matched doses
    /// first.
    enum SlotState {
        case pending
        case taken
        case skipped
    }

    struct MedSlot: Identifiable {
        let item: DailyDoseItem
        let time: Int?
        let index: Int
        let state: SlotState

        var taken: Bool {
            state == .taken
        }

        var id: String {
            item.substance + String(item.sortOrder) + "#" + String(index)
        }

        var isDueNow: Bool {
            guard state == .pending else { return false }
            guard let time else { return true }
            return time <= Self.nowMinutes
        }

        static var nowMinutes: Int {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: .now)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
    }

    private var allSlots: [MedSlot] {
        var slots: [MedSlot] = []
        let occurrencesByKey = Dictionary(
            todayOccurrences.map { (RoutineOccurrenceService.slotKey(for: $0), $0) },
            uniquingKeysWith: { _, last in last },
        )
        for item in items where !item.isAsNeeded && AdherenceCalculator.isDue(item, on: .now) {
            let times = item.reminderTimesMinutes.sorted()
            let expected = max(1, times.count)
            for index in 0 ..< expected {
                let slotMinutes = times.indices.contains(index) ? times[index] : nil
                let key = RoutineOccurrenceService.slotKey(
                    substance: item.substance,
                    substanceUID: item.substanceUID,
                    route: item.route,
                    slotMinutes: slotMinutes,
                )
                let state: SlotState = switch occurrencesByKey[key]?.state {
                case .logged: .taken
                case .skipped: .skipped
                default: .pending
                }
                slots.append(MedSlot(
                    item: item,
                    time: slotMinutes,
                    index: index,
                    state: state,
                ))
            }
        }
        return slots.sorted { ($0.time ?? .max) < ($1.time ?? .max) }
    }

    /// The Supplements fold only pays for itself with 2+ quiet slots — a
    /// single quiet med renders as a plain row rather than a one-item group.
    private var collapseQuiet: Bool {
        allSlots.count(where: \.item.isQuiet) >= 2
    }

    private var loudSlots: [MedSlot] {
        collapseQuiet ? allSlots.filter { !$0.item.isQuiet } : allSlots
    }

    private var quietSlots: [MedSlot] {
        collapseQuiet ? allSlots.filter(\.item.isQuiet) : []
    }

    private var takenCount: Int {
        allSlots.count(where: \.taken)
    }

    private var nextUpcoming: MedSlot? {
        allSlots.first { !$0.taken && $0.time != nil && $0.time! > MedSlot.nowMinutes }
    }

    // MARK: Body

    var body: some View {
        if !allSlots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header

                VStack(spacing: 0) {
                    ForEach(loudSlots) { slot in
                        slotRow(slot, indented: false)
                    }
                    if !quietSlots.isEmpty {
                        supplementsRow
                        if supplementsExpanded {
                            ForEach(quietSlots) { slot in
                                slotRow(slot, indented: true)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .themeCard()
            .task { await refreshStreak() }
            .sheet(isPresented: $showInteractionSheet) {
                InteractionWarningSheet(
                    warnings: interactionWarnings,
                    onProceed: {
                        showInteractionSheet = false
                        log(slots: pendingSlots)
                    },
                    onCancel: {
                        showInteractionSheet = false
                        pendingSlots = []
                    },
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        Button {
            navigator.push(.myMeds)
        } label: {
            HStack(spacing: 10) {
                progressRing
                VStack(alignment: .leading, spacing: 1) {
                    Text("My Meds")
                        .font(.headline)
                    // Status as a subtitle rather than a footer line — it
                    // swaps text (next dose → count left → "everything today")
                    // without ever changing the card's height, which is what
                    // made the old collapsing footer read as visually heavy.
                    statusSubtitle
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My Meds")
        .accessibilityValue("\(takenCount) of \(allSlots.count) taken")
        .accessibilityHint("Opens your meds")
    }

    /// The always-present status line under "My Meds": the completion note
    /// while done, otherwise the next timed dose, otherwise how many remain.
    /// One line in every state, so the card height never moves.
    @ViewBuilder
    private var statusSubtitle: some View {
        if isComplete {
            Text(completionText)
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if let next = nextUpcoming, let time = next.time {
            Text("Next: \(displayName(for: next.item)) at \(Self.timeText(time)) · \(Self.relativeText(time))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        } else {
            Text("\(allSlots.count - takenCount) left")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
    }

    /// Every scheduled slot logged for today — drives the ring's completion
    /// state and the transient celebration line.
    private var isComplete: Bool {
        !allSlots.isEmpty && takenCount == allSlots.count
    }

    private var progressRing: some View {
        let fraction = allSlots.isEmpty ? 0 : CGFloat(takenCount) / CGFloat(allSlots.count)
        return ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 4)
            // The arc grows as doses land — `.snappy` keyed on the fraction so
            // logging (or unlogging) animates the fill rather than snapping.
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: fraction)
            // At completion the count gives way to a checkmark that bounces —
            // the small "done!" moment. Reverts to the count if a dose is
            // unlogged.
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: isComplete)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(takenCount)/\(allSlots.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 36, height: 36)
        .animation(.snappy, value: isComplete)
        .accessibilityHidden(true)
    }

    private var completionText: String {
        if let streak, streak > 1 {
            String(localized: "That's everything today — \(streak) days and counting.")
        } else {
            String(localized: "That's everything today.")
        }
    }

    // MARK: Rows

    /// One checklist row as its own invalidation boundary (value inputs
    /// only), so toggling `supplementsExpanded` or logging one slot doesn't
    /// re-evaluate every other row's body.
    private func slotRow(_ slot: MedSlot, indented: Bool) -> some View {
        SlotRowView(
            title: displayName(for: slot.item),
            subtitle: "\(slot.item.amount.doseFormatted) \(slot.item.unit)",
            timeText: slot.time.map(Self.timeText),
            slotState: slot.state,
            due: slot.isDueNow,
            indented: indented,
            onToggle: {
                if slot.taken {
                    unlog(slot)
                } else {
                    attemptLog(slots: [slot])
                }
            },
            onOpen: {
                navigator.push(.medDetail(identityKey: slot.item.identityKey, sortOrder: slot.item.sortOrder))
            },
        )
    }

    private var supplementsRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { supplementsExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    supplementsCircle
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Supplements")
                            .font(.subheadline.weight(.medium))
                        Text("\(quietSlots.count(where: \.taken)) of \(quietSlots.count) taken")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supplements")
            .accessibilityValue("\(quietSlots.count(where: \.taken)) of \(quietSlots.count) taken")
            .accessibilityHint(supplementsExpanded ? Text("Collapses the list") : Text("Expands the list"))

            if quietSlots.contains(where: { !$0.taken }) {
                Button {
                    attemptLog(slots: quietSlots.filter { !$0.taken })
                } label: {
                    Text("Take All")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.snappy) { supplementsExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .rotationEffect(.degrees(supplementsExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
    }

    private var supplementsCircle: some View {
        let done = quietSlots.count(where: \.taken)
        let allDone = done == quietSlots.count
        return ZStack {
            if allDone {
                CheckCircle(state: .taken, due: false)
            } else {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: quietSlots.isEmpty ? 0 : CGFloat(done) / CGFloat(quietSlots.count))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    // MARK: Logging

    private func attemptLog(slots: [MedSlot]) {
        let names = slots.map(\.item.substance)
        let active = InteractionChecker.activeEntries(from: recentEntries)
        // See LogDailyDoseView.attemptLog: only `.notable` and above may block.
        let warnings = InteractionChecker.checkBatch(names, against: active).admitted(.notable)

        if warnings.isEmpty {
            log(slots: slots)
        } else {
            pendingSlots = slots
            interactionWarnings = warnings
            showInteractionSheet = true
        }
    }

    /// Mirrors `LogMedicationsView.logSelected` for the tapped slot(s): entry +
    /// session assignment + deterministic color + Live Activity + the deferred
    /// bookkeeping funnel.
    private func log(slots: [MedSlot]) {
        guard !slots.isEmpty else { return }
        let now = Date.now
        var affected: Set<String> = []
        var logged: [(entry: DoseEntry, substance: Substance?)] = []

        for slot in slots {
            let item = slot.item
            affected.insert(item.substance)

            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                timestamp: now,
                isBackgroundMed: item.isBackgroundMed,
            )
            modelContext.insert(entry)
            SessionService.assignSession(for: entry, in: modelContext)

            let matched = SubstanceLibrary.timelineLookup(item.substance).flatMap {
                $0.name.lowercased() == item.substance.lowercased() ? $0 : nil
            }
            logged.append((entry, matched))

            if !Array(substanceColors).hasColor(for: item.substance) {
                modelContext.insert(SubstanceColor(
                    substance: item.substance,
                    hexColor: PresetColor.deterministic(for: item.substance).hex,
                ))
            }
        }

        ActiveSessionManager.shared.addDoses(entries: logged, allColors: Array(substanceColors))
        DoseLogService.shared.changed()
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: affected, in: modelContext)
        pendingSlots = []
    }

    /// Undo a logged dose: delete today's most-recent entry matching this
    /// slot's med and drop it from the live session. The check-circle toggles,
    /// so an accidental tap-to-log is reversed by tapping the circle again —
    /// the whole-row log with no undo was the reported surprise.
    private func unlog(_ slot: MedSlot) {
        let item = slot.item
        guard let entry = todayEntries
            .filter({ AdherenceCalculator.entryMatches(entry: $0, item: item) })
            .max(by: { $0.timestamp < $1.timestamp })
        else { return }

        let id = entry.id
        let timestamp = entry.timestamp
        modelContext.delete(entry)
        ActiveSessionManager.shared.removeDose(
            id: id,
            substanceName: item.substance,
            timestamp: timestamp,
            allColors: Array(substanceColors),
        )
        DoseLogService.shared.changed()
    }

    // MARK: Helpers

    private func displayName(for item: DailyDoseItem) -> String {
        item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
    }

    /// The past-year streak, computed off the main actor over `Sendable`
    /// snapshots (same pattern as the Insights adherence card).
    private func refreshStreak() async {
        guard !items.isEmpty else { return }
        let entrySnaps = recentEntriesForStreak().map {
            AdherenceCalculator.EntrySnapshot(
                substance: $0.substance, identityKey: $0.identityKey,
                route: $0.route, timestamp: $0.timestamp,
            )
        }
        let itemSnaps = items.map {
            AdherenceCalculator.DailyItemSnapshot(
                substance: $0.substance, identityKey: $0.identityKey, route: $0.route,
                expectedPerDay: max(1, $0.reminderTimesMinutes.count), isAsNeeded: $0.isAsNeeded,
                startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays,
            )
        }
        let now = Date.now
        streak = await Task.detached(priority: .utility) {
            AdherenceCalculator.currentStreak(spanningDays: 365, endingAt: now, entries: entrySnaps, items: itemSnaps)
        }.value
    }

    private func recentEntriesForStreak() -> [DoseEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: .now) ?? .distantPast
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)],
        )
        // The snapshot mapping reads only these fields (identityKey derives
        // from the four identity facets) — a year of full-row faults on the
        // main actor was ~60 ms of every return to the Journal.
        descriptor.propertiesToFetch = [
            \.timestamp, \.substance, \.substanceUID, \.isomer, \.releaseForm, \.saltForm, \.route,
        ]
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func relativeText(_ minutes: Int) -> String {
        let delta = minutes - MedSlot.nowMinutes
        if delta < 60 {
            return String(localized: "in \(delta) min")
        }
        return String(localized: "in \(Int((Double(delta) / 60).rounded())) h")
    }
}

// MARK: - Row subviews

/// The checked/unchecked/skipped circle shared by slot rows and the collapsed
/// Supplements row.
private struct CheckCircle: View {
    let state: MyMedsCard.SlotState
    let due: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(state == .taken ? Color.green : Color.clear)
            Circle()
                .stroke(strokeColor, lineWidth: 2)
            switch state {
            case .taken:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            case .skipped:
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            case .pending:
                EmptyView()
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private var strokeColor: Color {
        switch state {
        case .taken: .green
        case .skipped: Color(.tertiarySystemFill)
        case .pending: due ? Theme.accent : Color(.tertiarySystemFill)
        }
    }
}

/// One checklist row — value inputs only, so it invalidates independently of
/// the card (CLAUDE.md decomposition rule: rows in a `ForEach` must not share
/// the parent's boundary).
private struct SlotRowView: View {
    let title: String
    let subtitle: String
    let timeText: String?
    let slotState: MyMedsCard.SlotState
    let due: Bool
    let indented: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    private var taken: Bool {
        slotState == .taken
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                CheckCircle(state: slotState, due: due)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(slotState == .skipped)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityStateValue)
            .accessibilityHint(slotState == .skipped ? Text("Skipped for today") : taken ? Text("Unlogs this dose") : Text("Logs this dose"))

            Button(action: onOpen) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(dismissed ? .regular : .medium))
                            .foregroundStyle(dismissed ? Theme.secondaryLabel : .primary)
                            .strikethrough(taken, color: Theme.secondaryLabel.opacity(0.5))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                    if slotState == .skipped {
                        Text("Skipped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if due, timeText != nil {
                        Text("due")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    if let timeText {
                        Text(timeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(due ? Theme.accent : Theme.secondaryLabel)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(title) details"))
            .accessibilityHint(Text("Opens this med"))
        }
        .padding(.vertical, 7)
        .padding(.leading, indented ? 22 : 0)
        .opacity(slotState == .skipped ? 0.6 : 1)
    }

    private var dismissed: Bool {
        taken || slotState == .skipped
    }

    private var accessibilityStateValue: Text {
        switch slotState {
        case .taken: Text("Taken")
        case .skipped: Text("Skipped")
        case .pending: Text("Not taken yet")
        }
    }
}
