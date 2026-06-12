import SwiftUI

/// Shared `•••` overflow toolbar menu: optional per-screen `menuExtras`
/// followed by the always-present Settings/Help. Used as a trailing
/// `ToolbarItem` on every tab root.
struct AppOverflowMenu<Extras: View>: View {
    @Environment(\.appNavigator) private var navigator
    @ViewBuilder var menuExtras: () -> Extras

    init(@ViewBuilder menuExtras: @escaping () -> Extras = { EmptyView() }) {
        self.menuExtras = menuExtras
    }

    var body: some View {
        Menu {
            menuExtras()
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
        }
        .accessibilityLabel(Text("More"))
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

extension View {
    /// The app's standard chrome for a tab root: a system navigation bar in
    /// inline-large style (non-collapsing bar, large-styled title that morphs
    /// to the small inline title on scroll), the soft top scroll-edge effect,
    /// and — unless `showsOverflow` is false because the screen builds its own
    /// toolbar — a trailing ``AppOverflowMenu``. Per-screen toolbar items are
    /// added by the caller with a regular `.toolbar { }`.
    ///
    /// `enabled` mirrors the old custom-header switch: a view used both as a
    /// tab root (chrome on) and embedded in the Search surface (chrome off).
    @ViewBuilder
    func appNavigationBar(
        _ title: LocalizedStringKey,
        enabled: Bool = true,
        showsOverflow: Bool = true,
        @ViewBuilder menuExtras: @escaping () -> some View = { EmptyView() },
    ) -> some View {
        if enabled {
            navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .toolbar {
                    if showsOverflow {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppOverflowMenu(menuExtras: menuExtras)
                        }
                    }
                }
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
