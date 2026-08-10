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
///   molecule, dose ladder, one-row onset/peak/total; Standard adds the effects
///   section).
/// - **Rich** renders a wide "specimen plate" — molecule ∣ effect-over-time graph,
///   a two-column band (dose ladder ∣ effects), and a pharmacology section (the
///   serotonin↔dopamine lean bar with the SERT:DAT ratio, and the graded receptor
///   meter). Designed to read like a plate you'd print in a pharmacopeia.
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

    /// Reported effects merged by their resolved display name — drug.community
    /// often lists the same effect under several phrasings that collapse to one
    /// localized vocab term (e.g. "increased sociability" + "emotional bonding").
    /// Merging sums the report counts and keeps the earliest emergence band.
    private var dedupedReportedEffects: [ReportedEffect] {
        var byName: [String: ReportedEffect] = [:]
        for effect in reportedEffects {
            if let existing = byName[effect.displayName] {
                byName[effect.displayName] = ReportedEffect(
                    name: existing.name,
                    displayName: existing.displayName,
                    domain: existing.domain,
                    reportCount: existing.reportCount + effect.reportCount,
                    emergesBand: [existing.emergesBand, effect.emergesBand].compactMap(\.self).min(),
                )
            } else {
                byName[effect.displayName] = effect
            }
        }
        // Stable order (count desc, then name) so a substance always renders the
        // same card — dictionary iteration order is otherwise nondeterministic.
        return byName.values.sorted {
            $0.reportCount != $1.reportCount ? $0.reportCount > $1.reportCount : $0.displayName < $1.displayName
        }
    }

    private var frequencyEffects: [ReportedEffect] {
        Array(dedupedReportedEffects.prefix(5))
    }

    private var hasBandedEffects: Bool {
        dedupedReportedEffects.contains { $0.emergesBand != nil }
    }

    /// The ramp rows: top-2 by report count from each band Light…Heavy (1…4), laid
    /// out band-ascending so the ribbon always spans the full arc — including the
    /// heavy-dose caution effects.
    private var rampEffects: [RampEffect] {
        var out: [RampEffect] = []
        for band in 1 ... 4 {
            let inBand = dedupedReportedEffects
                .filter { $0.emergesBand == band }
                .sorted { $0.reportCount > $1.reportCount }
                .prefix(2)
            out.append(contentsOf: inBand.map {
                RampEffect(name: $0.displayName, color: $0.domain.color, count: $0.reportCount, band: band)
            })
        }
        return out.sorted { $0.band != $1.band ? $0.band < $1.band : $0.count > $1.count }
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
    /// printed specimen. `RoundedRectangle.inset(by:)` already shrinks the corner
    /// radius by the inset (the same trick `strokeBorder` uses), so it must be given
    /// the *full* outer radius — the inset then yields `cornerRadius − borderInset`,
    /// staying concentric with the card's outer corner. Subtracting the inset from
    /// the radius here too would double-count and pinch the border's corners.
    private var plateBorder: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
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
            if let duration = route?.duration { phaseTrio(duration) }
            if detail != .minimal { effectsSection }
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
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(route.map { "Dose · \($0.route.displayName)" } ?? "Dose")
                    doseLadderRows
                    Spacer(minLength: 0)
                }
                .frame(width: 210, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    effectsSection
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let mechanism, !mechanism.summary.isEmpty {
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
                    HStack(spacing: 9) {
                        DoseTierMark(level: index, diameter: 18)
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

    // MARK: one-row onset · peak · total

    private func phaseTrio(_ duration: DurationProfile) -> some View {
        HStack(spacing: 0) {
            trioCell("arrow.up.forward", "Onset", duration.onset)
            trioDivider
            trioCell("sparkles", "Peak", duration.peak)
            trioDivider
            trioCell("clock", "Total", duration.total)
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var trioDivider: some View {
        Rectangle().fill(.white.opacity(0.10)).frame(width: 1, height: 44)
    }

    private func trioCell(_ symbol: String, _ name: LocalizedStringKey, _ range: DurationRange?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
            Text(range.map { Self.compactDuration($0) } ?? "—")
                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase).tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: effects section (ramp / columns / fallback)

    @ViewBuilder private var effectsSection: some View {
        if hasBandedEffects {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Most common effects · by dose")
                EmergenceRamp(
                    rows: rampEffects,
                    nameWidth: detail == .rich ? 178 : 158,
                    font: detail == .rich ? 11 : 10,
                )
            }
        } else if !frequencyEffects.isEmpty {
            frequencyBars
        } else if !topEffects.isEmpty {
            effectChips
        }
    }

    // MARK: effects fallback (flat frequency list)

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
        let maxCount = max(frequencyEffects.map(\.reportCount).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Most reported")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(frequencyEffects) { effect in
                    HStack(spacing: 10) {
                        Circle().fill(effect.domain.color).frame(width: 7, height: 7)
                        Text(effect.displayName)
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
    }

    // MARK: effect-over-time graph (Rich)

    private var curvePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("EFFECT OVER TIME")
                    .font(.system(size: 8, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                if let boundaries = route?.duration?.phaseBoundaries {
                    MonochromeDoseGraph(boundaries: boundaries).frame(height: 74)
                }
                if let duration = route?.duration {
                    phaseGrid(duration)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .frame(height: 190)
    }

    /// The symmetric phase legend — four even cells (Onset · Come-up · Peak ·
    /// Offset) with a phase icon and compact duration, decoupled from the
    /// time-accurate curve above so the grid stays balanced whatever the timing.
    private func phaseGrid(_ duration: DurationProfile) -> some View {
        HStack(spacing: 6) {
            phaseCell("arrow.up.forward", "Onset", duration.onset)
            phaseCell("arrow.up.right", "Come-up", duration.comeup)
            phaseCell("sparkles", "Peak", duration.peak)
            phaseCell("arrow.down.right", "Offset", duration.offset)
        }
    }

    private func phaseCell(_ symbol: String, _ name: LocalizedStringKey, _ range: DurationRange?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.8))
            Text(name)
                .font(.system(size: 8, weight: .bold))
                .textCase(.uppercase).tracking(0.3)
                .foregroundStyle(.white.opacity(0.6))
            Text(range.map { Self.compactDuration($0) } ?? "—")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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
                // A short, localized "what this drug is" blurb beside the receptor
                // table — replaces the old caption that just repeated the mechanism
                // label shown in the chip above.
                Text(descriptionBlurb ?? mechanism.summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A concise "what this drug is" blurb for the pharmacology caption — the first
    /// sentence of the (locale-resolved) substance overview, with parenthetical
    /// alias lists stripped. `nil` when no overview is available.
    private var descriptionBlurb: String? {
        guard let text = substance.overview?.text, !text.isEmpty else { return nil }
        let lead = Self.leadingSentence(Self.stripParentheticals(text))
        return lead.isEmpty ? nil : lead
    }

    private static func stripParentheticals(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "（" { depth += 1; continue }
            if ch == ")" || ch == "）" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        return out.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The first sentence — breaks on ". " / "! " or the CJK terminators "。" / "！",
    /// so decimals ("0.5 mg") and "Δ9" don't cut it short.
    private static func leadingSentence(_ s: String) -> String {
        let chars = Array(s)
        var end = chars.count
        for i in chars.indices {
            let ch = chars[i]
            if ch == "。" || ch == "！" { end = i + 1; break }
            if ch == "." || ch == "!" {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " { end = i + 1; break }
            }
        }
        return String(chars[0 ..< end]).trimmingCharacters(in: .whitespaces)
    }

    /// The dopamine↔serotonin lean bar as the pharmacology hero — a wide gradient
    /// with a marker, neurotransmitter chips at each end, the mechanism label, and
    /// the SERT:DAT selectivity ratio (the bar already *shows* the lean, so the
    /// ratio quantifies it rather than repeating "serotonin-leaning" in words).
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
            transporterRatioLabel
        }
    }

    /// The SERT:DAT selectivity, e.g. `SERT : DAT release ≈ 4 : 1`, with the
    /// transporter names tinted to match the lean-bar ends. Falls back to the
    /// profile's word label when no ratio is available.
    @ViewBuilder private var transporterRatioLabel: some View {
        if let ratio = transporterRatio {
            HStack(spacing: 0) {
                Text(verbatim: ratio.first).foregroundStyle(ratio.firstTint).fontWeight(.heavy)
                Text(verbatim: " : ").foregroundStyle(.white.opacity(0.85))
                Text(verbatim: ratio.second).foregroundStyle(ratio.secondTint).fontWeight(.heavy)
                Text(ratio.basis).foregroundStyle(.white.opacity(0.6)).padding(.leading, 7)
                Text(verbatim: "≈ \(ratio.value)").foregroundStyle(.white.opacity(0.9)).padding(.leading, 5)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
        } else if let profile = monoamineProfile {
            Text(profile.leanLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Resolves `datSertRatio` (SERT concentration ÷ DAT concentration — lower
    /// concentration means more potent) into a "more-potent-side : 1" display.
    private var transporterRatio: (
        first: String, firstTint: Color, second: String, secondTint: Color, basis: LocalizedStringKey, value: String,
    )? {
        guard let profile = monoamineProfile, let ratio = profile.datSertRatio, ratio > 0 else { return nil }
        let sertColor = SubstanceCategory.empathogen.color
        let datColor = SubstanceCategory.stimulant.color
        let basis: LocalizedStringKey = profile.basis == .release ? "release" : "uptake"
        let sertPotency = 1 / ratio // SERT potency relative to DAT
        if sertPotency >= 1 {
            return ("SERT", sertColor, "DAT", datColor, basis, "\(Int(sertPotency.rounded())) : 1")
        } else {
            return ("DAT", datColor, "SERT", sertColor, basis, "\(Int(ratio.rounded())) : 1")
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
                    StrengthMeter(filled: binding.affinity.rawValue, tint: .white, filledOpacity: 0.95, emptyOpacity: 0.20)
                }
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
                Text(verbatim: "kagerou.glass/piru")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var footerContent: some View {
        HStack(spacing: 8) {
            footerBrand
            Spacer()
            Text(verbatim: "kagerou.glass/piru")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var footerBrand: some View {
        HStack(spacing: 8) {
            Image("AppIconArtwork")
                .resizable().interpolation(.high)
                .frame(width: 22, height: 22)
            Text(verbatim: "Piru")
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

// MARK: - Dose tier mark

/// A distinct per-tier mark for the dose scale — each tier its own symbol rather
/// than one gauge "filling up." The set escalates from a faint speck to a caution
/// triangle, so a heavier dose reads as *more hazardous*, never as the "full" or
/// "complete" state a filling ring wrongly implied. Shared by the dose ladder and
/// the effect ramp's tier header so both read on one scale.
private struct DoseTierMark: View {
    let level: Int // 0 threshold · 1 light · 2 common · 3 strong · 4 heavy
    var diameter: CGFloat = 18

    private var symbol: String {
        switch level {
        case 0: "circle.dotted"
        case 1: "circle"
        case 2: "circle.fill"
        case 3: "exclamationmark.circle.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: diameter * 0.82))
            .foregroundStyle(.white.opacity(level == 0 ? 0.5 : level >= 3 ? 0.95 : 0.78))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Emergence ramp

/// One effect row for the ramp.
private struct RampEffect: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let count: Int
    let band: Int // 1 light … 4 heavy
}

/// A dose-emergence ribbon: each effect is a pill from the dose where it emerges to
/// the heavy edge; pill THICKNESS ∝ report frequency (log-normalized so a huge
/// outlier doesn't crush the rest), the raw count shown small beside the name, and
/// a ``DoseDial`` header marking each tier.
private struct EmergenceRamp: View {
    let rows: [RampEffect]
    var nameWidth: CGFloat
    var font: CGFloat

    private static let rowH: CGFloat = 30
    private static let headerH: CGFloat = 24
    private static let countW: CGFloat = 34
    private static let tailFrac: CGFloat = 0.14 // Heavy tick sits in from the edge

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let axisW = width - nameWidth
            let tierW = axisW * (1 - Self.tailFrac)
            let barEnd = nameWidth + axisW
            let bandX: (Int) -> CGFloat = { nameWidth + tierW * CGFloat($0 - 1) / 3 }
            let gridHeight = Self.headerH + CGFloat(rows.count) * Self.rowH - 6

            ZStack(alignment: .topLeading) {
                ForEach(1 ... 4, id: \.self) { band in
                    Rectangle().fill(.white.opacity(0.10))
                        .frame(width: 1, height: gridHeight)
                        .position(x: bandX(band), y: Self.headerH + (gridHeight - Self.headerH) / 2 - 3)
                    DoseTierMark(level: band, diameter: 18)
                        .position(x: bandX(band), y: Self.headerH / 2)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, effect in
                    let cy = Self.headerH + CGFloat(index) * Self.rowH + Self.rowH / 2
                    let startX = bandX(effect.band)
                    let thickness = self.thickness(effect.count)
                    Capsule().fill(effect.color.opacity(0.82))
                        .frame(width: max(thickness, barEnd - startX), height: thickness)
                        .position(x: (startX + barEnd) / 2, y: cy)
                    Text(effect.name)
                        .font(.system(size: font))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .frame(width: nameWidth - Self.countW - 12, alignment: .trailing)
                        .position(x: (nameWidth - Self.countW - 12) / 2, y: cy)
                    Text(Self.compact(effect.count))
                        .font(.system(size: font - 1, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: Self.countW, alignment: .trailing)
                        .position(x: nameWidth - Self.countW / 2 - 8, y: cy)
                }
            }
        }
        .frame(height: Self.headerH + CGFloat(rows.count) * Self.rowH + 4)
    }

    private func thickness(_ count: Int) -> CGFloat {
        let counts = rows.map { Double($0.count) }
        let lo = log(counts.min() ?? 1), hi = log(counts.max() ?? 1)
        let normalized = hi > lo ? (log(Double(count)) - lo) / (hi - lo) : 0.5
        return 7 + CGFloat(normalized) * 16 // 7…23pt
    }

    private static func compact(_ n: Int) -> String {
        n >= 1_000 ? "\(n / 1_000).\((n % 1_000) / 100)k" : "\(n)"
    }
}

// MARK: - Monochrome effect-over-time graph

/// The app's effect-over-time curve, rendered monochrome for the plate: faint
/// white phase bands, hour gridlines + labels, and the asymmetric intensity curve.
private struct MonochromeDoseGraph: View {
    let boundaries: PhaseBoundaries

    private struct Band: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let opacity: Double
    }

    private var bands: [Band] {
        [
            Band(id: 0, start: 0, end: boundaries.onsetEnd, opacity: 0.05),
            Band(id: 1, start: boundaries.onsetEnd, end: boundaries.comeupEnd, opacity: 0.07),
            Band(id: 2, start: boundaries.comeupEnd, end: boundaries.peakEnd, opacity: 0.12),
            Band(id: 3, start: boundaries.peakEnd, end: boundaries.offsetEnd, opacity: 0.07),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(boundaries.offsetEnd, 1)
            let width = geo.size.width
            let plotTop: CGFloat = 12
            let plotH = max(geo.size.height - plotTop, 1)
            let xf: (Double) -> CGFloat = { CGFloat($0 / total) * width }

            ZStack(alignment: .topLeading) {
                ForEach(bands) { band in
                    Rectangle().fill(.white.opacity(band.opacity))
                        .frame(width: max(xf(band.end) - xf(band.start), 0), height: plotH)
                        .offset(x: xf(band.start), y: plotTop)
                }
                ForEach(hourMarks(total), id: \.self) { hour in
                    let hx = xf(Double(hour) * 60)
                    Rectangle().fill(.white.opacity(0.14))
                        .frame(width: 1, height: plotH).offset(x: hx, y: plotTop)
                    Text(verbatim: "\(hour)h")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(x: hx - 6, y: 0)
                }
                Rectangle().fill(.white.opacity(0.25))
                    .frame(height: 1).offset(y: plotTop + plotH - 0.5)
                EffectCurveShape(boundaries: boundaries)
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .frame(height: plotH).offset(y: plotTop)
                EffectCurveShape(boundaries: boundaries, strokeOnly: true)
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(height: plotH).offset(y: plotTop)
            }
        }
    }

    private func hourMarks(_ total: Double) -> [Int] {
        var out: [Int] = []
        var hour = 1
        while Double(hour) * 60 < total {
            out.append(hour)
            hour += 1
        }
        return out
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
