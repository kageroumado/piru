import SwiftData
import SwiftUI

/// The schedule choice offered by the med form: a recurring cadence, or
/// as-needed (PRN) — which is a separate axis from `DoseFrequency` in the
/// model (`isAsNeeded`), folded into one picker here so the form stays one
/// decision.
private enum FormSchedule: Hashable {
    case frequency(DoseFrequency)
    case asNeeded
}

/// One reminder time on the med, carried with a stable identity. The times
/// list is edited by row (add, delete, drag) while a DatePicker in each row
/// reads its own value — an index-keyed `ForEach` crashes here, because a
/// delete shrinks the array before SwiftUI reconciles the children and a
/// stale index subscripts out of range. Identity keeps every row bound to
/// its own element, never to a position.
private struct MedReminderTime: Identifiable {
    let id = UUID()
    var minutes: Int
}

/// The form's edit draft — one `@Observable` model instead of a pile of
/// `@State` fields, so the form has a single source of mutable state and
/// each section invalidates from the draft it actually reads.
@Observable
@MainActor
private final class MedFormDraft {
    var substance = ""
    var amount: Double?
    var unit = "mg"
    var route: RouteOfAdministration = .oral

    // Schedule
    var schedule: FormSchedule = .frequency(.daily)
    var selectedWeekdays: Set<Int> = []
    var startDate: Date = .now
    var maxPerDay: Int?

    // Times & reminders
    var times: [MedReminderTime] = []
    var remind = true
    var nextDoseReminder = false

    // Quiet tier — `userTouchedQuiet` keeps the supplement smart-default from
    // overriding an explicit choice when the substance changes afterwards.
    var isQuiet = false
    var userTouchedQuiet = false

    var selectedSubstance: Substance?
    /// The brand the user picked ("Concerta"), kept so the med logs — and its
    /// "done today" check joins — as that form, not the canonical family.
    /// `nil` when they picked the canonical name. See ``QuickLogDose/identityKey``.
    var productName: String?
    var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases

    var isAsNeeded: Bool {
        schedule == .asNeeded
    }

    var frequency: DoseFrequency {
        if case let .frequency(freq) = schedule { freq } else { .daily }
    }
}

/// The 10-second add/edit form of the Meds redesign
/// (Specs/meds-reminders-redesign.md): what → how much → when → remind me.
/// Replaces `MedicationItemFormView` — no routine to pick, times live on the
/// med itself (Health-app-style rows), supplements default into the Quiet
/// tier, and "As needed" is a schedule choice rather than a separate concept.
struct MedFormView: View {
    @Environment(\.modelContext) private var modelContext
    /// Always presented as a *local* sheet (from the My Meds hub) — dismissal
    /// must be the environment dismiss, not navigator.dismiss(), which would
    /// pop the hosting navigator sheet out from under it.
    @Environment(\.dismiss) private var dismiss

    var item: DailyDoseItem?

    @State private var draft = MedFormDraft()

    @Query(sort: \DailyDoseItem.sortOrder) private var existingItems: [DailyDoseItem]
    @Query private var notificationPreferences: [NotificationPreferences]

    private var isEditing: Bool {
        item != nil
    }

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    private var currentUnits: [String] {
        if let sub = draft.selectedSubstance {
            let routeUnits = sub.routes.map(\.unit)
            let unique = Array(Set(routeUnits + defaultUnits))
            let defaultUnit = sub.unit(for: draft.route)
            return [defaultUnit] + unique.filter { $0 != defaultUnit }
        }
        return defaultUnits
    }

    private var askAgainCadence: [Int] {
        notificationPreferences.first?.askAgainDefaultMinutes ?? [10]
    }

    private static let weekdaySymbols: [(index: Int, short: String, full: String)] = {
        let cal = Calendar.current
        // 1=Sunday .. 7=Saturday
        return (1 ... 7).map { ($0, cal.shortWeekdaySymbols[$0 - 1], cal.weekdaySymbols[$0 - 1]) }
    }()

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    substanceSection
                    dosageSection
                    scheduleSection
                    if !draft.isAsNeeded {
                        timesSection
                    }
                    quietSection
                    nextDoseSection
                }
                .listRowBackground(CardBackground())
            }
            .themedPage()
            .navigationTitle(isEditing ? "Edit Med" : "Add a Med")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .buttonStyle(.glassProminent)
                        .disabled(draft.substance.isEmpty || draft.amount == nil
                            || (draft.frequency == .specificDays && draft.selectedWeekdays.isEmpty))
                        .accessibilityLabel("Save")
                }
            }
            .onAppear(perform: loadItem)
        }
    }

    // MARK: Sections

    private var substanceSection: some View {
        @Bindable var draft = draft
        return Section("Med") {
            SubstanceSearchField(text: $draft.substance) { selected, product in
                selectSubstance(selected, product: product)
            } onCustom: {
                useCustomSubstance()
            }
        }
    }

    private var dosageSection: some View {
        @Bindable var draft = draft
        return Section {
            HStack {
                TextField("Amount", value: $draft.amount, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $draft.unit) {
                    ForEach(currentUnits, id: \.self) { Text($0) }
                }
                .labelsHidden()
            }
            Picker("Route", selection: $draft.route) {
                ForEach(draft.availableRoutes) { r in
                    Text(r.localizedName).tag(r)
                }
            }
            .onChange(of: draft.route) {
                if let sub = draft.selectedSubstance {
                    draft.unit = sub.unit(for: draft.route)
                }
            }
        } header: {
            Text("Dosage")
        } footer: {
            Text("Checked off by a logged dose of the same substance and route.")
        }
    }

    private var scheduleSection: some View {
        @Bindable var draft = draft
        return Section {
            Picker("Schedule", selection: $draft.schedule) {
                ForEach(DoseFrequency.allCases) { freq in
                    Text(freq.displayName).tag(FormSchedule.frequency(freq))
                }
                Text("As needed").tag(FormSchedule.asNeeded)
            }

            if draft.isAsNeeded {
                Stepper(value: dailyLimit, in: 0 ... 12) {
                    if let limit = draft.maxPerDay {
                        Text("Up to \(limit)× daily")
                    } else {
                        Text("No daily limit")
                    }
                }
            }

            if draft.frequency == .specificDays, !draft.isAsNeeded {
                weekdayPicker
            }

            if draft.frequency != .daily, draft.frequency != .specificDays, !draft.isAsNeeded {
                DatePicker("Starting from", selection: $draft.startDate, displayedComponents: .date)
            }
        } header: {
            Text("Schedule")
        } footer: {
            scheduleFooter
        }
    }

    private var timesSection: some View {
        @Bindable var draft = draft
        return Section {
            ForEach($draft.times) { $time in
                VStack(alignment: .leading, spacing: 0) {
                    DatePicker(
                        selection: clockBinding(for: $time),
                        displayedComponents: .hourAndMinute,
                    ) {
                        Text(MedTimeGroup.group(forMinutes: time.minutes).label)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    // What that time actually does — onset, easing off, and (for
                    // the wake-promoting classes) how it sits against sleep.
                    // Silent when the med has no acute profile to state.
                    if let consequence {
                        MedTimeConsequenceLine(consequence: consequence, minutesOfDay: time.minutes)
                    }
                }
            }
            .onDelete { offsets in
                withAnimation(.snappy) { draft.times.remove(atOffsets: offsets) }
            }

            Button {
                withAnimation(.snappy) { draft.times.append(MedReminderTime(minutes: nextSuggestedTime())) }
            } label: {
                Label(draft.times.isEmpty ? "Add a Time" : "Add Another Time", systemImage: "plus.circle.fill")
            }

            if !draft.times.isEmpty {
                Toggle(isOn: $draft.remind) {
                    Label("Remind Me", systemImage: "bell")
                }
            }
        } header: {
            Text("Times")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if draft.times.isEmpty {
                    Text("No set time — this med still counts toward adherence once per due day.")
                } else if draft.remind {
                    Text("A reminder at each time. If you don't log it, Piru asks again \(askAgainListText) later — never a scold, just a nudge.")
                }
                if !draft.times.isEmpty, consequence != nil {
                    Text("Kick-in and wear-off come from this med's own duration data — the same model the timeline draws. An estimate.")
                }
            }
        }
    }

    /// The onset/wear-off/sleep readout for the picked med and route, resolved
    /// once for the whole section — every time row shares it, only the clock
    /// anchor differs. `nil` for a hand-typed substance or a chronic med with no
    /// acute profile, in which case the rows stay bare.
    private var consequence: MedTimeConsequence? {
        MedTimeConsequence.resolve(substance: draft.selectedSubstance, route: draft.route)
    }

    private var quietSection: some View {
        Section {
            Toggle(isOn: quietBinding) {
                Label("Quiet med", systemImage: "leaf")
            }
        } footer: {
            Text("Grouped under Supplements, off the timeline graphs. Reminders are silent.")
        }
    }

    private var nextDoseSection: some View {
        @Bindable var draft = draft
        return Section {
            Toggle("Next-dose window reminder", isOn: $draft.nextDoseReminder)
        } footer: {
            Text("Fires when the model's next dose window opens after a logged dose. Estimate only.")
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.sm) {
                ForEach(Self.weekdaySymbols, id: \.index) { day in
                    let isSelected = draft.selectedWeekdays.contains(day.index)
                    Button {
                        if isSelected {
                            draft.selectedWeekdays.remove(day.index)
                        } else {
                            draft.selectedWeekdays.insert(day.index)
                        }
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
        if draft.isAsNeeded {
            Text("Never marked missed. A daily limit feeds the cumulative dose warnings.")
        } else if draft.frequency == .specificDays, draft.selectedWeekdays.isEmpty {
            Text("Select at least one day.")
        }
    }

    // MARK: Bindings & helpers

    private var quietBinding: Binding<Bool> {
        Binding(
            get: { draft.isQuiet },
            set: { newValue in
                draft.isQuiet = newValue
                draft.userTouchedQuiet = true
            },
        )
    }

    /// Stepper binding where 0 renders as "No daily limit" (`maxPerDay == nil`).
    private var dailyLimit: Binding<Int> {
        Binding(
            get: { draft.maxPerDay ?? 0 },
            set: { draft.maxPerDay = $0 == 0 ? nil : $0 },
        )
    }

    private func clockBinding(for time: Binding<MedReminderTime>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = time.wrappedValue.minutes
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now,
                ) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                time.wrappedValue.minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            },
        )
    }

    /// The next time to append: 9:00 for the first, then 6 hours after the
    /// latest existing time (capped to late evening) — a sensible booster gap
    /// the user adjusts with one tap.
    private func nextSuggestedTime() -> Int {
        guard let latest = draft.times.map(\.minutes).max() else { return 9 * 60 }
        return min(latest + 6 * 60, 22 * 60)
    }

    private var askAgainListText: String {
        askAgainCadence.map { String(localized: "\($0) min") }.joined(separator: ", ")
    }

    private func selectSubstance(_ sub: Substance, product: String? = nil) {
        draft.selectedSubstance = sub
        let trimmed = product?.trimmingCharacters(in: .whitespaces)
        draft.productName = (trimmed?.isEmpty == false) ? trimmed : nil
        draft.route = sub.defaultRoute
        draft.unit = sub.unit(for: sub.defaultRoute)
        draft.availableRoutes = sub.orderedRoutes
        // Supplements default into the Quiet tier — a smart default only, so
        // it never overrides a choice the user already made.
        if !draft.userTouchedQuiet {
            draft.isQuiet = sub.category == .supplement
        }
    }

    private func useCustomSubstance() {
        draft.selectedSubstance = nil
        // A hand-typed custom substance names no catalog product.
        draft.productName = nil
        draft.availableRoutes = RouteOfAdministration.allCases
    }

    /// The identity to stamp on the saved item, derived from the picked product
    /// (or its canonical name): the PSID family plus the release/isomer the name
    /// resolves to, and the user's product word. Mirrors the quick-log capture, so
    /// a "Concerta" med joins the same identity a Concerta dose logs under.
    private func resolvedIdentity() -> (uid: String?, isomer: String?, release: String?, product: String?) {
        let product = (draft.productName?.isEmpty == false) ? draft.productName : nil
        let nameForFacets = product ?? draft.substance
        return (
            draft.selectedSubstance?.substanceUID,
            SubstanceLibrary.isomer(for: nameForFacets),
            SubstanceLibrary.releaseForm(for: nameForFacets),
            product,
        )
    }

    private func loadItem() {
        if let item {
            draft.substance = item.substance
            draft.amount = item.amount
            draft.unit = item.unit
            draft.route = item.route
            draft.schedule = item.isAsNeeded ? .asNeeded : .frequency(item.frequency)
            draft.selectedWeekdays = Set(item.frequencyDays)
            draft.startDate = item.startDate == .distantPast ? .now : item.startDate
            draft.maxPerDay = item.maxPerDay
            draft.times = item.reminderTimesMinutes.map { MedReminderTime(minutes: $0) }
            draft.remind = item.remind
            draft.nextDoseReminder = item.nextDoseReminder
            draft.isQuiet = item.isQuiet
            draft.userTouchedQuiet = true
            draft.productName = item.productName

            if let match = SubstanceLibrary.lookup(item.substance),
               match.name.lowercased() == item.substance.lowercased() {
                draft.selectedSubstance = match
                draft.availableRoutes = match.orderedRoutes
            }
        }
    }

    private func save() {
        guard let parsedAmount = draft.amount else { return }

        let sortedTimes = Array(Set(draft.times.map(\.minutes))).sorted()
        let identity = resolvedIdentity()
        let target: DailyDoseItem
        if let item {
            target = item
        } else {
            target = DailyDoseItem(substance: draft.substance, amount: parsedAmount, sortOrder: existingItems.count)
            modelContext.insert(target)
        }

        target.substance = draft.substance
        target.amount = parsedAmount
        target.unit = draft.unit
        target.route = draft.route
        target.frequency = draft.isAsNeeded ? .daily : draft.frequency
        target.frequencyDays = Array(draft.selectedWeekdays)
        target.startDate = draft.startDate
        target.reminderTimesMinutes = draft.isAsNeeded ? [] : sortedTimes
        target.remind = draft.remind
        target.isAsNeeded = draft.isAsNeeded
        target.maxPerDay = draft.isAsNeeded ? draft.maxPerDay : nil
        target.isQuiet = draft.isQuiet
        // Quiet meds are also background meds: they fold into an active
        // session rather than opening one (see SessionClustering).
        target.isBackgroundMed = draft.isQuiet
        target.nextDoseReminder = draft.nextDoseReminder
        target.substanceUID = identity.uid
        target.isomer = identity.isomer
        target.releaseForm = identity.release
        target.productName = identity.product

        // Reschedule from the saved state — times, remind, quiet grouping,
        // and Ask Again cadence all feed the pending-notification set.
        DoseNotificationManager.syncMedReminders(in: modelContext)
        dismiss()
    }
}
