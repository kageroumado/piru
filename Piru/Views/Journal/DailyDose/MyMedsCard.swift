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
    /// Yesterday's and today's occurrences — today's drive the slot states,
    /// yesterday's `missed` rows the missed-yesterday info line.
    @Query private var recentOccurrences: [RoutineOccurrence]

    @State private var supplementsExpanded = false
    @State private var streak: Int?
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var pendingSlots: [MedSlot] = []
    @State private var showInteractionSheet = false

    /// The info lines' fetched facts (supply projections) and the dismissed
    /// missed-day keys, refreshed off `body`.
    @State private var info = MyMedsInfoModel()

    init() {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let yesterdayStart = Self.yesterdayStart
        _todayEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= dayStart },
            sort: \DoseEntry.timestamp,
        )
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= cutoff },
            sort: \DoseEntry.timestamp,
        )
        _recentOccurrences = Query(
            filter: #Predicate<RoutineOccurrence> { $0.dueDay >= yesterdayStart },
        )
    }

    private static var yesterdayStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private var todayOccurrences: [RoutineOccurrence] {
        let today = Calendar.current.startOfDay(for: .now)
        return recentOccurrences.filter { $0.dueDay >= today }
    }

    /// Yesterday's slots that ended the day unlogged (`missed` is written by
    /// `RoutineOccurrenceService.reconcile`, never inferred here).
    private var yesterdayMissed: [RoutineOccurrence] {
        let today = Calendar.current.startOfDay(for: .now)
        return recentOccurrences.filter { $0.dueDay < today && $0.state == .missed }
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

    // MARK: Body

    /// Rows render only once the substance batch cache is warm: each row
    /// resolves its display name through `CustomSubstanceStore` → the batch
    /// index, and on the Journal's cold first frame that built the whole batch
    /// synchronously on the main actor (caught by the DEBUG tripwire in
    /// `SubstanceStore.all`). One empty frame in the warm case.
    @State private var warmed = false

    var body: some View {
        Group {
            if warmed {
                card
            } else {
                // A real (zero-height) view, not `EmptyView` — `.task` on a
                // view that never appears never fires, and the gate would
                // deadlock closed.
                Color.clear.frame(height: 0)
            }
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            warmed = true
        }
    }

    @ViewBuilder
    private var card: some View {
        // `allSlots` rebuilds the occurrence index and walks every item, so
        // derive it once per body pass and hand slices down.
        let slots = allSlots
        if !slots.isEmpty {
            // The Supplements fold only pays for itself with 2+ quiet slots — a
            // single quiet med renders as a plain row rather than a one-item group.
            let collapseQuiet = slots.count(where: \.item.isQuiet) >= 2
            let loudSlots = collapseQuiet ? slots.filter { !$0.item.isQuiet } : slots
            let quietSlots = collapseQuiet ? slots.filter(\.item.isQuiet) : []
            VStack(alignment: .leading, spacing: 10) {
                header(slots: slots)

                VStack(spacing: 0) {
                    ForEach(loudSlots) { slot in
                        slotRow(slot, indented: false)
                    }
                    if !quietSlots.isEmpty {
                        supplementsRow(quietSlots: quietSlots)
                        if supplementsExpanded {
                            ForEach(quietSlots) { slot in
                                slotRow(slot, indented: true)
                            }
                        }
                    }
                }

                let lines = infoLines(slots: slots)
                if !lines.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(lines, id: \.self) { line in
                            infoLine(line)
                        }
                    }
                }
            }
            .padding(14)
            .themeCard()
            .task { await refreshStreak() }
            .task(id: DoseLogService.shared.revision) {
                info.refresh(items: items, in: modelContext)
            }
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

    private func header(slots: [MedSlot]) -> some View {
        let takenCount = slots.count(where: \.taken)
        // Every scheduled slot logged for today — drives the ring's completion
        // state and the transient celebration line.
        let isComplete = !slots.isEmpty && takenCount == slots.count
        return Button {
            navigator.push(.myMeds)
        } label: {
            HStack(spacing: 10) {
                progressRing(takenCount: takenCount, total: slots.count, isComplete: isComplete)
                VStack(alignment: .leading, spacing: 1) {
                    Text("My Meds")
                        .font(.headline)
                    // Status as a subtitle rather than a footer line — it
                    // swaps text (next dose → count left → "everything today")
                    // without ever changing the card's height, keeping the
                    // card visually light.
                    statusSubtitle(slots: slots, takenCount: takenCount, isComplete: isComplete)
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
        .accessibilityValue("\(takenCount) of \(slots.count) taken")
        .accessibilityHint("Opens your meds")
    }

    /// The always-present status line under "My Meds": the completion note
    /// while done, otherwise what is due right now, otherwise that nothing is.
    /// One line in every state, so the card height never moves. What comes
    /// *next* is the info line under the rows, so it is never said twice.
    @ViewBuilder
    private func statusSubtitle(slots: [MedSlot], takenCount _: Int, isComplete: Bool) -> some View {
        let due = slots.filter(\.isDueNow)
        if isComplete {
            Text(completionText)
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if due.count == 1, let slot = due.first {
            Text("\(displayName(for: slot.item)) is due")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        } else if due.count > 1 {
            Text("\(due.count) doses due")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        } else {
            Text("Nothing due right now")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
    }

    private func progressRing(takenCount: Int, total: Int, isComplete: Bool) -> some View {
        let fraction = total == 0 ? 0 : CGFloat(takenCount) / CGFloat(total)
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
                Text("\(takenCount)/\(total)")
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

    private func supplementsRow(quietSlots: [MedSlot]) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { supplementsExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    supplementsCircle(quietSlots: quietSlots)
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

    private func supplementsCircle(quietSlots: [MedSlot]) -> some View {
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
        // See LogMedicationsView.attemptLog: only `.notable` and above may block.
        let warnings = InteractionChecker.checkBatch(names, against: active).admitted(.notable)

        if warnings.isEmpty {
            log(slots: slots)
        } else {
            pendingSlots = slots
            interactionWarnings = warnings
            showInteractionSheet = true
        }
    }

    /// Build the tapped slot(s)' entries and exact-name library matches; the
    /// shared batch pipeline owns the rest (sessions, colors, Live Activity,
    /// commit, deferred bookkeeping).
    private func log(slots: [MedSlot]) {
        guard !slots.isEmpty else { return }
        let now = Date.now
        var batch: [(entry: DoseEntry, substance: Substance?)] = []

        for slot in slots {
            let item = slot.item
            let entry = DoseEntry(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route,
                timestamp: now,
                isBackgroundMed: item.isBackgroundMed,
            )
            let matched = SubstanceLibrary.lookup(item.substance).flatMap {
                $0.name.lowercased() == item.substance.lowercased() ? $0 : nil
            }
            batch.append((entry, matched))
        }

        // Meds pass no deferredBookkeeping: routine medications skip the
        // ramp-down notifications on purpose.
        DoseLogService.shared.logBatch(batch, colors: Array(substanceColors), in: modelContext)
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
        let session = entry.session
        modelContext.delete(entry)
        session?.refreshDoseBounds()
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

    /// The past-year streak — fetch, snapshot, and calendar walk all on
    /// ``DatabaseActor``, so the main actor never materializes a year of rows.
    private func refreshStreak() async {
        guard !items.isEmpty else { return }
        streak = await AdherenceStreakFetcher.currentStreak(container: modelContext.container)
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Info lines

    /// The two-at-most facts under the rows, chosen by ``MyMedsInfo/select``.
    private func infoLines(slots: [MedSlot]) -> [MyMedsInfoLine] {
        let summaries = slots.map { slot in
            MyMedsInfo.SlotSummary(name: displayName(for: slot.item), minutes: slot.time, pending: slot.state == .pending)
        }
        let missed = yesterdayMissed.map { occurrence in
            let item = items.first { $0.substance.lowercased() == occurrence.substance.lowercased() }
            let name = item.map(displayName(for:)) ?? CustomSubstanceStore.shared.displayName(for: occurrence.substance)
            return (name: name, slotMinutes: occurrence.slotMinutes)
        }
        let missedLine = MyMedsInfo.missedYesterday(missed: missed, yesterday: Self.yesterdayStart)
        let missedDismissed: Bool = if case let .missedYesterday(notice)? = missedLine {
            info.isDismissed(notice.dayKey)
        } else {
            false
        }
        return MyMedsInfo.select(
            restock: info.restock,
            nextDue: MyMedsInfo.nextDue(slots: summaries, nowMinutes: MedSlot.nowMinutes),
            missed: missedLine,
            missedDismissed: missedDismissed,
        )
    }

    @ViewBuilder
    private func infoLine(_ line: MyMedsInfoLine) -> some View {
        switch line {
        case let .restock(name, daysLeft, itemID):
            RestockInfoLine(name: name, daysLeft: daysLeft) {
                navigator.present(.inventoryItemForm(id: itemID))
            }
        case let .nextDue(name, minutes):
            NextDueInfoLine(name: name, timeText: Self.timeText(minutes)) {
                navigator.push(.myMeds)
            }
        case let .missedYesterday(notice):
            MissedYesterdayInfoLine(
                notice: notice,
                onTap: { navigator.push(.myMeds) },
                onDismiss: { withAnimation(.snappy) { info.dismiss(notice.dayKey) } },
            )
        }
    }
}

/// The info lines' facts that need a store: each tracked med's supply
/// projection (a dose fetch per item, so refreshed on the dose-log revision
/// rather than per body pass) and the missed-notice dismissals.
@MainActor
@Observable
final class MyMedsInfoModel {
    private(set) var restock: MyMedsInfoLine?
    private var dismissedDayKeys: Set<String> = []

    private let defaults = UserDefaults(suiteName: "group.dev.yumeji.piru")

    func refresh(items: [DailyDoseItem], in context: ModelContext) {
        var projections: [MyMedsInfo.SupplyProjection] = []
        var seen = Set<UUID>()
        for item in items where !item.isAsNeeded {
            // A med scheduled without a salt still matches the salt-less
            // tracked supply; a salted schedule wants its own.
            guard let stock = InventoryService.find(substance: item.substance, saltForm: item.saltForm, in: context)
                ?? InventoryService.find(substance: item.substance, saltForm: nil, in: context),
                seen.insert(stock.id).inserted,
                let runOut = InventoryMath.runOut(for: stock, in: context)
            else { continue }
            let name = item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance)
            projections.append(MyMedsInfo.SupplyProjection(name: name, daysLeft: runOut.daysLeft, itemID: stock.id))
        }
        restock = MyMedsInfo.restock(from: projections)
        if let defaults {
            dismissedDayKeys = Set(defaults.stringArray(forKey: MissedNoticeDismissals.defaultsKey) ?? [])
        }
    }

    func isDismissed(_ dayKey: String) -> Bool {
        dismissedDayKeys.contains(dayKey)
    }

    func dismiss(_ dayKey: String) {
        dismissedDayKeys.insert(dayKey)
        if let defaults {
            MissedNoticeDismissals.dismiss(dayKey, in: defaults)
        }
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
                    Text(title)
                        .font(.subheadline.weight(dismissed ? .regular : .medium))
                        .foregroundStyle(dismissed ? Theme.secondaryLabel : .primary)
                        .strikethrough(taken, color: Theme.secondaryLabel.opacity(0.5))
                        .lineLimit(1)
                    Spacer(minLength: 4)
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
                    Text(subtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
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
        .padding(.leading, indented ? 28 : 6)
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
