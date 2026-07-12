import SwiftUI

/// First-run onboarding — a paged, progressive-commitment flow (welcome → privacy → feature
/// tour → personalize depth → Apple Health → reminders → import → done).
///
/// The design follows the health/wellness-app pattern: the earliest screens ask for *nothing*
/// (value prop, privacy reassurance, a feature tour) so the user is invested before any
/// permission is requested, and every step after the intro is skippable so nothing blocks the
/// user from reaching the app. Permissions are asked *just-in-time*, each next to the value it
/// unlocks, rather than batched into a wall of toggles.
///
/// The type name stays `OnboardingView` so the launch gate (`OnboardingGateModifier`) and the
/// `.onboarding` sheet route resolve unchanged; the single-screen toggle list it used to be is
/// replaced by this multi-step machine.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss

    /// The pushed steps after the root welcome screen. Using a real `NavigationStack` gives us the
    /// system back button (a full-size Liquid Glass chevron) for free, plus edge-swipe back and the
    /// standard push/pop transitions — while the progress bar rides in the nav bar's principal
    /// (titlebar) slot.
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingWelcomeStep()
                .modifier(OnboardingStepChrome(step: .welcome))
                .navigationDestination(for: OnboardingStep.self) { step in
                    stepView(step)
                        .modifier(OnboardingStepChrome(step: step))
                }
        }
        .tint(Theme.accent)
        .environment(\.onboardingNav, nav)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: OnboardingWelcomeStep()
        case .privacy: OnboardingPrivacyStep()
        case .tour: OnboardingFeatureTour()
        case .depth: OnboardingDepthStep()
        case .health: OnboardingHealthStep()
        case .reminders: OnboardingRemindersStep()
        case .importData: OnboardingImportStep()
        case .done: OnboardingDoneStep()
        }
    }

    // MARK: - Navigation

    private var nav: OnboardingNav {
        OnboardingNav(advance: advance, finish: finish)
    }

    private func advance() {
        let current = path.last ?? .welcome
        if let next = current.next { path.append(next) } else { finish() }
    }

    private func finish() {
        hasCompletedOnboarding = true
        OnboardingTips.markOnboardingComplete()
        dismiss()
    }
}

// MARK: - Step chrome

/// Wraps each step in the flow's shared nav-bar chrome: a transparent bar (so it blends into the
/// onboarding background), the progress bar in the principal slot for the counted middle steps, and
/// the OLED background. The system supplies the back button on every pushed step (none on the
/// welcome root), which is exactly the "come back a step" affordance we want.
private struct OnboardingStepChrome: ViewModifier {
    @Environment(\.onboardingNav) private var nav
    let step: OnboardingStep

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if OnboardingStep.progressSteps.contains(step) {
                    ToolbarItem(placement: .principal) {
                        OnboardingProgressBar(
                            current: (OnboardingStep.progressSteps.firstIndex(of: step) ?? -1) + 1,
                            total: OnboardingStep.progressSteps.count,
                        )
                        .frame(width: 210)
                    }
                }
                // A bail-out on the welcome screen for people who just want in.
                if step == .welcome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: nav.finish)
                            .tint(Theme.secondaryLabel)
                    }
                }
            }
    }
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case privacy
    case tour
    case depth
    case health
    case reminders
    case importData
    case done

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    /// Steps that show the progress bar + back affordance. The bookend welcome/done screens are
    /// deliberately chromeless for a cleaner first and last impression.
    static let progressSteps: [OnboardingStep] = [.privacy, .tour, .depth, .health, .reminders, .importData]
}

// MARK: - Navigation environment

/// Lightweight closure bundle passed down so each step can drive the flow without owning it. Back
/// navigation is handled by the system nav bar, so only forward/finish are needed here.
struct OnboardingNav {
    var advance: () -> Void
    var finish: () -> Void
}

extension EnvironmentValues {
    @Entry var onboardingNav: OnboardingNav = .init(advance: {}, finish: {})
}

// MARK: - Shared chrome

/// Segmented progress indicator: filled capsules for completed/current steps.
struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Theme.accent : Theme.accent.opacity(0.18))
                    .frame(height: 4)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("Step \(current) of \(total)"))
    }
}

/// Standard step scaffold: a hero visual, a bold title + subtitle, optional mid content, and a
/// footer of up to two buttons — so every step shares the same rhythm and spacing.
struct OnboardingLayout<Hero: View, Mid: View, Footer: View>: View {
    var title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var mid: () -> Mid
    @ViewBuilder var footer: () -> Footer

    init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        @ViewBuilder hero: @escaping () -> Hero,
        @ViewBuilder mid: @escaping () -> Mid = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.hero = hero
        self.mid = mid
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            hero()
                .padding(.bottom, 28)
            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            mid()
            Spacer(minLength: 8)
            VStack(spacing: 12) { footer() }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }
}

/// Primary CTA — a full-width, accent-tinted Liquid Glass pill, matching the system's prominent
/// glass buttons (the "Allow" button on a permission sheet). The tint colors the glass; the style
/// supplies the material, capsule shape, and legible foreground.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Theme.accent)
    }
}

/// Secondary action — a neutral Liquid Glass pill (the "Don't Allow" counterpart) for the
/// skip / not-now / do-this-later escape hatch on optional steps.
struct OnboardingSecondaryButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

#Preview {
    OnboardingView()
}
