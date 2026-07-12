import SwiftUI

/// The "·" separator used between caption fragments throughout the app,
/// pre-hidden from VoiceOver so it never reads as a lone "middle dot" stop.
/// Font and foreground style are inherited from the caller like any `Text`.
struct Middot: View {
    var body: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }
}

extension View {
    /// Collapses a chart (or any composite drawing) into a single VoiceOver
    /// element that speaks a name and a data summary, instead of per-mark
    /// fragments or — for `Canvas` charts — nothing at all.
    func chartSummaryAccessibility(label: Text, value: Text) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}
