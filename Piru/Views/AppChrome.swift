import SwiftUI

/// App-Store "Today"-style header: a large in-content title at the very top of
/// the scroll content, with Help + Settings on a glass pill to its right.
///
/// It lives inside the scrollable content (so the title scrolls away and is
/// never replaced by a centered inline title). Screens using it hide the system
/// navigation bar and set no `navigationTitle`.
struct ScreenHeaderBar: View {
    private let title: LocalizedStringKey
    @Environment(\.appNavigator) private var navigator

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                iconButton("lifepreserver") { present(.help) }
                iconButton("gearshape") { present(.settings) }
            }
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

/// Reusable content for a tappable overview card — leading icon, title, one or
/// more detail lines, trailing chevron. Wrap in a `NavigationLink`.
struct NavCardLabel<Detail: View>: View {
    let icon: String
    let title: Text
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.headline)
                    .foregroundStyle(.primary)
                detail()
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
        .contentShape(Rectangle())
    }
}
