import SwiftUI

struct VolumetricDosingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case solventNeeded = "Solvent Needed"
        case concentration = "Concentration"
        case doseVolume = "Dose Volume"
        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .solventNeeded: "Solvent Needed"
            case .concentration: "Concentration"
            case .doseVolume: "Dose Volume"
            }
        }
    }

    @State private var mode: Mode = .solventNeeded

    // Shared inputs (reused across modes)
    @State private var substanceAmount = ""
    @State private var solventVolume = ""
    @State private var concentrationValue = ""
    @State private var desiredDose = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                inputCard
                resultCard
                safetyCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "flask")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Volumetric Dosing")
                .font(.title3.weight(.semibold))
            Text("Calculate measurements for dissolving substances in liquid solvents.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // MARK: - Inputs

    @ViewBuilder
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .solventNeeded:
                numericField("Desired Concentration", value: $concentrationValue, unit: "mg/ml")
                numericField("Substance Amount", value: $substanceAmount, unit: "mg")
            case .concentration:
                numericField("Substance Amount", value: $substanceAmount, unit: "mg")
                numericField("Solvent Volume", value: $solventVolume, unit: "ml")
            case .doseVolume:
                numericField("Solution Concentration", value: $concentrationValue, unit: "mg/ml")
                numericField("Desired Dose", value: $desiredDose, unit: "mg")
            }
        }
        .padding()
        .themeCard()
    }

    private func numericField(_ label: LocalizedStringResource, value: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            HStack(spacing: 0) {
                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.trailing, 12)
            }
            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Result

    private var result: Double? {
        switch mode {
        case .solventNeeded:
            guard let conc = Double(concentrationValue), conc > 0,
                  let amount = Double(substanceAmount), amount > 0 else { return nil }
            return amount / conc

        case .concentration:
            guard let amount = Double(substanceAmount), amount > 0,
                  let volume = Double(solventVolume), volume > 0 else { return nil }
            return amount / volume

        case .doseVolume:
            guard let conc = Double(concentrationValue), conc > 0,
                  let dose = Double(desiredDose), dose > 0 else { return nil }
            return dose / conc
        }
    }

    private var resultLabel: LocalizedStringResource {
        switch mode {
        case .solventNeeded: "Solvent Needed"
        case .concentration: "Concentration"
        case .doseVolume: "Volume to Dose"
        }
    }

    private var resultUnit: String {
        switch mode {
        case .solventNeeded: "ml"
        case .concentration: "mg/ml"
        case .doseVolume: "ml"
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        VStack(spacing: 8) {
            Text(resultLabel)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            if let result {
                let formatted = result.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", result)
                    : String(format: "%.4g", result)

                Text("\(formatted) \(resultUnit)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: result)

                Button {
                    UIPasteboard.general.string = formatted
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else {
                Text("--")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safety", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 6) {
                safetyPoint("Always label solutions with substance name and concentration.")
                safetyPoint("Verify calculations independently before use.")
                safetyPoint("Use a milligram scale and graduated cylinder for accuracy.")
                safetyPoint("Store solutions in clearly marked, child-proof containers.")
            }
        }
        .padding()
        .themeCard()
    }

    private func safetyPoint(_ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.secondaryLabel)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}
