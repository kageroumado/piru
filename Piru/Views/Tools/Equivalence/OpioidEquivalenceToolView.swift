import SwiftUI

/// The **Opioid Equivalence** converter. The oral MME factors the tolerance model
/// already reads (`opioid_mme`) surfaced as a tool: a dose of one opioid expressed
/// as another, routed through oral morphine equivalents, with the cross-tolerance
/// warning that makes the number usable.
///
/// Pure full-agonist opioids convert linearly. Methadone, transdermal fentanyl,
/// and buprenorphine are structurally un-convertible (see ``OpioidEquivalence``)
/// and show an explanation instead of a number — a deliberate safety choice.
struct OpioidEquivalenceToolView: View {
    /// The converter's rows, resolved from the bundled DB's `opioid_mme` (cached in the store, so
    /// re-reading it per `body` evaluation is an array return).
    private var opioids: [OpioidEquivalence] {
        SubstanceStore.shared.opioidEquivalences()
    }

    @State private var fromName = "oxycodone"
    @State private var toName = "morphine"
    @State private var doseText = ""

    private var from: OpioidEquivalence? {
        opioids.first { $0.name == fromName }
    }
    private var to: OpioidEquivalence? {
        opioids.first { $0.name == toName }
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
                crossToleranceCard
                safetyCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .appNavigationBar("Opioid Equivalence")
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "cross.case")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Opioid Equivalence")
                .screenTitle()
            Text("Convert a dose of one opioid to another through oral morphine milligram equivalents (MME), using the CDC 2022 conversion factors.")
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
                Text("From")
                    .captionSecondary()
                HStack(spacing: Spacing.lg) {
                    opioidMenu(selection: $fromName)
                        .accessibilityLabel(Text("Convert from"))
                        .accessibilityValue(Text(from?.pickerLabel ?? String(localized: "Select")))
                    HStack(spacing: 0) {
                        TextField("0", text: $doseText)
                            .keyboardType(.decimalPad)
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

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("To")
                    .captionSecondary()
                opioidMenu(selection: $toName)
                    .accessibilityLabel(Text("Convert to"))
                    .accessibilityValue(Text(to?.pickerLabel ?? String(localized: "Select")))
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
            Text("Equivalent Dose")
                .captionSecondary()

            if let from, let to, let dose,
               let result = from.equivalentDose(forDoseMg: dose, in: to),
               let mme = from.mme(forDoseMg: dose) {
                Text("≈ \(EquivalenceFormat.mg(result)) mg")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: result)
                Text("\(EquivalenceFormat.mg(dose)) mg \(from.displayName) ≈ \(EquivalenceFormat.mg(result)) mg \(to.displayName)")
                    .captionSecondary()
                    .multilineTextAlignment(.center)

                mmeBadge(mme)
            } else {
                Text("--")
                    .font(.title.weight(.bold))
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

    /// The oral-MME readout.
    ///
    /// No daily caution/high-risk band: CDC 2022 dropped its 90 MME/day threshold and
    /// reframed 50 as a point to pause and reassess rather than a line, so grading one
    /// converted dose against either would claim more than the source does. What the
    /// reader needs about MME as a metric is in ``safetyCard``.
    private func mmeBadge(_ mme: Double) -> some View {
        Text("≈ \(EquivalenceFormat.mg(mme)) mg oral morphine equivalent")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.top, Spacing.xs)
    }

    private var fallbackReason: LocalizedStringResource {
        if from?.mmePerMg == nil { return "This opioid can't be linearly converted — see the note below." }
        if to?.mmePerMg == nil { return "The target opioid can't be linearly converted — see the note below." }
        if dose == nil { return "Enter a dose to convert." }
        return "Pick two opioids and a dose."
    }

    /// The explanation for a selected un-convertible opioid (methadone / fentanyl
    /// / buprenorphine), preferring the "from" side.
    private var unconvertibleExplanation: LocalizedStringResource? {
        from?.unconvertibleReason ?? to?.unconvertibleReason
    }

    private func specialCard(_ reason: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Not a simple conversion", systemImage: "exclamationmark.octagon")
                .sectionLabel()
                .foregroundStyle(.cautionText)
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Cross-tolerance

    private var crossToleranceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Incomplete cross-tolerance", systemImage: "arrow.triangle.2.circlepath")
                .sectionLabel()
                .foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
            Text("When switching opioids, the equianalgesic dose is an over-estimate: tolerance to one opioid doesn't fully transfer to another. Clinicians start the new opioid **25–50% lower** than the calculated dose (more for high doses or frail/elderly people) and re-titrate. Never take the full converted dose.")
                .captionSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Safety", systemImage: "exclamationmark.triangle")
                .sectionLabel()
                .foregroundStyle(.cautionText)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                safetyPoint("MME is a population risk metric. CDC states the calculated MME should not be used to determine the dose when switching opioids.")
                safetyPoint("Individual variation is large — genetics (e.g. CYP2D6 for codeine, tramadol, oxycodone), liver and kidney function all shift real potency.")
                safetyPoint("These oral factors don't cover every route or product. Transdermal, buccal, and IV forms differ.")
                safetyPoint("Opioids plus benzodiazepines, alcohol, or other depressants sharply raise overdose risk. Tolerance also drops fast after a break — a dose you once handled can be fatal.")
                safetyPoint("An opioid overdose is a sudden loss of consciousness with no warning — you can't give yourself naloxone. Don't use alone: someone with you needs naloxone and should call emergency services. Nodding off can also lead to choking on vomit or burns, so never use where you might pass out unattended.")
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
                .accessibilityHidden(true)
            Text(text)
                .captionSecondary()
        }
    }

    // MARK: - Formatting
}
