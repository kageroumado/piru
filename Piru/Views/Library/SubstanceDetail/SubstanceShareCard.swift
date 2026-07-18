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
    let detail: ShareDetailLevel

    /// Card width; height follows from the content (roughly square).
    static let width: CGFloat = 440

    private var accent: Color {
        substance.category.color
    }

    /// A rich diagonal wash of the category color — stays saturated top-left,
    /// deepens toward black-ish bottom-right so text and the skeleton read.
    private var background: some View {
        LinearGradient(
            colors: [
                accent.mix(with: .white, by: 0.10),
                accent.mix(with: .black, by: 0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay(
            RadialGradient(
                colors: [accent.mix(with: .white, by: 0.28).opacity(0.55), .clear],
                center: .topTrailing, startRadius: 0, endRadius: Self.width * 0.9,
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
        VStack(alignment: .leading, spacing: 20) {
            header
            if molecule != nil || detail != .minimal {
                heroRow
            }
            if detail != .minimal, !doseText.isEmpty {
                doseLadder
            }
            if detail == .rich, let total = route?.duration?.total?.displayString {
                durationLine(total)
            }
            if detail != .minimal, !topEffects.isEmpty {
                effectChips
            }
            if detail == .rich, let moa = substance.mechanismOfAction?.summary, !moa.isEmpty {
                moaLine(moa)
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
                if let iupac = substance.iupacName ?? substance.formula {
                    Text(iupac)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    // MARK: effects

    private var effectChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Reported effects")
            FlowChips(items: topEffects)
        }
    }

    private func moaLine(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "pills.fill")
                .font(.footnote.weight(.bold))
            Text("Piru")
                .font(.subheadline.weight(.heavy).width(.expanded))
            Spacer()
            Text("kagerou.glass/piru")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
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
