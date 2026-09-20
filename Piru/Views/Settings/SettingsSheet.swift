import SwiftUI

/// The Settings sheet, which shrinks to a panel while Appearance is open.
///
/// Trying a skin on re-dresses the whole app, so the best preview of a skin is
/// the app itself: the panel leaves the screen behind it in view, undimmed and
/// still scrollable, and the person watches their own journal change as the
/// carousel moves. Every other Settings screen is a full-height sheet.
struct SettingsSheet: View {
    @State private var showsPanel = false
    @State private var detent: PresentationDetent = .large

    /// Tall enough for the carousel, its caption and its button; everything
    /// under them scrolls, or the panel can be pulled up to full height.
    static let panel: PresentationDetent = .height(452)

    var body: some View {
        NavigationStack { SettingsView() }
            .environment(\.settingsPanel, SettingsPanel { wantsPanel in
                showsPanel = wantsPanel
                detent = wantsPanel ? Self.panel : .large
            })
            .presentationDetents(showsPanel ? [Self.panel, .large] : [.large], selection: $detent)
            .presentationBackgroundInteraction(showsPanel ? .enabled(upThrough: Self.panel) : .automatic)
    }
}

/// How a Settings screen asks the sheet it lives in to become a panel.
struct SettingsPanel {
    var setActive: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var settingsPanel = SettingsPanel()
}
