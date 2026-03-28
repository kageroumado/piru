import SwiftUI
import SwiftData

struct MedicationItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var item: DailyDoseItem?
    var initialCategory: String = ""

    @State private var substance = ""
    @State private var amount = ""
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral
    @State private var category = ""

    // Schedule
    @State private var frequency: DoseFrequency = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var startDate: Date = .now

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases

    @AppStorage("dailyDoseCategories") private var categoriesData = Data()

    @Query(sort: \DailyDoseItem.sortOrder) private var existingItems: [DailyDoseItem]

    private var isEditing: Bool { item != nil }

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

    private static let weekdaySymbols: [(index: Int, short: String)] = {
        let cal = Calendar.current
        // 1=Sunday .. 7=Saturday
        return (1...7).map { ($0, cal.shortWeekdaySymbols[$0 - 1]) }
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
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(currentUnits, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                    }
                    Picker("Route", selection: $route) {
                        ForEach(availableRoutes) { r in
                            Text(r.displayName).tag(r)
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
                                        Text(String(day.short.prefix(2)))
                                            .font(.caption.weight(.semibold))
                                            .frame(width: 34, height: 34)
                                            .background(isSelected ? Theme.accent : Color(.tertiarySystemFill))
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if frequency != .daily && frequency != .specificDays {
                        DatePicker("Starting from", selection: $startDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    scheduleFooter
                }

                if !categories.isEmpty {
                    Section("Category") {
                        Picker("Category", selection: $category) {
                            Text("None").tag("")
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                    }
                }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Prescription" : "Add Prescription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .disabled(substance.isEmpty || amount.isEmpty || (frequency == .specificDays && selectedWeekdays.isEmpty))
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
        (try? JSONDecoder().decode([String].self, from: categoriesData)) ?? []
    }

    private func loadItem() {
        if let item {
            substance = item.substance
            amount = String(item.amount)
            unit = item.unit
            route = item.route
            category = item.category
            frequency = item.frequency
            selectedWeekdays = Set(item.frequencyDays)
            startDate = item.startDate

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
        guard let parsedAmount = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }

        if let item {
            item.substance = substance
            item.amount = parsedAmount
            item.unit = unit
            item.route = route
            item.category = category
            item.frequency = frequency
            item.frequencyDays = Array(selectedWeekdays)
            item.startDate = startDate
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
                startDate: startDate
            )
            modelContext.insert(newItem)
        }

        dismiss()
    }
}
