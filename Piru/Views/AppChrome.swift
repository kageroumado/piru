import SwiftUI

/// Shared `•••` overflow toolbar menu: optional per-screen `menuExtras`
/// followed by the always-present Help, then Skins/Settings. Used as a trailing
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
            // Trailing Sections keep the always-present app actions grouped
            // below any per-screen extras, with no dangling divider when
            // `menuExtras` is empty. Help stands alone above the two that
            // change the app.
            Section {
                Button { present(.help) } label: {
                    Label("Help", systemImage: "lifepreserver")
                }
            }
            Section {
                Button { present(.skins) } label: {
                    Label("Skins", systemImage: "paintbrush")
                }
                Button { present(.settings) } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.sectionTitle)
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
                        ToolbarItem(placement: .platformTopBarTrailing) {
                            AppOverflowMenu(menuExtras: menuExtras)
                        }
                    }
                }
        } else {
            self
        }
    }
}
