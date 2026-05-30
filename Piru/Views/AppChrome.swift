import SwiftUI

/// App-Store "Today"-style header: a large title at the very top with Help +
/// Settings on a glass pill to its right. Lives in a top `safeAreaBar` (so the
/// soft scroll-edge effect has a bar to render under), and fades + slides up as
/// the content scrolls so it reads as "scrolling away".
struct ScreenHeaderBar: View {
    private let title: LocalizedStringKey
    private let scrollOffset: CGFloat
    @Environment(\.appNavigator) private var navigator

    /// Distance over which the header fades out and finishes sliding up.
    private let fadeDistance: CGFloat = 44

    init(_ title: LocalizedStringKey, scrollOffset: CGFloat = 0) {
        self.title = title
        self.scrollOffset = scrollOffset
    }

    var body: some View {
        let progress = min(max(scrollOffset / fadeDistance, 0), 1)
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
        .opacity(1 - progress)
        .offset(y: -min(scrollOffset, fadeDistance))
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

/// Attaches the standard app header (title + Help/Settings) to a scrollable
/// screen: pins it as a top bar for the soft scroll-edge blur, tracks scroll so
/// the header fades/slides away, and hides the system navigation bar.
private struct AppHeaderModifier: ViewModifier {
    let title: LocalizedStringKey
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, value in
                scrollOffset = value
            }
            .safeAreaBar(edge: .top) {
                ScreenHeaderBar(title, scrollOffset: scrollOffset)
            }
            .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// App-Store-style large title header with Help/Settings, soft scroll-edge,
    /// and scroll-away fade. Apply to a scrollable tab root.
    func appHeader(_ title: LocalizedStringKey) -> some View {
        modifier(AppHeaderModifier(title: title))
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
