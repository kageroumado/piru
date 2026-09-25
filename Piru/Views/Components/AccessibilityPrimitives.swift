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

    /// Grows a small control's touch target to at least `side` points square,
    /// centered on what is drawn, without moving anything: the extra room is
    /// padding that the same negative padding hands straight back to layout.
    /// Apply it to the control's label, where the content shape belongs. A
    /// `.plain`-styled button also reports the grown frame to assistive tech.
    func minimumHitTarget(_ side: CGFloat = 44) -> some View {
        modifier(MinimumHitTarget(side: side))
    }
}

private struct MinimumHitTarget: ViewModifier {
    let side: CGFloat
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let horizontal = max(0, (side - size.width) / 2)
        let vertical = max(0, (side - size.height) / 2)
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .contentShape([.interaction, .accessibility], .rect)
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
    }
}
