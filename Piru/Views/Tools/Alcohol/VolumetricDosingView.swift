import SwiftUI

struct VolumetricDosingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case solventNeeded = "Solvent Needed"
        case concentration = "Concentration"
        case doseVolume = "Dose Volume"
        var id: String {
            rawValue
        }

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
            VStack(spacing: Spacing.xxl) {
                headerCard

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.displayName)
                            .tag(m)
                            // Stable per-segment identifier — a `.segmented` Picker otherwise exposes no
                            // addressable label for its options to UI automation.
                            .accessibilityIdentifier("volumetric-mode-\(m.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("volumetric-mode-picker")

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
        VStack(spacing: Spacing.sm) {
            Image(systemName: "flask")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Volumetric Dosing")
                .screenTitle()
            Text("Calculate measurements for dissolving substances in liquid solvents.")
                .captionSecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // MARK: - Inputs

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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .captionSecondary()
            HStack(spacing: 0) {
                TextField("0", text: value)
                    .decimalKeyboard()
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)

                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.trailing, Spacing.xl)
            }
            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.inner))
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

    private var resultCard: some View {
        VStack(spacing: Spacing.md) {
            Text(resultLabel)
                .captionSecondary()

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
                    PlatformPasteboard.copy(formatted)
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Safety", systemImage: "exclamationmark.triangle")
                .sectionLabel()
                .foregroundStyle(.cautionText)

            VStack(alignment: .leading, spacing: Spacing.sm) {
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
        HStack(alignment: .top, spacing: Spacing.md) {
            Circle()
                .fill(Theme.secondaryLabel)
                .frame(width: 4, height: 4)
                .padding(.top, Spacing.sm)
            Text(text)
                .captionSecondary()
        }
    }
}
