import SwiftUI

/// A substance's monoamine-transporter character distilled from its DAT/NET/SERT bindings: whether it
/// **releases** (substrate efflux, MDMA-like) or **blocks** (reuptake inhibition, cocaine-like), and
/// where it sits on the **dopamine ↔ serotonin** axis — the empathogen↔stimulant spectrum that predicts
/// the *character* of a stimulant without shipping a false single potency. Plus two harm-reduction
/// flags: the 5-HT2B valvulopathy antitarget, and the "mis-sold as MDMA" adulterant warning for the
/// DAT-dominant blocker cathinones.
///
/// Everything is derived from the substance's own graded bindings (the same rows the Receptor Literature
/// section shows), so it stays faithful: a substance with no DAT+SERT data simply gets no card.
struct MonoamineProfile {
    enum Mechanism { case releaser, blocker, hybrid }
    /// Which endpoint the ratio is read from — release EC₅₀ (substrate) or uptake-inhibition IC₅₀ (blocker).
    enum Basis { case release, uptake }

    let mechanism: Mechanism
    let basis: Basis
    /// SERT-over-DAT potency ratio *within one assay* (release EC₅₀ or uptake IC₅₀). Higher = more
    /// dopamine/catecholamine-leaning; < 1 = serotonin-leaning. `nil` when DAT or SERT is missing.
    let datSertRatio: Double?
    /// 0 (serotonin-leaning) … 1 (strongly dopaminergic), log-scaled — the spectrum marker position.
    let leanPosition: Double?
    /// Carries a functional 5-HT2B agonist binding (the fenfluramine/MDA valvular-heart antitarget that
    /// MDMA does *not* engage).
    let engages5HT2B: Bool
    /// Frequently sold on the street as MDMA/"molly" despite being a pharmacological reuptake blocker —
    /// longer, more stimulant/anxiogenic, more dangerous on an empathogen-style redose.
    let misSoldAsMDMA: Bool

    /// Substances commonly pressed/sold as "MDMA" or "molly" but pharmacologically DAT-dominant blockers.
    private static let misSoldNames: Set<String> = [
        "eutylone", "n-ethylpentylone", "nep", "ephylone", "n-ethylnorpentylone", "pentylone",
    ]

    /// Build the profile from a substance's binding rows. Returns `nil` unless the substance has at least
    /// one DAT/NET/SERT release or uptake-inhibition row to characterize.
    static func from(bindings: [SubstanceStore.BindingHit], substanceName: String) -> MonoamineProfile? {
        func best(_ target: String, _ action: String) -> Double? {
            bindings
                .filter { $0.target.uppercased().hasPrefix(target) && $0.action == action }
                .compactMap { action == "releasingAgent" ? $0.ec50Nm : $0.ic50Nm }
                .min()
        }
        let datRel = best("DAT", "releasingAgent")
        let sertRel = best("SERT", "releasingAgent")
        let netRel = best("NET", "releasingAgent")
        let datUp = best("DAT", "reuptakeInhibitor")
        let sertUp = best("SERT", "reuptakeInhibitor")
        let netUp = best("NET", "reuptakeInhibitor")

        // A transporter is "released" if it has a substrate-efflux row, and "block-only" if it has an
        // uptake-inhibition row but NO release row. A normal releaser *also* inhibits uptake (it competes
        // as a substrate), so uptake data alone does NOT make a substance a hybrid — only release at one
        // transporter together with block-only at another does (e.g. butylone: DAT blocker, SERT substrate).
        let anyReleased = datRel != nil || sertRel != nil || netRel != nil
        let datBlockOnly = datUp != nil && datRel == nil
        let sertBlockOnly = sertUp != nil && sertRel == nil
        let netBlockOnly = netUp != nil && netRel == nil
        let anyBlockOnly = datBlockOnly || sertBlockOnly || netBlockOnly
        guard anyReleased || anyBlockOnly else { return nil }

        let mechanism: Mechanism = if anyReleased, anyBlockOnly {
            .hybrid
        } else if anyReleased {
            .releaser
        } else {
            .blocker
        }
        let basis: Basis = anyReleased ? .release : .uptake
        let dat = anyReleased ? datRel : datUp
        let sert = anyReleased ? sertRel : sertUp

        var ratio: Double?
        var position: Double?
        if let d = dat, d > 0, let s = sert, s > 0 {
            let r = s / d
            ratio = r
            // Map log₁₀(ratio) from −1 (serotonin-leaning) … +3 (strongly dopaminergic) onto 0…1.
            position = min(max((log10(r) + 1) / 4, 0), 1)
        }

        let engages5HT2B = bindings.contains {
            $0.target.uppercased().hasPrefix("5-HT2B") && $0.action == "agonist"
        }
        let misSold = mechanism != .releaser
            && misSoldNames.contains(substanceName.lowercased().trimmingCharacters(in: .whitespaces))

        return MonoamineProfile(
            mechanism: mechanism,
            basis: basis,
            datSertRatio: ratio,
            leanPosition: position,
            engages5HT2B: engages5HT2B,
            misSoldAsMDMA: misSold,
        )
    }

    var mechanismLabel: LocalizedStringResource {
        switch mechanism {
        case .releaser: "Substrate releaser"
        case .blocker: "Reuptake blocker"
        case .hybrid: "Mixed (releaser / blocker)"
        }
    }

    var mechanismDetail: LocalizedStringResource {
        switch mechanism {
        case .releaser: "Reverses the transporters to pump monoamines out (substrate efflux) — the MDMA/amphetamine-type mechanism."
        case .blocker: "Blocks reuptake without triggering release (cocaine/methylphenidate-type) — a different tolerance and redose profile from a releaser."
        case .hybrid: "Releases at one transporter while blocking another — an intermediate profile; a single α-alkyl or N-ethyl group flips DAT from substrate to blocker."
        }
    }

    var leanLabel: LocalizedStringResource {
        guard let r = datSertRatio else { return "Balance not characterized (DAT or SERT data missing)" }
        switch r {
        case ..<0.8: return "Serotonin-leaning (entactogenic)"
        case 0.8 ..< 3: return "Balanced — empathogen-like"
        case 3 ..< 15: return "Dopamine-leaning — more stimulant in character"
        default: return "Strongly dopaminergic (SERT-sparing)"
        }
    }
}

/// The card surfacing a ``MonoamineProfile`` — mechanism, the dopamine↔serotonin spectrum marker, and
/// the valvulopathy / mis-sold-as-MDMA flags. Shown in substance detail for any monoamine
/// releaser/blocker.
struct MonoamineProfileCard: View {
    let profile: MonoamineProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mechanismChip
            Text(profile.mechanismDetail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            if profile.leanPosition != nil {
                spectrum
            }

            if profile.engages5HT2B {
                flag(
                    icon: "heart.text.square",
                    tint: .orange,
                    text: "Activates 5-HT2B, which is linked to heart-valve damage (valvulopathy) with chronic or heavy use.",
                )
            }
            if profile.misSoldAsMDMA {
                flag(
                    icon: "exclamationmark.triangle.fill",
                    tint: .red,
                    text: "Often mis-sold as MDMA / \u{201C}molly,\u{201D} but it is pharmacologically a reuptake blocker — longer, more stimulant and anxiogenic, and more dangerous on an empathogen-style redose.",
                )
            }

            Text("Derived from this substance's graded DAT/NET/SERT bindings. Transporter potencies are mostly within-assay ratios.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// The releaser ⇄ blocker character as a tinted capsule — the single most useful axis for a
    /// stimulant/empathogen, so it leads the card. Neutral tint (no red "releaser" icon).
    private var mechanismChip: some View {
        Text(profile.mechanismLabel)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Theme.secondaryLabel.opacity(0.12)),
            )
            .overlay(
                Capsule().strokeBorder(Theme.secondaryLabel.opacity(0.18), lineWidth: 0.5),
            )
    }

    // MARK: - Dopamine ↔ serotonin spectrum

    private var spectrum: some View {
        DopamineSerotoninLeanBar(
            leanPosition: profile.leanPosition,
            leanLabel: profile.leanLabel,
            ratioText: profile.datSertRatio.map { ratioText($0) },
        )
    }

    private func flag(icon: String, tint: Color, text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A DAT:SERT ratio reads meaningfully only within a band — past ~100:1 the lean label ("Strongly
    /// dopaminergic") carries the signal and a raw "21797" is just noise. Clamp the extremes.
    private func ratioText(_ r: Double) -> String {
        if r >= 100 { return ">100" }
        if r >= 10 { return String(format: "%.0f", r) }
        if r >= 1 { return String(format: "%.1f", r) }
        if r >= 0.01 { return String(format: "%.2f", r) }
        return "<0.01"
    }
}

/// The dopamine ↔ serotonin lean spectrum — a gradient bar with a marker at `leanPosition`, the two
/// endpoint labels, and the lean label with its optional DAT:SERT ratio beneath. Shared by the unified
/// Pharmacology card and the standalone Monoamine Profile card so the axis reads identically on both,
/// and collapsed into a single VoiceOver element (the marker/gradient are decorative on their own).
struct DopamineSerotoninLeanBar: View {
    let leanPosition: Double?
    let leanLabel: LocalizedStringResource
    let ratioText: String?
    /// When false, the word lean-label ("Serotonin-leaning…") is dropped from the
    /// visible layout and folded into the a11y value instead — the unified
    /// Pharmacology card uses this because the bar plus the ratio line already
    /// convey the lean, so the restated words are noise (design review §3.3).
    var showsLeanLabel: Bool = true
    /// A ready-made ratio line ("SERT : DAT release ≈ 13 : 1") that replaces the
    /// raw "DAT:SERT <n>" caption when provided.
    var ratioLine: String?

    private var serotoninColor: Color {
        SubstanceCategory.empathogen.color
    }
    private var dopamineColor: Color {
        SubstanceCategory.stimulant.color
    }

    /// Half the knob; the ratio label centers on this and is clamped by it.
    private static let knobRadius: CGFloat = 8
    private static let ratioLabelWidth: CGFloat = 190
    /// Vertical room reserved above the track for the ratio label.
    private static let ratioRowHeight: CGFloat = 18

    /// Centered on the knob, then clamped so neither end escapes the track. At the
    /// extremes the text also switches its own alignment, so a clamped label hugs
    /// the edge it belongs to instead of drifting away from the knob.
    private func ratioOffset(knobX: CGFloat, width: CGFloat) -> CGFloat {
        let ideal = knobX - Self.ratioLabelWidth / 2
        return min(max(ideal, 0), max(0, width - Self.ratioLabelWidth))
    }

    private func ratioAlignment(knobX: CGFloat, width: CGFloat) -> TextAlignment {
        if knobX < Self.ratioLabelWidth / 2 { return .leading }
        if knobX > width - Self.ratioLabelWidth / 2 { return .trailing }
        return .center
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let knobX = geo.size.width * (leanPosition ?? 0.5)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [serotoninColor, dopamineColor], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .offset(y: Self.ratioRowHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: knobX - Self.knobRadius, y: Self.ratioRowHeight)
                    // The ratio rides directly above the knob, so it reads as that
                    // position's value rather than a caption about the whole bar —
                    // far left when a compound is serotonin-dominant, far right when
                    // it is dopamine-dominant. Clamped so it stays inside the track
                    // at either extreme.
                    if let ratioLine {
                        Text(verbatim: ratioLine)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: Self.ratioLabelWidth)
                            .multilineTextAlignment(ratioAlignment(knobX: knobX, width: geo.size.width))
                            .offset(x: ratioOffset(knobX: knobX, width: geo.size.width))
                    }
                }
                .frame(height: 16 + Self.ratioRowHeight)
            }
            .frame(height: 16 + Self.ratioRowHeight)

            HStack {
                Text("Serotonin").font(.caption2.weight(.medium)).foregroundStyle(serotoninColor)
                Spacer()
                Text("Dopamine").font(.caption2.weight(.medium)).foregroundStyle(dopamineColor)
            }

            if showsLeanLabel || (ratioLine == nil && ratioText != nil) {
                VStack(alignment: .leading, spacing: 1) {
                    if showsLeanLabel {
                        Text(leanLabel).font(.caption.weight(.semibold))
                    }
                    if ratioLine == nil, let ratioText {
                        Text("DAT:SERT \(ratioText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dopamine–serotonin lean"))
        .accessibilityValue(Text(leanLabel))
    }
}
