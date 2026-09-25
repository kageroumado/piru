import SwiftData

/// The one list of user-data models every target opens the store with.
///
/// Every `ModelContainer` in every target — the app, the widgets, the
/// Take-Med intents — is built from `Schema(PiruSchema.models)`, never from
/// a hand-written subset. SwiftData treats a schema that lacks an entity the
/// store holds as a migration to *remove* it: a read-only open then fails
/// ("Cannot migrate store in-place … readonly database") and the widget
/// renders its empty state, while a writable open succeeds and drops the
/// missing tables from the canonical app-group store. `PiruSchemaTests`
/// checks that this list names every `@Model` in the repo and that no
/// target constructs a container from anything else.
enum PiruSchema {
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
            Session.self,
            DoseRoutine.self,
            InventoryItem.self,
            UserProfileRecord.self,
            ToleranceState.self,
            CustomSubstanceRecord.self,
            CustomDrinkPreset.self,
            CustomUnitPreset.self,
            NotificationPreferences.self,
            RoutineOccurrence.self,
            SessionNote.self,
            LabMeasurement.self,
        ]
    }

    /// Remove every user-data entity in the schema and commit the deletion.
    static func deleteAll(in context: ModelContext) throws {
        do {
            for model in models {
                try deleteRows(of: model, in: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func deleteRows<M: PersistentModel>(of _: M.Type, in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<M>()) {
            context.delete(row)
        }
    }
}
