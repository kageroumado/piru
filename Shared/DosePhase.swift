import SwiftUI

/// The five phases of an acute dose's arc, with the name and colors every
/// surface draws them in: the dose hero's progress bar, the duration rows, the
/// journal gutter and the session export all read them here, so the bar (the
/// overview) and the rows (the detail) always agree on hue.
///
/// The palette traces the arc of an experience: cool and quiet before it
/// begins (blue), rising (teal), warm at the height (orange), cooling on the
/// way down (purple), then neutral residue (gray). The hues match the timeline
/// graph's to within a degree; only lightness and chroma differ, to clear the
/// contrast gates.
nonisolated enum DosePhase: CaseIterable {
    case onset
    case comeup
    case peak
    case offset
    case afterglow

    /// The phase a dose `elapsedMinutes` in is in. The state's boundaries are
    /// the effect curve's anchors, so this names the stretch of curve drawn at
    /// that moment: Come-up on the rise, Peak on the crest.
    static func at(_ state: ActiveSubstanceState, elapsedMinutes: Double) -> DosePhase {
        if elapsedMinutes <= state.onsetEndMinutes {
            .onset
        } else if elapsedMinutes <= state.comeupEndMinutes {
            .comeup
        } else if elapsedMinutes <= state.peakEndMinutes {
            .peak
        } else if elapsedMinutes <= state.offsetEndMinutes {
            .offset
        } else {
            .afterglow
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .onset: "Onset"
        case .comeup: "Come-up"
        case .peak: "Peak"
        case .offset: "Offset"
        case .afterglow: "Afterglow"
        }
    }

    /// Mark color: dots, bar fills, chart bands. Gated at the 3:1 non-text
    /// floor. Text uses ``labelColor``.
    @MainActor var color: Color {
        switch self {
        case .onset: .Phase.Onset.accent
        case .comeup: .Phase.Comeup.accent
        case .peak: .Phase.Peak.accent
        case .offset: .Phase.Offset.accent
        case .afterglow: .Phase.Afterglow.accent
        }
    }

    /// Legible text variant of ``color``, for a phase word on the bare card;
    /// clears AA against it.
    @MainActor var labelColor: Color {
        switch self {
        case .onset: .Phase.Onset.text
        case .comeup: .Phase.Comeup.text
        case .peak: .Phase.Peak.text
        case .offset: .Phase.Offset.text
        case .afterglow: .Phase.Afterglow.text
        }
    }
}
