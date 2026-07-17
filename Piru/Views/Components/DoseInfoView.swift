import SwiftUI

struct DoseInfoView: View {
    let substance: Substance
    let route: RouteOfAdministration
    /// Selected salt form; `nil` (the default) selects the route's default ladder.
    var saltForm: String?
    /// Selected isomer code; `nil` (the default) selects the racemic ladder.
    var isomer: String?
    let currentDose: Double?

    private var doseRange: DoseRange? {
        substance.doseRange(for: route, saltForm: saltForm, isomer: isomer)
    }

    var body: some View {
        if let doseRange {
            VStack(alignment: .leading, spacing: 10) {
                let unit = substance.unit(for: route, saltForm: saltForm, isomer: isomer)
                DoseLevelIndicator(doseRange: doseRange, currentDose: currentDose, unit: unit)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if let threshold = doseRange.threshold {
                        GridRow {
                            doseLabel("Threshold", level: DoseLevel.threshold)
                            Text("\(threshold.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let light = doseRange.light {
                        GridRow {
                            doseLabel("Light", level: DoseLevel.light)
                            Text("\(light.lowerBound.doseFormatted) - \(light.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let common = doseRange.common {
                        GridRow {
                            doseLabel("Common", level: DoseLevel.common)
                            Text("\(common.lowerBound.doseFormatted) - \(common.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let strong = doseRange.strong {
                        GridRow {
                            doseLabel("Strong", level: DoseLevel.strong)
                            Text("\(strong.lowerBound.doseFormatted) - \(strong.upperBound.doseFormatted) \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if let heavy = doseRange.heavy {
                        GridRow {
                            doseLabel("Heavy", level: DoseLevel.heavy)
                            Text("\(heavy.doseFormatted)+ \(unit)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                elementalNote(unit: unit)

                switch doseRange.dosingPrecision(unit: unit) {
                case .critical: VolumetricDosingDisclaimer()
                case .recommended: PreciseScaleNote()
                case .none: EmptyView()
                }
            }
        }
    }

    /// Elemental-content breakdown for salts where it matters (Magnesium,
    /// Lithium…): "≈ N mg elemental" for the entered dose, else the percentage.
    /// Hidden when the selected salt has no known elemental fraction.
    @ViewBuilder
    private func elementalNote(unit: String) -> some View {
        if let fraction = substance.elementalFraction(for: route, saltForm: saltForm, isomer: isomer) {
            HStack(spacing: 5) {
                Image(systemName: "atom").imageScale(.small)
                if let currentDose, let elemental = substance.elementalAmount(of: currentDose, for: route, saltForm: saltForm, isomer: isomer) {
                    Text("≈ \(elemental.doseFormatted) \(unit) elemental", comment: "Elemental content of a salt dose")
                } else {
                    Text("\(Int((fraction * 100).rounded()))% elemental", comment: "Elemental fraction of a salt")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func doseLabel(_ label: LocalizedStringResource, level: DoseLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.swiftUIColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

// MARK: - Volumetric Dosing Disclaimer

/// The labeled threshold/light/common/strong/heavy rows that accompany a
/// ``DoseLevelIndicator``. Shared between the substance detail screen and the
/// logged-entry detail screen so both render the dose ladder identically.
struct DoseRangeRows: View {
    let doseRange: DoseRange
    let unit: String

    var body: some View {
        if let threshold = doseRange.threshold {
            row("Threshold", value: "\(threshold.doseFormatted) \(unit)", level: .threshold)
        }
        if let light = doseRange.light {
            row("Light", value: "\(light.lowerBound.doseFormatted) – \(light.upperBound.doseFormatted) \(unit)", level: .light)
        }
        if let common = doseRange.common {
            row("Common", value: "\(common.lowerBound.doseFormatted) – \(common.upperBound.doseFormatted) \(unit)", level: .common)
        }
        if let strong = doseRange.strong {
            row("Strong", value: "\(strong.lowerBound.doseFormatted) – \(strong.upperBound.doseFormatted) \(unit)", level: .strong)
        }
        if let heavy = doseRange.heavy {
            row("Heavy", value: "\(heavy.doseFormatted)+ \(unit)", level: .heavy)
        }
    }

    private func row(_ label: LocalizedStringResource, value: String, level: DoseLevel) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(level.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Duration Info View

/// One route's dosage ladder and duration timeline presented together as a
/// single card — the unit the substance detail screen switches between with
/// its route picker, and the body of the shareable drug-info image.
///
/// Unlike ``DoseRangeRows`` / ``DurationPhaseRows`` (which emit bare rows that
/// only lay out correctly when a `List` flattens them), this card builds its
/// rows with explicit stacks so it renders identically on-List *and* off-List
/// through `ImageRenderer`.
struct RouteDosingCard: View {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange?
    let duration: DurationProfile?
    /// Long-acting release window (`DurationOfAction.formattedWindow`), if any.
    var releaseWindow: String?
    /// Elemental mass fraction of the selected salt (Magnesium, Lithium…), shown
    /// as a "N% elemental" note beneath the ladder. `nil` hides it.
    var elementalFraction: Double?
    var showsDoseLadder = true
    var showsDuration = true
    /// Volumetric / precise-scale / THC safety notes — shown in the app, hidden
    /// in the compact share image.
    var showDisclaimers = true
    /// The route name as a card title. Off in the detail list (the section
    /// header and the route picker already name it); on in the share image.
    var showsTitle = true

    private var hasDosage: Bool {
        showsDoseLadder && (doses?.hasAnyValue ?? false)
    }
    private var hasDuration: Bool {
        showsDuration && duration != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsTitle {
                Text(route.localizedName)
                    .font(.headline)
            }
            if hasDosage, let doses {
                dosageBlock(doses)
            }
            if hasDosage, hasDuration {
                Divider()
            }
            if hasDuration, let duration {
                durationBlock(duration)
            }
            if let releaseWindow {
                if hasDosage || hasDuration { Divider() }
                releaseBlock(releaseWindow)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Dosage

    private func dosageBlock(_ doses: DoseRange) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("Dosage")
            VStack(spacing: 0) {
                if let threshold = doses.threshold {
                    levelRow("Threshold", value: "\(threshold.doseFormatted) \(unit)")
                }
                if let light = doses.light {
                    levelRow("Light", value: rangeText(light))
                }
                if let common = doses.common {
                    levelRow("Common", value: rangeText(common), emphasized: true)
                }
                if let strong = doses.strong {
                    levelRow("Strong", value: rangeText(strong))
                }
                if let heavy = doses.heavy {
                    levelRow("Heavy", value: "\(heavy.doseFormatted)+ \(unit)")
                }
            }
            if let elementalFraction {
                HStack(spacing: 5) {
                    Image(systemName: "atom").imageScale(.small)
                    Text("\(Int((elementalFraction * 100).rounded()))% elemental", comment: "Elemental fraction of a salt")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            }
            if showDisclaimers {
                disclaimer(for: doses)
            }
        }
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        "\(range.lowerBound.doseFormatted) – \(range.upperBound.doseFormatted) \(unit)"
    }

    @ViewBuilder
    private func disclaimer(for doses: DoseRange) -> some View {
        if unit.localizedCaseInsensitiveContains("THC") {
            THCContentNote()
        } else {
            switch doses.dosingPrecision(unit: unit) {
            case .critical: VolumetricDosingDisclaimer()
            case .recommended: PreciseScaleNote()
            case .none: EmptyView()
            }
        }
    }

    // MARK: Duration

    private func durationBlock(_ duration: DurationProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("Duration")
            VStack(spacing: 0) {
                ForEach(ExperiencePhase.allCases, id: \.self) { phase in
                    if let range = phase.range(in: duration) {
                        levelRow(phase.label, value: range.displayString)
                    }
                }
                if let total = duration.total {
                    // Accent wash alone marks Total — a divider on top of it was
                    // redundant clutter.
                    levelRow("Total", value: total.displayString, emphasized: true)
                }
            }
        }
    }

    // MARK: Release window

    private func releaseBlock(_ window: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("Release Window")
            HStack {
                Label("Release window", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                Text(window).monospacedDigit()
            }
            .font(.subheadline)
        }
    }

    // MARK: Pieces

    private func eyebrow(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.secondaryLabel)
    }

    /// A clean dose/duration row — no colored dot or bar (those read as noise).
    /// `emphasized` highlights the typical value (Common dose, Total duration)
    /// with weight and a faint accent wash that bleeds slightly past the content
    /// so the labels/values stay edge-aligned. Every row carries the same
    /// vertical padding so the emphasised one is no taller than its neighbours.
    private func levelRow(_ label: LocalizedStringResource, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(emphasized ? Color.primary : Theme.secondaryLabel)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
        .font(.subheadline)
        .fontWeight(emphasized ? .semibold : .regular)
        .padding(.vertical, 6)
        .background {
            if emphasized {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent.opacity(0.08))
                    .padding(.horizontal, -10)
            }
        }
    }
}

// MARK: - Dose Level Color
