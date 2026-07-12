import SwiftData
import SwiftUI

struct MedicationItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    /// Always presented as a *local* sheet (from the Routines screens) —
    /// dismissal must be the environment dismiss, not navigator.dismiss(),
    /// which would pop the hosting navigator sheet out from under it.
    @Environment(\.dismiss) private var dismiss

    var item: DailyDoseItem?
    var initialCategory: String = ""

    @State private var substance = ""
    @State private var amount: Double?
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral
    @State private var category = ""

    // Schedule
    @State private var frequency: DoseFrequency = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var startDate: Date = .now
    @State private var isBackgroundMed = false

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases

    @Query(sort: \DailyDoseItem.sortOrder) private var existingItems: [DailyDoseItem]
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]

    private var isEditing: Bool {
        item != nil
    }

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    private var currentUnits: [String] {
        if let sub = selectedSubstance {
            let routeUnits = sub.routes.map(\.unit)
            let unique = Array(Set(routeUnits + defaultUnits))
            let defaultUnit = sub.unit(for: route)
            return [defaultUnit] + unique.filter { $0 != defaultUnit }
        }
        return defaultUnits
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
                    Section("Substance") {
                        SubstanceSearchField(text: $substance) { selected in
                            selectSubstance(selected)
                        } onCustom: {
                            useCustomSubstance()
                        }
                    }

                    Section("Dosage") {
                        HStack {
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $unit) {
                                ForEach(currentUnits, id: \.self) { Text($0) }
                            }
                            .labelsHidden()
                        }
                        Picker("Route", selection: $route) {
                            ForEach(availableRoutes) { r in
                                Text(r.localizedName).tag(r)
                            }
                        }
                        .onChange(of: route) {
                            if let sub = selectedSubstance {
                                unit = sub.unit(for: route)
                            }
                        }
                    }

                    Section {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(DoseFrequency.allCases) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }

                        if frequency == .specificDays {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Days")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .accessibilityAddTraits(.isHeader)
                                HStack(spacing: 6) {
                                    ForEach(Self.weekdaySymbols, id: \.index) { day in
                                        let isSelected = selectedWeekdays.contains(day.index)
                                        Button {
                                            if isSelected {
                                                selectedWeekdays.remove(day.index)
                                            } else {
                                                selectedWeekdays.insert(day.index)
                                            }
                                        } label: {
                                            // 44pt hit target around the 34pt
                                            // circle; the negative padding keeps
                                            // the row's layout identical.
                                            Text(String(day.short.prefix(2)))
                                                .font(.caption.weight(.semibold))
                                                .frame(width: 34, height: 34)
                                                .background(isSelected ? Theme.accent : Color(.tertiarySystemFill))
                                                .foregroundStyle(isSelected ? .white : .primary)
                                                .clipShape(Circle())
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .padding(-5)
                                        .accessibilityLabel(day.full)
                                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if frequency != .daily, frequency != .specificDays {
                            DatePicker("Starting from", selection: $startDate, displayedComponents: .date)
                        }
                    } header: {
                        Text("Schedule")
                    } footer: {
                        scheduleFooter
                    }

                    Section {
                        Toggle("Background medication", isOn: $isBackgroundMed)
                    } footer: {
                        Text("Keeps this medication out of your sessions — it joins an active session if one is running, but on its own never starts a new session. Maintenance meds show as a compact \u{201C}Medications\u{201D} row in the Journal.")
                    }

                    if !categories.isEmpty {
                        Section("Routine") {
                            Picker("Routine", selection: $category) {
                                Text("None").tag("")
                                ForEach(categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(CardBackground())
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .disabled(substance.isEmpty || amount == nil || (frequency == .specificDays && selectedWeekdays.isEmpty))
                        .accessibilityLabel("Save")
                }
            }
            .onAppear(perform: loadItem)
        }
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        switch frequency {
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
            if selectedWeekdays.isEmpty {
                Text("Select at least one day.")
            } else {
                let names = selectedWeekdays.sorted().compactMap { idx in
                    Self.weekdaySymbols.first { $0.index == idx }?.short
                }
                Text("Checked every \(names.joined(separator: ", ")).")
            }
        }
    }

    private func selectSubstance(_ sub: Substance) {
        selectedSubstance = sub
        route = sub.defaultRoute
        unit = sub.unit(for: sub.defaultRoute)
        availableRoutes = sub.orderedRoutes
    }

    private func useCustomSubstance() {
        selectedSubstance = nil
        availableRoutes = RouteOfAdministration.allCases
    }

    private var categories: [String] {
        // An item edited out of a deleted routine can still carry its old
        // name — keep it pickable so the selection isn't silently lost.
        var names = routines.map(\.name)
        if !category.isEmpty, !names.contains(category) {
            names.append(category)
        }
        return names
    }

    private func loadItem() {
        if let item {
            substance = item.substance
            amount = item.amount
            unit = item.unit
            route = item.route
            category = item.category
            frequency = item.frequency
            selectedWeekdays = Set(item.frequencyDays)
            startDate = item.startDate
            isBackgroundMed = item.isBackgroundMed

            if let match = SubstanceLibrary.search(item.substance).first,
               match.name.lowercased() == item.substance.lowercased() {
                selectedSubstance = match
                availableRoutes = match.orderedRoutes
            }
        } else {
            category = initialCategory
        }
    }

    private func save() {
        guard let parsedAmount = amount else { return }

        if let item {
            item.substance = substance
            item.amount = parsedAmount
            item.unit = unit
            item.route = route
            item.category = category
            item.frequency = frequency
            item.frequencyDays = Array(selectedWeekdays)
            item.startDate = startDate
            item.isBackgroundMed = isBackgroundMed
        } else {
            let newItem = DailyDoseItem(
                substance: substance,
                amount: parsedAmount,
                unit: unit,
                route: route,
                sortOrder: existingItems.count,
                category: category,
                frequency: frequency,
                frequencyDays: Array(selectedWeekdays),
                startDate: startDate,
                isBackgroundMed: isBackgroundMed,
            )
            modelContext.insert(newItem)
        }

        dismiss()
    }
}
