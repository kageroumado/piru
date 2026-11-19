import Foundation
import SwiftData

/// A type that holds the journal store, or state derived from it, past one
/// call: it must follow the active profile. ``StoreBinding/bindAll(to:)`` binds
/// every one of them at launch and again on every profile switch.
///
/// A type that declares a stored `ModelContainer?` and is not in
/// ``StoreBinding/boundTypes`` fails `StoreBindingTests`: it would keep reading
/// the previous profile's store after a switch.
@MainActor
protocol StoreBound {
    static func bindStore(_ container: ModelContainer)
}

/// The one list of ``StoreBound`` types, in the order launch binds them.
@MainActor
enum StoreBinding {
    static var boundTypes: [any StoreBound.Type] {
        var types: [any StoreBound.Type] = [
            UserProfileStore.self,
            ToleranceStore.self,
            BodyLevelsManager.self,
            CustomSubstanceStore.self,
            CustomUnitStore.self,
            NotificationPreferencesStore.self,
            AppLanguageModel.self,
            DoseNotificationManager.self,
            ActiveSessionManager.self,
            DayResolveCache.self,
        ]
        // The App Intents, which Android does not build.
        #if !os(Android)
            types.append(DoseIntentLogger.self)
        #endif
        #if os(iOS)
            types.append(PhoneSyncCoordinator.self)
        #endif
        return types
    }

    /// Point every store-backed singleton at `container`, the active profile's
    /// store, and drop what each derived from the previous one.
    static func bindAll(to container: ModelContainer) {
        for type in boundTypes {
            type.bindStore(container)
        }
    }
}

// MARK: - Conformances

extension UserProfileStore: StoreBound {
    /// The legacy disclosure-tier file belongs to the owner, so only the
    /// owner's store migrates it.
    static func bindStore(_ container: ModelContainer) {
        if ProfileScope.isOwner {
            shared.configure(container: container)
        } else {
            shared.configure(container: container, legacyPrefsDBURL: nil)
        }
    }
}

extension ToleranceStore: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.configure(container: container)
    }
}

extension BodyLevelsManager: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.configure(container: container)
    }
}

extension CustomSubstanceStore: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.configure(container: container)
    }
}

extension CustomUnitStore: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.configure(container: container)
    }
}

extension NotificationPreferencesStore: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.configure(container: container)
    }
}

#if !os(Android)
    extension DoseIntentLogger: StoreBound {
        static func bindStore(_ container: ModelContainer) {
            modelContainer = container
        }
    }
#endif

extension AppLanguageModel: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        shared.modelContainer = container
    }
}

extension DoseNotificationManager: StoreBound {
    static func bindStore(_ container: ModelContainer) {
        modelContainer = container
    }
}

extension ActiveSessionManager: StoreBound {
    /// The previous profile's live doses go; ``AppLaunch`` recovers the new
    /// store's session once its passes have run.
    static func bindStore(_: ModelContainer) {
        shared.clearSession()
    }
}

extension DayResolveCache: StoreBound {
    static func bindStore(_: ModelContainer) {
        shared.clear()
    }
}

#if os(iOS)
    extension PhoneSyncCoordinator: StoreBound {
        /// The watch always logs into the owner's journal, whoever is active.
        static func bindStore(_ container: ModelContainer) {
            let owner = ProfileScope.isOwner
                ? container
                : ProfileDirectory.shared.container(for: ProfileDirectory.shared.owner.id, writable: true)
            shared.configure(container: owner ?? container)
        }
    }
#endif
