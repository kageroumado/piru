import SwiftData
import SwiftUI

// MARK: - Lab calibration

struct LabCalibrationSection: View {
    @Bindable var model: InjectionLevelsModel
    let labs: [LabMeasurement]
    let ester: EsterPKRecord
    let onAdd: () -> Void
    let onToggleExclude: (LabMeasurement) -> Void
    let onDelete: (LabMeasurement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Calibrate to your lab results")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                calibrationChip
            }

            if labs.isEmpty {
                Text("Add a blood test to pin this curve to your own levels. The band narrows once you do.")
                    .captionSecondary()
            } else {
                ForEach(labs) { lab in
                    labRow(lab)
                }
            }

            Button(action: onAdd) {
                Label("Add lab result", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)

            ReferenceLinesEditor(model: model, unit: model.analyte.canonicalUnit)
        }
        .padding()
        .themeCard()
    }

    private var calibrationChip: some View {
        let count = labs.filter { !$0.excludedFromCalibration }.count
        let label = count == 0
            ? String(localized: "Uncalibrated")
            : count == 1 ? String(localized: "1 result") : String(localized: "Calibrated · \(count) results")
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xxs)
            .background(
                (count == 0 ? Theme.secondaryLabel : Theme.accent).opacity(Theme.Opacity.tint),
                in: Capsule(),
            )
            .foregroundStyle(count == 0 ? Theme.secondaryLabel : Theme.accent)
    }

    private func labRow(_ lab: LabMeasurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lab.date, format: .dateTime.year().month(.abbreviated).day())
                    .font(.subheadline)
                Text("\(model.analyte.fromCanonical(lab.value, to: lab.inputUnit).formatted(.number.precision(.fractionLength(1)))) \(lab.inputUnit)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Button {
                onToggleExclude(lab)
            } label: {
                Image(systemName: lab.excludedFromCalibration ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(lab.excludedFromCalibration ? Theme.secondaryLabel : Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lab.excludedFromCalibration ? Text("Excluded from calibration") : Text("Included in calibration"))
        }
        .padding(.vertical, Spacing.xs)
        .swipeActions {
            Button(role: .destructive) { onDelete(lab) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Reference lines

private struct ReferenceLinesEditor: View {
    @Bindable var model: InjectionLevelsModel
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Reference lines")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            HStack(spacing: Spacing.xl) {
                field(String(localized: "Low line"), value: $model.referenceLow)
                field(String(localized: "High line"), value: $model.referenceHigh)
            }
            Text("Lines you choose to see — not a target the app sets.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func field(_ label: String, value: Binding<Double?>) -> some View {
        HStack(spacing: 0) {
            TextField(label, value: value, format: .number)
                .decimalKeyboard()
                .padding(Spacing.md)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.trailing, Spacing.md)
        }
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
    }
}

// MARK: - Provenance

struct InjectionLevelsProvenanceCard: View {
    let ester: EsterPKRecord
    let analyte: Analyte

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Where these numbers come from")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                confidenceBadge
            }
            Text(ester.provenance)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Older lab data used radioimmunoassay; modern LC-MS/MS reads lower. Calibrating to your own results absorbs whichever assay your lab uses.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Link(destination: URL(string: "https://github.com/WHSAH/estrannaise.js")!) {
                Text("Parameters from estrannaise.js (MIT), cross-checked against primary literature")
                    .font(.caption2)
            }
            .tint(Theme.accent)
        }
        .padding()
        .themeCard()
    }

    private var confidenceBadge: some View {
        let label = switch ester.confidence {
        case "high": String(localized: "High confidence")
        case "medium": String(localized: "Medium confidence")
        default: String(localized: "Low confidence")
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xxs)
            .background(Theme.accent.opacity(Theme.Opacity.tint), in: Capsule())
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - Add lab sheet

struct AddLabResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let analyte: Analyte
    let ester: EsterPKRecord?
    let onSave: (LabMeasurement) -> Void

    @State private var date = Date.now
    @State private var value: Double?
    @State private var unit: String

    init(analyte: Analyte, ester: EsterPKRecord?, onSave: @escaping (LabMeasurement) -> Void) {
        self.analyte = analyte
        self.ester = ester
        self.onSave = onSave
        _unit = State(initialValue: analyte.canonicalUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Draw date", selection: $date, displayedComponents: [.date])
                    HStack {
                        TextField("Serum level", value: $value, format: .number)
                            .decimalKeyboard()
                        Picker("Unit", selection: $unit) {
                            ForEach(analyte.acceptedUnits, id: \.self) { u in Text(u).tag(u) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } footer: {
                    Text("Your result is stored in \(analyte.canonicalUnit); enter it in whichever unit your lab reported.")
                }
            }
            .navigationTitle(Text("Add lab result"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((value ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        guard let raw = value, raw > 0 else { return }
        let canonical = analyte.toCanonical(raw, from: unit)
        onSave(LabMeasurement(
            date: date, analyteKey: analyte.key, value: canonical,
            inputUnit: unit, esterID: ester?.esterID,
        ))
        dismiss()
    }
}
