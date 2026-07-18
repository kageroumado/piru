import SwiftUI

/// How much detail the shared substance card shows. The user picks this in the
/// share sheet; the card re-renders live.
enum ShareDetailLevel: String, CaseIterable, Identifiable {
    case minimal
    case standard
    case rich

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .minimal: "Minimal"
        case .standard: "Standard"
        case .rich: "Rich"
        }
    }

    var icon: String {
        switch self {
        case .minimal: "rectangle"
        case .standard: "rectangle.grid.1x2"
        case .rich: "rectangle.grid.2x2"
        }
    }
}

/// The colorful, roughly-square "specimen card" rendered to an image when the
/// user shares a substance. Self-contained (no `@Environment`, all data passed
/// in) so `ImageRenderer` can draw it off-screen. The whole card is tinted by
/// the substance's category color — a rich diagonal wash — with the molecule
/// skeleton as a frosted hero and the dose ladder / effects layered by
/// ``ShareDetailLevel``.
struct SubstanceShareCard: View {
    let substance: Substance
    let route: SubstanceRoute?
    let molecule: MoleculeStructure?
    /// drug.community reported effects with per-effect report counts, used for the
    /// Rich card's frequency viz. Empty for compounds without dc coverage.
    var reportedEffects: [ReportedEffect] = []
    let detail: ShareDetailLevel

    /// Card width; height follows from the content (roughly square).
    static let width: CGFloat = 440

    private var accent: Color {
        substance.category.color
    }

    /// A vibrant diagonal wash that stays in the *class* hue — the category color
    /// brightened at the top-left, only gently deepened toward the bottom-right
    /// (not toward black) so an empathogen reads pink-red, a stimulant orange,
    /// etc., while white text and the skeleton still have enough contrast.
    private var background: some View {
        LinearGradient(
            colors: [
                accent.mix(with: .white, by: 0.16),
                accent.mix(with: .black, by: 0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay(
            RadialGradient(
                colors: [accent.mix(with: .white, by: 0.34).opacity(0.6), .clear],
                center: .topTrailing, startRadius: 0, endRadius: Self.width * 0.95,
            ),
        )
    }

    private var doseText: [Int: String] {
        guard let route else { return [:] }
        return EffectsIntensityModel.bandDoseText(from: route.doses, unit: route.unit)
    }

    private var topEffects: [String] {
        substance.subjectiveEffects.prefix(6).map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if molecule != nil || detail != .minimal {
                heroRow
            }
            if detail != .minimal, !doseText.isEmpty {
                doseLadder
                if detail == .rich, let total = route?.duration?.total?.displayString {
                    durationLine(total)
                }
            }
            if detail == .rich, !frequencyEffects.isEmpty {
                frequencyBars
            } else if detail != .minimal, !topEffects.isEmpty {
                effectChips
            }
            if detail == .rich {
                if chemistryStats.count >= 2 { chemistryStrip }
                if let moa = substance.mechanismOfAction?.summary, !moa.isEmpty { moaLine(moa) }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(26)
        .frame(width: Self.width, alignment: .leading)
        .background(background)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(substance.displayTitle)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            HStack(spacing: 8) {
                categoryChip
                if let formula = substance.formula {
                    Text(formula)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }

    private var categoryChip: some View {
        Text(substance.category.displayName)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
    }

    // MARK: hero (molecule specimen)

    private var heroRow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.white.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.15), lineWidth: 1))
            if let molecule {
                MoleculeStructureView(structure: molecule, color: .white, lineWidth: 2.2)
                    .padding(18)
            } else {
                Image(systemName: "atom")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: detail == .minimal ? 220 : 168)
    }

    // MARK: dose ladder

    private static let ladder: [(Int, LocalizedStringKey)] = [
        (0, "Threshold"), (1, "Light"), (2, "Common"), (3, "Strong"), (4, "Heavy"),
    ]

    private var doseLadder: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(route.map { "Dose · \($0.route.displayName)" } ?? "Dose")
            ForEach(Self.ladder, id: \.0) { index, name in
                if let text = doseText[index] {
                    HStack {
                        Text(name)
                            .font(.subheadline.weight(index == 2 ? .bold : .regular))
                            .foregroundStyle(index == 2 ? .white : .white.opacity(0.75))
                        Spacer()
                        Text(text)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) {
                        if index != 4, doseText[index + 1] != nil {
                            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func durationLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Text("Total \(text)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: effects — simple chips (Standard)

    private var effectChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Reported effects")
            FlowChips(items: topEffects)
        }
    }

    // MARK: effects — frequency bars (Rich)

    /// Top reported effects by report count — the drug.community frequency signal.
    private var frequencyEffects: [ReportedEffect] {
        Array(reportedEffects.sorted { $0.reportCount > $1.reportCount }.prefix(5))
    }

    private var frequencyBars: some View {
        let maxCount = max(frequencyEffects.map(\.reportCount).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Most reported")
            ForEach(frequencyEffects) { effect in
                HStack(spacing: 10) {
                    Circle().fill(effect.domain.color).frame(width: 7, height: 7)
                    Text(effect.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(effect.domain.color.opacity(0.9))
                                .frame(width: max(8, geo.size.width * CGFloat(effect.reportCount) / CGFloat(maxCount)))
                        }
                    }
                    .frame(width: 84, height: 7)
                    Text("\(effect.reportCount)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    // MARK: chemistry strip (Rich)

    /// Compact physicochemical stats for the Rich card — molar mass + the two most
    /// telling constants. Only shown when at least two are present.
    private var chemistryStats: [(LocalizedStringKey, String)] {
        var out: [(LocalizedStringKey, String)] = []
        if let mass = substance.molarMass {
            out.append(("MOLAR MASS", "\(Int(mass.rounded())) g/mol"))
        }
        if let logP = substance.physicochemical?.logP {
            out.append(("LOGP", logP.formatted(.number.precision(.fractionLength(1)))))
        }
        if let tpsa = substance.physicochemical?.tpsa {
            out.append(("TPSA", "\(Int(tpsa.rounded())) Å²"))
        }
        return out
    }

    private var chemistryStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(chemistryStats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.0)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(stat.1)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func moaLine(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Pharmacology")
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image("AppIconArtwork")
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 0.5),
                )
            Text("Piru")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
            Spacer()
            Text("kagerou.glass/piru")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.bottom, 6)
    }
}

/// A minimal wrapping chip row for effect names — lays chips out left-to-right,
/// wrapping to new lines. Self-contained for `ImageRenderer` (no `Layout`
/// dependency on measured environment).
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.16), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }
}
