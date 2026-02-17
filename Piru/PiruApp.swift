import SwiftUI
import SwiftData

// MARK: - Schema Versioning

enum PiruSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [DoseEntry.self, SubstanceColor.self, UserColor.self, DailyDoseItem.self]
    }
}

enum PiruMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PiruSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - App

@main
struct PiruApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: PiruSchemaV1.self)
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
