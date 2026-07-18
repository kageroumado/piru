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
}

/// The shareable substance card, tinted by the substance's category color.
///
/// - **Minimal / Standard** render a compact single column (shared top: title,
///   molecule, dose ladder, duration; Standard adds the reported-effect bars).
/// - **Rich** renders a wide, symmetric "specimen plate" — two matched hero
///   panels (molecule ∣ effect curve), two balanced data columns (dose ∣
///   effects), and a full-width pharmacology section (mechanism, the
///   dopamine↔serotonin lean bar, and the graded receptor table). Designed to
///   read like a plate you'd print in a pharmacopeia.
///
/// Self-contained (no `@Environment`, all data passed in) so `ImageRenderer` can
/// draw it off-screen.
struct SubstanceShareCard: View {
    let substance: Substance
    let route: SubstanceRoute?
    let molecule: MoleculeStructure?
    var reportedEffects: [ReportedEffect] = []
    var mechanism: MechanismOfAction?
    var monoamineProfile: MonoamineProfile?
    let detail: ShareDetailLevel

    private var cardWidth: CGFloat {
        detail == .rich ? 680 : 440
    }
    private var accent: Color {
        substance.category.color
    }

    // MARK: shared data

    private var doseText: [Int: String] {
        guard let route else { return [:] }
        return EffectsIntensityModel.bandDoseText(from: route.doses, unit: route.unit)
    }

    private var topEffects: [String] {
        substance.subjectiveEffects.prefix(6).map(\.name)
    }

    private var frequencyEffects: [ReportedEffect] {
        Array(reportedEffects.sorted { $0.reportCount > $1.reportCount }.prefix(5))
    }

    private var hasCurve: Bool {
        (route?.duration?.phaseBoundaries.offsetEnd ?? 0) > 0
    }

    // MARK: body

    var body: some View {
        Group {
            if detail == .rich {
                richPlate
            } else {
                compactCard
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(plateBorder)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    /// The card's outer corner radius; the plate border and panels round
    /// concentrically off it.
    private static let cornerRadius: CGFloat = 34
    /// Inset of the plate border from the card edge.
    private static let borderInset: CGFloat = 13

    /// A vibrant diagonal wash that stays in the class hue (empathogen pink-red,
    /// stimulant orange…) — brightened at the top-left, gently deepened toward the
    /// bottom-right so white text and the skeleton keep contrast without ever
    /// crushing to black.
    private var background: some View {
        LinearGradient(
            colors: [accent.mix(with: .white, by: 0.16), accent.mix(with: .black, by: 0.30)],
            startPoint: .topLeading, endPoint: .bottomTrailing,
        )
        .overlay(
            RadialGradient(
                colors: [accent.mix(with: .white, by: 0.34).opacity(0.6), .clear],
                center: .topTrailing, startRadius: 0, endRadius: cardWidth * 0.95,
            ),
        )
    }

    /// A hairline inset frame — the "plate" edge that makes the card read as a
    /// printed specimen. Rounded and concentric with the card's outer corner
    /// (radius − inset), matching the rounding of the molecule/curve panels.
    private var plateBorder: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius - Self.borderInset, style: .continuous)
            .inset(by: Self.borderInset)
            .stroke(.white.opacity(0.22), lineWidth: 1)
            .allowsHitTesting(false)
    }

    // MARK: - Compact (Minimal / Standard)

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            heroPanel(height: 176)
            if !doseText.isEmpty { doseLadder }
            if let total = route?.duration?.total?.displayString { durationLine(total) }
            if detail != .minimal {
                if !frequencyEffects.isEmpty {
                    frequencyBars
                } else if !topEffects.isEmpty {
                    effectChips
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(26)
    }

    // MARK: - Rich plate

    private var richPlate: some View {
        VStack(spacing: 22) {
            centeredHeader
            HStack(spacing: 18) {
                heroPanel(height: 190)
                curvePanel.frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 26) {
                plateColumn("Dose · \(route?.route.displayName ?? "")") { doseLadderRows }
                plateColumn("Most reported") { effectsColumnBody }
            }
            if let mechanism, !mechanism.summary.isEmpty {
                sectionRule("Pharmacology")
                pharmacologyBody(mechanism)
            }
            richFooter
        }
        .padding(34)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(substance.displayTitle)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            subtitleRow
        }
    }

    private var centeredHeader: some View {
        VStack(spacing: 10) {
            Text(substance.displayTitle)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            subtitleRow
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var subtitleRow: some View {
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

    private var categoryChip: some View {
        Text(substance.category.displayName)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
    }

    // MARK: hero (molecule specimen)

    private func heroPanel(height: CGFloat) -> some View {
        panel {
            if let molecule {
                MoleculeStructureView(structure: molecule, color: .white, lineWidth: 2.2)
                    .padding(18)
            } else {
                Image(systemName: "atom")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: height)
    }

    // MARK: dose ladder

    private static let ladder: [(Int, LocalizedStringKey)] = [
        (0, "Threshold"), (1, "Light"), (2, "Common"), (3, "Strong"), (4, "Heavy"),
    ]

    private var doseLadder: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(route.map { "Dose · \($0.route.displayName)" } ?? "Dose")
            doseLadderRows
        }
    }

    /// Fixed row height shared by the dose ladder and the effect bars so the two
    /// Rich-plate columns line up row-for-row.
    private static let dataRowHeight: CGFloat = 34

    private var doseLadderRows: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .frame(height: Self.dataRowHeight)
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
            Image(systemName: "clock").font(.footnote).foregroundStyle(.white.opacity(0.7))
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

    /// Compact report count — "1.2k" past a thousand, plain otherwise.
    private static func compactCount(_ n: Int) -> String {
        n >= 1_000 ? "\(n / 1_000).\((n % 1_000) / 100)k" : "\(n)"
    }

    private var frequencyBars: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Most reported")
            effectsColumnBody
        }
    }

    /// The reported-effect bars without a heading — reused in the compact card
    /// (under a section label) and the Rich plate's right column.
    private var effectsColumnBody: some View {
        let maxCount = max(frequencyEffects.map(\.reportCount).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
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
                    .frame(width: 64, height: 7)
                    Text(verbatim: Self.compactCount(effect.reportCount))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(height: Self.dataRowHeight)
            }
        }
    }

    // MARK: effect curve + phase labels (Rich)

    private var curvePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("EFFECT OVER TIME")
                    .font(.system(size: 8, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                if let boundaries = route?.duration?.phaseBoundaries {
                    ZStack {
                        EffectCurveShape(boundaries: boundaries)
                            .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                        EffectCurveShape(boundaries: boundaries, strokeOnly: true)
                            .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 52)
                }
                if let duration = route?.duration {
                    phaseLabels(duration).frame(height: 46)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .frame(height: 190)
    }

    /// Phase durations written under the curve, each centered on its segment and
    /// staggered onto two rows so the numbers never overlap. Durations are
    /// abbreviated (30–45m, 1.5–2.5h) to keep them compact.
    private func phaseLabels(_ duration: DurationProfile) -> some View {
        let b = duration.phaseBoundaries
        let total = max(b.offsetEnd, 1)
        var phases: [(name: LocalizedStringKey, text: String, mid: CGFloat)] = []
        func add(_ name: LocalizedStringKey, _ range: DurationRange?, _ start: Double, _ end: Double) {
            guard let range else { return }
            phases.append((name, Self.compactDuration(range), CGFloat((start + end) / 2 / total)))
        }
        add("Onset", duration.onset, 0, b.onsetEnd)
        add("Come-up", duration.comeup, b.onsetEnd, b.comeupEnd)
        add("Peak", duration.peak, b.comeupEnd, b.peakEnd)
        add("Offset", duration.offset, b.peakEnd, b.offsetEnd)
        return GeometryReader { geo in
            ForEach(Array(phases.enumerated()), id: \.offset) { i, phase in
                VStack(spacing: 1) {
                    Text(phase.name)
                        .font(.system(size: 8, weight: .bold)).tracking(0.3)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: phase.text)
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                }
                .fixedSize()
                .position(
                    x: min(max(geo.size.width * phase.mid, 24), geo.size.width - 24),
                    y: i.isMultiple(of: 2) ? 13 : 34,
                )
            }
        }
    }

    /// Compact duration like "~30–45m", "~1.5–2.5h", or a mixed "~90m–2.5h" —
    /// the unit is written once when both bounds share it.
    private static func compactDuration(_ range: DurationRange) -> String {
        func part(_ minutes: Double) -> (value: String, unit: String) {
            if minutes >= 120 {
                let h = (minutes / 60 * 2).rounded() / 2
                return (h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h), "h")
            }
            return ("\(Int(minutes.rounded()))", "m")
        }
        let lo = part(range.min), hi = part(range.max)
        if lo.value == hi.value, lo.unit == hi.unit { return "~\(lo.value)\(lo.unit)" }
        if lo.unit == hi.unit { return "~\(lo.value)–\(hi.value)\(lo.unit)" }
        return "~\(lo.value)\(lo.unit)–\(hi.value)\(hi.unit)"
    }

    // MARK: pharmacology (Rich)

    private func pharmacologyBody(_ mechanism: MechanismOfAction) -> some View {
        VStack(spacing: 18) {
            if let monoamineProfile, monoamineProfile.leanPosition != nil {
                leanBarHero(monoamineProfile)
            } else {
                Text(mechanism.summary)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 26) {
                bindingTable(mechanism).frame(maxWidth: .infinity, alignment: .leading)
                // The prose mechanism is the least-important text — kept small as a
                // secondary caption beside the receptor table.
                Text(mechanism.summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The dopamine↔serotonin lean bar as the pharmacology hero — a wide gradient
    /// with a marker, neurotransmitter chips at each end (Serotonin / Dopamine —
    /// friendlier than SERT/DAT), the mechanism label, and the lean summary. The
    /// bar *shows* the character instead of spelling it out.
    private func leanBarHero(_ profile: MonoamineProfile) -> some View {
        VStack(spacing: 12) {
            Text(profile.mechanismLabel)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.white.opacity(0.18), in: Capsule())
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [SubstanceCategory.empathogen.color, SubstanceCategory.stimulant.color],
                            startPoint: .leading, endPoint: .trailing,
                        ))
                        .frame(height: 12)
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: min(max(geo.size.width * CGFloat(profile.leanPosition ?? 0.5) - 11, 0), geo.size.width - 22))
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            HStack {
                neurotransmitterChip("Serotonin", tint: SubstanceCategory.empathogen.color)
                Spacer()
                neurotransmitterChip("Dopamine", tint: SubstanceCategory.stimulant.color)
            }
            Text(profile.leanLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func neurotransmitterChip(_ name: LocalizedStringKey, tint: Color) -> some View {
        Text(name)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.mix(with: .white, by: 0.12).opacity(0.85), in: Capsule())
    }

    private func bindingTable(_ mechanism: MechanismOfAction) -> some View {
        let bindings = Array(mechanism.bindings.sorted { $0.affinity > $1.affinity }.prefix(6))
        return VStack(spacing: 7) {
            ForEach(bindings) { binding in
                HStack(spacing: 10) {
                    Text(binding.target)
                        .font(.caption.weight(.bold).monospaced())
                        .frame(width: 82, alignment: .leading)
                    Text(binding.action.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    strengthDots(binding.affinity.rawValue)
                }
            }
        }
    }

    private func strengthDots(_ filled: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle().fill(.white.opacity(i < filled ? 0.95 : 0.22)).frame(width: 6, height: 6)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        footerContent.padding(.top, 2)
    }

    private var richFooter: some View {
        VStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
            HStack(alignment: .center) {
                footerBrand
                Spacer()
                Text("kagerou.glass/piru")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var footerContent: some View {
        HStack(spacing: 8) {
            footerBrand
            Spacer()
            Text("kagerou.glass/piru")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var footerBrand: some View {
        HStack(spacing: 8) {
            Image("AppIconArtwork")
                .resizable().interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.5))
            Text("Piru")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    // MARK: shared bits

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.bold)).textCase(.uppercase).tracking(0.6)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.bottom, 6)
    }

    /// A centered small-caps section rule — the editorial divider on the plate.
    private func sectionRule(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
            Text(title)
                .font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.4)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
        }
    }

    /// A titled column for the Rich plate's symmetric two-column band.
    private func plateColumn(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The frosted specimen panel used for the molecule and curve heroes.
    private func panel(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15), lineWidth: 1))
            content()
        }
    }
}

/// A stylized effect-over-time curve derived from a duration profile's phase
/// boundaries: an S-rise across come-up, a plateau across peak, a fall across
/// offset. The x-axis stops at `offsetEnd` (the acute end) — extending it to the
/// long after-glow made the peak a spike with a huge flat tail. `strokeOnly`
/// traces just the top line; otherwise it closes to the baseline for a fill.
private struct EffectCurveShape: Shape {
    let boundaries: PhaseBoundaries
    var strokeOnly: Bool = false

    func path(in rect: CGRect) -> Path {
        let total = max(boundaries.offsetEnd, 1)
        let steps = 96
        var path = Path()
        if !strokeOnly { path.move(to: CGPoint(x: rect.minX, y: rect.maxY)) }
        for i in 0 ... steps {
            let f = Double(i) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(f)
            let y = rect.maxY - rect.height * CGFloat(intensity(at: f * total))
            if i == 0, strokeOnly {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if !strokeOnly {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    private func intensity(at t: Double) -> Double {
        let comeupEnd = max(boundaries.comeupEnd, boundaries.onsetEnd + 1)
        let peakEnd = max(boundaries.peakEnd, comeupEnd + 1)
        let offsetEnd = max(boundaries.offsetEnd, peakEnd + 1)
        func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
            guard b > a else { return x >= b ? 1 : 0 }
            let u = min(max((x - a) / (b - a), 0), 1)
            return u * u * (3 - 2 * u)
        }
        if t <= comeupEnd { return 0.06 + 0.94 * smooth(0, comeupEnd, t) }
        if t <= peakEnd { return 1 }
        return 0.06 + 0.94 * (1 - smooth(peakEnd, offsetEnd, t))
    }
}

/// A minimal wrapping chip row for effect names — lays chips out left-to-right,
/// wrapping to new lines. Uses the shared ``FlowLayout``.
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
