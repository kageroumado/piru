import os

/// One logger per area of the app, all under ``AppIdentity/subsystem``. Log through the
/// static for the area (`Logger.substanceStore.info(…)`); a new area is a new ``Category``
/// case and its static here.
nonisolated extension Logger {
    /// The category each logger files its entries under — the name Console filters on.
    enum Category: String {
        case app = "App"
        case backupCrypto = "BackupCrypto"
        case backupManager = "BackupManager"
        case checkIn = "CheckIn"
        case curatedIdentityBackfill = "CuratedIdentityBackfill"
        case customSubstance = "CustomSubstance"
        case databaseSuspension = "DatabaseSuspension"
        case dockGeometry = "dock-geometry"
        case doseLog = "DoseLog"
        case esterIdentityBackfill = "EsterIdentityBackfill"
        case healthKitBodyMass = "HealthKitBodyMass"
        case healthKitVitals = "HealthKitVitals"
        case legacyHandoff = "LegacyHandoff"
        case liveActivity = "LiveActivity"
        case medsMigrator = "MedsMigrator"
        case notificationPrefs = "NotificationPrefs"
        case psidBackfill = "PSIDBackfill"
        case psidRepin = "PSIDRepin"
        case routeTour = "RouteTour"
        case sessionNotes = "SessionNotes"
        case sessionNotifications = "SessionNotifications"
        case skinShop = "SkinShop"
        case storeHealth = "StoreHealth"
        case storeRecovery = "StoreRecovery"
        case subjectiveEffects = "SubjectiveEffects"
        case substanceColorStore = "SubstanceColorStore"
        case substanceStore = "SubstanceStore"
        case userProfileStore = "UserProfileStore"
        case watchSync = "WatchSync"
    }

    init(_ category: Category) {
        self.init(subsystem: AppIdentity.subsystem, category: category.rawValue)
    }

    static let app = Logger(.app)
    static let backupCrypto = Logger(.backupCrypto)
    static let backupManager = Logger(.backupManager)
    static let checkIn = Logger(.checkIn)
    static let curatedIdentityBackfill = Logger(.curatedIdentityBackfill)
    static let customSubstance = Logger(.customSubstance)
    static let databaseSuspension = Logger(.databaseSuspension)
    static let dockGeometry = Logger(.dockGeometry)
    static let doseLog = Logger(.doseLog)
    static let esterIdentityBackfill = Logger(.esterIdentityBackfill)
    static let healthKitBodyMass = Logger(.healthKitBodyMass)
    static let healthKitVitals = Logger(.healthKitVitals)
    static let legacyHandoff = Logger(.legacyHandoff)
    static let liveActivity = Logger(.liveActivity)
    static let medsMigrator = Logger(.medsMigrator)
    static let notificationPrefs = Logger(.notificationPrefs)
    static let psidBackfill = Logger(.psidBackfill)
    static let psidRepin = Logger(.psidRepin)
    static let routeTour = Logger(.routeTour)
    static let sessionNotes = Logger(.sessionNotes)
    static let sessionNotifications = Logger(.sessionNotifications)
    static let skinShop = Logger(.skinShop)
    static let storeHealth = Logger(.storeHealth)
    static let storeRecovery = Logger(.storeRecovery)
    static let subjectiveEffects = Logger(.subjectiveEffects)
    static let substanceColorStore = Logger(.substanceColorStore)
    static let substanceStore = Logger(.substanceStore)
    static let userProfileStore = Logger(.userProfileStore)
    static let watchSync = Logger(.watchSync)
}
