import SwiftUI

/// A timeline or one of the two session effect estimates.
nonisolated enum EffectLens: String, CaseIterable, Identifiable {
    /// Classic per-substance duration bells — the universal default, works for
    /// anything logged (rendered by the existing `TimelineGraphView`).
    case timeline
    /// Dopamine reward + serotonin warmth + opioid liking, minus the comedown.
    case feeling
    /// Focused, activated energy (NE + cortical DA). Dips into sedation.
    case energy
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
        }
    }

    var symbol: String {
        switch self {
        case .timeline: "chart.xyaxis.line"
        case .feeling: "face.smiling"
        case .energy: "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .timeline: Color(hex: "8e8e93")
        case .feeling: Color(hex: "ff9f0a")
        case .energy: Color(hex: "ff6b35")
        }
    }

    /// The ``EffectTimeline`` channel this lens reads. `nil` for ``timeline``,
    /// which is drawn from the classic duration model instead.
    var channel: KeyPath<EffectTimeline, [Double]>? {
        switch self {
        case .timeline: nil
        case .feeling: \.eu
        case .energy: \.drive
        }
    }

    /// Whether the modeled value can fall below zero.
    var isSigned: Bool {
        switch self {
        case .feeling, .energy: true
        case .timeline: false
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
        case .energy: (2.0, -0.95)
        }
    }

    /// Qualitative label for a sampled model value.
    func readout(_ value: Double) -> LocalizedStringKey {
        switch self {
        case .timeline:
            ""
        case .feeling:
            value > 1.2 ? "Euphoric" : value > 0.4 ? "Good" : value > -0.2 ? "Mild" : "Comedown"
        case .energy:
            value > 1.5 ? "Wired" : value > 0.4 ? "Driven" : value > -0.4 ? "Flat" : "Sedated"
        }
    }

    static let mechanisticBase: [EffectLens] = [.feeling, .energy]
}
