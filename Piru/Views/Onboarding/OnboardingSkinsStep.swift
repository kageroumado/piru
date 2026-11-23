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
    @State private var focused: Skin = SkinStore.shared.current

    var body: some View {
        OnboardingLayout(
            title: "Make it yours",
            subtitle: "Buy once, keep forever. Skins keep Piru independent: no ads, no subscription, and every feature free.",
        ) {
            EmptyView()
        } mid: {
            VStack(spacing: Spacing.xxl) {
                SkinWardrobe(focused: $focused)
                VStack(alignment: .leading, spacing: 18) {
                    SkinShopOffers()
                }
                .buttonStyle(.plain)
                .onboardingGroupedCard()
                .padding(.horizontal, Spacing.xxxl)
            }
            .padding(.top, 24)
        } footer: {
            GlassPillButton(title: "Continue", action: nav.advance)
        }
    }
}

#Preview {
    NavigationStack { OnboardingSkinsStep() }
}
