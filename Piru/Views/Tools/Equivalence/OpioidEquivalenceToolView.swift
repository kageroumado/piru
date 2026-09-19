import SwiftUI

/// The **Opioid MME** reference. The oral MME factors the tolerance model already
/// reads (`opioid_mme`) surfaced as a tool: a recorded opioid dose expressed in
/// oral morphine milligram equivalents, the unit CDC uses to compare opioid load.
///
/// The readout stops at MME: one opioid and an amount, never a second opioid.
///
/// Pure full-agonist opioids scale linearly. Methadone, transdermal fentanyl,
/// and buprenorphine are structurally un-convertible (see ``OpioidEquivalence``)
/// and show an explanation instead of a number — a deliberate safety choice.
struct OpioidEquivalenceToolView: View {
    /// The converter's rows, resolved from the bundled DB's `opioid_mme` (cached in the store, so
    /// re-reading it per `body` evaluation is an array return).
    private var opioids: [OpioidEquivalence] {
        SubstanceStore.shared.opioidEquivalences()
    }

    @State private var fromName = "oxycodone"
    @State private var doseText = ""

    private var from: OpioidEquivalence? {
        opioids.first { $0.name == fromName }
    }
    private var dose: Double? {
        guard let d = Double(doseText), d > 0 else { return nil }
        return d
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                headerCard
                inputCard
                resultCard
                if let reason = unconvertibleExplanation {
                    specialCard(reason)
                }
                sourceCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .skinBackdrop()
        .appNavigationBar("Opioid MME")
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "cross.case")
                .font(.piru(.largeTitle))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Opioid MME")
                .screenTitle()
            Text("Express a recorded opioid dose in oral morphine milligram equivalents (MME), the unit CDC uses to compare opioid load, using the CDC 2022 factors.")
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
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Opioid and dose")
                    .captionSecondary()
                HStack(spacing: Spacing.lg) {
                    opioidMenu(selection: $fromName)
                        .accessibilityLabel(Text("Opioid"))
                        .accessibilityValue(Text(from?.pickerLabel ?? String(localized: "Select")))
                    HStack(spacing: 0) {
                        TextField("0", text: $doseText)
                            .decimalKeyboard()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.lg)
                        Text("mg")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                            .padding(.trailing, Spacing.xl)
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.inner))
                }
            }
        }
        .padding()
        .themeCard()
    }

    private func opioidMenu(selection: Binding<String>) -> some View {
        Menu {
            ForEach(opioids) { opioid in
                Button {
                    selection.wrappedValue = opioid.name
                } label: {
                    if opioid.name == selection.wrappedValue {
                        Label(opioid.pickerLabel, systemImage: "checkmark")
                    } else {
                        Text(opioid.pickerLabel)
                    }
                }
            }
        } label: {
            HStack {
                Text(opioids.first { $0.name == selection.wrappedValue }?.pickerLabel ?? String(localized: "Select"))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.inner))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(spacing: Spacing.md) {
            Text("Oral morphine equivalent")
                .captionSecondary()

            if let from, let dose, let mme = from.mme(forDoseMg: dose) {
                Text("≈ \(EquivalenceFormat.mg(mme)) MME")
                    .font(.piru(.title, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: mme)
                Text("\(EquivalenceFormat.mg(dose)) mg \(from.displayName), by the CDC 2022 factor")
                    .captionSecondary()
                    .multilineTextAlignment(.center)
            } else {
                Text("--")
                    .font(.piru(.title, weight: .bold))
                    .foregroundStyle(Theme.secondaryLabel)
                Text(fallbackReason)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // No daily caution/high-risk band here: CDC 2022 dropped its 90 MME/day
    // threshold and reframed 50 as a point to pause and reassess, so grading one
    // dose against either would claim more than the source does.

    private var fallbackReason: LocalizedStringResource {
        if from?.mmePerMg == nil { return "This opioid has no linear MME factor — see the note below." }
        return "Enter a dose."
    }

    /// The explanation for a selected opioid with no linear factor (methadone /
    /// fentanyl / buprenorphine).
    private var unconvertibleExplanation: LocalizedStringResource? {
        from?.unconvertibleReason
    }

    private func specialCard(_ reason: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("No figure", systemImage: "info.circle")
                .sectionLabel()
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Source", systemImage: "text.quote")
                .sectionLabel()
                .accessibilityAddTraits(.isHeader)
            Text("CDC Clinical Practice Guideline for Prescribing Opioids for Pain — United States, 2022, oral MME conversion factors. Shown as published; Piru makes no claim to their correctness.")
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}
