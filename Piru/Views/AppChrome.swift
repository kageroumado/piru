import SwiftUI

/// App-Store "Today"-style header: a large title at the very top with a glass
/// control cluster on its right. The cluster always ends in a `•••` overflow
/// menu (Settings, Help, plus any per-screen `menuExtras`); screens can also
/// inject their own `leadingControls` (e.g. the Journal's grouping picker and
/// filter) before it. Lives in a top `safeAreaBar` (so the soft scroll-edge
/// effect has a bar to render under) and stays pinned while the content
/// scrolls beneath it.
struct ScreenHeaderBar<Leading: View, Extras: View>: View {
    private let title: LocalizedStringKey
    private let leadingControls: Leading
    private let menuExtras: Extras
    @Environment(\.appNavigator) private var navigator

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder leadingControls: () -> Leading = { EmptyView() },
        @ViewBuilder menuExtras: () -> Extras = { EmptyView() },
    ) {
        self.title = title
        self.leadingControls = leadingControls()
        self.menuExtras = menuExtras()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            // One glass container so the per-screen controls and the overflow
            // menu sample/morph as a single floating unit (glass can't sample
            // other glass — grouping them avoids muddy edges).
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    leadingControls
                    overflowMenu
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var overflowMenu: some View {
        Menu {
            menuExtras
            // A trailing Section keeps the always-present app actions visually
            // grouped and below any per-screen extras, with no dangling
            // divider when `menuExtras` is empty.
            Section {
                Button { present(.settings) } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button { present(.help) } label: {
                    Label("Help", systemImage: "lifepreserver")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel(Text("More"))
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

/// Attaches the standard app header (title + control cluster) to a scrollable
/// screen: pins it as a top bar for the soft scroll-edge blur and hides the
/// system navigation bar.
private struct AppHeaderModifier<Leading: View, Extras: View>: ViewModifier {
    let title: LocalizedStringKey
    @ViewBuilder let leadingControls: () -> Leading
    @ViewBuilder let menuExtras: () -> Extras

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                ScreenHeaderBar(
                    title,
                    leadingControls: leadingControls,
                    menuExtras: menuExtras,
                )
            }
            .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// App-Store-style large title header with a `•••` overflow (Settings/Help)
    /// plus optional per-screen `leadingControls` and `menuExtras`. Soft
    /// scroll-edge effect; the header stays pinned. Apply to a scrollable tab
    /// root.
    func appHeader(
        _ title: LocalizedStringKey,
        @ViewBuilder leadingControls: @escaping () -> some View = { EmptyView() },
        @ViewBuilder menuExtras: @escaping () -> some View = { EmptyView() },
    ) -> some View {
        modifier(AppHeaderModifier(title: title, leadingControls: leadingControls, menuExtras: menuExtras))
    }

    /// Applies ``appHeader(_:leadingControls:menuExtras:)`` only when `enabled`
    /// — e.g. a view used both as a tab root (header on) and embedded in the
    /// Search surface (header off).
    @ViewBuilder
    func appHeader(
        _ title: LocalizedStringKey,
        enabled: Bool,
        @ViewBuilder leadingControls: @escaping () -> some View = { EmptyView() },
        @ViewBuilder menuExtras: @escaping () -> some View = { EmptyView() },
    ) -> some View {
        if enabled {
            appHeader(title, leadingControls: leadingControls, menuExtras: menuExtras)
        } else {
            self
        }
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
