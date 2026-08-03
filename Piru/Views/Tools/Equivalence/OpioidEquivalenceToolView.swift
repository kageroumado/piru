import SwiftUI

/// The **Opioid Equivalence** converter. Piru already carries oral MME factors
/// internally (for tolerance PK); this surfaces them as a harm-reduction tool —
/// convert a dose of one opioid to another via oral morphine equivalents (MME),
/// with the CDC daily-risk bands and the mandatory cross-tolerance warning.
///
/// Pure full-agonist opioids convert linearly. Methadone, transdermal fentanyl,
/// and buprenorphine are structurally un-convertible (see ``OpioidEquivalence``)
/// and show an explanation instead of a number — a deliberate safety choice.
struct OpioidEquivalenceToolView: View {
    private let opioids = OpioidEquivalence.table

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
            VStack(spacing: 16) {
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
        VStack(spacing: 6) {
            Image(systemName: "cross.case")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Opioid Equivalence")
                .font(.title3.weight(.semibold))
            Text("Convert a dose of one opioid to another through oral morphine milligram equivalents (MME), using the CDC 2022 conversion factors.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // MARK: - Inputs

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(spacing: 10) {
                    opioidMenu(selection: $fromName)
                        .accessibilityLabel(Text("Convert from"))
                        .accessibilityValue(Text(from?.displayName ?? String(localized: "Select")))
                    HStack(spacing: 0) {
                        TextField("0", text: $doseText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        Text("mg")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                            .padding(.trailing, 12)
                    }
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("To")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                opioidMenu(selection: $toName)
                    .accessibilityLabel(Text("Convert to"))
                    .accessibilityValue(Text(to?.displayName ?? String(localized: "Select")))
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
                        Label(opioid.displayName, systemImage: "checkmark")
                    } else {
                        Text(opioid.displayName)
                    }
                }
            }
        } label: {
            HStack {
                Text(opioids.first { $0.name == selection.wrappedValue }?.displayName ?? String(localized: "Select"))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(spacing: 8) {
            Text("Equivalent Dose")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            if let from, let to, let dose,
               let result = from.equivalentDose(forDoseMg: dose, in: to),
               let mme = from.mme(forDoseMg: dose) {
                Text("≈ \(Self.formatMg(result)) mg")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: result)
                Text("\(Self.formatMg(dose)) mg \(from.displayName) ≈ \(Self.formatMg(result)) mg \(to.displayName)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
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

    /// The oral-MME readout with the CDC daily-risk band (if this were a daily dose).
    private func mmeBadge(_ mme: Double) -> some View {
        let band = riskBand(mme)
        return VStack(spacing: 4) {
            Text("≈ \(Self.formatMg(mme)) mg oral morphine equivalent")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Text(band.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(band.color)
            Text("CDC daily-risk bands: ≥ \(Int(OpioidEquivalence.cautionMMEPerDay)) MME caution, ≥ \(Int(OpioidEquivalence.highRiskMMEPerDay)) MME high-risk (per day).")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private func riskBand(_ mme: Double) -> (label: LocalizedStringResource, color: Color) {
        if mme >= OpioidEquivalence.highRiskMMEPerDay {
            return ("If taken over a day, this is a high-risk daily MME.", .red)
        }
        if mme >= OpioidEquivalence.cautionMMEPerDay {
            return ("If taken over a day, this reaches the CDC caution band.", .orange)
        }
        return ("Below the CDC daily caution band.", .green)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Not a simple conversion", systemImage: "exclamationmark.octagon")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Cross-tolerance

    private var crossToleranceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Incomplete cross-tolerance", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
            Text("When switching opioids, the equianalgesic dose is an over-estimate: tolerance to one opioid doesn't fully transfer to another. Clinicians start the new opioid **25–50% lower** than the calculated dose (more for high doses or frail/elderly people) and re-titrate. Never take the full converted dose.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safety", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
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
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.secondaryLabel)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Formatting

    /// Two significant figures below 10, integer at or above — an opioid-dose-scale
    /// readout without implying false precision.
    static func formatMg(_ value: Double) -> String {
        if value <= 0 { return "0" }
        if value >= 10 { return String(Int(value.rounded())) }
        if value >= 1 { return String(format: "%.1f", value) }
        return String(format: "%.2g", value)
    }
}
