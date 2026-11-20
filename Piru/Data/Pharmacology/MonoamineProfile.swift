import Foundation

/// A substance's monoamine-transporter character distilled from its DAT/NET/SERT bindings: whether it
/// **releases** (substrate efflux, MDMA-like) or **blocks** (reuptake inhibition, cocaine-like), and
/// where it sits on the **dopamine ↔ serotonin** axis — the empathogen↔stimulant spectrum that predicts
/// the *character* of a stimulant without shipping a false single potency. Plus the "mis-sold as
/// MDMA" adulterant warning for the DAT-dominant blocker cathinones. The 5-HT2B heart-valve warning
/// is ``ValvularWarning``, on the substance page: most substances that carry it have no transporter
/// row, so this card is never built for them.
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

        let misSold = mechanism != .releaser && isSoldAsMDMA

        return MonoamineProfile(
            mechanism: mechanism,
            basis: basis,
            datSertRatio: ratio,
            leanPosition: position,
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

    var leanLabel: LocalizedStringResource {
        guard let r = datSertRatio else { return "Balance not characterized (DAT or SERT data missing)" }
        switch r {
        case ..<0.8: return "Serotonin-leaning (entactogenic)"
        case 0.8 ..< 3: return "Balanced, empathogen-like"
        case 3 ..< 15: return "Dopamine-leaning, more stimulant in character"
        default: return "Strongly dopaminergic (SERT-sparing)"
        }
    }
}
