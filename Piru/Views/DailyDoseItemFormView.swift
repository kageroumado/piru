import SwiftUI
import SwiftData

struct DailyDoseItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var item: DailyDoseItem?

    @State private var substance = ""
    @State private var amount = ""
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases

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

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(substance.isEmpty || amount.isEmpty)
                }
            }
            .onAppear(perform: loadItem)
        }
    }

    private func selectSubstance(_ sub: Substance) {
        selectedSubstance = sub
        route = sub.defaultRoute
        unit = sub.unit(for: sub.defaultRoute)
        let subRoutes = sub.routes.map(\.route)
        let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
        availableRoutes = subRoutes + otherRoutes
    }

    private func useCustomSubstance() {
        selectedSubstance = nil
        availableRoutes = RouteOfAdministration.allCases
    }

    private func loadItem() {
        guard let item else { return }
        substance = item.substance
        amount = String(item.amount)
        unit = item.unit
        route = item.route

        if let match = SubstanceLibrary.shared.search(item.substance).first,
           match.name.lowercased() == item.substance.lowercased() {
            selectedSubstance = match
            let subRoutes = match.routes.map(\.route)
            let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
            availableRoutes = subRoutes + otherRoutes
        }
    }

    private func save() {
        guard let parsedAmount = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }

        if let item {
            item.substance = substance
            item.amount = parsedAmount
            item.unit = unit
            item.route = route
        } else {
            let newItem = DailyDoseItem(
                substance: substance,
                amount: parsedAmount,
                unit: unit,
                route: route,
                sortOrder: existingItems.count
            )
            modelContext.insert(newItem)
        }

        dismiss()
    }
}
