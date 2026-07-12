import SwiftUI

// Peptide-specific detail components. Peptides differ fundamentally from the
// psychoactive small molecules the rest of the detail view is built for: they
// are injected (reconstituted from lyophilized powder), dosed on clinical
// protocols rather than a trip-intensity ladder, cold-chain sensitive, and
// identified by an amino-acid sequence. These views surface that information in
// place of the dose ladder / trip timeline / comedown guide.

// MARK: - Protocol Dosing Card

/// Renders a clinical-protocol dosing schedule (amount · frequency · titration ·
/// course) — the replacement for the threshold→heavy ladder for peptides/PEDs.
struct ProtocolDosingCard: View {
    let unit: String
    let protocolDosing: ProtocolDosing

    private var amountText: String? {
        switch (protocolDosing.lowAmount, protocolDosing.highAmount) {
        case let (lo?, hi?) where lo != hi: "\(lo.doseFormatted)–\(hi.doseFormatted) \(unit)"
        case let (lo?, _): "\(lo.doseFormatted) \(unit)"
        case let (_, hi?): "\(hi.doseFormatted) \(unit)"
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Typical protocol")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            if let amountText {
                LabeledContent {
                    Text(amountText).fontWeight(.medium)
                } label: {
                    Text("Dose")
                }
                .font(.subheadline)
            }

            LabeledContent {
                Text(protocolDosing.frequency).fontWeight(.medium)
            } label: {
                Text("Frequency")
            }
            .font(.subheadline)

            if let course = protocolDosing.courseDuration {
                LabeledContent { Text(course) } label: { Text("Course") }
                    .font(.subheadline)
            }

            if let titration = protocolDosing.titration, !titration.isEmpty {
                Divider()
                Text("Titration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(titration.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(step.label)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                        Spacer()
                        Text("\(step.amount.doseFormatted) \(unit)")
                            .font(.caption.weight(.medium))
                    }
                }
            }

            if let notes = protocolDosing.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Peptide Handling Card

/// Sequence, molar mass, supplied form, and storage / cold-chain — the reference
/// data a peptide user actually needs.
struct PeptideHandlingCard: View {
    let profile: PeptideProfile
    let molarMass: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sequence = profile.sequence {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sequence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(sequence)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let molarMass {
                LabeledContent("Molar mass") {
                    Text("\(molarMass.doseFormatted) g/mol")
                }
                .font(.subheadline)
            }

            if let form = profile.suppliedForm {
                LabeledContent("Supplied as") {
                    Text(form.displayName)
                }
                .font(.subheadline)
            }

            if let storage = profile.storage {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: storage.temperature.icon)
                        .foregroundStyle(.cyan)
                        .accessibilityHidden(true)
                    Text(storage.temperature.displayName)
                        .font(.subheadline.weight(.medium))
                }
                if storage.lightSensitive {
                    Label("Protect from light", systemImage: "light.min")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if let days = storage.reconstitutedStabilityDays {
                    Label(
                        "Stable ~\(days.doseFormatted) days once reconstituted",
                        systemImage: "drop.fill",
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reconstitution Calculator

/// Computes injection draw volume from vial strength, diluent volume, and target
/// dose. Pure arithmetic, no persistence — the single most-requested peptide tool.
struct ReconstitutionCalculatorView: View {
    enum DoseUnitChoice: String, CaseIterable, Identifiable {
        case mcg
        case mg
        var id: String {
            rawValue
        }
        var label: String {
            rawValue
        }
        /// Multiplier to milligrams.
        var toMg: Double {
            self == .mcg ? 0.001 : 1
        }
    }

    let defaultVialMg: Double?

    @State private var vialMg: Double
    @State private var waterML: Double = 2
    @State private var doseAmount: Double = 250
    @State private var doseUnit: DoseUnitChoice = .mcg

    init(defaultVialMg: Double?) {
        self.defaultVialMg = defaultVialMg
        _vialMg = State(initialValue: defaultVialMg ?? 5)
        // A 5 mg vial in 2 mL with a 250 mcg target is a sensible peptide default.
        _doseAmount = State(initialValue: defaultVialMg != nil ? 250 : 250)
    }

    /// Concentration in mg/mL. nil when inputs are non-positive.
    private var concentrationMgPerML: Double? {
        guard vialMg > 0, waterML > 0 else { return nil }
        return vialMg / waterML
    }

    /// Volume to draw for the target dose, in mL.
    private var drawVolumeML: Double? {
        guard let c = concentrationMgPerML, c > 0, doseAmount > 0 else { return nil }
        let doseMg = doseAmount * doseUnit.toMg
        return doseMg / c
    }

    /// U-100 insulin-syringe units (100 units = 1 mL).
    private var insulinUnits: Double? {
        drawVolumeML.map { $0 * 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputRow(label: "Vial amount", value: $vialMg, unit: "mg")
            inputRow(label: "Bacteriostatic water", value: $waterML, unit: "mL")

            HStack {
                Text("Target dose")
                    .font(.subheadline)
                Spacer()
                TextField("Dose", value: $doseAmount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
                    .accessibilityLabel(Text("Target dose"))
                Picker("Unit", selection: $doseUnit) {
                    ForEach(DoseUnitChoice.allCases) { u in
                        Text(u.label).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }

            Divider()

            if let c = concentrationMgPerML, let mL = drawVolumeML, let units = insulinUnits {
                resultRow(label: "Concentration", value: "\(c.doseFormatted) mg/mL")
                resultRow(label: "Draw", value: "\(mL.doseFormatted) mL", emphasised: true)
                resultRow(label: "On a U-100 syringe", value: "\(units.doseFormatted) units", emphasised: true)
            } else {
                Text("Enter a vial amount, diluent volume, and target dose.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Text("Estimates only. Verify against your product and a clinician.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 4)
    }

    private func inputRow(label: LocalizedStringResource, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityLabel(Text(label))
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func resultRow(label: LocalizedStringResource, value: String, emphasised: Bool = false) -> some View {
        LabeledContent {
            Text(value)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(emphasised ? Color.accentColor : .primary)
        } label: {
            Text(label).font(.subheadline)
        }
    }
}
