import SwiftUI

/// A half-width card that pushes one screen: tinted icon, title, and a
/// two-line subtitle in a compact `themeCard`. The Tools and Insights tabs lay
/// these out in a two-column grid under their full-width cards.
struct CompactLinkCard: View {
    let icon: String
    var tint: Color = Theme.accent
    let title: Text
    let subtitle: Text
    let route: PushRoute

    var body: some View {
        RouteLink(route) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.piru(.title3))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
