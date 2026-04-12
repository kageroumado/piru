import SwiftUI
import SwiftData

struct CustomSubstanceFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existing: CustomSubstance?
    var initialName: String?

    @State private var name: String
    @State private var category: SubstanceCategory
    @State private var defaultRoute: RouteOfAdministration
    @State private var unit: String
    @State private var notes: String
    @State private var showDuplicateAlert = false

    @Query private var allCustom: [CustomSubstance]

    private var isEditing: Bool { existing != nil }

    init(existing: CustomSubstance? = nil, initialName: String? = nil) {
        self.existing = existing
        self.initialName = initialName
        _name = State(initialValue: existing?.name ?? initialName ?? "")
        _category = State(initialValue: existing?.category ?? .other)
        _defaultRoute = State(initialValue: existing?.defaultRoute ?? .oral)
        _unit = State(initialValue: existing?.unit ?? "mg")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Substance name", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Classification") {
                    Picker("Category", selection: $category) {
                        ForEach(SubstanceCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                Section("Dosing Defaults") {
                    Picker("Default Route", selection: $defaultRoute) {
                        ForEach(RouteOfAdministration.allCases) { route in
                            Text(route.displayName).tag(route)
                        }
                    }
                    TextField("Unit (e.g. mg, ml, µg)", text: $unit)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Optional notes about this substance for your reference.")
                }

                if !isEditing {
                    Section {
                        Label("Custom substances have no dose range data. You'll enter doses manually when logging.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Substance" : "New Custom Substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Duplicate Name", isPresented: $showDuplicateAlert) {
                Button("OK") {}
            } message: {
                Text("A custom substance named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.")
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let existing {
            existing.name = trimmed
            existing.category = category
            existing.defaultRoute = defaultRoute
            existing.unit = unit
            existing.notes = notes
        } else {
            let isDuplicate = allCustom.contains {
                $0.name.lowercased() == trimmed.lowercased()
            }
            if isDuplicate {
                showDuplicateAlert = true
                return
            }
            let custom = CustomSubstance(
                name: trimmed,
                category: category,
                defaultRoute: defaultRoute,
                unit: unit,
                notes: notes
            )
            modelContext.insert(custom)
        }
        dismiss()
    }
}
