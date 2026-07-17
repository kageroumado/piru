import SwiftData
import SwiftUI
import UIKit

// MARK: - Drink Preset Manager

/// Full management surface for a by-volume substance's drink presets, presented
/// as a sheet from the drink chip's "Edit Drinks…" menu item. A native List
/// permanently in edit mode: grabbers reorder, minus/swipe deletes, tap a row
/// to edit it, `+` to add — the same pattern as ``QuickLogEditSheet`` (see
/// there for why rows are `Button`s and `editMode` is scoped to the `List`).
struct DrinkPresetManagerView: View {
    let substanceName: String

    @Query private var presets: [CustomDrinkPreset]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var path: [CustomDrinkPreset] = []

    init(substanceName: String) {
        self.substanceName = substanceName
        let lower = substanceName.lowercased()
        _presets = Query(
            filter: #Predicate { $0.substanceName == lower },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)],
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            path.append(preset)
                        } label: {
                            presetRow(preset)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("Drag to reorder. Swipe left to remove.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationDestination(for: CustomDrinkPreset.self) { preset in
                DrinkPresetForm(preset: preset, substanceName: substanceName)
            }
            .navigationTitle("Drinks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DrinkPresetForm(preset: nil, substanceName: substanceName)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Drink")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func presetRow(_ preset: CustomDrinkPreset) -> some View {
        DrinkPresetRow(preset: preset)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = presets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, preset) in ordered.enumerated() {
            preset.sortOrder = Double(index)
        }
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(presets[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Preset Row

/// One drink preset's list row (emoji, name, strength/volume detail, chevron) —
/// shared between ``DrinkPresetManagerView`` and ``QuickLogEditSheet``.
struct DrinkPresetRow: View {
    let preset: CustomDrinkPreset

    var body: some View {
        HStack(spacing: 12) {
            Text(preset.emoji)
                .font(.title3)
            Text(preset.name)
            Spacer()
            Text(preset.detailLabel)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Add / Edit Form

/// One drink preset's editor: emoji + name, strength, and an optional fixed
/// serving volume. Strength + name define a preset; a fixed-volume preset (a
/// 330 mL can) fills both dials on select, a strength-only one (an IPA you
/// pour freely) fills just the strength.
/// Internal (not private) so ``QuickLogEditSheet`` can push the same editor.
struct DrinkPresetForm: View {
    /// `nil` creates a new preset on save.
    let preset: CustomDrinkPreset?
    let substanceName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🍺"
    @State private var strengthText = ""
    @State private var volumeText = ""
    @State private var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit
    @State private var fixedVolume = true

    private var enteredABV: Double? {
        guard let value = Double(strengthText.replacingOccurrences(of: ",", with: ".")), value > 0, value <= 95 else { return nil }
        return value
    }

    private var enteredVolumeML: Double? {
        guard let value = Double(volumeText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return Measurement(value: value, unit: volumeUnit).converted(to: .milliliters).value
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && enteredABV != nil
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    EmojiField(text: $emoji)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Drink emoji")
                    TextField("Name (e.g. IPA)", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            Section {
                LabeledContent("Strength") {
                    // One HStack — LabeledContent stacks multiple content
                    // views vertically.
                    HStack(spacing: 4) {
                        TextField("0", text: $strengthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Text(verbatim: "%")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Toggle("Fixed serving size", isOn: $fixedVolume)
                    .tint(Theme.accent)
                if fixedVolume {
                    LabeledContent("Volume") {
                        HStack(spacing: 4) {
                            TextField("0", text: $volumeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                            Picker("Volume unit", selection: $volumeUnit) {
                                Text(verbatim: "mL").tag(UnitVolume.milliliters)
                                Text(verbatim: "fl oz").tag(UnitVolume.fluidOunces)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            } footer: {
                Text("A fixed serving fills strength and volume when selected — like a 330 mL can. Without one, only the strength is filled.")
            }
        }
        .navigationTitle(preset == nil ? "New Drink" : "Edit Drink")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: seed)
        .onChange(of: volumeUnit) { old, new in
            ByVolumeDefaults.preferredVolumeUnit = new
            guard let value = Double(volumeText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            volumeText = ByVolumeDefaults.format(Measurement(value: value, unit: old).converted(to: new).value)
        }
    }

    private func seed() {
        guard let preset else { return }
        name = preset.name
        emoji = preset.emoji
        strengthText = ByVolumeDefaults.format(preset.strengthABV)
        fixedVolume = preset.volumeML != nil
        if let ml = preset.volumeML {
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let abv = enteredABV else { return }
        let glyph = emoji.isEmpty ? "🍺" : emoji
        let volume = fixedVolume ? enteredVolumeML : nil

        if let preset {
            preset.name = trimmed
            preset.emoji = glyph
            preset.strengthABV = abv
            preset.volumeML = volume
        } else {
            let lower = substanceName.lowercased()
            var descriptor = FetchDescriptor<CustomDrinkPreset>(
                predicate: #Predicate { $0.substanceName == lower },
                sortBy: [SortDescriptor(\.sortOrder, order: .reverse)],
            )
            descriptor.fetchLimit = 1
            let maxOrder = (try? modelContext.fetch(descriptor))?.first?.sortOrder ?? -1
            modelContext.insert(CustomDrinkPreset(
                name: trimmed, emoji: glyph, strengthABV: abv, volumeML: volume,
                substanceName: lower, sortOrder: maxOrder + 1,
            ))
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Emoji Field

/// A one-glyph text field that presents the system **emoji** keyboard, for the
/// drink-preset emoji. Standard `UITextField` override of `textInputMode`; keeps
/// only the last entered emoji so the field always holds a single glyph.
private struct EmojiField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = EmojiUITextField()
        field.text = text
        field.delegate = context.coordinator
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 24)
        field.tintColor = .clear
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) {
            _text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn _: NSRange, replacementString string: String) -> Bool {
            // Keep only the newly typed glyph (single emoji), replacing any prior.
            if string.isEmpty {
                text = ""
                textField.text = ""
            } else {
                text = string
                textField.text = string
            }
            return false
        }
    }
}

/// `UITextField` that forces the emoji keyboard by advertising the emoji input mode.
private final class EmojiUITextField: UITextField {
    override var textInputContextIdentifier: String? {
        ""
    }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
