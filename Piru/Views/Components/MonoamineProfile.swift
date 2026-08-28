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
    /// Carries 5-HT2B agonism potent enough to matter — the valvular-heart antitarget that killed
    /// fenfluramine, engaged by the benzofurans (6-APB EC₅₀ 140 nM) and not by MDMA. See
    /// ``engagesValvularAntitarget(_:)`` for what "potent enough" means and why partial agonism counts.
    let engages5HT2B: Bool
    /// Frequently sold on the street as MDMA/"molly" despite being a pharmacological reuptake blocker —
    /// longer, more stimulant/anxiogenic, more dangerous on an empathogen-style redose.
    let misSoldAsMDMA: Bool

    /// Build the profile from a substance's binding rows. Returns `nil` unless the substance has at least
    /// one DAT/NET/SERT release or uptake-inhibition row to characterize.
    ///
    /// `isSoldAsMDMA` is the substance's `missold-as-mdma` flag from the bundled DB — a market fact the
    /// caller resolves. It only becomes ``misSoldAsMDMA`` for a non-releaser, because the warning is
    /// about the mismatch: a blocker sold as an empathogen behaves nothing like one on a redose.
    static func from(bindings: [BindingHit], isSoldAsMDMA: Bool) -> MonoamineProfile? {
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

        let engages5HT2B = engagesValvularAntitarget(bindings)
        let misSold = mechanism != .releaser && isSoldAsMDMA

        return MonoamineProfile(
            mechanism: mechanism,
            basis: basis,
            datSertRatio: ratio,
            leanPosition: position,
            engages5HT2B: engages5HT2B,
            misSoldAsMDMA: misSold,
        )
    }

    /// Whether the substance engages 5-HT2B strongly enough for the valvulopathy warning.
    ///
    /// **Partial agonism counts.** Pergolide, cabergoline and norfenfluramine are partial agonists at
    /// this receptor and are precisely the drugs that caused valvular fibrosis; reading only `agonist`
    /// missed 25B-NBOMe and 25C-NBOMe at Kᵢ 0.5 and 1.1 nM. Antagonists never count — cariprazine,
    /// phentermine and viloxazine block the receptor.
    ///
    /// **Potency counts too**, on the app's own ``ReceptorStrength`` bands, at moderate or better.
    /// Without that floor 4-fluoroamphetamine qualifies on a 14.4 µM EC₅₀ — three orders of magnitude
    /// above any dose — and a heart-valve warning that appears on anything ever assayed at 5-HT2B
    /// teaches the reader to ignore it. A row with no measurement falls back to its curated
    /// ``BindingHit/affinityTier``, so a hand-graded row still speaks; a row with neither says nothing.
    static func engagesValvularAntitarget(_ bindings: [BindingHit]) -> Bool {
        bindings.contains { hit in
            guard hit.target.uppercased().hasPrefix("5-HT2B"),
                  hit.action == "agonist" || hit.action == "partialAgonist" else { return false }
            let tier = ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm)
                ?? hit.affinityTier
            return (tier ?? 0) >= 2
        }
    }

    var mechanismLabel: LocalizedStringResource {
        switch mechanism {
        case .releaser: "Substrate releaser"
        case .blocker: "Reuptake blocker"
        case .hybrid: "Mixed (releaser / blocker)"
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

/// The dopamine ↔ serotonin lean spectrum — a gradient bar with a marker at `leanPosition`, the two
/// endpoint labels, and the lean label with its optional DAT:SERT ratio beneath. Rendered by the
/// unified Pharmacology card, and collapsed into a single VoiceOver element (the marker/gradient are
/// decorative on their own).
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
    var onInfo: (() -> Void)?

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
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("About monoamine profile")
                    Spacer()
                }
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
