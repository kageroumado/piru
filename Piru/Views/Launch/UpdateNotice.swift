import Foundation
import SwiftData

/// Something a new build has to tell the people already using the app: a
/// change that needs a decision, a migration, what's new. The App Store has no
/// TestFlight-style "what to test" sheet and its release notes go unread, so
/// the app says it itself — once, at launch, through ``LaunchSheetModifier``.
///
/// To add one: a case, its ``introducedInBuild``, its ``isEligible(in:)`` rule,
/// and a page in ``UpdateNoticeView``. Declaration order is priority.
enum UpdateNotice: String, CaseIterable, Identifiable {
    /// The legacy build: Piru lives in a new app, which brings this install's
    /// data across on its own.
    case appMoved
    /// The successor: the journal came over from the legacy app.
    case journalArrived
    /// Substance colors follow class; existing colors can move or stay.
    case classColors

    var id: String { rawValue }

    /// The first build carrying the change. An install that began at or after
    /// it has nothing to be told. `nil` for a notice about which app this is,
    /// which every install is owed however new.
    var introducedInBuild: Int? {
        switch self {
        case .appMoved, .journalArrived: nil
        case .classColors: 53
        }
    }

    @MainActor
    func isEligible(in context: ModelContext) -> Bool {
        switch self {
        case .appMoved: AppIdentity.isLegacy
        case .journalArrived: !AppIdentity.isLegacy && LegacyHandoff.importedJournalEntries > 0
        case .classColors: SubstanceColorStore.legacyRowCount(in: context) > 0
        }
    }

    /// How long after a dismissal the notice is owed again; `nil` shows it once.
    ///
    /// The move notice comes back: a TestFlight tester opens the app every few
    /// days, and one swipe should not be the only chance to hear where Piru
    /// went. Every three days is often enough to be seen and rare enough not to
    /// nag. Once the successor has imported this install, anything logged here
    /// stays here, so it returns daily.
    var resurfaceInterval: TimeInterval? {
        switch self {
        case .appMoved: LegacyHandoff.successorImportedAt == nil ? 3 * 86400 : 86400
        case .journalArrived, .classColors: nil
        }
    }

    // MARK: - Bookkeeping

    private var seenKey: String { "updateNotice.\(rawValue).seen" }
    private var seenAtKey: String { "updateNotice.\(rawValue).seenAt" }

    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    func markSeen(at date: Date = Date()) {
        UserDefaults.standard.set(true, forKey: seenKey)
        UserDefaults.standard.set(date, forKey: seenAtKey)
    }

    /// Unseen, or seen at least ``resurfaceInterval`` ago.
    func isOwed(now: Date = Date()) -> Bool {
        guard hasBeenSeen else { return true }
        guard let interval = resurfaceInterval,
              let seenAt = UserDefaults.standard.object(forKey: seenAtKey) as? Date else { return false }
        return now.timeIntervalSince(seenAt) >= interval
    }

    /// The first notice this install is owed, in declaration order.
    @MainActor
    static func next(in context: ModelContext) -> UpdateNotice? {
        let firstBuild = InstallRecord.firstBuild
        return allCases.first { notice in
            let isNewToInstall = notice.introducedInBuild.map { firstBuild < $0 } ?? true
            return notice.isOwed() && isNewToInstall && notice.isEligible(in: context)
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
