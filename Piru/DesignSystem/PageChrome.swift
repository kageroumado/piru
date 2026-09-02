import SwiftUI

extension View {
    /// The app's page backdrop for a `List` or `Form`: drop the system's own
    /// scroll background and paint ``Theme/background`` behind it, so a grouped
    /// list reaches true black in dark mode like every other surface.
    func themedPage() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}
