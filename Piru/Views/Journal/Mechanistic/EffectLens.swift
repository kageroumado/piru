import SwiftUI

/// One "lens" on a modeled session — either the classic per-substance duration
/// **Timeline**, or a mechanistic axis read straight off the ``EffectEngine``
/// output (``EffectTimeline``). The lens selector cycles through these; a
/// session that the engine can't model surfaces only ``timeline``.
///
/// Ports the `LENS` table from the `app-timeline` prototype (`gen-app.mjs`):
/// same colors, thresholds, and copy, so the shipped view matches the approved
/// design. Pure value type — safe to read off the main actor while sampling
/// channels during an off-main simulate.
nonisolated enum EffectLens: String, CaseIterable, Identifiable {
    /// Classic per-substance duration bells — the universal default, works for
    /// anything logged (rendered by the existing `TimelineGraphView`).
    case timeline
    /// Dopamine reward + serotonin warmth + opioid liking, minus the comedown.
    case feeling
    /// Focused, activated energy (NE + cortical DA). Dips into sedation.
    case energy
    /// How much you'd *want* it — incentive salience, the rush prediction error.
    /// Separates the craving/pull signal from the hedonic experience. Visible
    /// only when the session involves dopaminergic substances with meaningful
    /// rush signal.
    case wanting
    /// How much you'd *enjoy* it — mu-opioid hedonic warmth minus dynorphin
    /// aversion. Visible only when the session involves opioidergic substances.
    case liking
    /// The pull to redose — incentive salience, rate-gated, serotonin-braked.
    case compulsion
    /// Physiological load (cardiovascular + respiratory cost), paired with Apple
    /// Health heart rate & blood pressure. Higher = more strain on the body.
    case strain

    var id: String {
        rawValue
    }

    /// Negative area (a crash / comedown) reads red on every signed lens — a
    /// universal "cost" signal.
    static let crash = Color(hex: "ff453a")

    var label: LocalizedStringKey {
        switch self {
        case .timeline: "Timeline"
        case .feeling: "Feeling"
        case .wanting: "Wanting"
        case .liking: "Liking"
        case .energy: "Energy"
        case .compulsion: "Compulsion"
        case .strain: "Strain"
        }
    }

    var symbol: String {
        switch self {
        case .timeline: "chart.xyaxis.line"
        case .feeling: "face.smiling"
        case .wanting: "arrow.up.heart.fill"
        case .liking: "sparkles"
        case .energy: "bolt.fill"
        case .compulsion: "flame.fill"
        case .strain: "gauge.with.dots.needle.67percent"
        }
    }

    var color: Color {
        switch self {
        case .timeline: Color(hex: "8e8e93")
        case .feeling: Color(hex: "ff9f0a")
        case .wanting: Color(hex: "ff375f")
        case .liking: Color(hex: "bf5af2")
        case .energy: Color(hex: "ff6b35")
        case .compulsion: Color(hex: "e0457b")
        case .strain: Color(hex: "ff3b30")
        }
    }

    /// The ``EffectTimeline`` channel this lens reads. `nil` for ``timeline``,
    /// which is drawn from the classic duration model instead.
    var channel: KeyPath<EffectTimeline, [Double]>? {
        switch self {
        case .timeline: nil
        case .feeling: \.eu
        case .wanting: \.wanting
        case .liking: \.liking
        case .energy: \.drive
        case .compulsion: \.compul
        case .strain: \.danger
        }
    }

    /// Whether the axis is signed — i.e. it can dip below zero into a crash
    /// (drawn red). Compulsion and Strain are one-sided (they only rise from zero).
    var isSigned: Bool {
        switch self {
        case .feeling, .energy, .liking: true
        case .timeline, .wanting, .compulsion, .strain: false
        }
    }

    /// A fixed, **semi-absolute** axis anchor per lens (in raw engine-output
    /// units), so heights mean the same thing across sessions and lenses instead
    /// of every card rescaling to its own peak. Calibrated to the ``readout``
    /// word bands: the top-tier word ("Euphoric", "Wired", "Strong", "High")
    /// lands high on the axis but with headroom, so a genuinely mild session
    /// reads *visually* mild. A session that overshoots the anchor grows the axis
    /// (see ``MechanisticSessionModel``) — the scale is absolute until the data
    /// truly won't fit. `hi` is the neutral-to-strong ceiling; `lo` reserves
    /// comedown/sedation room below the baseline on signed lenses (and is always
    /// present, so the horizontal baseline reads as horizontal even when nothing
    /// dips below it).
    var referenceScale: (hi: Double, lo: Double) {
        switch self {
        case .timeline: (1, 0)
        case .feeling: (1.5, -0.55)
        case .wanting: (1.2, 0)
        case .liking: (1.0, -0.3)
        case .energy: (2.0, -0.95)
        case .compulsion: (0.8, 0)
        case .strain: (2.4, 0)
        }
    }

    /// Pair Apple Health HR/BP with this lens (the harm-reduction payoff).
    var pairsVitals: Bool {
        self == .strain
    }

    /// A short, glanceable cue for which direction is desirable — the fix for
    /// four similar-looking curves whose "up" means opposite things. `nil` for
    /// ``timeline`` (not a felt-effect axis).
    var valenceHint: LocalizedStringKey? {
        switch self {
        case .timeline: nil
        case .feeling: "Higher is better"
        case .wanting: "Higher is more pull"
        case .liking: "Higher is more pleasure"
        case .energy: "Higher is livelier"
        case .compulsion: "Lower is better"
        case .strain: "Lower is better"
        }
    }

    /// A state-reflecting icon from a sampled now-value (happy vs flat face, full
    /// vs slashed bolt, …) and whether it reads as a "cost". `nil` value → the
    /// lens's default ``symbol``.
    func state(value: Double?) -> (symbol: String, isNegative: Bool) {
        guard let value else { return (symbol, false) }
        switch self {
        case .timeline:
            return (symbol, false)
        case .feeling:
            if value > 0.4 { return ("face.smiling", false) }
            if value > -0.2 { return ("face.dashed", false) }
            return ("face.dashed", true)
        case .wanting:
            if value > 0.6 { return ("arrow.up.heart.fill", false) }
            return ("arrow.up.heart", false)
        case .liking:
            if value > 0.4 { return ("sparkles", false) }
            if value > -0.1 { return ("sparkle", false) }
            return ("sparkle", true)
        case .energy:
            if value > 1.5 { return ("bolt.fill", false) }
            if value > -0.4 { return ("bolt", false) }
            return ("bolt.slash", true)
        case .compulsion:
            if value > 0.5 { return ("flame.fill", false) }
            return ("flame", false)
        case .strain:
            if value > 1.6 { return ("exclamationmark.triangle.fill", true) }
            return (symbol, false)
        }
    }

    /// A qualitative word for a sampled value — the glanceable "now" readout.
    /// One consistent vocabulary per lens; ``strain`` reads as a magnitude
    /// (High/Moderate/Low) so the word matches the "higher = more load" curve.
    func readout(_ value: Double) -> LocalizedStringKey {
        switch self {
        case .timeline:
            ""
        case .feeling:
            value > 1.2 ? "Euphoric" : value > 0.4 ? "Good" : value > -0.2 ? "Mild" : "Comedown"
        case .wanting:
            value > 0.8 ? "Craving" : value > 0.3 ? "Pull" : value > 0.05 ? "Mild" : "Quiet"
        case .liking:
            value > 0.6 ? "Bliss" : value > 0.2 ? "Warm" : value > -0.1 ? "Faint" : "Flat"
        case .energy:
            value > 1.5 ? "Wired" : value > 0.4 ? "Driven" : value > -0.4 ? "Flat" : "Sedated"
        case .compulsion:
            value > 0.5 ? "Strong" : value > 0.15 ? "Mild" : "Quiet"
        case .strain:
            value > 1.6 ? "High" : value > 0.7 ? "Moderate" : "Low"
        }
    }

    /// The base mechanistic lenses, in display order (excludes ``timeline``
    /// and the conditional wanting/liking pair).
    static let mechanisticBase: [EffectLens] = [.feeling, .energy, .compulsion, .strain]

    /// The mechanistic lenses for a given simulation result. When the wanting
    /// or liking channels carry meaningful signal (peak > threshold), they
    /// appear after Feeling — surfacing the incentive-sensitization split
    /// ("the drug does less *and* you want it more") on stimulant/opioid
    /// sessions without cluttering sessions where those signals are inert.
    static func mechanisticLenses(for timeline: EffectTimeline) -> [EffectLens] {
        let wantingPeak = timeline.wanting.reduce(0.0) { max($0, $1) }
        let likingPeak = timeline.liking.reduce(0.0) { max($0, abs($1)) }
        let threshold = 0.05
        var lenses: [EffectLens] = [.feeling]
        if wantingPeak > threshold { lenses.append(.wanting) }
        if likingPeak > threshold { lenses.append(.liking) }
        lenses.append(contentsOf: [.energy, .compulsion, .strain])
        return lenses
    }

    /// Backward-compatible accessor for contexts that don't have a timeline.
    static let mechanistic: [EffectLens] = mechanisticBase
}
