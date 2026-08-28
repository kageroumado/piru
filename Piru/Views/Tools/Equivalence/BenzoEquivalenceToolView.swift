import SwiftUI

/// The **Benzodiazepine Equivalence** converter (Stage 6). Piru already ships the
/// cited `dose_to_diazepam` data for every benzodiazepine; this surfaces it as the
/// single most-used benzo harm-reduction tool — the Ashton-style equivalence table.
///
/// Pick a benzo + dose → its diazepam-equivalent, or convert directly between two
/// benzos (A → diazepam → B) for a cross-taper. Every number is shown with its
/// **cited source prose** and a "tables disagree" disclaimer — the differentiator
/// over an uncited table — joined to each drug's half-life (the "why switch"). It
/// converts and informs; it is **not** a taper schedule.
struct BenzoEquivalenceToolView: View {
    @State private var entries: [BenzoEquivalence] = []
    @State private var fromName: String?
    @State private var toName: String?
    @State private var doseText = ""
    @State private var picking: PickTarget?

    private enum PickTarget: Identifiable {
        case from
        case to
        var id: Int {
            self == .from ? 0 : 1
        }
    }

    private var from: BenzoEquivalence? {
        entries.first { $0.name == fromName }
    }
    private var to: BenzoEquivalence? {
        entries.first { $0.name == toName }
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
                if from != nil || to != nil { citationCard }
                if from != nil || to != nil { halfLifeCard }
                safetyCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .appNavigationBar("Benzo Equivalence")
        .task { load() }
        .sheet(item: $picking) { target in
            BenzoPickerSheet(
                entries: entries,
                selection: target == .from ? fromName : toName,
            ) { picked in
                if target == .from { fromName = picked } else { toName = picked }
            }
        }
    }

    private func load() {
        guard entries.isEmpty else { return }
        entries = SubstanceStore.shared.benzoEquivalences()
        // Sensible defaults: a common short-acting benzo → diazepam (the canonical
        // "what did I take, in diazepam terms" and cross-taper starting point).
        if fromName == nil {
            fromName = entries.first { $0.name.lowercased() == "alprazolam" }?.name ?? entries.first?.name
        }
        if toName == nil {
            toName = entries.first { $0.name.lowercased() == "diazepam" }?.name
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Benzo Equivalence")
                .font(.title3.weight(.semibold))
            Text("Compare benzodiazepine doses against diazepam, or convert between two. Switching to a long-acting benzo before tapering is standard practice, though evidence for better outcomes is limited.")
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
                    pickerButton(for: .from, selection: from)
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
                pickerButton(for: .to, selection: to)
            }
        }
        .padding()
        .themeCard()
    }

    private func pickerButton(for target: PickTarget, selection: BenzoEquivalence?) -> some View {
        Button {
            picking = target
        } label: {
            HStack {
                Text(selection?.displayName ?? String(localized: "Select"))
                    .foregroundStyle(selection == nil ? Theme.secondaryLabel : .primary)
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
        .accessibilityLabel(target == .from ? Text("Convert from") : Text("Convert to"))
        .accessibilityValue(Text(selection?.displayName ?? String(localized: "Select")))
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(spacing: 8) {
            Text("Equivalent Dose")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            if let from, let to, let dose, let result = from.equivalentDose(forDoseMg: dose, in: to) {
                Text("≈ \(EquivalenceFormat.mg(result)) mg")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: result)
                Text("\(EquivalenceFormat.mg(dose)) mg \(from.displayName) ≈ \(EquivalenceFormat.mg(result)) mg \(to.displayName)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                if to.name.lowercased() != "diazepam", let diazepam = from.diazepamEquivalent(forDoseMg: dose) {
                    Text("(≈ \(EquivalenceFormat.mg(diazepam)) mg diazepam)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Text("Approximate — equivalence tables disagree. Treat this as a ballpark.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            } else {
                Text("--")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.secondaryLabel)
                Text(unconvertibleReason)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    private var unconvertibleReason: LocalizedStringResource {
        if dose == nil { return "Enter a dose to convert." }
        if from?.diazepamPerMg == nil { return "No numeric equivalence is available for this substance." }
        if to?.diazepamPerMg == nil { return "No numeric equivalence is available for the target substance." }
        return "Pick both substances and a dose."
    }

    // MARK: - Provenance

    private var citationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Where this comes from", systemImage: "text.quote")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let text = from?.equivalent.displayText {
                citationLine(text)
            }
            if let to, to.name != from?.name, let text = to.equivalent.displayText {
                citationLine(text)
            }
            Text(sourceLine)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    private func citationLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Half-life join (the "why switch")

    private var halfLifeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Half-life", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let from { halfLifeLine(for: from) }
            if let to, to.name != from?.name { halfLifeLine(for: to) }
            Text("A cross-taper usually switches from a short- to a long-half-life benzo: the longer drug self-tapers more smoothly. Diazepam's long-acting active metabolites stretch its effective half-life well beyond the parent.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    /// What the numbers on screen actually rest on. Ashton's Table 1 is where 23 of the shipped
    /// equivalences come from and it says of itself that the doses are approximate and not
    /// universally agreed; the five it omits are not sourced at all, and saying which is which is
    /// the whole difference between a citation and a decoration.
    private var sourceLine: LocalizedStringResource {
        let shown = [from, to].compactMap(\.self)
        let uncited = shown.filter { !$0.equivalent.isCited }
        if uncited.isEmpty {
            return "Source: the Ashton Manual's equivalence table, which calls these doses approximate and notes that not every clinician agrees with them."
        }
        if uncited.count == shown.count {
            return "Not in the Ashton Manual's equivalence table, and not sourced elsewhere — treat the number as a rough guide and dose by this drug's own threshold."
        }
        return "One of these is from the Ashton Manual's equivalence table; the other is not in it and is not sourced elsewhere. Equivalences are approximate either way."
    }

    private func halfLifeLine(for benzo: BenzoEquivalence) -> some View {
        HStack {
            Text(benzo.displayName)
                .font(.caption.weight(.medium))
            Spacer()
            if let minutes = SubstanceLibrary.lookup(benzo.name)?.halfLifeMinutes {
                Text(Self.formatHalfLife(minutes))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safety", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                safetyPoint("This converts and compares — it is not a taper schedule. Plan any dose reduction with a clinician.")
                safetyPoint("Never stop a benzodiazepine abruptly. Withdrawal can be dangerous (seizures); a slow taper is the safe path.")
                safetyPoint("Single-dose equivalence isn't steady-state equivalence — long-acting metabolites accumulate over days.")
                safetyPoint("Equivalences are approximate and contested. Use the cited value as a starting estimate.")
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

    static func formatHalfLife(_ minutes: Double) -> String {
        let hours = minutes / 60
        if hours < 1 {
            return String(localized: "~\(Int(minutes.rounded())) min")
        }
        if hours < 10 {
            return String(localized: "~\(String(format: "%.1f", hours)) h")
        }
        return String(localized: "~\(Int(hours.rounded())) h")
    }
}

/// A searchable benzodiazepine picker — there are ~100 entries, so a flat menu
/// would be unusable. Filters by display name as the user types.
private struct BenzoPickerSheet: View {
    let entries: [BenzoEquivalence]
    let selection: String?
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [BenzoEquivalence] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.displayName.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { benzo in
                Button {
                    onPick(benzo.name)
                    dismiss()
                } label: {
                    HStack {
                        Text(benzo.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if benzo.name == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .listRowBackground(CardBackground())
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: Text("Search benzodiazepines"))
            .navigationTitle("Select Benzodiazepine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
