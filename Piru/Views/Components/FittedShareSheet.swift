import SwiftUI

/// The frame both share sheets sit in: an inline-titled navigation stack with a
/// close button, a scrolling body, and a first detent sized to that body so the
/// sheet comes up showing everything.
struct FittedShareSheet<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat
    @State private var safeAreaBottom: CGFloat = 34

    /// Inline nav bar + grabber allowance — the chrome above the scroll content
    /// that `.height` detents must include but `contentHeight` omits.
    private static var chromeAllowance: CGFloat {
        64
    }

    /// `estimatedHeight` is the body's height until it has been measured.
    init(_ title: LocalizedStringKey, estimatedHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _contentHeight = State(initialValue: estimatedHeight)
    }

    /// The detent that shows everything: measured content + nav-bar chrome +
    /// the bottom safe-area inset (home indicator), so it doesn't come up short.
    private var fittedHeight: CGFloat {
        contentHeight + Self.chromeAllowance + safeAreaBottom
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = max(0, $0) }
        }
        .presentationDetents([.height(fittedHeight), .large])
        .presentationDragIndicator(.visible)
    }
}

extension Label {
    /// The "Tap to…" hint laid over a share preview's corner: a caption on a
    /// material capsule, `inset` from the corner, letting taps through to the
    /// preview beneath.
    func shareHintPill(inset: CGFloat) -> some View {
        font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(inset)
            .allowsHitTesting(false)
    }
}
