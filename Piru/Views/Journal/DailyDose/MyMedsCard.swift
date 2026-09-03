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
    @State private var showInteractionSheet = false

    /// Today's slots, the adherence streak, and the interaction warnings a tap
    /// has to clear — see ``MyMedsModel``.
    @State private var model = MyMedsModel()

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
        // The slot derivation rebuilds the occurrence index and walks every
        // item, so derive it once per body pass and hand slices down.
        let slots = MyMedsModel.slots(items: items, occurrences: todayOccurrences)
        if !slots.isEmpty {
            // The Supplements fold only pays for itself with 2+ quiet slots — a
            // single quiet med renders as a plain row rather than a one-item group.
            let collapseQuiet = slots.count(where: \.item.isQuiet) >= 2
            let loudSlots = collapseQuiet ? slots.filter { !$0.item.isQuiet } : slots
            let quietSlots = collapseQuiet ? slots.filter(\.item.isQuiet) : []
            VStack(alignment: .leading, spacing: Spacing.lg) {
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
            .task { await model.refreshStreak(items: items, container: modelContext.container) }
            .task(id: DoseLogService.shared.revision) {
                info.refresh(items: items, in: modelContext)
            }
            .sheet(isPresented: $showInteractionSheet) {
                InteractionWarningSheet(
                    warnings: model.interactionWarnings,
                    onProceed: {
                        showInteractionSheet = false
                        log(slots: model.pendingSlots)
                    },
                    onCancel: {
                        showInteractionSheet = false
                        model.clearPending()
                    },
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func header(slots: [MedSlot]) -> some View {
        let due = slots.filter(\.isDueNow)
        return MyMedsHeader(
            takenCount: slots.count(where: \.taken),
            total: slots.count,
            completionText: completionText,
            dueCount: due.count,
            firstDueName: due.first.map { displayName(for: $0.item) },
            onTap: { navigator.push(.myMeds) },
        )
    }

    private var completionText: String {
        if let streak = model.streak, streak > 1 {
            String(localized: "That's everything today — \(streak) days and counting")
        } else {
            String(localized: "That's everything today")
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
        SupplementsRowView(
            takenCount: quietSlots.count(where: \.taken),
            total: quietSlots.count,
            expanded: $supplementsExpanded,
            onTakeAll: { attemptLog(slots: quietSlots.filter { !$0.taken }) },
        )
    }

    // MARK: Logging

    private func attemptLog(slots: [MedSlot]) {
        if model.mayLog(slots: slots, against: recentEntries) {
            log(slots: slots)
        } else {
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
        model.clearPending()
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

// MARK: - Header

/// The card's tappable header: the completion ring, the title, and the status
/// line under it. Value inputs only, so a row logging elsewhere in the card
/// doesn't re-evaluate the ring's animation state.
private struct MyMedsHeader: View {
    let takenCount: Int
    let total: Int
    let completionText: String
    let dueCount: Int
    let firstDueName: String?
    let onTap: () -> Void

    /// Every scheduled slot logged for today — drives the ring's completion
    /// state and the transient celebration line.
    private var isComplete: Bool {
        total > 0 && takenCount == total
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.lg) {
                progressRing
                VStack(alignment: .leading, spacing: 1) {
                    Text("My Meds")
                        .cardTitle()
                    // Status as a subtitle rather than a footer line — it
                    // swaps text (next dose → count left → "everything today")
                    // without ever changing the card's height, keeping the
                    // card visually light.
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
        .accessibilityValue("\(takenCount) of \(total) taken")
        .accessibilityHint("Opens your meds")
    }

    /// The always-present status line under "My Meds": the completion note
    /// while done, otherwise what is due right now, otherwise that nothing is.
    /// One line in every state, so the card height never moves. What comes
    /// *next* is the info line under the rows, so it is never said twice.
    @ViewBuilder
    private var statusSubtitle: some View {
        if isComplete {
            Text(completionText)
                .font(.caption)
                .foregroundStyle(Color.successText)
                .lineLimit(1)
        } else if dueCount == 1, let firstDueName {
            Text("\(firstDueName) is due")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        } else if dueCount > 1 {
            Text("\(dueCount) doses due")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        } else {
            Text("Nothing due right now")
                .captionSecondary()
                .lineLimit(1)
        }
    }

    private var progressRing: some View {
        let fraction = total == 0 ? 0 : CGFloat(takenCount) / CGFloat(total)
        return ZStack {
            Circle()
                .stroke(Color.platformTertiarySystemFill, lineWidth: 4)
            // The arc grows as doses land — `.snappy` keyed on the fraction so
            // logging (or unlogging) animates the fill rather than snapping.
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.successAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: fraction)
            // At completion the count gives way to a checkmark that bounces —
            // the small "done!" moment. Reverts to the count if a dose is
            // unlogged.
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.successText)
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
}

// MARK: - Row subviews

/// The collapsed "Supplements" group row: a fractional ring, the taken count,
/// a one-tap Take All, and the disclosure chevron.
private struct SupplementsRowView: View {
    let takenCount: Int
    let total: Int
    @Binding var expanded: Bool
    let onTakeAll: () -> Void

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.lg) {
                    circle
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Supplements")
                            .font(.subheadline.weight(.medium))
                        Text("\(takenCount) of \(total) taken")
                            .captionSecondary()
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supplements")
            .accessibilityValue("\(takenCount) of \(total) taken")
            .accessibilityHint(expanded ? Text("Collapses the list") : Text("Expands the list"))

            if takenCount < total {
                Button(action: onTakeAll) {
                    Text("Take All")
                        .capsuleChip(
                            text: Color.successText,
                            fill: Color.successAccent,
                            size: .hero,
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
    }

    private var circle: some View {
        ZStack {
            if takenCount == total {
                CheckCircle(state: .taken, due: false)
            } else {
                Circle()
                    .stroke(Color.platformTertiarySystemFill, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : CGFloat(takenCount) / CGFloat(total))
                    .stroke(Color.successAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
        .accessibilityHidden(true)
    }
}

/// The checked/unchecked/skipped circle shared by slot rows and the collapsed
/// Supplements row.
private struct CheckCircle: View {
    let state: MyMedsCard.SlotState
    let due: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(state == .taken ? Color.successAccent : Color.clear)
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
                    .foregroundStyle(Theme.secondaryLabel)
            case .pending:
                EmptyView()
            }
        }
        .frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
        .accessibilityHidden(true)
    }

    private var strokeColor: Color {
        switch state {
        case .taken: Color.successAccent
        case .skipped: Color.platformTertiarySystemFill
        case .pending: due ? Theme.accent : Color.platformTertiarySystemFill
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
        HStack(spacing: Spacing.lg) {
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
                HStack(spacing: Spacing.lg) {
                    Text(title)
                        .font(.subheadline.weight(dismissed ? .regular : .medium))
                        .foregroundStyle(dismissed ? Theme.secondaryLabel : .primary)
                        .strikethrough(taken, color: Theme.secondaryLabel.opacity(Theme.Opacity.dimmed))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if slotState == .skipped {
                        Text("Skipped")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    } else if due, timeText != nil {
                        Text("due")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, Spacing.xxs)
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
