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
/// rather than a generic SF Symbol. `AppIconArtwork` is the system-rendered Liquid Glass icon —
/// squircle, specular sheen, and rim light baked in by the OS icon pipeline — so we draw it as-is
/// and add only a drop shadow to lift it off the page.
struct OnboardingAppIconHero: View {
    var size: CGFloat = 108

    var body: some View {
        Image("AppIconArtwork")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.045)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Wraps a bullet list in the app's grouped-card surface (matching Settings/inset-grouped
    /// rows) so the "what you get" lists read as a cohesive card rather than floating text.
    func onboardingGroupedCard() -> some View {
        padding(18)
            .themeCard(cornerRadius: Theme.CornerRadius.card)
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .sectionLabel()
                Text(detail)
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
            GlassPillButton(title: "Get Started", action: nav.advance)
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
            .padding(.horizontal, Spacing.xxxl)
            .padding(.top, 28)
        } footer: {
            GlassPillButton(title: "Continue", action: nav.advance)
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
            .insetGroupedListStyle()
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 340)
            .padding(.top, Spacing.md)
        } footer: {
            GlassPillButton(title: "Continue") {
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
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.displayName)
                        .sectionLabel()
                        .foregroundStyle(.primary)
                    Text(tier.summary)
                        .captionSecondary()
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
            }
            .contentShape(.rect)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .listRowBackground(CardBackground())
    }
}

// MARK: - Reminders

struct OnboardingRemindersStep: View {
    @Environment(\.onboardingNav) private var nav
    @State private var requesting = false

    // Progressive, benefit-framed disclosure (notifications spec, Stage 4):
    // the user opts into meaningful groups rather than answering one blanket
    // prompt or facing a wall of nine switches. All three start on; each
    // group is one tap to decline.
    @State private var doseReminders = true
    @State private var sessionAlerts = true
    @State private var safetyNet = true

    var body: some View {
        OnboardingLayout(
            title: "Notifications, your pick",
            subtitle: "Choose what Piru may send. Everything stays adjustable in Settings, switch by switch.",
        ) {
            OnboardingIconHero(symbol: "bell.badge")
        } mid: {
            VStack(spacing: 18) {
                OnboardingToggleRow(
                    symbol: "repeat",
                    title: "Never miss a dose",
                    detail: "Reminders at each routine's time — and, if you want, a gentle re-ask a little later, like snooze.",
                    isOn: $doseReminders,
                )
                OnboardingToggleRow(
                    symbol: "drop",
                    title: "During a session",
                    detail: "Hydration and wind-down nudges, wearing-off alerts, and onset/peak timing cues while something is active.",
                    isOn: $sessionAlerts,
                )
                OnboardingToggleRow(
                    symbol: "exclamationmark.triangle",
                    title: "A safety net",
                    detail: "A heads-up if one substance's daily total climbs into a heavy range, or tracked stock runs low.",
                    isOn: $safetyNet,
                )
            }
            .onboardingGroupedCard()
            .padding(.horizontal, Spacing.xxxl)
            .padding(.top, 28)
        } footer: {
            GlassPillButton(title: requesting ? "Turning On…" : "Enable Selected") {
                Task { await enableSelected() }
            }
            GlassPillButton(title: "Not Now", prominence: .neutral, action: nav.advance)
        }
    }

    private func enableSelected() async {
        guard !requesting else { return }
        let anySelected = doseReminders || sessionAlerts || safetyNet
        if anySelected {
            // The single OS prompt, asked at the moment of the first yes.
            requesting = true
            _ = await DoseNotificationManager.requestAuthorization()
            requesting = false
        }
        // Persist the choices regardless of the grant — if the user denied at
        // the system prompt these are harmless no-ops, and the Notifications
        // screen surfaces the denied state with a path back to Settings.
        let prefs = NotificationPreferencesStore.shared
        prefs.setEnabled(.routine, doseReminders)
        prefs.setEnabled(.routineFollowUp, doseReminders)
        prefs.setEnabled(.nextDose, doseReminders)
        prefs.setEnabled(.comedown, sessionAlerts)
        prefs.setEnabled(.hydration, sessionAlerts)
        prefs.setEnabled(.sleep, sessionAlerts)
        prefs.setEnabled(.phase, sessionAlerts)
        prefs.setEnabled(.cumulative, safetyNet)
        prefs.setEnabled(.inventory, safetyNet)
        nav.advance()
    }
}

/// An ``OnboardingBulletRow`` with a trailing switch — the progressive
/// notification groups are opt-in choices, not just descriptions.
struct OnboardingToggleRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 34)
                .accessibilityHidden(true)
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .sectionLabel()
                    Text(detail)
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
        }
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
            .padding(.horizontal, Spacing.xxxl)
            .padding(.top, 28)
        } footer: {
            GlassPillButton(title: "Start Using Piru", action: nav.finish)
        }
    }
}
