import Foundation
import SwiftData
import Testing
@testable import Piru

/// The routine→med fold that migrates every shipped (v2.2) user's routines
/// onto the Meds redesign's per-med fields (`Specs/meds-reminders-redesign.md`).
@Suite("MedsMigrator", .serialized)
@MainActor
struct MedsMigratorTests {
    /// A throwaway in-memory container. Each test must hold this for its
    /// whole body — a `ModelContext` does NOT retain its container.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    /// A fresh defaults suite per test so the one-shot flag never leaks
    /// between tests (or into the real app's defaults).
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "MedsMigratorTests-\(UUID().uuidString)"))
    }

    @discardableResult
    private func addRoutine(
        _ name: String,
        timeMinutes: Int? = nil,
        remind: Bool = false,
        followUps: [Int] = [],
        in context: ModelContext,
    ) -> DoseRoutine {
        let routine = DoseRoutine(name: name, timeMinutes: timeMinutes, remind: remind)
        routine.followUpMinutes = followUps
        context.insert(routine)
        return routine
    }

    @discardableResult
    private func addItem(
        _ substance: String,
        category: String,
        isBackgroundMed: Bool = false,
        in context: ModelContext,
    ) -> DailyDoseItem {
        let item = DailyDoseItem(
            substance: substance, amount: 10, unit: "mg",
            category: category, isBackgroundMed: isBackgroundMed,
        )
        context.insert(item)
        return item
    }

    @Test
    func `Items inherit their routine's time and remind flag`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addRoutine("Morning", timeMinutes: 8 * 60, remind: true, in: context)
        addRoutine("Untimed", timeMinutes: nil, remind: false, in: context)
        let timed = addItem("Sertraline", category: "Morning", in: context)
        let untimed = addItem("Melatonin", category: "Untimed", in: context)

        try MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: makeDefaults())

        #expect(timed.reminderTimesMinutes == [8 * 60])
        #expect(timed.remind == true)
        #expect(untimed.reminderTimesMinutes.isEmpty)
        #expect(untimed.remind == false)
    }

    @Test
    func `Orphaned categories fold to no times`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let orphan = addItem("Caffeine", category: "Deleted Routine", in: context)

        try MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: makeDefaults())

        #expect(orphan.reminderTimesMinutes.isEmpty)
    }

    @Test
    func `Background meds and supplements fold into the Quiet tier`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addRoutine("Morning", timeMinutes: 8 * 60, remind: true, in: context)
        let background = addItem("Sertraline", category: "Morning", isBackgroundMed: true, in: context)
        // A library supplement — quiet by category, matching the form's
        // smart default (the shipped 6-supplement routine must not migrate
        // into six individual notifications).
        let supplement = addItem("Magnesium", category: "Morning", in: context)
        let regular = addItem("Methylphenidate", category: "Morning", in: context)

        try MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: makeDefaults())

        #expect(background.isQuiet)
        #expect(supplement.isQuiet)
        #expect(!regular.isQuiet)
    }

    @Test
    func `The most common routine cadence becomes the global Ask Again default`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(NotificationPreferences())
        addRoutine("Morning", timeMinutes: 8 * 60, remind: true, followUps: [10, 30], in: context)
        addRoutine("Noon", timeMinutes: 12 * 60, remind: true, followUps: [10, 30], in: context)
        addRoutine("Night", timeMinutes: 22 * 60, remind: true, followUps: [10], in: context)

        try MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: makeDefaults())

        let record = try #require(try context.fetch(FetchDescriptor<NotificationPreferences>()).first)
        #expect(record.askAgainDefaultMinutes == [10, 30])
    }

    @Test
    func `No preferences record means no crash and no phantom record`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addRoutine("Morning", timeMinutes: 8 * 60, remind: true, followUps: [10], in: context)
        addItem("Sertraline", category: "Morning", in: context)

        try MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: makeDefaults())

        #expect(try context.fetch(FetchDescriptor<NotificationPreferences>()).isEmpty)
    }

    @Test
    func `The fold runs exactly once — later edits survive a second call`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let defaults = try makeDefaults()
        addRoutine("Morning", timeMinutes: 8 * 60, remind: true, in: context)
        let item = addItem("Sertraline", category: "Morning", in: context)

        MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: defaults)
        #expect(item.reminderTimesMinutes == [8 * 60])

        // The user edits their med after the fold; a relaunch must not
        // clobber it back to the routine's time.
        item.reminderTimesMinutes = [9 * 60, 14 * 60]
        MedsMigrator.foldRoutinesIfNeeded(context: context, defaults: defaults)
        #expect(item.reminderTimesMinutes == [9 * 60, 14 * 60])
    }
}
