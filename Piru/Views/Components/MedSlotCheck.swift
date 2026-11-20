import SwiftUI

/// The state glyph of one med slot, shared by the Journal's My Meds card and
/// the Tools tab's My Meds card. A taken slot wears the success check the
/// Adherence screen uses; the accent stays on the empty ring of a slot that is
/// due, the one thing in the row to act on. The glyph differs per state, so it
/// reads without color.
struct MedSlotCheck: View {
    let state: MyMedsCard.SlotState
    /// Pending and past its time.
    let due: Bool

    var body: some View {
        image
            .font(.system(size: 16))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private var image: Image {
        switch state {
        case .taken: Image(systemName: "checkmark.circle.fill")
        case .skipped: Image(systemName: "minus.circle")
        case .pending: Image(systemName: "circle")
        }
    }

    private var color: Color {
        switch state {
        case .taken: Color.successAccent
        case .skipped: Theme.secondaryLabel.opacity(Theme.Opacity.muted)
        case .pending: due ? Theme.accent : Color.platformTertiarySystemFill
        }
    }
}
