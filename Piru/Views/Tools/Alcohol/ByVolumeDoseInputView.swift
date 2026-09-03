import SwiftUI

/// Concentration × measured-volume dose input (alcohol by %ABV in v1). Pure
/// presentation: the parent owns `volumeText`/`abvText`/`volumeUnit` and computes
/// `grams`; this view renders the drink presets, the volume + strength fields, and
/// the live grams/standard-drinks readout. Preset taps are reported back so the
/// parent can pre-fill the fields (converting the preset volume into the chosen
/// display unit).
struct ByVolumeDoseInputView: View {
    let capability: ByVolumeDosing
    @Binding var volumeText: String
    @Binding var abvText: String
    @Binding var volumeUnit: UnitVolume

    /// Canonical grams computed by the parent from the bindings (nil until the
    /// fields hold a usable volume + strength).
    let grams: Double?
    /// Dose-level tint for the grams readout (matches the badge the manual field shows).
    let readoutColor: Color?
    /// Whether to show the tappable drink presets. Off in the quick-log tray,
    /// where the presets live on the card and this panel is the custom path.
    var showsPresets: Bool = true
    /// Optional drink name (custom drinks). When bound, a "Name" field is shown
    /// and the value is recorded in the dose's breadcrumb.
    var name: Binding<String>?
    var onSelectPreset: (DrinkPreset) -> Void = { _ in }

    /// Volume units offered in the picker — mL plus US fluid ounces. Foundation
    /// converts between them; the canonical grams always works from mL internally.
    private static let offeredUnits: [UnitVolume] = [.milliliters, .fluidOunces]

    private var standardDrinks: Double? {
        grams.map { ByVolumeDosing.standardDrinks(grams: $0) }
    }

    var body: some View {
        if showsPresets {
            presetRow
        }
        strengthField
        volumeField
        if let name {
            nameField(name)
        }
        readout
    }

    // MARK: Presets

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(capability.drinkPresets) { preset in
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: preset.systemImage)
                                .font(.title3)
                            Text(preset.name)
                                .font(.caption)
                        }
                        .frame(width: 60)
                        .padding(.vertical, Spacing.md)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.accent)
                    .accessibilityLabel(Text(preset.name))
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8))
    }

    // MARK: Fields

    private var volumeField: some View {
        HStack {
            Text("Volume")
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
            TextField("0", text: $volumeText)
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Picker("Volume unit", selection: $volumeUnit) {
                ForEach(Self.offeredUnits, id: \.self) { unit in
                    Text(unit.shortLabel).tag(unit)
                }
            }
            .labelsHidden()
        }
    }

    private var strengthField: some View {
        HStack {
            Text("Strength")
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
            TextField("0", text: $abvText)
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text("% ABV")
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func nameField(_ name: Binding<String>) -> some View {
        HStack {
            Text("Name")
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
            TextField("Optional", text: name)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }

    // MARK: Readout

    @ViewBuilder
    private var readout: some View {
        if let grams, let standardDrinks {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(grams.rounded())) g")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(readoutColor ?? .primary)
                    .contentTransition(.numericText())
                Text("ethanol · ≈ \(standardDrinks, format: .number.precision(.fractionLength(1))) standard drinks")
                    .captionSecondary()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No placeholder when empty — the volume/strength fields are right above.
    }
}

private extension UnitVolume {
    /// Compact label for the unit picker.
    var shortLabel: String {
        switch self {
        case .milliliters: "mL"
        case .fluidOunces: "fl oz"
        default: symbol
        }
    }
}

// MARK: - Shared defaults / formatting

/// Preferred-unit persistence + numeric formatting shared by the by-volume input
/// and the forms that host it (EntryDetailView, DoseTray).
enum ByVolumeDefaults {
    private static let unitKey = "byVolumePreferredVolumeUnit"

    /// The volume unit to pre-select — the user's last choice, defaulting to mL on
    /// first use. Globally mL dominates (and US wine/spirits are mL-labeled); a
    /// US beer drinker switches to fl oz once and it sticks.
    static var preferredVolumeUnit: UnitVolume {
        get {
            UserDefaults.standard.string(forKey: unitKey) == "flOz" ? .fluidOunces : .milliliters
        }
        set {
            UserDefaults.standard.set(newValue == .fluidOunces ? "flOz" : "mL", forKey: unitKey)
        }
    }

    /// Trim a numeric field value: integer when whole, else one decimal.
    static func format(_ value: Double) -> String {
        ByVolumeDosing.formatTrimmed(value)
    }
}
