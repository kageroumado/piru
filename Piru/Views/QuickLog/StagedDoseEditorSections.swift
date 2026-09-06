import SwiftUI

// MARK: - Header

/// The editor's title row: name, recognition subtitle, the disclosure chevron
/// that collapses it, and the trash.
struct StagedDoseEditorHeader: View {
    let title: String
    let subtitle: String?
    let morphID: UUID
    let namespace: Namespace.ID
    let onCollapse: () -> Void
    let onRemove: () -> Void

    var body: some View {
        // 8pt chevron→text gap, matching the collapsed row exactly so the
        // matched-geometry morph doesn't shift the leading column.
        HStack(spacing: Spacing.md) {
            // The title + chevron are the collapse target — merged into ONE
            // element carrying the "Collapses the editor" hint. Keeping the
            // trash a separate sibling stops that hint from bleeding onto it
            // (it used to read "trash … Collapses the editor").
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 1) {
                    // No "recognized" seal beside the name: it fired only when
                    // the typed alias resolved to a different canonical entry,
                    // which the subtitle underneath already says in words, and
                    // a green seal against a substance name reads as a claim
                    // about how much to trust it. A custom substance got no
                    // seal at all, the opposite of how testers read it.
                    Text(title)
                        .font(.body.weight(.semibold))
                        .trayMorph(id: "title-\(morphID)", in: namespace, isSource: false)
                    if let subtitle {
                        Text(subtitle)
                            .captionSecondary()
                            .lineLimit(1)
                    }
                }
                Spacer()
                // Same glyph as the collapsed row, rotated to point down
                // (expanded, per Apple's disclosure convention) — trailing,
                // where the row's chevron now lives, so the matched-geometry
                // swap morphs it in place like a rotation.
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 16)
                    .trayMorph(id: "chevron-\(morphID)", in: namespace, isSource: false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onCollapse)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Collapses the editor")

            // 42pt — the stepper-button size, so the trash sits on the same
            // vertical line as the + button below it.
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove dose")
        }
    }
}

// MARK: - Shared controls

/// 42pt circles — the same height as the amount field, so a stepper row reads as
/// one control at one size.
struct StagedDoseStepButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(Color.platformSecondarySystemFill, in: Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
    }
}

/// "= 150 + 182 mg · light" — the breakdown and dose-level line under a stepper.
struct StagedDoseReadout: View {
    let breakdown: String?
    let level: DoseLevel?

    var body: some View {
        HStack(spacing: 5) {
            if let breakdown {
                Text(verbatim: breakdown)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if breakdown != nil, level != nil {
                Middot().foregroundStyle(.tertiary)
            }
            if let level {
                Text(level.displayName)
                    .textCase(.lowercase)
                    .foregroundStyle(level.labelColor)
            }
        }
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity)
        // One spoken element ("13 mg, light") instead of a fragmented run that
        // includes a lone "·" stop.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Amount stepper

/// The amount −/+ stepper and its breakdown/level readout — the default for every
/// substance, and the "By Weight" mode for alcohol.
struct StagedDoseStepperBlock: View {
    @Binding var item: StagedDose
    @Bindable var model: StagedDoseEditorModel
    let namespace: Namespace.ID
    var amountFocus: FocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Stepper increment anchored to the substance's reference dose when the
    /// library knows one (LSD → 10 µg, pregabalin → 25 mg), falling back to a
    /// magnitude table for unknowns.
    private var amountStep: Double {
        DoseStepping.step(referenceDose: item.referenceDose, amount: item.amount)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: Spacing.md) {
                StagedDoseStepButton(systemImage: "minus") {
                    let next = max(0, item.amount - amountStep)
                    model.setAmount(next, item: &item)
                }
                .accessibilityLabel("Decrease amount")
                amountField
                StagedDoseStepButton(systemImage: "plus") {
                    let next = item.amount + amountStep
                    model.setAmount(next, item: &item)
                }
                .accessibilityLabel("Increase amount")
            }
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.03], trigger: model.stepTick) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .snappy(duration: 0.15)
            }
            if item.breakdownLabel != nil || item.doseLevel != nil {
                StagedDoseReadout(
                    breakdown: item.breakdownLabel.map { "= \($0) \(item.unit)" },
                    level: item.doseLevel,
                )
            }
        }
    }

    /// The amount is centered in the pill itself; the unit menu is a trailing
    /// overlay so it never shifts the number off-center.
    private var amountField: some View {
        TextField("0", text: $model.amountText)
            .decimalKeyboard()
            .focused(amountFocus)
            .multilineTextAlignment(.center)
            .screenTitle()
            .onChange(of: model.amountText) {
                model.commitAmountText(to: &item)
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            // Same fill as the −/+ buttons — one control system, one shade.
            .background(Color.platformSecondarySystemFill, in: Capsule())
            // Label the field *before* the overlay, so the "Amount" label
            // sticks to the text field and doesn't shadow the unit menu
            // composited on top (which keeps its own "Dose unit" label).
            .accessibilityLabel("Amount")
            .overlay(alignment: .trailing) {
                StagedDoseUnitMenu(unit: $item.unit, choices: model.unitMenuChoices(current: item.unit))
                    .padding(.trailing, Spacing.xl)
            }
            .trayMorph(id: "amount-\(item.id)", in: namespace, isSource: false)
    }
}

/// The unit picker overlaid on the amount field.
struct StagedDoseUnitMenu: View {
    @Binding var unit: String
    let choices: [String]

    var body: some View {
        // Decoupled + fixed-size like the route pill: as a `Menu` label the
        // UIKit button sized "mg" outside the transaction, so the amount field's
        // morph squeezed it into two stacked letters ("m / g") mid-flight.
        HStack(spacing: Spacing.xxs) {
            Text(unit)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.secondaryLabel)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        unit = choice
                    } label: {
                        if choice == unit {
                            Label(choice, systemImage: "checkmark")
                        } else {
                            Text(choice)
                        }
                    }
                }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .accessibilityLabel("Dose unit")
            .accessibilityValue(unit)
        }
    }
}

// MARK: - By Drink (strength + volume steppers)

/// Strength (%ABV) and Volume steppers — the exact grams-picker control (42pt
/// capsule, centered number, unit as a trailing overlay) — plus a live grams /
/// standard-drinks readout. Tap the number to type; use −/+ to nudge without the
/// keyboard.
struct StagedDoseByDrinkBlock: View {
    @Bindable var model: StagedDoseEditorModel
    /// The concentration capability — drives the copy (Strength/% vs
    /// Concentration/(mg/mL)) and the readout unit (g + std drinks vs mg).
    let capability: ByVolumeDosing
    /// The converted canonical amount (grams of ethanol, or mg of ester).
    let grams: Double?
    let level: DoseLevel?
    var abvFocus: FocusState<Bool>.Binding
    var volumeFocus: FocusState<Bool>.Binding

    private var strengthStep: Double {
        capability.isMassPerVolume ? 5 : 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            StagedDoseByDrinkRow(
                label: Text(capability.strengthFieldLabel),
                text: $model.abvText,
                focus: abvFocus,
                trailing: Text(verbatim: capability.strengthUnitLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel),
                onDec: { model.adjustStrength(-strengthStep, capability: capability) },
                onInc: { model.adjustStrength(strengthStep, capability: capability) },
                decLabel: "Lower strength",
                incLabel: "Raise strength",
            )
            StagedDoseByDrinkRow(
                label: Text("Volume"),
                text: $model.volumeText,
                focus: volumeFocus,
                trailing: StagedDoseVolumeUnitMenu(unit: $model.volumeUnit),
                onDec: { model.adjustVolume(-1, capability: capability) },
                onInc: { model.adjustVolume(1, capability: capability) },
                decLabel: "Lower volume",
                incLabel: "Raise volume",
            )
            readout
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let grams {
            HStack(spacing: Spacing.sm) {
                Text("\(Int(grams.rounded())) \(capability.canonicalUnit)")
                    .fontWeight(.semibold)
                    .foregroundStyle(level?.labelColor ?? .primary)
                    .contentTransition(.numericText())
                if !capability.isMassPerVolume {
                    // The US-standard-drink gloss is alcohol-only.
                    let drinks = ByVolumeDosing.standardDrinks(grams: grams)
                    Text("· \(drinks, format: .number.precision(.fractionLength(1))) std drinks")
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if let level {
                    Middot().foregroundStyle(.tertiary)
                    Text(level.displayName)
                        .textCase(.lowercase)
                        .foregroundStyle(level.labelColor)
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            // One spoken element instead of a run broken by a lone "·" stop.
            .accessibilityElement(children: .combine)
        } else if capability.isMassPerVolume {
            // A volume with no concentration can't become a dose — the mg on the
            // syringe depend entirely on the vial's mg/mL. Say so where it's typed.
            Text("Enter the vial's concentration — a volume alone isn't a dose.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No placeholder for the empty alcohol case — the steppers are right above.
    }
}

/// One stepper row in the grams-picker shape: the number is centered in the
/// capsule itself; the unit is a trailing overlay so it never shifts the number
/// off-center (mirrors the amount field).
struct StagedDoseByDrinkRow<Trailing: View>: View {
    let label: Text
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let trailing: Trailing
    let onDec: () -> Void
    let onInc: () -> Void
    let decLabel: LocalizedStringKey
    let incLabel: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            label
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            HStack(spacing: Spacing.md) {
                StagedDoseStepButton(systemImage: "minus", action: onDec)
                    .accessibilityLabel(decLabel)
                TextField("0", text: $text)
                    .decimalKeyboard()
                    .focused(focus)
                    .multilineTextAlignment(.center)
                    .screenTitle()
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .background(Color.platformSecondarySystemFill, in: Capsule())
                    // Label before the overlay so it scopes to the field, not
                    // the unit menu / "%" composited on top of it.
                    .accessibilityLabel(label)
                    .overlay(alignment: .trailing) {
                        trailing
                            .padding(.trailing, Spacing.xl)
                    }
                StagedDoseStepButton(systemImage: "plus", action: onInc)
                    .accessibilityLabel(incLabel)
            }
        }
    }
}

struct StagedDoseVolumeUnitMenu: View {
    @Binding var unit: UnitVolume

    var body: some View {
        Menu {
            Picker("Volume unit", selection: $unit) {
                Text(verbatim: "mL").tag(UnitVolume.milliliters)
                Text(verbatim: "fl oz").tag(UnitVolume.fluidOunces)
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(unit == .fluidOunces ? "fl oz" : "mL")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Volume unit")
    }
}

// MARK: - Pill picker (branded fixed-strength meds)

/// The pill-entry surface: strength chips (mirroring the drink-preset chips),
/// then a tablet-count stepper — or the plain mg stepper when the user drops to
/// free-form via the "mg…" chip.
struct StagedDosePillBlock: View {
    @Binding var item: StagedDose
    let model: StagedDoseEditorModel
    let product: ProductStrengths
    let pillHeight: CGFloat
    let namespace: Namespace.ID
    var amountFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(product.strengths, id: \.self) { mg in
                        StagedDoseStrengthChip(
                            mg: mg,
                            selected: model.pillStrength == mg,
                            pillHeight: pillHeight,
                            action: { model.selectStrength(mg, item: &item) },
                        )
                    }
                    StagedDoseFreeFormChip(
                        selected: model.pillStrength == nil,
                        pillHeight: pillHeight,
                        action: { model.selectFreeForm(item: item) },
                    )
                }
                .padding(.horizontal, Spacing.xxs)
            }
            if model.pillStrength != nil {
                StagedDosePillCountRow(item: $item, model: model, product: product)
            } else {
                StagedDoseStepperBlock(
                    item: $item,
                    model: model,
                    namespace: namespace,
                    amountFocus: amountFocus,
                )
            }
        }
    }
}

struct StagedDoseStrengthChip: View {
    let mg: Double
    let selected: Bool
    let pillHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Text(mg.doseFormatted)
                    .sectionLabel()
                Text(verbatim: "mg")
                    .font(.caption2)
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accent.opacity(0.85)) : AnyShapeStyle(Theme.secondaryLabel))
            }
            .padding(.horizontal, 13)
            .frame(height: pillHeight)
            .background(
                selected ? AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Color.platformSecondarySystemFill),
                in: Capsule(),
            )
            .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
            .overlay(Capsule().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(mg.doseFormatted) mg"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct StagedDoseFreeFormChip: View {
    let selected: Bool
    let pillHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "mg…")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .frame(height: pillHeight)
                .background(Color.platformSecondarySystemFill, in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.secondaryLabel))
                .overlay(Capsule().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Custom milligrams"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// −/+ over the pill count, with the "1 tablet · 36 mg" readout and the live
/// dose-level, so a branded pill reads in the unit the user holds.
struct StagedDosePillCountRow: View {
    @Binding var item: StagedDose
    let model: StagedDoseEditorModel
    let product: ProductStrengths

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: Spacing.md) {
                StagedDoseStepButton(systemImage: "minus") {
                    model.setPillCount(model.pillCount - 1, item: &item)
                }
                .accessibilityLabel("Fewer pills")
                Text(quantityLabel)
                    .screenTitle()
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .background(Color.platformSecondarySystemFill, in: Capsule())
                    .accessibilityLabel("Quantity")
                    .accessibilityValue(quantityLabel)
                StagedDoseStepButton(systemImage: "plus") {
                    model.setPillCount(model.pillCount + 1, item: &item)
                }
                .accessibilityLabel("More pills")
            }
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.03], trigger: model.stepTick) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .snappy(duration: 0.15)
            }
            StagedDoseReadout(
                breakdown: "= \(item.totalAmount.doseFormatted) \(item.unit)",
                level: item.doseLevel,
            )
        }
    }

    /// Localized count noun for a form — "1 tablet" / "2 capsules". Kept simple
    /// (English adds a trailing "s"; zh has no plural); the count shows numerically.
    private var quantityLabel: String {
        let n = "\(model.pillCount)"
        switch product.form {
        case "capsule":
            return model.pillCount == 1 ? String(localized: "\(n) capsule") : String(localized: "\(n) capsules")
        default:
            return model.pillCount == 1 ? String(localized: "\(n) tablet") : String(localized: "\(n) tablets")
        }
    }
}

// MARK: - Pills row

/// Behaves like the location chip: neutral "Note" when empty, accent-tinted with
/// the note's first words once one exists. Toggles the multi-line editor below.
struct StagedDoseNotePill: View {
    let note: String
    let pillHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(note.isEmpty ? String(localized: "Note") : note)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            .background(
                note.isEmpty ? AnyShapeStyle(Color.platformSecondarySystemFill) : AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)),
                in: Capsule(),
            )
            .foregroundStyle(note.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .leading)
        .accessibilityLabel("Note")
        .accessibilityValue(note.isEmpty ? Text("None") : Text(note))
        .accessibilityHint("Adds a note to this dose")
    }
}

/// Per-dose "had grapefruit" toggle — shown only for CYP3A4-heavy substrates when
/// grapefruit logging is enabled in Settings. Tinted when on; recorded on the
/// committed dose.
struct StagedDoseGrapefruitPill: View {
    @Binding var isOn: Bool
    let pillHeight: CGFloat

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            Image(systemName: "carrot")
                .imageScale(.small)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: pillHeight)
                .background(
                    isOn ? AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Color.platformSecondarySystemFill),
                    in: Capsule(),
                )
                .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Had grapefruit with this dose"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The route pill and its menu.
struct StagedDoseRouteMenu: View {
    @Binding var item: StagedDose
    let pillHeight: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        // Decoupled like the When chip: the visible pill is plain SwiftUI with
        // the Menu overlaid as an invisible tap target. As a `Menu` *label* the
        // pill was sized by the UIKit menu button, which applies the width
        // outside the SwiftUI transaction — so the tray's expand/collapse morph
        // interpolated a stale frame and clipped the label ("Sublingual" →
        // "subling…"). `fixedSize` pins it to its ideal width for the whole
        // animation; the overlay keeps the width SwiftUI-owned.
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle")
                .imageScale(.small)
            Text(item.route.localizedName)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .frame(height: pillHeight)
        .background(Color.platformSecondarySystemFill, in: Capsule())
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                ForEach(RouteOfAdministration.allCases) { route in
                    Button {
                        item.route = route
                        // saltForm is the shared salt/ester axis: a real salt route
                        // defaults to its first form, but an ester is only ever
                        // kept-or-cleared (never assumed), so pick the reconciler
                        // that fits which axis this substance uses.
                        let saltForms = item.librarySubstance?.saltForms(for: route) ?? []
                        if saltForms.isEmpty {
                            EsterPicker.revalidate(&item.saltForm, against: item.esterForms(for: route))
                        } else {
                            SaltPicker.revalidate(&item.saltForm, against: saltForms)
                        }
                        IsomerPicker.revalidate(
                            &item.isomer,
                            against: (item.librarySubstance?.isomerOptions(for: route) ?? []).map {
                                IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
                            },
                        )
                    } label: {
                        if route == item.route {
                            Label(String(localized: route.localizedName), systemImage: "checkmark")
                        } else {
                            Text(route.localizedName)
                        }
                    }
                }
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel("Route")
            .accessibilityValue(item.route.localizedName)
        }
        .trayMorph(id: "route-\(item.id)", in: namespace, isSource: false)
    }
}

// MARK: - Note editor

/// Multi-line note editor — a single line that grows with its content, with an
/// explicit close.
struct StagedDoseNoteEditor: View {
    @Binding var note: String
    var focus: FocusState<Bool>.Binding
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            TextField("Add note…", text: $note, axis: .vertical)
                .font(.footnote.weight(.medium))
                .lineLimit(1 ... 6)
                .focused(focus)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
