import Foundation
import SwiftData
import Testing
@testable import Piru

/// The "week" persona is the default an empty DEBUG store fills with, so its
/// shape is a contract: every surface the brief lists must be populated, and
/// every logged substance must draw a timeline curve.
@MainActor
@Suite("DemoData — week persona")
struct DemoDataWeekTests {
    @Test
    func `Seeds seven days, three titled sessions, notes, meds, inventory, and favorites`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        // The container must outlive the context: `mainContext` does not
        // retain it, and inserting into an orphaned context traps.
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let calendar = Calendar.current
        // Pinned past the morning slot so today's meds exist regardless of
        // when the test runs.
        let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now))

        DemoData.seedWeek(context: context, now: noon)
        try context.save()
        SessionService.assignUnassignedDoses(in: context)

        let doses = try context.fetch(FetchDescriptor<DoseEntry>())
        let days = Set(doses.map { calendar.startOfDay(for: $0.timestamp) })
        #expect(days.count == 7)
        #expect(doses.allSatisfy { $0.timestamp <= noon })
        for entry in doses where !entry.isBackgroundMed {
            #expect(SubstanceLibrary.lookup(entry.substance) != nil, "\(entry.substance) resolves")
            #expect(ActiveSubstanceState.from(entry: entry, colorHex: "") != nil, "\(entry.substance) draws a curve")
        }
        #expect(doses.allSatisfy { $0.session != nil })

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let titles = sessions.compactMap(\.title).sorted()
        #expect(titles == ["Forest walk", "Friday drinks", "Lake evening"])
        let lake = try #require(sessions.first { $0.title == "Lake evening" })
        #expect(lake.checkInIntervalMinutes != nil)
        #expect(lake.orderedNotes.count == 5)
        #expect(lake.orderedNotes.contains { $0.kind == .summary })
        #expect(lake.orderedNotes.contains { $0.kind == .checkIn })
        #expect(lake.orderedNotes.allSatisfy { note in
            note.descriptors.allSatisfy { SubjectiveEffectOntology.shared.name(for: $0) != nil }
        })

        let notes = try context.fetch(FetchDescriptor<SessionNote>())
        #expect(notes.count >= 7)

        let drinks = try #require(sessions.first { $0.title == "Friday drinks" })
        let beers = drinks.orderedDoses.filter { $0.substance == "Alcohol" }
        #expect(beers.count == 3)
        #expect(beers.allSatisfy { $0.unit == "g" && $0.volumeML == 330 && $0.abv == 5 && $0.drinkName != nil })

        #expect(try context.fetchCount(FetchDescriptor<DailyDoseItem>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<InventoryItem>()) == 5)
        #expect(try context.fetchCount(FetchDescriptor<FavoriteSubstance>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<SubstanceColor>()) == 8)
        #expect(try context.fetchCount(FetchDescriptor<QuickLogDose>()) >= 8)
        #expect(try context.fetchCount(FetchDescriptor<CustomSubstanceRecord>()) == 0)

        // Six past mornings × two scheduled meds, each satisfied by its dose.
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(occurrences.count == 12)
        #expect(occurrences.allSatisfy { $0.state == .logged && $0.satisfyingEntryID != nil })
    }
}
