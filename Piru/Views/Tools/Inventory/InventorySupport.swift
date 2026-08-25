import SwiftUI

// MARK: - Stock status

/// The health of an item's stock. Drives color, which — per the HIG rule the
/// spec adopts — carries meaning *only* for Low/Out; a healthy supply reads
/// neutral.
enum StockStatus: String, CaseIterable, Identifiable {
    case ok
    case low
    case out

    var id: String {
        rawValue
    }

    /// Facet label. "In Stock" rather than "OK" — the filter reads as a
    /// statement about the item, not a grade.
    var displayName: LocalizedStringResource {
        switch self {
        case .ok: "In Stock"
        case .low: "Low"
        case .out: "Out"
        }
    }

    /// Glyph used in the filter menu, standing in for the checkmark while a
    /// status is unselected.
    var icon: String {
        switch self {
        case .ok: "checkmark.circle"
        case .low: "exclamationmark.circle"
        case .out: "xmark.circle"
        }
    }

    /// Attention order (out → low → ok), so chips and rows agree on ranking.
    var sortIndex: Int {
        switch self {
        case .out: 0
        case .low: 1
        case .ok: 2
        }
    }

    /// Number / label color. Neutral (`primary`) when healthy so color is
    /// reserved for the states that need attention.
    @MainActor var numberColor: Color {
        switch self {
        case .ok: .primary
        case .low: .cautionText
        case .out: .dangerText
        }
    }

    /// Supply-bar fill. Healthy stays neutral so colour is reserved for the
    /// states that need attention.
    ///
    /// **This is the only tint the supply bar takes.** Never tint it with the
    /// substance's own color: the bar's job is remaining supply, and identity
    /// already has the row's color dot, which is where an L3 color belongs.
    @MainActor var barTint: Color {
        switch self {
        case .ok: Color.primary.opacity(0.35)
        case .low: .cautionAccent
        case .out: .dangerAccent
        }
    }
}

extension InventoryItem {
    /// Healthy / low / out, derived from the cached quantity and threshold.
    var stockStatus: StockStatus {
        if currentQuantity <= 0 { return .out }
        if let threshold = lowStockThreshold, threshold > 0, currentQuantity <= threshold { return .low }
        return .ok
    }

    /// A baseline is "set" only when it's a positive number; `nil` or `0` mean
    /// the supply bar is disabled.
    var hasBaseline: Bool {
        (baselineQuantity ?? 0) > 0
    }

    /// Fraction of the baseline currently on hand, clamped to `0...1`. `nil` when
    /// no baseline is set (no bar).
    var fillFraction: Double? {
        guard let baseline = baselineQuantity, baseline > 0 else { return nil }
        return min(1, max(0, currentQuantity / baseline))
    }

    /// Substance with its salt inline, so variants don't read as duplicates.
    ///
    /// The stored ``substance`` is the canonical name (so doses match); for
    /// display we resolve it to the library's presentation name — the same one
    /// the journal and quick-log show (e.g. canonical "Bromoketamine" →
    /// "2-Br-DCK") — falling back to the stored name for custom substances.
    @MainActor
    var displayTitle: String {
        // Batch projection — this property is hit per row in body, per keystroke
        // in the inventory search filter, and inside sort comparators; the heavy
        // per-substance resolve here cost ~21 SQL per uncached name.
        let resolved = SubstanceLibrary.lookup(substance)?.displayTitle ?? substance
        if let salt = saltForm, !salt.isEmpty {
            return "\(resolved) · \(salt)"
        }
        return resolved
    }
}

// MARK: - Run-out formatting (shared by detail + substance card)

/// The one-line supply summary shown under the amount. Always surfaces the
/// doses-left estimate when one can be made (explicit or reference dose), and
/// appends the run-out duration when the rolling-average guard passes:
///   "~24 doses · ~3 weeks left" / "~24 doses left" / "~3 weeks left".
/// Returns `nil` only when nothing can be estimated (off-library, no history).
@MainActor
func inventorySupplyLine(for item: InventoryItem, runOut: InventoryMath.RunOut?) -> String? {
    let doses = InventoryMath.dosesLeft(for: item)
    if let runOut {
        let humanized = inventoryHumanizeDays(runOut.daysLeft)
        if let doses {
            return String(localized: "~\(doses) doses · \(humanized) left")
        }
        return String(localized: "\(humanized) left")
    }
    if let doses {
        return String(localized: "~\(doses) doses left")
    }
    return nil
}

/// Humanize a days-left figure: `< 14` → days, `< 60` → weeks, else months.
func inventoryHumanizeDays(_ days: Double) -> String {
    if days < 14 {
        return String(localized: "~\(Int(days.rounded())) days")
    } else if days < 60 {
        return String(localized: "~\(Int((days / 7).rounded())) weeks")
    }
    return String(localized: "~\(Int((days / 30).rounded())) months")
}

// MARK: - Supply bar

/// A thin status-tinted supply bar. Shown only when an item has a baseline.
struct InventorySupplyBar: View {
    let fraction: Double
    let tint: Color
    var thickness: CGFloat = 6
    /// The status the tint encodes, so the bar can carry that meaning without
    /// colour when asked to. Optional because some callers only have a fraction.
    var status: StockStatus?

    /// Colour is the *only* thing distinguishing a healthy bar from a low or
    /// empty one, which fails for anyone who cannot separate those hues. Apple's
    /// guidance is to add a non-colour signal when colour carries meaning; this
    /// is that signal, gated on the setting so it costs nothing for everyone
    /// else.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * fraction))
                if differentiateWithoutColor, let status, status != .ok {
                    // A hatched overlay on the filled portion: same information,
                    // carried by texture instead of hue.
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
    }
}

// MARK: - Amount stepper

/// A "nice" step increment ≈10% of the current value, snapped to a 1 / 2.5 / 5 ×
/// 10ᵏ series — the same heuristic the quick-log dose stepper uses
/// (`DoseTray.niceStep`), so a 200,000 IU stock nudges by 25,000 while a 5 g bag
/// nudges by 0.5.
enum InventoryStep {
    static func nice(for value: Double) -> Double {
        let basis = max(abs(value), 1)
        let raw = basis / 10
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let snapped: Double = normalized < 1.75 ? 1 : normalized < 3.75 ? 2.5 : normalized < 7.5 ? 5 : 10
        return snapped * magnitude
    }
}

/// The amount editor used across the inventory forms, styled to match the
/// quick-log dose stepper: two neutral circular step buttons flanking a centered
/// capsule field with a trailing unit. The value is a real text field, so people
/// can nudge with `±` or type an exact figure. When `unitChoices` is supplied the
/// unit becomes a trailing menu (the add form, where the unit isn't yet fixed);
/// otherwise it's plain text.
struct InventoryStepperRow: View {
    @Binding var value: Double
    let unit: String
    /// What quantity this stepper edits, spoken as the VoiceOver label of the
    /// combined, adjustable element the whole row collapses into.
    let label: LocalizedStringResource
    /// A fixed dose-anchored increment basis (the substance's reference dose) so
    /// caffeine nudges in ~5 mg regardless of the current value; falls back to a
    /// value-relative step for off-library substances or a still-empty field.
    var stepBasis: Double?
    var unitChoices: [String]?
    var onUnitChange: ((String) -> Void)?

    @State private var stepTick = 0
    @FocusState private var focused: Bool

    private var step: Double {
        if let stepBasis, stepBasis > 0 { return InventoryStep.nice(for: stepBasis) }
        return InventoryStep.nice(for: value)
    }

    var body: some View {
        HStack(spacing: 12) {
            stepButton(systemImage: "minus") {
                bump(to: max(0, value - step))
            }
            amountField
            stepButton(systemImage: "plus") {
                bump(to: value + step)
            }
        }
        .phaseAnimator([1.0, 1.03], trigger: stepTick) { content, scale in
            content.scaleEffect(scale)
        } animation: { _ in
            .snappy(duration: 0.15)
        }
        .sensoryFeedback(.increase, trigger: stepTick)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: "\(value.doseFormatted) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(to: value + step)
            case .decrement: bump(to: max(0, value - step))
            @unknown default: break
            }
        }
    }

    /// The number and its unit share a baseline so "50,000 mg" reads as one
    /// figure; the pair is centered between the step buttons. The whole field is
    /// tappable to type an exact amount.
    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .focused($focused)
            unitView
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var unitView: some View {
        if let unitChoices, let onUnitChange {
            Menu {
                ForEach(unitChoices, id: \.self) { choice in
                    Button {
                        onUnitChange(choice)
                    } label: {
                        if choice == unit {
                            Label(choice, systemImage: "checkmark")
                        } else {
                            Text(choice)
                        }
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(unit)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
        } else {
            Text(unit)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "minus" ? "Decrease" : "Increase")
    }

    private func bump(to newValue: Double) {
        stepTick += 1
        // Snap to the step grid so repeated taps stay on round numbers.
        value = (newValue / step).rounded() * step
    }
}

// MARK: - Substance dot

/// The small colored dot identifying a substance, matching the journal's dots.
struct SubstanceDot: View {
    let name: String
    let colorMap: [String: Color]
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(SubstancePalette.color(for: name, colorMap: colorMap))
            .frame(width: size, height: size)
    }
}
