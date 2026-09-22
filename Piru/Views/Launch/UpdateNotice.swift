import Foundation
import SwiftData

/// Something a new build has to tell the people already using the app: a
/// change that needs a decision, a migration, what's new. The App Store has no
/// TestFlight-style "what to test" sheet and its release notes go unread, so
/// the app says it itself — once, at launch, through ``LaunchSheetModifier``.
///
/// To add one: a case, its ``introducedInBuild``, its ``isEligible(in:)`` rule,
/// and a page in ``UpdateNoticeView``.
enum UpdateNotice: String, CaseIterable, Identifiable {
    /// Substance colors follow class; existing colors can move or stay.
    case classColors

    var id: String { rawValue }

    /// The first build carrying the change. An install that began at or after
    /// it has nothing to be told.
    var introducedInBuild: Int {
        switch self {
        case .classColors: 53
        }
    }

    @MainActor
    func isEligible(in context: ModelContext) -> Bool {
        switch self {
        case .classColors: SubstanceColorStore.legacyRowCount(in: context) > 0
        }
    }

    // MARK: - Bookkeeping

    private var seenKey: String { "updateNotice.\(rawValue).seen" }

    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// The first notice this install is owed, in declaration order.
    @MainActor
    static func next(in context: ModelContext) -> UpdateNotice? {
        let firstBuild = InstallRecord.firstBuild
        return allCases.first { notice in
            !notice.hasBeenSeen && firstBuild < notice.introducedInBuild && notice.isEligible(in: context)
        }
    }
}

/// The build this install first ran, so a fresh install is never walked
/// through changes to an app it has only just met.
enum InstallRecord {
    private static let key = "install.firstBuild"

    /// Records the first build when none is on file. An install that has
    /// already finished onboarding predates the record and counts as build 0.
    static func recordIfNeeded(hasCompletedOnboarding: Bool) {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        let current = Int(LaunchCacheInputs.appBuild) ?? 0
        UserDefaults.standard.set(hasCompletedOnboarding ? 0 : current, forKey: key)
    }

    static var firstBuild: Int {
        UserDefaults.standard.integer(forKey: key)
    }
}
