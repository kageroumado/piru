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
    }

    // MARK: Slot derivation

    /// One checkable dose slot: a due med × one of its reminder times (or a
    /// single "anytime" slot). Earliest slots absorb today's matched doses
    /// first.
    struct MedSlot: Identifiable {
        let item: DailyDoseItem
        let time: Int?
        let index: Int
        let taken: Bool

        var id: String {
            item.substance + String(item.sortOrder) + "#" + String(index)
        }

        var isDueNow: Bool {
            guard !taken else { return false }
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
        for item in items where !item.isAsNeeded && AdherenceCalculator.isDue(item, on: .now) {
            let times = item.reminderTimesMinutes.sorted()
            let expected = max(1, times.count)
            let matched = todayEntries.count { AdherenceCalculator.entryMatches(entry: $0, item: item) }
            for index in 0 ..< expected {
                slots.append(MedSlot(
                    item: item,
                    time: times.indices.contains(index) ? times[index] : nil,
                    index: index,
                    taken: index < matched,
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

                footer
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
                Text("My Meds")
                    .font(.headline)
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

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 4)
            Circle()
                .trim(from: 0, to: allSlots.isEmpty ? 0 : CGFloat(takenCount) / CGFloat(allSlots.count))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(takenCount)/\(allSlots.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var footer: some View {
        if takenCount == allSlots.count {
            Text(completionText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
        } else if let next = nextUpcoming, let time = next.time {
            Text("Next: \(displayName(for: next.item)) at \(Self.timeText(time)) · \(Self.relativeText(time))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
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
            taken: slot.taken,
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
                CheckCircle(done: true, due: false)
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
        let warnings = InteractionChecker.checkBatch(names, against: active)

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

            let matched = SubstanceLibrary.search(item.substance).first {
                $0.name.lowercased() == item.substance.lowercased()
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
        let descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)],
        )
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

/// The checked/unchecked circle shared by slot rows and the collapsed
/// Supplements row.
private struct CheckCircle: View {
    let done: Bool
    let due: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(done ? Color.green : Color.clear)
            Circle()
                .stroke(done ? Color.green : (due ? Theme.accent : Color(.tertiarySystemFill)), lineWidth: 2)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// One checklist row — value inputs only, so it invalidates independently of
/// the card (CLAUDE.md decomposition rule: rows in a `ForEach` must not share
/// the parent's boundary).
private struct SlotRowView: View {
    let title: String
    let subtitle: String
    let timeText: String?
    let taken: Bool
    let due: Bool
    let indented: Bool
    /// Log (when untaken) or unlog (when taken) — driven by the check-circle.
    let onToggle: () -> Void
    /// Open the med's detail — driven by the rest of the row.
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // The check-circle is the ONLY logging control — tap to log, tap
            // again to unlog. Isolating it here is what stops a stray tap on
            // the row from silently writing (or being unable to reverse) a dose.
            Button(action: onToggle) {
                CheckCircle(done: taken, due: due)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(taken ? Text("Taken") : Text("Not taken yet"))
            .accessibilityHint(taken ? Text("Unlogs this dose") : Text("Logs this dose"))

            // The rest of the row opens the med — a safe, non-destructive tap
            // (matching the Reminders idiom: circle completes, text opens).
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(taken ? .regular : .medium))
                            .foregroundStyle(taken ? Theme.secondaryLabel : .primary)
                            .strikethrough(taken, color: Theme.secondaryLabel.opacity(0.5))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer()
                    if due, timeText != nil {
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
    }
}
