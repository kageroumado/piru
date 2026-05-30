import SwiftUI

/// Settings + Help buttons, both pinned to the top-right of the navigation bar.
/// Shared across the main tabs so every screen exposes the same chrome.
struct AppToolbarButtons: ToolbarContent {
    @Environment(\.appNavigator) private var navigator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.help)
            } label: {
                Image(systemName: "lifepreserver")
            }
            Button {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.settings)
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}

/// App-Store–style in-content large title: it lives at the top of the scroll
/// content, scrolls away with it, and is never replaced by a centered inline
/// navigation title (the screens that use it set no `navigationTitle`).
struct ScreenHeader: View {
    private let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
