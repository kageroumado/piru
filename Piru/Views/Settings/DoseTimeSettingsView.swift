import SwiftUI

/// Edits the relative-time presets shown in the quick-log "When" menu. The list
/// mirrors ``DoseTimeDefaults`` — reorder and delete in place, add via a sheet —
/// and writes back the comma-joined minutes on every change.
struct DoseTimeSettingsView: View {
    @AppStorage(DoseTimeDefaults.choicesKey, store: UserDefaults(suiteName: DoseTimeDefaults.suite))
    private var choicesRaw = DoseTimeDefaults.defaultRaw

    /// The working copy the List edits; persisted back to `choicesRaw` on change.
    @State private var choices: [Int] = []
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                ForEach(choices, id: \.self) { minutes in
                    Label(TrayTime.offsetLabel(minutes: minutes), systemImage: "clock.arrow.circlepath")
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                if choices.count < DoseTimeDefaults.maxCount {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add Preset", systemImage: "plus")
                    }
                }
            } header: {
                Text("Dose Times")
            } footer: {
                Text("These appear in the “When” menu when logging a dose, alongside Now and the full date picker. Swipe to remove, drag to reorder.")
            }
            .listRowBackground(CardBackground())

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    choices = DoseTimeDefaults.defaultChoices
                }
                .disabled(choices == DoseTimeDefaults.defaultChoices)
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Dose Times")
        .inlineNavigationTitle()
        #if os(iOS)
            .toolbar { EditButton() }
        #endif
            .sheet(isPresented: $showAdd) {
                DoseTimeAddSheet(existing: choices) { minutes in
                    choices.append(minutes)
                }
            }
            .onAppear { choices = DoseTimeDefaults.parse(choicesRaw) }
            .onChange(of: choices) { _, new in
                choicesRaw = DoseTimeDefaults.format(new)
            }
    }

    private func delete(at offsets: IndexSet) {
        // Keep at least one preset so the menu never empties out.
        guard choices.count - offsets.count >= 1 else { return }
        choices.remove(atOffsets: offsets)
    }

    private func move(from source: IndexSet, to destination: Int) {
        choices.move(fromOffsets: source, toOffset: destination)
    }
}

/// Picks a new "When" preset as hours + minutes, rejecting duplicates and values
/// outside ``DoseTimeDefaults/range``.
private struct DoseTimeAddSheet: View {
    let existing: [Int]
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hours = 1
    @State private var minutes = 0

    private var total: Int {
        hours * 60 + minutes
    }
    private var isDuplicate: Bool {
        existing.contains(total)
    }
    private var isValid: Bool {
        DoseTimeDefaults.range.contains(total) && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0 ..< 24) { Text("\($0) h").tag($0) }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0 ..< 60) { Text("\($0) min").tag($0) }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                    }
                    .labelsHidden()
                } footer: {
                    if isDuplicate {
                        Text("That preset already exists.")
                    } else if total < DoseTimeDefaults.range.lowerBound {
                        Text("Choose at least one minute.")
                    } else {
                        Text("Adds “\(TrayTime.offsetLabel(minutes: total))”.")
                    }
                }
            }
            .themedPage()
            .navigationTitle("Add Preset")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(total)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
