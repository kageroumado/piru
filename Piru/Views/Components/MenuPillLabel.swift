import SwiftUI

/// The tray menu-pill scaffold shared by ``BrandPicker``, ``IsomerPicker``, and
/// ``SaltPicker``: a capsule label (icon · text · chevron) with the actual
/// `Menu` as an invisible overlay.
///
/// Decoupled + fixed-size like the tray's route pill on purpose: a `Menu`
/// label is sized by the UIKit menu button outside the SwiftUI transaction, so
/// the tray's expand/collapse `matchedGeometryEffect` interpolated a stale
/// frame and clipped the label. The visible chrome stays a plain SwiftUI view;
/// only a clear content shape belongs to the menu button.
struct MenuPillLabel<MenuContent: View>: View {
    let systemImage: String
    let text: String
    let namespace: Namespace.ID
    let geometryID: String
    let height: CGFloat
    /// VoiceOver name for the invisible menu button (the chrome itself is
    /// hidden from accessibility).
    let accessibilityLabel: Text
    let accessibilityValue: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(text)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .frame(height: height)
        .background(Color(.secondarySystemFill), in: Capsule())
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                menuContent()
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
        }
        .matchedGeometryEffect(id: geometryID, in: namespace)
    }
}
