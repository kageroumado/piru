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

/// The one presenter for every self-raised launch sheet. Candidates are tried
/// in priority order — an update notice, then the Discord invite — and at most
/// one is shown per launch, so they never stack or race each other's
/// presentation. Nothing shows until onboarding is done.
///
/// The Discord invite keeps its own bar: only once the user is genuinely
/// engaged — past the first couple of sessions (`appLaunchCount >= 3`) with at
/// least one dose logged — a single time, never in the first session.
struct LaunchSheetModifier: ViewModifier {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("discordPromptShown") private var discordShown = false
    @AppStorage("discordPromptDismissedForever") private var discordDismissed = false
    @AppStorage("appLaunchCount") private var appLaunchCount = 0
    @Environment(\.modelContext) private var modelContext
    @State private var sheet: LaunchSheet?

    /// Lets the first frame and the launch passes settle before a sheet rises.
    private static let settleDelay: Duration = .seconds(1)

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
                guard sheet == nil else { return }
                sheet = nextSheet()
            }
    }

    private func nextSheet() -> LaunchSheet? {
        #if DEBUG
            // `-piruShowUpdateNotice <id>` raises a notice regardless of
            // eligibility, to look at a page on a store that no longer owes it.
            if let forced = UserDefaults.standard.string(forKey: "piruShowUpdateNotice").flatMap(UpdateNotice.init) {
                return .updateNotice(forced)
            }
        #endif
        if let notice = UpdateNotice.next(in: modelContext) {
            return .updateNotice(notice)
        }
        if discordInviteIsDue {
            discordShown = true
            return .discordInvite
        }
        return nil
    }

    private var discordInviteIsDue: Bool {
        #if DEBUG
            // Same opt-in as the tips: a reset simulator would otherwise
            // re-invite on every third launch.
            guard UserDefaults.standard.bool(forKey: "piruShowTips") else { return false }
        #endif
        guard !discordShown, !discordDismissed, appLaunchCount >= 3 else { return false }
        return ((try? modelContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0) > 0
    }
}
