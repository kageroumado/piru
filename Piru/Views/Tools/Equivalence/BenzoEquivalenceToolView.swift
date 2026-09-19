import SwiftUI

/// The **Diazepam Equivalence** reference: one benzodiazepine and an amount,
/// expressed in milligrams of diazepam by the Ashton Manual's table
/// (`dose_to_diazepam`), with the table's own wording for that drug beside it.
/// The readout stops at diazepam, and the source line claims nothing beyond the
/// table.
struct BenzoEquivalenceToolView: View {
    @State private var entries: [BenzoEquivalence] = []
    @State private var selectedName: String?
    @State private var amountText = ""
    @State private var isPicking = false

    private var selected: BenzoEquivalence? {
        entries.first { $0.name == selectedName }
    }
    private var amount: Double? {
        guard let value = Double(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                headerCard
                inputCard
                resultCard
                sourceCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .skinBackdrop()
        .appNavigationBar("Diazepam Equivalence")
        .task { load() }
        .sheet(isPresented: $isPicking) {
            BenzoPickerSheet(entries: entries, selection: selectedName) { picked in
                selectedName = picked
            }
        }
    }

    private func load() {
        guard entries.isEmpty else { return }
        entries = SubstanceStore.shared.benzoEquivalences()
        if selectedName == nil {
            selectedName = entries.first { $0.name.lowercased() == "alprazolam" }?.name ?? entries.first?.name
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "moon.fill")
                .font(.piru(.largeTitle))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Diazepam Equivalence")
                .screenTitle()
            Text("A benzodiazepine amount in milligrams of diazepam, from the Ashton Manual's table.")
                .captionSecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    // MARK: - Input

    private var inputCard: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                isPicking = true
            } label: {
                HStack {
                    Text(selected?.displayName ?? String(localized: "Select"))
                        .foregroundStyle(selected == nil ? Theme.secondaryLabel : .primary)
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
            .accessibilityLabel(Text("Benzodiazepine"))
            .accessibilityValue(Text(selected?.displayName ?? String(localized: "Select")))

            HStack(spacing: 0) {
                TextField("0", text: $amountText)
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
        .padding()
        .themeCard()
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(spacing: Spacing.md) {
            Text("Diazepam equivalent")
                .captionSecondary()

            if let selected, let amount, let diazepam = selected.diazepamEquivalent(forDoseMg: amount) {
                Text("≈ \(EquivalenceFormat.mg(diazepam)) mg")
                    .font(.piru(.title, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.default, value: diazepam)
                Text("\(EquivalenceFormat.mg(amount)) mg \(selected.displayName)")
                    .captionSecondary()
                    .multilineTextAlignment(.center)
            } else {
                Text("--")
                    .font(.piru(.title, weight: .bold))
                    .foregroundStyle(Theme.secondaryLabel)
                Text(emptyReason)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .themeCard()
    }

    private var emptyReason: LocalizedStringResource {
        if selected != nil, selected?.diazepamPerMg == nil { return "The table has no figure for this one." }
        return "Enter an amount."
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label("Source", systemImage: "text.quote")
                .sectionLabel()
                .accessibilityAddTraits(.isHeader)
            if let text = selected?.equivalent.displayText {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, Spacing.xxs)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            Text(sourceLine)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    /// Ashton's Table 1 supplies most shipped figures; a figure outside it carries no citation, and
    /// the line says so.
    private var sourceLine: LocalizedStringResource {
        if let selected, !selected.equivalent.isCited {
            return "Not in the Ashton Manual's table. Shown as recorded; Piru makes no claim to its correctness."
        }
        return "Ashton, Benzodiazepines: How They Work and How to Withdraw, Table 1. Shown as published; Piru makes no claim to its correctness."
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
            .insetGroupedListStyle()
            .themedPage()
            .searchable(text: $query, prompt: Text("Search benzodiazepines"))
            .navigationTitle("Select Benzodiazepine")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
