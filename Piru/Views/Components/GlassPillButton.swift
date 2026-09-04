import SwiftUI

/// A full-width pill CTA — the app's one standard for prominent standalone
/// actions (onboarding steps, empty-state CTAs, list-footer actions).
/// `.prominent` is the accent-tinted primary (the system "Allow" pill);
/// `.neutral` is its plain counterpart for skip / not-now escape hatches.
/// The skin supplies the form (Liquid Glass, or an edged sticker) through
/// ``skinButtonStyle``; `controlSize(.large)` gives the system pill height so
/// the label always sits optically centered.
struct GlassPillButton: View {
    enum Prominence {
        case prominent
        case neutral
    }

    let title: LocalizedStringResource
    var prominence: Prominence = .prominent
    let action: () -> Void

    var body: some View {
        switch prominence {
        case .prominent:
            button
                .skinButtonStyle(.prominent)
                .controlSize(.large)
                .tint(Theme.accent)
        case .neutral:
            button
                .skinButtonStyle(.neutral)
                .controlSize(.large)
        }
    }

    private var button: some View {
        Button(action: action) {
            // The style owns the prominent label colour (system glass, or the
            // skin's on-accent ink); only the neutral label sets its own.
            label
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var label: some View {
        let text = Text(title).cardTitle()
        if prominence == .neutral {
            text.foregroundStyle(Theme.secondaryLabel)
        } else {
            text
        }
    }
}
