import SwiftUI

/// Pick a look, and the one place onboarding mentions money.
///
/// Stopping on a skin tries it on, so this screen — and the step after it —
/// wears it. Continue is never held back and never smaller than the purchase:
/// whoever buys nothing still leaves having chosen a free skin they like.
/// ``SkinStore/settleTryOn()`` keeps an owned choice and drops an unowned one
/// when onboarding finishes.
struct OnboardingSkinsStep: View {
    @Environment(\.onboardingNav) private var nav

    var body: some View {
        OnboardingLayout(
            title: "Make it yours",
            subtitle: "Skins pay for Piru's development. The journal, the library, and every tool are free either way.",
        ) {
            EmptyView()
        } mid: {
            SkinWardrobe(offersUse: false)
                .padding(.top, 24)
        } footer: {
            GlassPillButton(title: "Continue", action: nav.advance)
        }
    }
}

#Preview {
    NavigationStack { OnboardingSkinsStep() }
}
