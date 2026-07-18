import Foundation
import SwiftData
import Testing
@testable import Piru

/// The `Specs/routine-occurrences.md` test matrix: materialization, the §D
/// matching rules, re-derivation (edit/delete robustness), sticky skips,
/// end-of-day expiry, and the satisfied gate the follow-ups read.
@Suite("RoutineOccurrences", .serialized)
@MainActor
struct RoutineOccurrenceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return container.mainContext
    }

    @discardableResult
    private func addRoutine(_ name: String, timeMinutes: Int? = 9 * 60, in context: ModelContext) -> DoseRoutine {
        let routine = DoseRoutine(name: name, timeMinutes: timeMinutes)
        context.insert(routine)
        return routine
    }

    @discardableResult
    private func addItem(
        _ substance: String,
        routine: String,
        route: RouteOfAdministration = .oral,
        uid: String? = nil,
        frequency: DoseFrequency = .daily,
        in context: ModelContext,
    ) -> DailyDoseItem {
        let item = DailyDoseItem(substance: substance, amount: 10, unit: "mg", route: route, category: routine)
        item.substanceUID = uid
        item.frequency = frequency
        item.startDate = .distantPast
        context.insert(item)
        return item
    }

    @discardableResult
    private func addEntry(
        _ substance: String,
        route: RouteOfAdministration = .oral,
        uid: String? = nil,
        at timestamp: Date = .now,
        in context: ModelContext,
    ) -> DoseEntry {
        let entry = DoseEntry(substance: substance, amount: 10, unit: "mg", route: route, substanceUID: uid, timestamp: timestamp)
        context.insert(entry)
        return entry
    }

    private func occurrences(in context: ModelContext) throws -> [RoutineOccurrence] {
        try context.fetch(FetchDescriptor<RoutineOccurrence>())
    }

    // MARK: - Materialization

    @Test
    func `Due items get occurrences; off-schedule items don't; reruns are idempotent`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        // Weekly item starting a distant Monday-ish past date — only due on
        // its cycle day; today is almost surely not day 0 of .distantPast.
        let weekly = addItem("B12", routine: "Morning", frequency: .weekly, in: context)
        weekly.startDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))

        RoutineOccurrenceService.reconcile(in: context)
        let first = try occurrences(in: context)
        #expect(first.count == 1)
        #expect(first.first?.substance == "Vitamin D3")
        #expect(first.first?.state == .pending)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).count == 1)
    }

    @Test
    func `Items outside any routine get no occurrence`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Orphan", routine: "", in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).isEmpty)
    }

    // MARK: - Matching (§D)

    @Test
    func `A logged dose satisfies its occurrence by name`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        let entry = addEntry("vitamin d3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        let occurrence = try #require(try occurrences(in: context).first)
        #expect(occurrence.state == .logged)
        #expect(occurrence.satisfyingEntryID == entry.id)
    }

    @Test
    func `Identity matching prefers substanceUID over the name`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Concerta", routine: "Morning", uid: "psid:mph", in: context)
        // Relabeled dose: different name, same identity (spec §D — a relabel
        // doesn't break the match).
        addEntry("Methylphenidate XR", uid: "psid:mph", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .logged)
    }

    @Test
    func `A route mismatch does not match`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Melatonin", routine: "Morning", route: .oral, in: context)
        addEntry("Melatonin", route: .sublingual, in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .pending)
    }

    @Test
    func `One entry claims one occurrence; two entries satisfy two routines by nearest time`() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        addRoutine("Morning", timeMinutes: 8 * 60, in: context)
        addRoutine("Night", timeMinutes: 22 * 60, in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        addItem("Vitamin D3", routine: "Night", in: context)

        let morning = try #require(calendar.date(bySettingHour: 8, minute: 10, second: 0, of: .now))
        addEntry("Vitamin D3", at: morning, in: context)

        RoutineOccurrenceService.reconcile(in: context)
        let all = try occurrences(in: context)
        #expect(all.count == 2)
        #expect(all.first { $0.routineName == "Morning" }?.state == .logged)
        #expect(all.first { $0.routineName == "Night" }?.state == .pending)
    }

    @Test
    func `An ad-hoc dose matching nothing claims nothing`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        addEntry("Caffeine", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .pending)
    }

    // MARK: - Re-derivation

    @Test
    func `Deleting the satisfying dose returns the occurrence to pending`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        let entry = addEntry("Vitamin D3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .logged)

        context.delete(entry)
        RoutineOccurrenceService.reconcile(in: context)
        let occurrence = try #require(try occurrences(in: context).first)
        #expect(occurrence.state == .pending)
        #expect(occurrence.satisfyingEntryID == nil)
    }

    @Test
    func `Skipped is sticky through reconciles and matching`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        RoutineOccurrenceService.skipToday(routineName: "Morning", in: context)
        #expect(try occurrences(in: context).first?.state == .skipped)

        // Neither a plain reconcile nor a matching dose reclaims it.
        addEntry("Vitamin D3", in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .skipped)
    }

    // MARK: - Expiry

    @Test
    func `Yesterday's pending expires to missed; history states survive`() throws {
        let context = try makeContext()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)))
        let stale = RoutineOccurrence(routineName: "Morning", substance: "Vitamin D3", route: .oral, dueDay: yesterday)
        let done = RoutineOccurrence(routineName: "Morning", substance: "Magnesium", route: .oral, dueDay: yesterday)
        done.state = .logged
        context.insert(stale)
        context.insert(done)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(stale.state == .missed)
        #expect(done.state == .logged)
    }

    // MARK: - The follow-up gate

    @Test
    func `Satisfied means every occurrence logged or skipped; partial keeps asking`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)
        addItem("Magnesium", routine: "Morning", in: context)
        addEntry("Vitamin D3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(!RoutineOccurrenceService.isSatisfiedToday(routineName: "Morning", in: context))

        addEntry("Magnesium", in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(RoutineOccurrenceService.isSatisfiedToday(routineName: "Morning", in: context))
    }

    @Test
    func `Nothing due counts as satisfied`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(RoutineOccurrenceService.isSatisfiedToday(routineName: "Morning", in: context))
    }

    @Test
    func `Skipping the whole routine satisfies it`() throws {
        let context = try makeContext()
        addRoutine("Morning", in: context)
        addItem("Vitamin D3", routine: "Morning", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(!RoutineOccurrenceService.isSatisfiedToday(routineName: "Morning", in: context))

        RoutineOccurrenceService.skipToday(routineName: "Morning", in: context)
        #expect(RoutineOccurrenceService.isSatisfiedToday(routineName: "Morning", in: context))
    }
}
