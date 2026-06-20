import Foundation
import SwiftData

/// Shared read-only access to the canonical app-group SwiftData store for the
/// widget timeline providers.
///
/// Two guarantees matter here (both learned from a data-stranding incident
/// where the widget raced the app on first launch and *created* an empty
/// store the app then adopted):
/// 1. The store is never created from this process — if the file doesn't
///    exist yet, the widget renders its empty state instead.
/// 2. The store is opened read-only (`allowsSave: false`) with CloudKit
///    mirroring disabled, so the widget can never mutate the canonical file.
enum WidgetStoreAccess {
    static let appGroupID = "group.dev.yumeji.piru"

    /// Opens the canonical store, or returns `nil` when the app group is
    /// unavailable, the store file doesn't exist yet, or the open fails.
    static func makeContainer() -> ModelContainer? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID,
        ) else { return nil }
        let storeURL = groupURL.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        let config = ModelConfiguration(url: storeURL, allowsSave: false, cloudKitDatabase: .none)
        return try? ModelContainer(
            for: DoseEntry.self, SubstanceColor.self, UserColor.self,
            DailyDoseItem.self, FavoriteSubstance.self, QuickLogDose.self, Session.self,
            DoseRoutine.self, InventoryItem.self,
            configurations: config,
        )
    }
}
