import SwiftData
import UserNotifications
import WidgetKit

/// Delete Everything: the journal itself, then every store, cache, schedule
/// and system surface that holds a copy of it or would act on it.
///
/// Two steps, so a caller can drop its own references to the old journal
/// between them: ``deleteJournal(context:)`` throws and leaves everything else
/// untouched when the journal cannot be deleted; ``resetEverythingElse(context:)``
/// runs only after it succeeds.
enum AllDataDeletion {
    /// Deletes every journal row in `context`'s store, with pending deferred
    /// bookkeeping cancelled first so none of it lands on the empty store.
    static func deleteJournal(context: ModelContext) throws {
        DoseLogService.shared.cancelPendingBookkeeping()
        try DataExportImport.deleteAll(context: context)
    }

    /// Resets the in-memory stores, the on-disk caches and recovery copies, the
    /// scheduled and delivered notifications, Live Activities, the automatic
    /// iCloud backup and the widgets. Returns the message of each cleanup step
    /// that failed; the steps after a failure still run.
    static func resetEverythingElse(context: ModelContext) async -> [String] {
        JournalResetGeneration.advance()
        DoseLogService.shared.changed()
        #if os(iOS)
            PhoneSyncCoordinator.shared.journalWasDeleted()
        #endif
        ActiveSessionManager.shared.clearSession()
        DayResolveCache.shared.clear()
        NotificationPreferencesStore.shared.resetAfterDeletion()
        CustomSubstanceStore.shared.resetAfterDeletion()
        CustomUnitStore.shared.configure(container: context.container)
        SearchHistoryStore.shared.clear()
        QuickLogManager.suppressedRecents = []
        var cleanupErrors: [String] = []
        for cleanup in [
            { try UserProfileStore.shared.resetAfterDeletion() },
            { try StoreRecovery.deleteRecoveryCopies() },
            { try JournalDeriveCache.clear() },
            { try TimelineStripCache.clear() },
            { try BodyLevelsTrailCache.clear() },
        ] {
            do { try cleanup() } catch { cleanupErrors.append(error.localizedDescription) }
        }
        CheckInScheduler.cancelAll()
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        await LiveActivityManager.shared.deleteJournalActivities()
        await BackupManager.shared.disableAndRemoveBackup()
        WidgetCenter.shared.reloadAllTimelines()
        return cleanupErrors
    }
}
