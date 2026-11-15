import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Changes whose journal the app shows. One path for the avatar menu, the Mac
/// shortcuts, a `profile=` deep link and a notification tap:
///
/// 1. the previous profile's Live Activity ends and its live session clears;
/// 2. the new store opens (``ProfileDirectory/activate(_:)``) and every
///    ``StoreBound`` singleton binds to it;
/// 3. revision-keyed memos drop, navigation returns to the tab roots (a pushed
///    record belongs to the old journal), and the root view rebuilds on the
///    new ``ProfileDirectory/activeProfileID``;
/// 4. the store's launch passes run, then every other profile's reminders
///    are rolled forward so nobody's stop firing.
@MainActor
enum ProfileSwitcher {
    static func switchTo(_ id: UUID, directory: ProfileDirectory = .shared) async {
        guard id != directory.activeProfileID, directory.profile(id: id) != nil else { return }
        LiveActivityManager.shared.endForProfileSwitch()
        ActiveSessionManager.shared.clearSession()
        guard let container = directory.activate(id) else { return }
        StoreBinding.bindAll(to: container)
        DoseLogService.shared.storeSwitched()
        AppNavigator.shared.dismissAll()
        AppNavigator.shared.resetAllPaths()
        WidgetCenter.shared.reloadAllTimelines()
        await SubstanceStore.shared.ensureAllLoaded()
        // Its session recovery re-arms the Live Activity for the new journal.
        await AppLaunch.profileOpened(container: container)
    }

    /// Delete a profile and set its journal aside (``ProfileDirectory/deleteProfile(id:)``),
    /// switching to the owner first when it is the one open, and withdraw
    /// every reminder still pending or shown for it and every item still shared
    /// with it.
    static func delete(_ id: UUID, directory: ProfileDirectory = .shared) async throws {
        if id == directory.activeProfileID {
            await switchTo(PiruProfile.ownerID, directory: directory)
        }
        try directory.deleteProfile(id: id)
        await SharedInventory.shared.profileDeleted(id)
        let prefix = "piru.notif.\(ProfileScope.notificationNamespace(for: id))"
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Open `url` in the profile it names (`profile=<uuid>`), switching first.
    static func open(_ url: URL, route: @escaping @MainActor (URL) -> Void) {
        guard let profile = DeepLink.profileID(in: url), profile != ProfileDirectory.shared.activeProfileID else {
            route(url)
            return
        }
        Task(name: "Open link in profile") {
            await switchTo(profile)
            route(url)
        }
    }
}
