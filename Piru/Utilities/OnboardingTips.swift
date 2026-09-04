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
        #if DEBUG
            // Debug builds reset the simulator constantly and every reset re-arms the whole
            // ladder, so tips stay hidden unless a run opts in with `-piruShowTips YES`.
            if !UserDefaults.standard.bool(forKey: "piruShowTips") {
                Tips.hideAllTipsForTesting()
            }
        #endif
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

    /// Retire the "log a dose" tip the moment the button is tapped — the point has been made,
    /// whether or not the log is completed. Closing the tip (its ✕) already invalidates it.
    static func logDoseInvoked() {
        LogDoseTip().invalidate(reason: .actionPerformed)
    }

    /// Retire the "where your data lives" tip once the session-menu tip has had its one
    /// showing: one menu-shaped hint per ladder. Awaits the session-menu tip's status
    /// stream, so run it from a `.task` on the screen that anchors that tip.
    static func retireDataTipAfterSessionMenuTip() async {
        for await status in SessionMenuTip().statusUpdates {
            if case .invalidated = status {
                SettingsDataTip().invalidate(reason: .tipClosed)
            }
        }
    }
}

/// Points at the "Log a dose" accessory while the user is on the Journal root and hasn't logged
/// anything yet, and retires the moment they close it or tap the button.
///
/// The Journal-root gating is *not* a rule: the tip is anchored to the tab bar's bottom accessory,
/// which is mounted on every tab and behind every pushed screen, and TipKit does not retract an
/// already-shown popover when a rule flips false — it only gates when a tip may first appear. So
/// the accessory attaches `.popoverTip` only while on the Journal root (see `ContentView`);
/// leaving tears the popover down, returning re-offers it, until the user closes or acts on it.
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

/// Once the user has logged a dose, points at the ••• menu to say where backups and export/import
/// live (Tools › Data & Backup) and where preferences do (Settings) — the one thing the tour
/// deliberately doesn't cover.
struct SettingsDataTip: Tip {
    var title: Text {
        Text("Your data lives here")
    }
    var message: Text? {
        Text("Backups, export & import are under Tools › Data & Backup; preferences are under Settings.")
    }
    var image: Image? {
        Image(systemName: "gearshape")
    }

    /// Shown once, ever — once the user has seen where their data lives, we don't say it again.
    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }

    var rules: [Rule] {
        #Rule(LogDoseTip.$onboardingComplete) { $0 == true }
        #Rule(LogDoseTip.$hasLoggedFirstDose) { $0 == true }
    }
}

/// Points at a session's ••• menu the first time a session detail is open after the
/// first logged dose: notes, check-ins and splitting all sit behind that one glyph,
/// with nothing on the screen itself to suggest so. Shown once; when it has been, the
/// "where your data lives" tip retires (``OnboardingTips/retireDataTipAfterSessionMenuTip()``).
struct SessionMenuTip: Tip {
    var title: Text {
        Text("Notes live here")
    }
    var message: Text? {
        Text("Notes, check-ins and splitting live under this menu.")
    }
    var image: Image? {
        Image(systemName: "ellipsis.circle")
    }

    /// Shown once, ever.
    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }

    var rules: [Rule] {
        #Rule(LogDoseTip.$onboardingComplete) { $0 == true }
        #Rule(LogDoseTip.$hasLoggedFirstDose) { $0 == true }
    }
}

/// One-time hint on a session's timeline graph, replacing the always-on gesture
/// caption. Points out the pan/zoom/inspect gestures the first time a graph is
/// on screen, then retires itself once dismissed.
struct GraphGestureTip: Tip {
    var title: Text {
        Text("Explore the timeline")
    }
    var message: Text? {
        Text("Slide to move, pinch to zoom, and hold to inspect a moment.")
    }
    var image: Image? {
        Image(systemName: "hand.draw")
    }

    /// Shown once, ever.
    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

/// One-time hint on the session's Share button, surfacing that it exports a
/// screenshot, a PDF report, or a Markdown summary — otherwise invisible behind
/// a single icon.
struct ShareSessionTip: Tip {
    var title: Text {
        Text("Share this session")
    }
    var message: Text? {
        Text("Save it as a screenshot, a PDF report, or a Markdown summary.")
    }
    var image: Image? {
        Image(systemName: "square.and.arrow.up")
    }

    /// Shown once, ever.
    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}
