import Foundation
import SwiftData

/// Shared access to the canonical app-group SwiftData store for the widget
/// timeline providers and the interactive Take-Med intents.
///
/// Two guarantees matter here (both learned from a data-stranding incident
/// where the widget raced the app on first launch and *created* an empty
/// store the app then adopted):
/// 1. The store is never created from this process — if the file doesn't
///    exist yet, the widget renders its empty state instead. This holds for
///    BOTH open modes below.
/// 2. Timeline providers open read-only (`allowsSave: false`) with CloudKit
///    mirroring disabled, so a mere render can never mutate the canonical
///    file. Only the explicit user action of tapping a Take button (via
///    ``makeWritableContainer()``) is allowed to write, and it only ever
///    inserts rows — it never deletes or rewrites existing data.
enum WidgetStoreAccess {
    static let appGroupID = "group.dev.yumeji.piru"

    /// Opens the canonical store read-only, or returns `nil` when the app
    /// group is unavailable, the store file doesn't exist yet, or the open
    /// fails.
    static func makeContainer() -> ModelContainer? {
        openStore(allowsSave: false)
    }

    /// Opens the canonical store for writing — used exclusively by the
    /// Take-Med App Intents, which insert a `DoseEntry` on the user's explicit
    /// tap. Same never-create guard as ``makeContainer()``.
    static func makeWritableContainer() -> ModelContainer? {
        openStore(allowsSave: true)
    }

    private static func openStore(allowsSave: Bool) -> ModelContainer? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID,
        ) else { return nil }
        let storeURL = groupURL.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        let config = ModelConfiguration(url: storeURL, allowsSave: allowsSave, cloudKitDatabase: .none)
        return try? ModelContainer(
            for: DoseEntry.self, SubstanceColor.self, UserColor.self,
            DailyDoseItem.self, FavoriteSubstance.self, QuickLogDose.self, Session.self,
            DoseRoutine.self, InventoryItem.self, UserProfileRecord.self, ToleranceState.self,
            CustomSubstanceRecord.self, SessionNote.self,
            configurations: config,
        )
    }
}
