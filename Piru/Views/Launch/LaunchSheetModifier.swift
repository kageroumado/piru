import SwiftData
import SwiftUI

/// A sheet the app raises on its own at launch.
enum LaunchSheet: Identifiable {
    case updateNotice(UpdateNotice)
    case discordInvite

    var id: String {
        switch self {
        case let .updateNotice(notice): "updateNotice.\(notice.rawValue)"
        case .discordInvite: "discordInvite"
        }
    }
}

/// The launch's one turn at raising a sheet. It outlives the root view, which a
/// skin, language or profile change re-creates along with every `@State` in it.
@MainActor
final class LaunchPick {
    static let shared = LaunchPick()

    private(set) var isTaken = false

    /// True the first time it is asked, false every time after.
    func claim() -> Bool {
        guard !isTaken else { return false }
        isTaken = true
        return true
    }
}

/// The one presenter for everything the app raises on its own at launch.
/// Candidates are tried in priority order — an update notice, the Skins picker,
/// then the Discord invite — and at most one is shown per launch, so they never
/// stack or race each other's presentation. Nothing shows until onboarding is
/// done.
///
/// The Skins picker and the Discord invite each show a single time, never in
/// the first sessions and only to someone with a dose logged. The picker comes
/// first (`appLaunchCount >= 3`), because a skin is found by being seen; the
/// invite waits a few launches more.
struct LaunchSheetModifier: ViewModifier {
    @AppStorage(OnboardingState.completedKey) private var hasCompletedOnboarding = false
    @AppStorage("discordPromptShown") private var discordShown = false
    @AppStorage("discordPromptDismissedForever") private var discordDismissed = false
    @AppStorage("appLaunchCount") private var appLaunchCount = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @State private var sheet: LaunchSheet?

    /// What a launch may raise: a sheet of its own, or the Skins picker, which
    /// goes up through the navigator like any hand-opened one so it keeps its
    /// panel height and the app stays in view behind it.
    private enum Candidate {
        case sheet(LaunchSheet)
        case skinsPicker
    }

    /// Lets the first frame and the launch passes settle before a sheet rises.
    private static let settleDelay: Duration = .seconds(1)

    private enum Threshold {
        static let skinsPickerLaunches = 3
        static let discordLaunches = 6
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case let .updateNotice(notice): UpdateNoticeView(notice: notice)
                case .discordInvite: DiscordPromptView()
                }
            }
            .task {
                InstallRecord.recordIfNeeded(hasCompletedOnboarding: hasCompletedOnboarding)
                guard hasCompletedOnboarding else { return }
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled, sheet == nil, navigator.sheetStack.isEmpty else { return }
                // The root is re-created by a skin, language or profile change, which runs this
                // task again; the pick itself happens once per process.
                guard LaunchPick.shared.claim() else { return }
                switch nextCandidate() {
                case let .sheet(next): sheet = next
                case .skinsPicker: navigator.present(.skins)
                case nil: break
                }
            }
    }

    private func nextCandidate() -> Candidate? {
        #if DEBUG
            // `-piruShowUpdateNotice <id>` raises a notice regardless of
            // eligibility, to look at a page on a store that no longer owes it.
            if let forced = UserDefaults.standard.string(forKey: "piruShowUpdateNotice").flatMap(UpdateNotice.init) {
                return .sheet(.updateNotice(forced))
            }
            // A notice would cover the screens the screenshot tour captures.
            if ScreenshotTour.isRequested { return nil }
            // `-piruShowSkinsPicker YES` raises the picker regardless of eligibility.
            if UserDefaults.standard.bool(forKey: "piruShowSkinsPicker") { return .skinsPicker }
        #endif
        if let notice = UpdateNotice.next(in: modelContext) {
            return .sheet(.updateNotice(notice))
        }
        if skinsPickerIsDue {
            return .skinsPicker
        }
        if discordInviteIsDue {
            discordShown = true
            return .sheet(.discordInvite)
        }
        return nil
    }

    /// Someone who has never had the picker in front of them, wears the skin
    /// the app came in and owns none: everyone else has found it already.
    private var skinsPickerIsDue: Bool {
        #if os(iOS)
            guard promptsAreEnabled, !SkinsPickerRecord.seen, appLaunchCount >= Threshold.skinsPickerLaunches else { return false }
            guard SkinStore.shared.chosen == SkinDefaults.skinDefault, SkinShop.shared.owned.isEmpty else { return false }
            return hasLoggedDose
        #else
            // On a Mac the picker is a dialog over the window, with no app in
            // view behind it to watch change.
            return false
        #endif
    }

    private var discordInviteIsDue: Bool {
        guard promptsAreEnabled, !discordShown, !discordDismissed, appLaunchCount >= Threshold.discordLaunches else { return false }
        return hasLoggedDose
    }

    /// Debug builds raise these only on request, the same opt-in as the tips:
    /// a reset simulator would otherwise be prompted again every few launches.
    private var promptsAreEnabled: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "piruShowTips")
        #else
            true
        #endif
    }

    private var hasLoggedDose: Bool {
        ((try? modelContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0) > 0
    }
}
