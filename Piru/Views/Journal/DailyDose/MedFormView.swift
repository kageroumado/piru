import SwiftData
import SwiftUI

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
    var schedule: MedScheduleChoice = .frequency(.daily)
    var selectedWeekdays: Set<Int> = []
    var intervalDays = DoseFrequency.defaultIntervalDays
    var startDate: Date = .now
    var maxPerDay: Int?

    // Times & reminders
    var times: [MedReminderTime] = []
    var remind = true

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

    // Product — a liquid, or a compound of several substances, is saved as a
    // combination product (``MedProductDraft``) that the med then names.

    /// Several substances in one product (co-codamol), rather than one.
    var isCompounded = false
    var product = MedProductDraft()
    /// Whether the user picked a schedule, so switching to a product keeps it
    /// rather than moving it to As needed on their behalf.
    var scheduleTouched = false

    /// Taken by volume, each component's amount per mL.
    var isLiquid: Bool {
        get { product.isLiquid }
        set { product.isLiquid = newValue }
    }

    /// The med is a product rather than a plain substance: a liquid, a
    /// compound, or a product already saved (one solid component included).
    var isProduct: Bool {
        isCompounded || isLiquid || product.existing != nil
    }

    var isAsNeeded: Bool {
        schedule == .asNeeded
    }

    var frequency: DoseFrequency {
        if case let .frequency(freq) = schedule { freq } else { .daily }
    }
}

/// The 10-second add/edit form of the Meds redesign:
/// what → how much → when → remind me.
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

    @State private var draft: MedFormDraft
    @State private var showsNameTaken = false
    @State private var showsComponentPicker = false

    /// `product` opens the form on a saved product no med names yet, so
    /// saving makes it one: an As needed med of one unit (or mL) by default.
    init(item: DailyDoseItem? = nil, product: CustomSubstanceEntry? = nil) {
        self.item = item
        let draft = MedFormDraft()
        if let product {
            draft.product = MedProductDraft(product: product)
            draft.isCompounded = (product.components?.count ?? 0) > 1
            draft.schedule = .asNeeded
            draft.amount = 1
        }
        _draft = State(initialValue: draft)
    }

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

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    // The kind is chosen once: a saved product keeps it, since
                    // a count of pills and a volume mean different doses.
                    if !isEditing, draft.product.existing == nil {
                        kindSection
                    }
                    if draft.isProduct {
                        MedProductNameSection(draft: draft.product)
                        MedProductUnitSection(draft: draft.product)
                        MedProductComponentsSection(draft: draft.product, allowsSeveral: draft.isCompounded) {
                            showsComponentPicker = true
                        }
                        MedProductDoseSection(amount: $draft.amount, unitWord: draft.product.unitWord, isLiquid: draft.isLiquid)
                    } else {
                        substanceSection
                        dosageSection
                    }
                    scheduleSection
                    if !draft.isAsNeeded {
                        timesSection
                    }
                    quietSection
                }
                .listRowBackground(CardBackground())
            }
            .productComponentPicker(
                isPresented: $showsComponentPicker,
                draft: draft.product,
                allowsSeveral: draft.isCompounded,
            )
            .themedPage()
            .navigationTitle(isEditing ? "Edit Med" : "Add a Med")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .skinButtonStyle(.prominent)
                        .disabled(!canSave)
                        .accessibilityLabel("Save")
                }
            }
            .alert("Name Taken", isPresented: $showsNameTaken) {
                Button("OK") {}
            } message: {
                Text("\"\(draft.product.trimmedName)\" already names a substance. Choose another name for this product.")
            }
            .onChange(of: draft.isProduct) {
                // A product is most often taken as needed (a syrup, a
                // co-codamol), so it starts there until the user picks.
                if !draft.scheduleTouched {
                    draft.schedule = draft.isProduct ? .asNeeded : .frequency(.daily)
                }
                if draft.isProduct, draft.amount == nil {
                    draft.amount = 1
                }
            }
            .onAppear(perform: loadItem)
        }
    }

    /// A schedule that makes sense, a substance (or a complete product), and an amount.
    private var canSave: Bool {
        guard !(draft.frequency == .specificDays && draft.selectedWeekdays.isEmpty) else { return false }
        if draft.isProduct {
            return draft.product.canSave && (draft.amount ?? 0) > 0
        }
        return !draft.substance.isEmpty && draft.amount != nil
    }

    // MARK: Sections

    /// One substance or a compound of several, and solid or liquid. Anything
    /// but a single solid substance is saved as a product.
    private var kindSection: some View {
        @Bindable var draft = draft
        return Section {
            Picker("Kind", selection: $draft.isCompounded.animation()) {
                Text("Single compound").tag(false)
                Text("Compounded").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker("Form", selection: $draft.isLiquid.animation()) {
                Text("Solid").tag(false)
                Text("Liquid").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            if draft.isProduct {
                Text("Logged as a whole: one pick records each component.")
            }
        }
    }

    private var substanceSection: some View {
        @Bindable var draft = draft
        return Section("Med") {
            SubstanceSearchField(text: $draft.substance, keepsMatchedName: true) { selected, product in
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
                    .accessibilityLabel(Text("Amount"))
                    .decimalKeyboard()
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
            Text("Checked off by an entry for the same substance and route.")
        }
    }

    private var scheduleSection: some View {
        @Bindable var draft = draft
        return Section {
            Picker("Schedule", selection: scheduleBinding) {
                ForEach(DoseFrequency.allCases) { freq in
                    Text(freq.displayName).tag(MedScheduleChoice.frequency(freq))
                }
                Text("As needed").tag(MedScheduleChoice.asNeeded)
            }

            if draft.isAsNeeded {
                Stepper(value: dailyLimit, in: 0 ... 12) {
                    if let limit = draft.maxPerDay {
                        Text("Up to \(limit)× daily")
                    } else {
                        Text("No daily limit entered")
                    }
                }
            }

            if draft.frequency == .specificDays, !draft.isAsNeeded {
                WeekdayPicker(selection: $draft.selectedWeekdays)
            }

            if draft.frequency == .everyNDays, !draft.isAsNeeded {
                Stepper(value: $draft.intervalDays, in: DoseFrequency.intervalRange) {
                    Text("Every \(draft.intervalDays) days")
                }
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
                // Deletes by identity, never an offset; see MedDetailView's times.
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        let id = time.id
                        withAnimation(.snappy) { draft.times.removeAll { $0.id == id } }
                    }
                }
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
                    Text("No set time. This med still counts toward adherence once per due day.")
                } else if draft.remind {
                    Text("A reminder at each time. If you don't log it, Piru asks again \(askAgainListText) later.")
                }
                if !draft.times.isEmpty, consequence != nil {
                    Text("Kick-in and wear-off come from this med's own duration data, the same model the timeline draws. An estimate.")
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

    @ViewBuilder
    private var scheduleFooter: some View {
        if draft.isAsNeeded {
            Text("Never marked missed. A daily limit feeds the cumulative dose warnings.")
        } else if draft.frequency == .specificDays, draft.selectedWeekdays.isEmpty {
            Text("Select at least one day.")
        }
    }

    // MARK: Bindings & helpers

    /// The schedule picker, recording that the user chose one.
    private var scheduleBinding: Binding<MedScheduleChoice> {
        Binding(
            get: { draft.schedule },
            set: { newValue in
                draft.schedule = newValue
                draft.scheduleTouched = true
            },
        )
    }

    private var quietBinding: Binding<Bool> {
        Binding(
            get: { draft.isQuiet },
            set: { newValue in
                draft.isQuiet = newValue
                draft.userTouchedQuiet = true
            },
        )
    }

    /// Stepper binding where 0 renders as "No daily limit entered" (`maxPerDay == nil`).
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
            // Show the brand the med was saved under ("Medikinet") in the field,
            // while identity resolution below still keys off the canonical name.
            draft.substance = item.productName ?? item.substance
            draft.amount = item.amount
            draft.unit = item.unit
            draft.route = item.route
            draft.schedule = item.isAsNeeded ? .asNeeded : .frequency(item.frequency)
            draft.selectedWeekdays = Set(item.frequencyDays)
            draft.intervalDays = item.frequencyIntervalDays
            draft.startDate = item.startDate == .distantPast ? .now : item.startDate
            draft.maxPerDay = item.maxPerDay
            draft.times = item.reminderTimesMinutes.map { MedReminderTime(minutes: $0) }
            draft.remind = item.remind
            draft.isQuiet = item.isQuiet
            draft.userTouchedQuiet = true
            draft.scheduleTouched = true
            draft.productName = item.productName

            if let product = CustomSubstanceStore.shared.combination(named: item.substance) {
                draft.product = MedProductDraft(product: product)
                draft.isCompounded = (product.components?.count ?? 0) > 1
            } else if let match = SubstanceLibrary.lookup(item.substance),
                      match.name.lowercased() == item.substance.lowercased() {
                draft.selectedSubstance = match
                draft.availableRoutes = match.orderedRoutes
            }
        }
    }

    /// What the med names: a saved product (written to the custom store
    /// here), or a substance. `nil` when the product's name is taken.
    private func savedSubstance() -> (
        substance: String, unit: String, route: RouteOfAdministration,
        identity: (uid: String?, isomer: String?, release: String?, product: String?),
    )? {
        if draft.isProduct {
            let store = CustomSubstanceStore.shared
            guard !draft.product.nameIsTaken(in: store) else { return nil }
            let entry = draft.product.makeEntry()
            if let existing = draft.product.existing {
                store.update(entry)
                if existing.name != entry.name {
                    MedProductStore.rename(existing.name, to: entry.name, in: modelContext)
                }
            } else {
                store.add(entry)
            }
            // A product carries no catalog identity of its own: its components do.
            return (entry.name, entry.unit, entry.defaultRoute, (nil, nil, nil, nil))
        }
        // The field text may read as the brand the user picked ("Medikinet"); the
        // stored substance is always the canonical family (Methylphenidate), with
        // the brand kept separately in `productName`. A hand-typed custom substance
        // has no `selectedSubstance`, so its typed name is the substance.
        return (draft.selectedSubstance?.name ?? draft.substance, draft.unit, draft.route, resolvedIdentity())
    }

    private func save() {
        guard canSave, let parsedAmount = draft.amount else { return }
        guard let saved = savedSubstance() else {
            showsNameTaken = true
            return
        }

        let sortedTimes = Array(Set(draft.times.map(\.minutes))).sorted()
        let identity = saved.identity
        let target: DailyDoseItem
        if let item {
            target = item
        } else {
            target = DailyDoseItem(substance: saved.substance, amount: parsedAmount, sortOrder: existingItems.count)
            modelContext.insert(target)
        }

        target.substance = saved.substance
        target.amount = parsedAmount
        target.unit = saved.unit
        target.route = saved.route
        target.frequency = draft.isAsNeeded ? .daily : draft.frequency
        target.frequencyDays = Array(draft.selectedWeekdays)
        target.frequencyIntervalDays = draft.intervalDays
        target.startDate = draft.startDate
        target.reminderTimesMinutes = draft.isAsNeeded ? [] : sortedTimes
        target.remind = draft.remind
        target.isAsNeeded = draft.isAsNeeded
        target.maxPerDay = draft.isAsNeeded ? draft.maxPerDay : nil
        target.isQuiet = draft.isQuiet
        // Quiet meds are also background meds: they fold into an active
        // session rather than opening one (see SessionClustering).
        target.isBackgroundMed = draft.isQuiet
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
