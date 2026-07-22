import SwiftUI

/// A full-width Liquid Glass pill CTA — the app's one standard for prominent
/// standalone actions (onboarding steps, empty-state CTAs, list-footer
/// actions). `.prominent` is the accent-tinted primary (the system "Allow"
/// pill); `.neutral` is its plain-glass counterpart for skip / not-now
/// escape hatches. The style supplies the material, capsule shape, and
/// legible foreground; `controlSize(.large)` gives the system pill height so
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
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Theme.accent)
        case .neutral:
            button
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(prominence == .neutral ? AnyShapeStyle(Theme.secondaryLabel) : AnyShapeStyle(.foreground))
                .frame(maxWidth: .infinity)
        }
    }
}
