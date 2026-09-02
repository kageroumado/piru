import SwiftData
import SwiftUI

/// The schedule choice, folding `DoseFrequency` and the separate `isAsNeeded`
/// axis into one picker value (mirrors the add form).
private enum MedScheduleChoice: Hashable {
    case frequency(DoseFrequency)
    case asNeeded
}

/// The per-med detail screen, pushed from the My Meds hub
/// (`PushRoute.medDetail`). Everything is editable in place — dose, schedule,
/// times, reminders, quiet tier — binding straight to the `@Model`, so there
/// is no separate Edit modal. The substance itself is fixed once created (to
/// change it, delete and re-add), so its identity — and the "done today" join
/// — never drifts out from under logged doses.
struct MedDetailView: View {
    @Bindable var item: DailyDoseItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    private static let weekdaySymbols: [(index: Int, short: String, full: String)] = {
        let cal = Calendar.current
        return (1 ... 7).map { ($0, cal.shortWeekdaySymbols[$0 - 1], cal.weekdaySymbols[$0 - 1]) }
    }()

    /// The Ask Again override choices. `nil` = follow the global default;
    /// `[]` = opted out.
    private enum AskAgainChoice: String, CaseIterable, Identifiable {
        case globalDefault
        case off
        case ten
        case tenThirty

        var id: String {
            rawValue
        }

        var override: [Int]? {
            switch self {
            case .globalDefault: nil
            case .off: []
            case .ten: [10]
            case .tenThirty: [10, 30]
            }
        }

        var label: LocalizedStringResource {
            switch self {
            case .globalDefault: "Default"
            case .off: "Off"
            case .ten: "10 min later"
            case .tenThirty: "10 and 30 min later"
            }
        }

        static func from(_ override: [Int]?) -> AskAgainChoice {
            switch override {
            case nil: .globalDefault
            case []: .off
            case [10]: .ten
            case [10, 30]: .tenThirty
            default: .globalDefault
            }
        }
    }

    var body: some View {
        List {
            headerSection
            dosageSection
            scheduleSection

            if !item.isAsNeeded {
                timesSection
                remindersSection
            }

            quietSection

            Section {
                Button("Delete Med", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity)
                // Attached to the button, not the List — the dialog adapts to a
                // popover on this screen, and a List-attached popover anchors to
                // some mid-list row instead of the control that summoned it.
                .confirmationDialog(
                    "Delete this med?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible,
                ) {
                    Button("Delete Med", role: .destructive) {
                        modelContext.delete(item)
                        dismiss()
                    }
                } message: {
                    Text("Reminders and adherence tracking stop. Doses you already logged stay in your journal.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationBarTitleDisplayMode(.inline)
        // Every field edits the model directly; one resync on close reschedules
        // reminders from the saved state (times, cadence, quiet grouping).
        .onDisappear {
            DoseNotificationManager.syncMedReminders(in: modelContext)
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: Spacing.xl) {
                Image(systemName: "pill")
                    .screenTitle()
                    .foregroundStyle(.white)
                    .frame(width: IconSize.touchTarget, height: IconSize.touchTarget)
                    .background(Theme.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                        .cardTitle()
                    Text(scheduleSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .listRowBackground(CardBackground())
    }

    private var dosageSection: some View {
        Section {
            HStack {
                TextField("Amount", value: $item.amount, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $item.unit) {
                    ForEach(unitOptions, id: \.self) { Text($0) }
                }
                .labelsHidden()
            }
            Picker("Route", selection: $item.route) {
                ForEach(availableRoutes) { route in
                    Text(route.localizedName).tag(route)
                }
            }
        } header: {
            Text("Dosage")
        } footer: {
            Text("A logged dose checks this med off when the substance and route match — the same substance by another route stays a regular journal entry.")
        }
        .listRowBackground(CardBackground())
    }

    private var scheduleSection: some View {
        Section {
            Picker("Schedule", selection: scheduleBinding) {
                ForEach(DoseFrequency.allCases) { freq in
                    Text(freq.displayName).tag(MedScheduleChoice.frequency(freq))
                }
                Text("As needed").tag(MedScheduleChoice.asNeeded)
            }

            if item.isAsNeeded {
                Stepper(value: dailyLimit, in: 0 ... 12) {
                    if let limit = item.maxPerDay {
                        Text("Up to \(limit)× daily")
                    } else {
                        Text("No daily limit")
                    }
                }
            } else if item.frequency == .specificDays {
                weekdayPicker
            } else if item.frequency != .daily {
                DatePicker("Starting from", selection: startDateBinding, displayedComponents: .date)
            }
        } header: {
            Text("Schedule")
        } footer: {
            scheduleFooter
        }
        .listRowBackground(CardBackground())
    }

    private var timesSection: some View {
        Section {
            ForEach(item.reminderTimesMinutes.indices, id: \.self) { index in
                DatePicker(
                    selection: timeBinding(at: index),
                    displayedComponents: .hourAndMinute,
                ) {
                    Text(MedTimeGroup.group(forMinutes: item.reminderTimesMinutes[index]).label)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .onDelete { offsets in
                var times = item.reminderTimesMinutes
                times.remove(atOffsets: offsets)
                withAnimation(.snappy) { item.reminderTimesMinutes = times }
            }

            Button {
                var times = item.reminderTimesMinutes
                times.append(nextSuggestedTime(after: times))
                withAnimation(.snappy) { item.reminderTimesMinutes = times.sorted() }
            } label: {
                Label(
                    item.reminderTimesMinutes.isEmpty ? "Add a Time" : "Add Another Time",
                    systemImage: "plus.circle.fill",
                )
            }
        } header: {
            Text("Times")
        } footer: {
            if item.reminderTimesMinutes.isEmpty {
                Text("No set time — this med still counts toward adherence once per due day.")
            }
        }
        .listRowBackground(CardBackground())
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $item.remind) {
                Label("Remind Me", systemImage: "bell")
            }
            .disabled(item.reminderTimesMinutes.isEmpty)

            if item.remind, !item.reminderTimesMinutes.isEmpty {
                Picker(selection: askAgainBinding) {
                    ForEach(AskAgainChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                } label: {
                    Label("Ask Again", systemImage: "clock.arrow.circlepath")
                }
            }

            Toggle(isOn: $item.nextDoseReminder) {
                Label("Next-Dose Window", systemImage: "timer")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Ask Again re-asks if a dose isn't logged — \u{201C}Default\u{201D} follows the cadence in Notification Settings. Never a scold, just a nudge.")
        }
        .listRowBackground(CardBackground())
    }

    private var quietSection: some View {
        Section {
            Toggle(isOn: $item.isQuiet) {
                Label("Quiet med", systemImage: "leaf")
            }
            .onChange(of: item.isQuiet) {
                // Quiet meds are also background meds (session folding).
                item.isBackgroundMed = item.isQuiet
            }
        } footer: {
            Text("Folds into the \u{201C}Supplements\u{201D} row and stays off the timeline graphs. Its reminders are silent — they wait in Notification Center instead of buzzing, and batch into iOS Scheduled Summary if you use it.")
        }
        .listRowBackground(CardBackground())
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.sm) {
                ForEach(Self.weekdaySymbols, id: \.index) { day in
                    let isSelected = item.frequencyDays.contains(day.index)
                    Button {
                        var days = Set(item.frequencyDays)
                        if isSelected { days.remove(day.index) } else { days.insert(day.index) }
                        item.frequencyDays = Array(days)
                    } label: {
                        Text(String(day.short.prefix(2)))
                            .font(.caption.weight(.semibold))
                            .selectableChip(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    // Cancels the chip's hit-target frame back to the visible
                    // circle so the row's layout is unchanged.
                    .padding(-5)
                    .accessibilityLabel(day.full)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        if item.isAsNeeded {
            Text("No schedule and never marked missed — adherence doesn't count as-needed meds. A daily limit feeds the cumulative dose warnings.")
        } else {
            switch item.frequency {
            case .daily:
                Text("Checked every day.")
            case .everyOtherDay:
                Text("Checked every 2 days starting from the start date.")
            case .weekly:
                Text("Checked once per week on the same day as the start date.")
            case .biweekly:
                Text("Checked every 2 weeks on the same day as the start date.")
            case .monthly:
                Text("Checked once per month on the same day-of-month as the start date.")
            case .specificDays:
                if item.frequencyDays.isEmpty {
                    Text("Select at least one day.")
                } else {
                    let names = item.frequencyDays.sorted().compactMap { idx in
                        Self.weekdaySymbols.first { $0.index == idx }?.short
                    }
                    Text("Checked every \(names.joined(separator: ", ")).")
                }
            }
        }
    }

    // MARK: Bindings & helpers

    private var scheduleBinding: Binding<MedScheduleChoice> {
        Binding(
            get: { item.isAsNeeded ? .asNeeded : .frequency(item.frequency) },
            set: { choice in
                switch choice {
                case .asNeeded:
                    item.isAsNeeded = true
                case let .frequency(freq):
                    item.isAsNeeded = false
                    item.frequency = freq
                    // A concrete start date only matters for the offset
                    // cadences; default it forward the first time one is picked.
                    if freq != .daily, freq != .specificDays, item.startDate == .distantPast {
                        item.startDate = .now
                    }
                }
            },
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { item.startDate == .distantPast ? .now : item.startDate },
            set: { item.startDate = $0 },
        )
    }

    private var askAgainBinding: Binding<AskAgainChoice> {
        Binding(
            get: { AskAgainChoice.from(item.askAgainOverrideMinutes) },
            set: { item.askAgainOverrideMinutes = $0.override },
        )
    }

    /// Stepper binding where 0 renders as "No daily limit" (`maxPerDay == nil`).
    private var dailyLimit: Binding<Int> {
        Binding(
            get: { item.maxPerDay ?? 0 },
            set: { item.maxPerDay = $0 == 0 ? nil : $0 },
        )
    }

    private func timeBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                let times = item.reminderTimesMinutes
                guard times.indices.contains(index) else { return .now }
                let minutes = times[index]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
                ) ?? .now
            },
            set: { newValue in
                var times = item.reminderTimesMinutes
                guard times.indices.contains(index) else { return }
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                times[index] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                item.reminderTimesMinutes = times
            },
        )
    }

    /// The substance's catalog entry, when its name resolves — supplies the
    /// route + unit options. `nil` for a hand-typed custom med. Batch-projection
    /// dict hit, guarded to the same canonical-exact-name semantics the old
    /// ranked-search-then-filter form had (an alias match stays `nil`).
    private var resolvedSubstance: Substance? {
        guard let substance = SubstanceLibrary.lookup(item.substance),
              substance.name.lowercased() == item.substance.lowercased() else { return nil }
        return substance
    }

    private var availableRoutes: [RouteOfAdministration] {
        resolvedSubstance?.orderedRoutes ?? RouteOfAdministration.allCases
    }

    private var unitOptions: [String] {
        guard let sub = resolvedSubstance else { return defaultUnits }
        let routeUnits = sub.routes.map(\.unit)
        let unique = Array(Set(routeUnits + defaultUnits))
        let preferred = sub.unit(for: item.route)
        return [preferred] + unique.filter { $0 != preferred }
    }

    /// The next time to append: 9:00 for the first, then 6 hours after the
    /// latest (capped to late evening).
    private func nextSuggestedTime(after times: [Int]) -> Int {
        guard let latest = times.max() else { return 9 * 60 }
        return min(latest + 6 * 60, 22 * 60)
    }

    private var scheduleSummary: String {
        let dose = "\(item.amount.doseFormatted) \(item.unit) · \(String(localized: item.route.localizedName))"
        if item.isAsNeeded {
            if let limit = item.maxPerDay {
                return "\(dose) · \(String(localized: "up to \(limit)× daily"))"
            }
            return "\(dose) · \(String(localized: "as needed"))"
        }
        let count = item.reminderTimesMinutes.count
        if count > 1 {
            return "\(dose) · \(String(localized: "\(count)× daily"))"
        }
        return "\(dose) · \(String(localized: item.frequency.shortLabel))"
    }
}
