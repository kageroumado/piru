import SwiftUI

/// One "lens" on a modeled session — either the classic per-substance duration
/// **Timeline**, or a mechanistic axis read straight off the ``EffectEngine``
/// output (``EffectTimeline``). The lens selector cycles through these; a
/// session that the engine can't model surfaces only ``timeline``.
///
/// Ports the `LENS` table from the `app-timeline` prototype (`gen-app.mjs`):
/// same colours, thresholds, and copy, so the shipped view matches the approved
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
    /// The pull to redose — incentive salience, rate-gated, serotonin-braked.
    case urge
    /// Physiological cost, paired with Apple Health heart rate & blood pressure.
    case safety

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
        case .energy: "Energy"
        case .urge: "Urge"
        case .safety: "Safety"
        }
    }

    /// VoiceOver / non-`Text` label.
    var accessibilityName: String {
        switch self {
        case .timeline: String(localized: "Timeline")
        case .feeling: String(localized: "Feeling")
        case .energy: String(localized: "Energy")
        case .urge: String(localized: "Urge")
        case .safety: String(localized: "Safety")
        }
    }

    var symbol: String {
        switch self {
        case .timeline: "chart.xyaxis.line"
        case .feeling: "face.smiling"
        case .energy: "bolt.fill"
        case .urge: "flame.fill"
        case .safety: "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .timeline: Color(hex: "8e8e93")
        case .feeling: Color(hex: "ff9f0a")
        case .energy: Color(hex: "ff6b35")
        case .urge: Color(hex: "e0457b")
        case .safety: Color(hex: "ff3b30")
        }
    }

    /// The ``EffectTimeline`` channel this lens reads. `nil` for ``timeline``,
    /// which is drawn from the classic duration model instead.
    var channel: KeyPath<EffectTimeline, [Double]>? {
        switch self {
        case .timeline: nil
        case .feeling: \.eu
        case .energy: \.drive
        case .urge: \.compul
        case .safety: \.danger
        }
    }

    /// Whether the axis is signed — i.e. it can dip below zero into a crash
    /// (drawn red). Urge and Safety are one-sided.
    var isSigned: Bool {
        switch self {
        case .feeling, .energy: true
        case .timeline, .urge, .safety: false
        }
    }

    /// Pair Apple Health HR/BP with this lens (the harm-reduction payoff).
    var pairsVitals: Bool {
        self == .safety
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .timeline:
            "What's active, by substance — the classic duration view. Works for anything you log, from vitamins to a full session."
        case .feeling:
            "How good it feels — dopamine reward + serotonin warmth + opioid liking, minus the comedown."
        case .energy:
            "Focused, activated energy (norepinephrine + cortical dopamine). Goes negative into sedation."
        case .urge:
            "The pull to redose — incentive salience (wanting), rate-gated and serotonin-braked."
        case .safety:
            "Physiological cost. Paired with your Apple Health heart rate & blood pressure."
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
        case .energy:
            if value > 1.5 { return ("bolt.fill", false) }
            if value > -0.4 { return ("bolt", false) }
            return ("bolt.slash", true)
        case .urge:
            if value > 0.5 { return ("flame.fill", false) }
            return ("flame", false)
        case .safety:
            if value > 1.6 { return ("exclamationmark.triangle.fill", true) }
            return ("waveform.path.ecg", false)
        }
    }

    /// A qualitative word for a sampled value — the glanceable "now" readout.
    /// Ports each lens's `unit()` from the prototype.
    func readout(_ value: Double) -> LocalizedStringKey {
        switch self {
        case .timeline:
            ""
        case .feeling:
            value > 1.2 ? "Euphoric" : value > 0.4 ? "Good" : value > -0.2 ? "Level" : "Low"
        case .energy:
            value > 1.5 ? "Wired" : value > 0.4 ? "Driven" : value > -0.4 ? "Flat" : "Sedated"
        case .urge:
            value > 0.5 ? "Strong" : value > 0.15 ? "Present" : "Low"
        case .safety:
            value > 1.6 ? "Elevated" : value > 0.7 ? "Moderate" : "Low"
        }
    }

    /// The mechanistic lenses, in display order (excludes ``timeline``).
    static let mechanistic: [EffectLens] = [.feeling, .energy, .urge, .safety]
}
