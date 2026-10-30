import SwiftUI

// MARK: - Product cell

/// A staged combination product, drawn on its lead row
/// (``DoseTrayModel/leadRowID(ofCombination:)``) in place of one row per
/// component: collapsed, the product and how much of it; expanded, a single
/// quantity control (units for a solid, mL for a liquid) with each
/// component's mass beneath it, read-only. The components stay separate
/// staged rows underneath, so each commits as its own entry.
struct TrayProductCell: View {
    let product: CustomSubstanceEntry
    let leadID: UUID
    /// Stable reference: the cell reads its own rows and writes the quantity
    /// through the model, so the card passes no closures.
    let model: DoseTrayModel
    let namespace: Namespace.ID

    var body: some View {
        let rows = model.staged.filter { $0.combinationName == product.name }
        let quantity = model.stagedQuantity(of: product)
        if model.expandedItemIDs.contains(leadID) {
            StagedProductEditor(
                product: product,
                leadID: leadID,
                rows: rows,
                quantity: quantity,
                model: model,
                namespace: namespace,
            )
            .padding(.vertical, Spacing.md)
        } else {
            TrayProductRow(product: product, leadID: leadID, rows: rows, quantity: quantity, namespace: namespace) {
                withAnimation(.snappy) { model.openForEditing(leadID, focusesAmount: product.isLiquidCombination) }
            }
            .contextMenuPreviewShape(Rectangle())
            .contextMenu {
                Button {
                    withAnimation(.snappy) { _ = model.expandedItemIDs.insert(leadID) }
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                Button(role: .destructive) {
                    withAnimation(.snappy) { model.removeCombination(product.name) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Collapsed row

/// The product as one compact row: its name over its components' masses,
/// the quantity on the trailing edge, and the disclosure chevron.
private struct TrayProductRow: View {
    let product: CustomSubstanceEntry
    let leadID: UUID
    let rows: [StagedDose]
    let quantity: Double?
    let namespace: Namespace.ID
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.resolvedDisplayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .trayMorph(id: "title-\(leadID)", in: namespace)
                Text(verbatim: rows.map { "\($0.totalAmount.doseFormatted) \($0.unit) \($0.displayTitle)" }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let quantity {
                Text(verbatim: product.quantityLabel(quantity))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .trayMorph(id: "amount-\(leadID)", in: namespace)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(width: 16)
                .trayMorph(id: "chevron-\(leadID)", in: namespace)
        }
        .padding(.vertical, Spacing.xl)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Expands the editor")
    }
}

// MARK: - Expanded editor

/// The product's editor: one quantity control that drives every component,
/// and the components' masses beneath it as read-only lines.
private struct StagedProductEditor: View {
    let product: CustomSubstanceEntry
    let leadID: UUID
    let rows: [StagedDose]
    let quantity: Double?
    let model: DoseTrayModel
    let namespace: Namespace.ID

    @State private var volume = StagedProductVolumeModel()
    @FocusState private var volumeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StagedDoseEditorHeader(
                title: product.resolvedDisplayName,
                subtitle: nil,
                morphID: leadID,
                namespace: namespace,
                onCollapse: { withAnimation(.snappy) { _ = model.expandedItemIDs.remove(leadID) } },
            )

            if product.isLiquidCombination {
                StagedDoseByDrinkRow(
                    label: Text("Volume"),
                    text: $volume.text,
                    focus: $volumeFocused,
                    trailing: Text(verbatim: CombinationComponent.volumeUnitWord)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel),
                    onDec: { volume.adjust(-1) },
                    onInc: { volume.adjust(1) },
                    decLabel: "Lower volume",
                    incLabel: "Raise volume",
                )
            } else {
                unitStepper
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(rows) { row in
                    StagedProductComponentLine(row: row)
                }
            }
        }
        .sensoryFeedback(.increase, trigger: volume.stepTick)
        .onAppear(perform: seed)
        .onChange(of: volume.text) {
            // Compared as shown, so seeding the field with a rounded volume
            // (0.125 mL reads "0.13") never writes the rounding back.
            guard let entered = volume.enteredML, entered.doseFormatted != quantity?.doseFormatted else { return }
            model.setVolume(entered, ofCombination: product.name)
        }
        .onChange(of: quantity) {
            guard product.isLiquidCombination else { return }
            volume.show(quantity)
        }
    }

    /// −/+ around "2 pills": a solid product is counted, never typed.
    private var unitStepper: some View {
        let units = Int(quantity ?? 1)
        return HStack(spacing: Spacing.md) {
            StagedDoseStepButton(systemImage: "minus") {
                model.setUnits(units - 1, of: product)
            }
            .disabled(units <= 1)
            .accessibilityLabel("Fewer")
            Text(verbatim: product.quantityLabel(Double(units)))
                .screenTitle()
                .contentTransition(.numericText())
                .frame(minHeight: 42)
                .frame(maxWidth: .infinity)
                .background(Color.platformSecondarySystemFill, in: skinChipShape())
            StagedDoseStepButton(systemImage: "plus") {
                model.setUnits(units + 1, of: product)
            }
            .disabled(units >= CombinationComponent.maximumUnits)
            .accessibilityLabel("More")
        }
        .accessibilityElement(children: .contain)
    }

    private func seed() {
        guard product.isLiquidCombination else { return }
        volume.show(quantity)
        // A liquid is picked at a placeholder 1 mL; the volume is what the
        // row was opened to type.
        if let index = model.staged.firstIndex(where: { $0.id == leadID }), model.staged[index].wantsAmountFocus {
            model.staged[index].wantsAmountFocus = false
            volumeFocused = true
        }
    }
}

/// "Paracetamol   1,000 mg · common" — one component's share of the product,
/// following from the quantity above it.
private struct StagedProductComponentLine: View {
    let row: StagedDose

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(row.displayTitle)
                .foregroundStyle(Theme.secondaryLabel)
            Spacer(minLength: 8)
            Text(verbatim: "\(row.totalAmount.doseFormatted) \(row.unit)")
                .fontWeight(.semibold)
                .foregroundStyle(row.doseLevel?.labelColor ?? .primary)
                .contentTransition(.numericText())
            if let level = row.doseLevel {
                Middot().foregroundStyle(.tertiary)
                Text(level.displayName)
                    .textCase(.lowercase)
                    .foregroundStyle(level.labelColor)
            }
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Volume field

/// The text behind a liquid product's volume field. Always mL: the product's
/// amounts are per mL, so the field takes no other unit.
@Observable
@MainActor
final class StagedProductVolumeModel {
    var text = ""
    /// Bumped on each −/+ tap, for the step haptic.
    private(set) var stepTick = 0

    /// The typed volume in mL, `nil` until the text is a positive number.
    var enteredML: Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = DecimalInput.parse(trimmed), value > 0
        else { return nil }
        return value
    }

    /// Show the staged volume in the field, unless the field already reads it
    /// — so a value the user is part-way through typing ("0." on the way to
    /// "0.25") is never rewritten.
    func show(_ volumeML: Double?) {
        guard let volumeML, volumeML > 0 else { return }
        if let enteredML, abs(enteredML - volumeML) < 0.0001 { return }
        text = volumeML.doseFormatted
    }

    /// The −/+ step: tenths of a milliliter under 2 mL (a dropper or an oral
    /// syringe), halves up to 10 mL, whole millilitres above.
    static func step(at volumeML: Double) -> Double {
        if volumeML < 2 { return 0.1 }
        if volumeML < 10 { return 0.5 }
        return 1
    }

    /// Bump the volume by one step, snapped to the step's grid and kept at or
    /// above the smallest step. The view hands the new volume to the tray,
    /// which rescales every component of the product.
    func adjust(_ direction: Double) {
        let current = enteredML ?? 0
        // Stepping down from a boundary uses the finer step below it, so 2 mL
        // goes to 1.9, not 1.5.
        let step = Self.step(at: direction < 0 ? max(current - 0.0001, 0) : current)
        let snapped = ((current + direction * step) / step).rounded() * step
        let next = min(max(snapped, Self.step(at: 0)), CombinationComponent.maximumVolumeML)
        text = next.doseFormatted
        stepTick += 1
    }
}
