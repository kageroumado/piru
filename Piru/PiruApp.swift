import SwiftUI
import SwiftData

// MARK: - Schema Versioning

enum PiruSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DoseEntry.self, SubstanceColor.self, UserColor.self, DailyDoseItem.self]
    }
}

enum PiruSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DoseEntry.self, SubstanceColor.self, UserColor.self, DailyDoseItem.self, FavoriteSubstance.self]
    }
}

enum PiruSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DoseEntry.self, SubstanceColor.self, UserColor.self, DailyDoseItem.self, FavoriteSubstance.self]
    }
}

enum PiruMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PiruSchemaV1.self, PiruSchemaV2.self, PiruSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: PiruSchemaV1.self,
        toVersion: PiruSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: PiruSchemaV2.self,
        toVersion: PiruSchemaV3.self
    )
}

// MARK: - App

@main
struct PiruApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: PiruSchemaV3.self)
            container = try ModelContainer(
                for: schema,
                migrationPlan: PiruMigrationPlan.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
