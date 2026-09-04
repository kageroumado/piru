import SwiftUI

/// The phase a point of a substance's effect curve is in. The strip's stroke
/// carries it as a color shift along the line — the substance color itself at
/// the peak, lighter while the effect is arriving, warmer and deeper while it
/// leaves, washed out once only the afterglow is left.
nonisolated enum TimelineCurvePhase: Hashable, CaseIterable {
    /// From the dose to the end of the come-up.
    case onset
    case peak
    case offset
    /// The afterglow, from the offset's end to the modeled total.
    case after

    /// The phase of the newest dose whose window contains `t`. A redose
    /// restarts the arc, so the line turns light again at the moment it was
    /// taken; `nil` outside every window.
    static func phase(at t: Date, states: [ActiveSubstanceState]) -> TimelineCurvePhase? {
        var newest: (start: Date, phase: TimelineCurvePhase)?
        for state in states {
            guard let phase = phase(minutes: t.timeIntervalSince(state.doseTimestamp) / 60, of: state) else { continue }
            if newest.map({ state.doseTimestamp > $0.start }) ?? true {
                newest = (state.doseTimestamp, phase)
            }
        }
        return newest?.phase
    }

    /// The phase `minutes` after `state`'s dose, `nil` before the dose or past
    /// its modeled total.
    static func phase(minutes: Double, of state: ActiveSubstanceState) -> TimelineCurvePhase? {
        guard minutes >= 0, minutes <= state.totalMinutes else { return nil }
        if minutes < state.comeupEndMinutes { return .onset }
        if minutes < state.peakEndMinutes { return .peak }
        if minutes < state.offsetEndMinutes { return .offset }
        return .after
    }

    /// This phase's color, as a shift from the substance color: onset is
    /// lighter (+0.12 L), peak is the color itself, offset turns toward the
    /// warmer neighbor (+15° hue) and deeper (−0.06 L), after keeps half the
    /// chroma.
    func shifted(_ base: Oklch) -> Oklch {
        switch self {
        case .onset: base.shifted(lightness: 0.12)
        case .peak: base
        case .offset: base.shifted(lightness: -0.06, hue: 15)
        case .after: base.shifted(chromaScale: 0.5)
        }
    }
}

/// A run of consecutive curve points in one phase. Neighboring runs share
/// their boundary point, so the strokes meet without a gap.
nonisolated struct TimelineCurveSegment: Equatable {
    let range: ClosedRange<Int>
    let phase: TimelineCurvePhase?

    /// Splits `phases` (one per curve point, in point order) into runs.
    static func segments(of phases: [TimelineCurvePhase?]) -> [TimelineCurveSegment] {
        guard !phases.isEmpty else { return [] }
        var result: [TimelineCurveSegment] = []
        var start = 0
        for i in 1 ..< phases.count where phases[i] != phases[start] {
            result.append(TimelineCurveSegment(range: start ... i, phase: phases[start]))
            start = i
        }
        result.append(TimelineCurveSegment(range: start ... (phases.count - 1), phase: phases[start]))
        return result
    }
}

/// The per-phase colors of one substance's curve, resolved once per series
/// per draw from the substance color.
struct TimelineCurvePalette {
    let base: Color
    private let colors: [TimelineCurvePhase: Color]

    /// Fraction of a segment's length over which the stroke blends into the
    /// next phase's color.
    static let transitionFraction: CGFloat = 0.1

    init(base: Color, environment: EnvironmentValues) {
        self.base = base
        let resolved = base.resolve(in: environment)
        let oklch = Oklch(
            linearRed: Double(resolved.linearRed),
            green: Double(resolved.linearGreen),
            blue: Double(resolved.linearBlue),
        )
        var colors: [TimelineCurvePhase: Color] = [:]
        for phase in TimelineCurvePhase.allCases {
            let rgb = phase.shifted(oklch).linearRGB
            colors[phase] = Color(.sRGBLinear, red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        self.colors = colors
    }

    /// The stroke color for `phase`; the substance color itself when a point
    /// carries no phase (body-load curves).
    func color(for phase: TimelineCurvePhase?) -> Color {
        phase.flatMap { colors[$0] } ?? base
    }
}
