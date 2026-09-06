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

            Divider()
            CalibrationControl(model: model)

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

// MARK: - Personal calibration control

/// The amplitude "run high / run low" knob and its lab-driven state. When the user
/// has labs and auto-calibration is on, the fit owns the amplitude and this shows it
/// read-only (plus a note when the shape — the terminal rate — was fitted too); with
/// no labs or auto off, it's a hand-set multiplier. Never a target: it scales the
/// estimate to the person, it doesn't recommend a level.
private struct CalibrationControl: View {
    @Bindable var model: InjectionLevelsModel

    private var multiplierText: String {
        "×\(model.effectiveMultiplier.formatted(.number.precision(.fractionLength(2))))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Personal calibration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                Text(multiplierText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(model.isLabDriven ? Theme.accent : Theme.secondaryLabel)
            }

            if model.hasLabs {
                Toggle(isOn: $model.autoCalibrateFromLabs) {
                    Text("Set from my lab results")
                        .font(.subheadline)
                }
                .tint(Theme.accent)
            }

            if model.isLabDriven {
                if let cal = model.calibration, cal.didFitRate {
                    Text("Amplitude and shape both fit to your results — your terminal release ran \(ratePhrase(cal.k1Scale)).")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    Text("Amplitude fit to your result. Add a second test on a different day and the curve's shape fits too.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if model.calibrationMeasurements.count >= 2 {
                    Toggle(isOn: $model.fitRates) {
                        Text("Fit the curve's shape, not just its height")
                            .font(.subheadline)
                    }
                    .tint(Theme.accent)
                }
            } else {
                Slider(value: $model.personalMultiplier, in: 0.3 ... 3.0, step: 0.05)
                    .tint(Theme.accent)
                Text("Nudge this if you run higher or lower than average. A blood test replaces it with a fit to your own levels — far better than a guess.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    /// A fully-formed comparative — "faster than the population (1.3×)" — so it folds
    /// into "…your terminal release ran %@." as one localizable unit. A String (not
    /// Text) so it interpolates as a single `%@` catalog placeholder.
    private func ratePhrase(_ k1Scale: Double) -> String {
        // k1 larger → faster terminal release/decay; smaller → slower.
        let factor = (k1Scale >= 1 ? k1Scale : 1 / k1Scale).formatted(.number.precision(.fractionLength(2)))
        return k1Scale >= 1
            ? String(localized: "faster than the population (\(factor)×)")
            : String(localized: "slower than the population (\(factor)×)")
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
            Text("Subcutaneous injection reaches levels close to intramuscular for these esters — 196 vs 190 pg/mL in one head-to-head — so the same curve serves both routes (Herndon 2023; Misakian 2025).")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Link(destination: URL(string: "https://github.com/WHSAH/estrannaise.js")!) {
                Text("Parameters from estrannaise.js (MIT), cross-checked against primary literature")
                    .font(.caption2)
            }
            .tint(Theme.accent)
            Link(destination: URL(string: "https://diyhrt.info/transfem/dosing/")!) {
                Text("More on injectable estradiol dosing (diyhrt.info)")
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
