import SwiftUI
import TipKit

/// First-run contextual tips. Onboarding stays deliberately light — instead of explaining every
/// affordance up front, these TipKit popovers point things out *in context*, the first time the
/// user is somewhere they'd matter. Gated on `onboardingComplete` so they never fire behind the
/// onboarding cover.
enum OnboardingTips {
    /// Configure the TipKit datastore once at launch, then seed the onboarding-complete parameter
    /// from persisted state so returning users (who won't re-run onboarding) still become eligible.
    static func configure() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            markOnboardingComplete()
        }
    }

    /// Flip every onboarding-gated tip's eligibility on. Called when onboarding finishes and at
    /// launch for users who already completed it.
    static func markOnboardingComplete() {
        LogDoseTip.onboardingComplete = true
    }

    /// Record whether the user has ever logged a dose. This advances the tip ladder: the "log a
    /// dose" tip retires once true, and the "where your data lives" tip becomes eligible.
    static func updateEngagement(hasLoggedDose: Bool) {
        LogDoseTip.hasLoggedFirstDose = hasLoggedDose
    }
}

/// Points at the "Log a dose" accessory the first time the Journal is seen after onboarding, and
/// retires itself once the user has actually logged something.
struct LogDoseTip: Tip {
    @Parameter static var onboardingComplete: Bool = false
    /// Shared across the ladder — also read by ``SettingsDataTip`` to sequence after this one.
    @Parameter static var hasLoggedFirstDose: Bool = false

    var title: Text {
        Text("Log your first dose")
    }
    var message: Text? {
        Text("Tap here any time to record what you've taken — it only takes a few seconds.")
    }
    var image: Image? {
        Image(systemName: "plus.circle.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$onboardingComplete) { $0 == true }
        #Rule(Self.$hasLoggedFirstDose) { $0 == false }
    }
}

/// Once the user has logged a dose, points at the ••• menu to reveal that backups, export/import,
/// and preferences all live under Settings — the one thing the tour deliberately doesn't cover.
struct SettingsDataTip: Tip {
    var title: Text {
        Text("Your data lives here")
    }
    var message: Text? {
        Text("Backups, export & import, and preferences are all under Settings.")
    }
    var image: Image? {
        Image(systemName: "gearshape")
    }

    var rules: [Rule] {
        #Rule(LogDoseTip.$onboardingComplete) { $0 == true }
        #Rule(LogDoseTip.$hasLoggedFirstDose) { $0 == true }
    }
}

/// Appears on a session's detail screen, where a Live Activity can actually be started — so the
/// feature is introduced exactly when it's usable, not as onboarding friction.
struct LiveActivityTip: Tip {
    var title: Text {
        Text("Track it on your Lock Screen")
    }
    var message: Text? {
        Text("Start a Live Activity to follow this session on your Lock Screen and Dynamic Island.")
    }
    var image: Image? {
        Image(systemName: "bolt.heart")
    }
}
