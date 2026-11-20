import SwiftUI

/// A half-width card that pushes a route: tinted icon, a title and a subtitle of
/// at most two lines each, in a compact `themeCard`. Sized for a two-column grid.
struct CompactRouteCard: View {
    let icon: String
    let tint: Color
    let title: Text
    let subtitle: Text
    let route: PushRoute

    init(icon: String, tint: Color = Theme.accent, title: Text, subtitle: Text, route: PushRoute) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.route = route
    }

    init(icon: String, tint: Color = Theme.accent, title: LocalizedStringKey, subtitle: LocalizedStringKey, route: PushRoute) {
        self.init(icon: icon, tint: tint, title: Text(title), subtitle: Text(subtitle), route: route)
    }

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
