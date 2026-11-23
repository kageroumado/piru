import SwiftData
import SwiftUI

/// The med's editable fields as they were when the editor opened, so Cancel
/// can put them back.
private struct MedEditSnapshot {
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
    let isAsNeeded: Bool
    let frequency: DoseFrequency
    let frequencyDays: [Int]
    let frequencyIntervalDays: Int
    let startDate: Date
    let maxPerDay: Int?
    let reminderTimesMinutes: [Int]
    let remind: Bool
    let askAgainOverrideMinutes: [Int]?
    let isQuiet: Bool
    let isBackgroundMed: Bool

    init(_ item: DailyDoseItem) {
        amount = item.amount
        unit = item.unit
        route = item.route
        isAsNeeded = item.isAsNeeded
        frequency = item.frequency
        frequencyDays = item.frequencyDays
        frequencyIntervalDays = item.frequencyIntervalDays
        startDate = item.startDate
        maxPerDay = item.maxPerDay
        reminderTimesMinutes = item.reminderTimesMinutes
        remind = item.remind
        askAgainOverrideMinutes = item.askAgainOverrideMinutes
        isQuiet = item.isQuiet
        isBackgroundMed = item.isBackgroundMed
    }

    func restore(to item: DailyDoseItem) {
        item.amount = amount
        item.unit = unit
        item.route = route
        item.isAsNeeded = isAsNeeded
        item.frequency = frequency
        item.frequencyDays = frequencyDays
        item.frequencyIntervalDays = frequencyIntervalDays
        item.startDate = startDate
        item.maxPerDay = maxPerDay
        item.reminderTimesMinutes = reminderTimesMinutes
        item.remind = remind
        item.askAgainOverrideMinutes = askAgainOverrideMinutes
        item.isQuiet = isQuiet
        item.isBackgroundMed = isBackgroundMed
    }
}

/// The per-med editor, pushed from the My Meds hub (`PushRoute.medDetail`).
/// Every row binds straight to the `@Model` — dose, schedule, times,
/// reminders, quiet tier — and the toolbar's ✕ puts back the values the
/// editor opened with, ✓ keeps them. The substance itself is fixed once
/// created (to change it, delete and re-add), so its identity — and the
/// "done today" join — never drifts out from under logged doses.
struct MedDetailView: View {
    @Bindable var item: DailyDoseItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigator) private var navigator
    @Query private var substanceColors: [SubstanceColor]

    @State private var showingDeleteConfirmation = false
    @State private var showingProductEditor = false
    @State private var snapshot: MedEditSnapshot?

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

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
            if let product = CustomSubstanceStore.shared.combination(named: item.substance) {
                MedProductDetailSection(item: item, product: product) {
                    showingProductEditor = true
                }
            } else {
                dosageSection
            }
            scheduleSection

            if !item.isAsNeeded {
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
                        let identityKey = item.identityKey, sortOrder = item.sortOrder
                        modelContext.delete(item)
                        close(identityKey: identityKey, sortOrder: sortOrder)
                    }
                } message: {
                    Text("Reminders and adherence tracking stop. Existing entries stay in your journal.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .sheet(isPresented: $showingProductEditor) {
            if let product = CustomSubstanceStore.shared.combination(named: item.substance) {
                MedProductEditSheet(product: product)
            }
        }
        .themedPage()
        // Titled as the editor it is: every row below writes straight to the
        // med, and a bare page read as a static summary to testers.
        .navigationTitle("Edit Med")
        .inlineNavigationTitle()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    snapshot?.restore(to: item)
                    close(identityKey: item.identityKey, sortOrder: item.sortOrder)
                } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    close(identityKey: item.identityKey, sortOrder: item.sortOrder)
                } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Save")
            }
        }
        .onAppear {
            if snapshot == nil { snapshot = MedEditSnapshot(item) }
        }
        .tabAccessoryClearance()
        // Every field edits the model directly; one resync on close reschedules
        // reminders from the saved state (times, cadence, quiet grouping).
        .onDisappear {
            DoseNotificationManager.syncMedReminders(in: modelContext)
        }
    }

    /// Leaves the editor: beside a list, `dismiss()` cannot reach the open
    /// record, so its route is taken out instead.
    private func close(identityKey: String, sortOrder: Int) {
        let removed = navigator.removeDeletedRecord {
            $0 == .medDetail(identityKey: identityKey, sortOrder: sortOrder)
        }
        if !removed { dismiss() }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: Spacing.xl) {
                Circle()
                    .fill(SubstancePalette.color(for: item.substance, colorMap: substanceColors.colorMap))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(item.productName ?? CustomSubstanceStore.shared.displayName(for: item.substance))
                    .cardTitle()
            }
        }
        .listRowBackground(CardBackground())
    }

    private var dosageSection: some View {
        Section {
            HStack {
                TextField("Amount", value: $item.amount, format: .number)
                    .accessibilityLabel(Text("Amount"))
                    .decimalKeyboard()
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
            Text("Checked off by an entry for the same substance and route.")
        }
        .listRowBackground(CardBackground())
    }

    private var scheduleSection: some View {
        Section {
            Picker("Repeats", selection: scheduleBinding) {
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
                        Text("No daily limit entered")
                    }
                }
            } else if item.frequency == .specificDays {
                WeekdayPicker(selection: weekdays)
            } else if item.frequency != .daily {
                if item.frequency == .everyNDays {
                    Stepper(value: $item.frequencyIntervalDays, in: DoseFrequency.intervalRange) {
                        Text("Every \(item.frequencyIntervalDays) days")
                    }
                }
                DatePicker("Starting from", selection: startDateBinding, displayedComponents: .date)
            }

            if !item.isAsNeeded {
                timeRows
            }
        } header: {
            Text("Schedule")
        } footer: {
            scheduleFooter
        }
        .listRowBackground(CardBackground())
    }

    /// One row per reminder time, then the button that adds one.
    @ViewBuilder
    private var timeRows: some View {
        ForEach(item.reminderTimesMinutes.indices, id: \.self) { index in
            let minutes = item.reminderTimesMinutes[index]
            DatePicker(
                selection: timeBinding(at: index),
                displayedComponents: .hourAndMinute,
            ) {
                Text(MedTimeGroup.group(forMinutes: minutes).label)
            }
            // Deletes the row's own time, never an offset: on Android the
            // swipe can report a delete twice, and a second offset into
            // the shortened list removes the next time or traps.
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    withAnimation(.snappy) { item.reminderTimesMinutes.removeAll { $0 == minutes } }
                }
            }
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
    }

    private var remindersSection: some View {
        Section {
            // Never `.disabled` on an empty time list: `remind` defaults on, so
            // a med with no set time would sit lit and ignore every tap.
            Toggle(isOn: remindBinding) {
                Label("Remind Me", systemImage: "bell")
            }

            if item.remind, !item.reminderTimesMinutes.isEmpty {
                Picker(selection: askAgainBinding) {
                    ForEach(AskAgainChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                } label: {
                    Label("Ask Again", systemImage: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Ask Again sends another reminder if a dose isn't logged. “Default” uses the intervals in Notification Settings.")
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
            Text("Grouped under Supplements, off the timeline graphs. Reminders are silent.")
        }
        .listRowBackground(CardBackground())
    }

    /// The model stores the days as an array; the picker edits them as a set.
    private var weekdays: Binding<Set<Int>> {
        Binding(
            get: { Set(item.frequencyDays) },
            set: { item.frequencyDays = Array($0) },
        )
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        if item.isAsNeeded {
            Text("Never marked missed. A daily limit feeds the cumulative dose warnings.")
        } else if item.frequency == .specificDays, item.frequencyDays.isEmpty {
            Text("Select at least one day.")
        } else if item.reminderTimesMinutes.isEmpty {
            Text("No set time. This med still counts toward adherence once per due day.")
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

    /// Reads on only when a reminder can actually fire (a set time exists).
    /// Turning it on for a med with no time adds the suggested first time,
    /// since a reminder needs a time to fire at.
    private var remindBinding: Binding<Bool> {
        Binding(
            get: { item.remind && !item.reminderTimesMinutes.isEmpty },
            set: { isOn in
                if isOn, item.reminderTimesMinutes.isEmpty {
                    withAnimation(.snappy) {
                        item.reminderTimesMinutes = [nextSuggestedTime(after: [])]
                    }
                }
                item.remind = isOn
            },
        )
    }

    private var askAgainBinding: Binding<AskAgainChoice> {
        Binding(
            get: { AskAgainChoice.from(item.askAgainOverrideMinutes) },
            set: { item.askAgainOverrideMinutes = $0.override },
        )
    }

    /// Stepper binding where 0 renders as "No daily limit entered" (`maxPerDay == nil`).
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
    /// dict hit, guarded to an exact canonical-name match (an alias match stays
    /// `nil`).
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
}
