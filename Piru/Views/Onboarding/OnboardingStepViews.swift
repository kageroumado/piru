import SwiftUI

// MARK: - Reusable pieces

/// A rounded "squircle" tile with a soft accent gradient and a centered SF Symbol — the hero
/// used by the text-forward steps (welcome, privacy, reminders, done, depth).
struct OnboardingIconHero: View {
    let symbol: String
    var size: CGFloat = 96

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Theme.accent.opacity(0.14)),
            )
            .accessibilityHidden(true)
    }
}

/// The app icon as the welcome-screen hero, so the first thing a user sees is the app's face
/// rather than a generic SF Symbol. `AppIconArtwork` is the *flat* icon composite (the same layers
/// the OS icon pipeline consumes); we recreate the Liquid Glass look the way the system does — clip
/// to the icon squircle, then layer a specular sheen, a top rim light, and a drop shadow. Keeping
/// the source flat means it stays crisp at any size and matches the on-device icon's colour.
struct OnboardingAppIconHero: View {
    var size: CGFloat = 108

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        Image("AppIconArtwork")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                // Specular sheen — brightest along the top, gone by the middle.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.38), .white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .center,
                    ),
                )
                .blendMode(.softLight)
            }
            .overlay {
                // A crisp rim light along the top edge that fades toward the bottom.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: max(0.75, size * 0.006),
                )
            }
            .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.045)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Wraps a bullet list in the app's grouped-card surface (matching Settings/inset-grouped
    /// rows) so the "what you get" lists read as a cohesive card rather than floating text.
    func onboardingGroupedCard() -> some View {
        padding(18)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Icon + title + supporting line, used for the small "what you get" lists inside steps.
struct OnboardingBulletRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    @Environment(\.onboardingNav) private var nav

    var body: some View {
        OnboardingLayout(
            title: "Welcome to Piru",
            subtitle: "Track what you take — and understand how it affects your body.",
        ) {
            OnboardingAppIconHero(size: 108)
        } footer: {
            OnboardingPrimaryButton(title: "Get Started", action: nav.advance)
        }
    }
}

// MARK: - Privacy

struct OnboardingPrivacyStep: View {
    @Environment(\.onboardingNav) private var nav

    var body: some View {
        OnboardingLayout(
            title: "Private by design",
            subtitle: "Piru is built for sensitive data. Yours never leaves your device unless you choose.",
        ) {
            OnboardingIconHero(symbol: "lock.shield")
        } mid: {
            VStack(spacing: 18) {
                OnboardingBulletRow(
                    symbol: "iphone",
                    title: "Stays on your device",
                    detail: "Your journal lives locally. No sign-up, no account required.",
                )
                OnboardingBulletRow(
                    symbol: "icloud.slash",
                    title: "No cloud unless you ask",
                    detail: "Backups are opt-in and end-to-end encrypted with your key.",
                )
                OnboardingBulletRow(
                    symbol: "hand.raised",
                    title: "Never sold or shared",
                    detail: "There are no ads and no trackers. Your data is yours alone.",
                )
            }
            .onboardingGroupedCard()
            .padding(.horizontal, 24)
            .padding(.top, 28)
        } footer: {
            OnboardingPrimaryButton(title: "Continue", action: nav.advance)
        }
    }
}

// MARK: - Personalize depth

struct OnboardingDepthStep: View {
    @Environment(\.onboardingNav) private var nav
    @State private var selection: UserProfile = .harmReduction

    var body: some View {
        OnboardingLayout(
            title: "How much detail?",
            subtitle: "Piru can keep it simple or go deep into the pharmacology. Change this anytime in Settings.",
        ) {
            OnboardingIconHero(symbol: "slider.horizontal.3")
        } mid: {
            // A grouped List so the rows adopt the system's adaptive inset-grouped shape (larger,
            // continuous corners that match the rest of the app's settings surfaces).
            List(UserProfile.allCases) { tier in
                tierRow(tier)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 340)
            .padding(.top, 8)
        } footer: {
            OnboardingPrimaryButton(title: "Continue") {
                UserProfileStore.shared.setDisclosureTier(selection)
                nav.advance()
            }
        }
    }

    private func tierRow(_ tier: UserProfile) -> some View {
        let isSelected = selection == tier
        return Button {
            withAnimation(.smooth(duration: 0.2)) { selection = tier }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: tier.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryLabel)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(tier.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.cardBackground)
    }
}

// MARK: - Reminders

struct OnboardingRemindersStep: View {
    @Environment(\.onboardingNav) private var nav
    @AppStorage("wellnessNotificationsEnabled") private var wellnessNotificationsEnabled = false
    @AppStorage("phaseNotificationsEnabled") private var phaseNotificationsEnabled = false
    @State private var requesting = false

    var body: some View {
        OnboardingLayout(
            title: "Gentle reminders",
            subtitle: "Optional nudges that look out for you while a substance is active.",
        ) {
            OnboardingIconHero(symbol: "bell.badge")
        } mid: {
            VStack(spacing: 18) {
                OnboardingBulletRow(
                    symbol: "drop",
                    title: "Stay hydrated",
                    detail: "A reminder to drink water during stimulants and long sessions.",
                )
                OnboardingBulletRow(
                    symbol: "moon.zzz",
                    title: "Wind down for sleep",
                    detail: "A heads-up when it's late enough that another dose could cost you sleep.",
                )
                OnboardingBulletRow(
                    symbol: "waveform.path.ecg",
                    title: "Know the phases",
                    detail: "Optional alerts for onset, come-up, and peak so nothing catches you off guard.",
                )
            }
            .onboardingGroupedCard()
            .padding(.horizontal, 24)
            .padding(.top, 28)
        } footer: {
            OnboardingPrimaryButton(title: requesting ? "Turning On…" : "Turn On Reminders") {
                Task { await enableReminders() }
            }
            OnboardingSecondaryButton(title: "Not Now", action: nav.advance)
        }
    }

    private func enableReminders() async {
        guard !requesting else { return }
        requesting = true
        let granted = await RampDownScheduler.requestPermissionIfNeeded()
        requesting = false
        // Persist the intent regardless — if the user denied at the system prompt the toggles are
        // harmless no-ops, and the Settings screen surfaces how to re-enable notifications.
        wellnessNotificationsEnabled = granted
        phaseNotificationsEnabled = granted
        nav.advance()
    }
}

// MARK: - Done

struct OnboardingDoneStep: View {
    @Environment(\.onboardingNav) private var nav

    var body: some View {
        OnboardingLayout(
            title: "You're all set",
            subtitle: "Tap the + button any time to log your first dose. Tips will point out the rest as you go.",
        ) {
            OnboardingIconHero(symbol: "checkmark.seal.fill", size: 108)
        } mid: {
            VStack(spacing: 18) {
                OnboardingBulletRow(
                    symbol: "bolt.heart",
                    title: "Live Activity, when you want it",
                    detail: "Start one from any active session to watch it on your Lock Screen.",
                )
                OnboardingBulletRow(
                    symbol: "archivebox.fill",
                    title: "Track your stock",
                    detail: "Keep tabs on what you have on hand and get a heads-up when it runs low.",
                )
                OnboardingBulletRow(
                    symbol: "lock.shield",
                    title: "Back up anytime",
                    detail: "Turn on end-to-end encrypted backups whenever you're ready.",
                )
            }
            .onboardingGroupedCard()
            .padding(.horizontal, 24)
            .padding(.top, 28)
        } footer: {
            OnboardingPrimaryButton(title: "Start Using Piru", action: nav.finish)
        }
    }
}
