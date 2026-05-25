import SwiftUI

struct CustomSubstanceFormView: View {
    @Environment(\.appNavigator) private var navigator
    @State private var store = CustomSubstanceStore.shared

    var existing: CustomSubstanceEntry?
    var initialName: String?
    var onSaved: ((CustomSubstanceEntry) -> Void)?

    @State private var name: String
    @State private var category: SubstanceCategory
    @State private var defaultRoute: RouteOfAdministration
    @State private var unit: String
    @State private var notes: String
    @State private var hasDuration: Bool
    @State private var onsetMin: String
    @State private var onsetMax: String
    @State private var comeupMin: String
    @State private var comeupMax: String
    @State private var peakMin: String
    @State private var peakMax: String
    @State private var offsetMin: String
    @State private var offsetMax: String
    @State private var showDuplicateAlert = false

    private var isEditing: Bool { existing != nil }

    init(
        existing: CustomSubstanceEntry? = nil,
        initialName: String? = nil,
        onSaved: ((CustomSubstanceEntry) -> Void)? = nil
    ) {
        self.existing = existing
        self.initialName = initialName
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? initialName ?? "")
        _category = State(initialValue: existing?.category ?? .other)
        _defaultRoute = State(initialValue: existing?.defaultRoute ?? .oral)
        _unit = State(initialValue: existing?.unit ?? "mg")
        _notes = State(initialValue: existing?.notes ?? "")

        let duration = existing?.duration
        _hasDuration = State(initialValue: duration != nil)
        _onsetMin = State(initialValue: Self.format(duration?.onset?.min))
        _onsetMax = State(initialValue: Self.format(duration?.onset?.max))
        _comeupMin = State(initialValue: Self.format(duration?.comeup?.min))
        _comeupMax = State(initialValue: Self.format(duration?.comeup?.max))
        _peakMin = State(initialValue: Self.format(duration?.peak?.min))
        _peakMax = State(initialValue: Self.format(duration?.peak?.max))
        _offsetMin = State(initialValue: Self.format(duration?.offset?.min))
        _offsetMax = State(initialValue: Self.format(duration?.offset?.max))
    }

    private static func format(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    @ViewBuilder
    private func durationRow(_ label: LocalizedStringResource, min: Binding<String>, max: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("min", text: min)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("–").foregroundStyle(Theme.secondaryLabel)
            TextField("max", text: max)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("minutes").foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func buildDuration() -> DurationProfile? {
        guard hasDuration else { return nil }
        func range(_ minStr: String, _ maxStr: String) -> DurationRange? {
            guard let lo = Double(minStr), lo > 0 else { return nil }
            let hi = Double(maxStr) ?? lo
            guard hi >= lo else { return nil }
            return DurationRange(min: lo, max: hi)
        }
        let onset = range(onsetMin, onsetMax)
        let comeup = range(comeupMin, comeupMax)
        let peak = range(peakMin, peakMax)
        let offset = range(offsetMin, offsetMax)
        // Return nil when no phase was filled out — nothing to render.
        guard onset != nil || comeup != nil || peak != nil || offset != nil else { return nil }
        return DurationProfile(
            onset: onset,
            comeup: comeup,
            peak: peak,
            offset: offset,
            afterglow: nil,
            total: nil
        )
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
                            Label(cat.displayName, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                Section("Dosing Defaults") {
                    Picker("Default Route", selection: $defaultRoute) {
                        ForEach(RouteOfAdministration.allCases) { route in
                            Text(route.localizedName).tag(route)
                        }
                    }
                    TextField("Unit (e.g. mg, ml, µg)", text: $unit)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("Custom duration", isOn: $hasDuration.animation())
                    if hasDuration {
                        durationRow("Onset", min: $onsetMin, max: $onsetMax)
                        durationRow("Come-up", min: $comeupMin, max: $comeupMax)
                        durationRow("Peak", min: $peakMin, max: $peakMax)
                        durationRow("Offset", min: $offsetMin, max: $offsetMax)
                    }
                } header: {
                    Text("Duration")
                } footer: {
                    Text(hasDuration
                        ? "Minutes for each phase. Leave a phase blank to skip it; the timeline will interpolate from what you provide."
                        : "Add per-phase timing so this substance gets a Live-Activity timeline like library substances."
                    )
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Optional notes about this substance for your reference.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Substance" : "New Custom Substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { navigator.dismiss() }
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

        let saved: CustomSubstanceEntry
        if let existing {
            // Editing: allow rename as long as it doesn't collide with a different entry.
            if let collision = store.first(whereName: trimmed), collision.id != existing.id {
                showDuplicateAlert = true
                return
            }
            var updated = existing
            updated.name = trimmed
            updated.category = category
            updated.defaultRoute = defaultRoute
            updated.unit = unit
            updated.notes = notes
            updated.duration = buildDuration()
            store.update(updated)
            saved = updated
        } else {
            if store.contains(name: trimmed) {
                showDuplicateAlert = true
                return
            }
            let entry = CustomSubstanceEntry(
                name: trimmed,
                category: category,
                defaultRoute: defaultRoute,
                unit: unit,
                notes: notes,
                duration: buildDuration()
            )
            store.add(entry)
            saved = entry
        }

        onSaved?(saved)
        navigator.dismiss()
    }
}
