import Foundation
import SwiftData
import Testing
@testable import Piru

/// The occurrence test matrix, re-keyed by the Meds redesign
/// (`Specs/meds-reminders-redesign.md`): per-slot materialization, the §D
/// matching rules with nearest-slot claims, re-derivation (edit/delete
/// robustness), sticky skips, end-of-day expiry, and the satisfied-slot gate
/// the follow-ups read.
@Suite("RoutineOccurrences", .serialized)
@MainActor
struct RoutineOccurrenceTests {
    /// A throwaway in-memory container. Each test must hold this for its
    /// whole body: a `ModelContext` does NOT retain its container, and an
    /// orphaned context traps (EXC_BREAKPOINT) on the first mutation — the
    /// lifetime rule documented on `UserProfileStore`.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }

    @discardableResult
    private func addItem(
        _ substance: String,
        times: [Int] = [9 * 60],
        route: RouteOfAdministration = .oral,
        uid: String? = nil,
        frequency: DoseFrequency = .daily,
        isAsNeeded: Bool = false,
        in context: ModelContext,
    ) -> DailyDoseItem {
        let item = DailyDoseItem(
            substance: substance, amount: 10, unit: "mg", route: route,
            reminderTimesMinutes: times, isAsNeeded: isAsNeeded,
        )
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

    private func key(_ item: DailyDoseItem, slot: Int?) -> String {
        RoutineOccurrenceService.slotKey(
            substance: item.substance, substanceUID: item.substanceUID,
            route: item.route, slotMinutes: slot,
        )
    }

    // MARK: - Materialization

    @Test
    func `Due items get one occurrence per slot; off-schedule items don't; reruns are idempotent`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Methylphenidate", times: [8 * 60, 13 * 60], in: context)
        // Weekly item off its cycle day — no occurrence today.
        let weekly = addItem("B12", frequency: .weekly, in: context)
        weekly.startDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))

        RoutineOccurrenceService.reconcile(in: context)
        let first = try occurrences(in: context)
        #expect(first.count == 2)
        #expect(Set(first.map(\.slotMinutes)) == [8 * 60, 13 * 60])
        #expect(first.allSatisfy { $0.state == .pending })

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).count == 2)
    }

    @Test
    func `A med with no set times gets a single anytime slot`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Vitamin D3", times: [], in: context)
        RoutineOccurrenceService.reconcile(in: context)
        let all = try occurrences(in: context)
        #expect(all.count == 1)
        #expect(all.first?.slotMinutes == nil)
    }

    @Test
    func `As-needed meds get no occurrences`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Ibuprofen", times: [], isAsNeeded: true, in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).isEmpty)
    }

    // MARK: - Matching (§D)

    @Test
    func `A logged dose satisfies its occurrence by name`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Vitamin D3", in: context)
        let entry = addEntry("vitamin d3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        let occurrence = try #require(try occurrences(in: context).first)
        #expect(occurrence.state == .logged)
        #expect(occurrence.satisfyingEntryID == entry.id)
    }

    @Test
    func `Identity matching prefers substanceUID over the name`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Concerta", uid: "psid:mph", in: context)
        // Relabeled dose: different name, same identity (spec §D — a relabel
        // doesn't break the match).
        addEntry("Methylphenidate XR", uid: "psid:mph", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .logged)
    }

    @Test
    func `A route mismatch does not match`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Melatonin", route: .oral, in: context)
        addEntry("Melatonin", route: .sublingual, in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .pending)
    }

    @Test
    func `One entry claims the nearest slot; a second entry fills the other`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        addItem("Methylphenidate", times: [8 * 60, 22 * 60], in: context)

        let morning = try #require(calendar.date(bySettingHour: 8, minute: 10, second: 0, of: .now))
        addEntry("Methylphenidate", at: morning, in: context)

        RoutineOccurrenceService.reconcile(in: context)
        var all = try occurrences(in: context)
        #expect(all.count == 2)
        #expect(all.first { $0.slotMinutes == 8 * 60 }?.state == .logged)
        #expect(all.first { $0.slotMinutes == 22 * 60 }?.state == .pending)

        let night = try #require(calendar.date(bySettingHour: 21, minute: 45, second: 0, of: .now))
        addEntry("Methylphenidate", at: night, in: context)
        RoutineOccurrenceService.reconcile(in: context)
        all = try occurrences(in: context)
        #expect(all.allSatisfy { $0.state == .logged })
    }

    @Test
    func `An ad-hoc dose matching nothing claims nothing`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Vitamin D3", in: context)
        addEntry("Caffeine", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .pending)
    }

    // MARK: - Re-derivation

    @Test
    func `Deleting the satisfying dose returns the occurrence to pending`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        addItem("Vitamin D3", in: context)
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
    func `Removing a reminder time drops its pending occurrence`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = addItem("Methylphenidate", times: [8 * 60, 13 * 60], in: context)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).count == 2)

        item.reminderTimesMinutes = [8 * 60]
        RoutineOccurrenceService.reconcile(in: context)
        let all = try occurrences(in: context)
        #expect(all.count == 1)
        #expect(all.first?.slotMinutes == 8 * 60)
    }

    @Test
    func `Skipped is sticky through reconciles and matching`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = addItem("Vitamin D3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        RoutineOccurrenceService.skipToday(slotKeys: [key(item, slot: 9 * 60)], in: context)
        #expect(try occurrences(in: context).first?.state == .skipped)

        // Neither a plain reconcile nor a matching dose reclaims it.
        addEntry("Vitamin D3", in: context)
        RoutineOccurrenceService.reconcile(in: context)
        #expect(try occurrences(in: context).first?.state == .skipped)
    }

    // MARK: - Expiry

    @Test
    func `Yesterday's pending expires to missed; history states survive`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)))
        let stale = RoutineOccurrence(substance: "Vitamin D3", route: .oral, dueDay: yesterday, slotMinutes: 9 * 60)
        let done = RoutineOccurrence(substance: "Magnesium", route: .oral, dueDay: yesterday, slotMinutes: 9 * 60)
        done.state = .logged
        context.insert(stale)
        context.insert(done)

        RoutineOccurrenceService.reconcile(in: context)
        #expect(stale.state == .missed)
        #expect(done.state == .logged)
    }

    // MARK: - The follow-up gate

    @Test
    func `Satisfied slot keys cover logged and skipped, not pending`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let d3 = addItem("Vitamin D3", times: [9 * 60], in: context)
        let mag = addItem("Magnesium", times: [21 * 60], in: context)
        addEntry("Vitamin D3", in: context)

        RoutineOccurrenceService.reconcile(in: context)
        var satisfied = RoutineOccurrenceService.satisfiedSlotKeys(in: context)
        #expect(satisfied.contains(key(d3, slot: 9 * 60)))
        #expect(!satisfied.contains(key(mag, slot: 21 * 60)))

        RoutineOccurrenceService.skipToday(slotKeys: [key(mag, slot: 21 * 60)], in: context)
        satisfied = RoutineOccurrenceService.satisfiedSlotKeys(in: context)
        #expect(satisfied.contains(key(mag, slot: 21 * 60)))
    }

    @Test
    func `A multi-time med is satisfied per slot, not per med`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let item = addItem("Methylphenidate", times: [8 * 60, 13 * 60], in: context)
        let morning = try #require(calendar.date(bySettingHour: 8, minute: 5, second: 0, of: .now))
        addEntry("Methylphenidate", at: morning, in: context)

        RoutineOccurrenceService.reconcile(in: context)
        let satisfied = RoutineOccurrenceService.satisfiedSlotKeys(in: context)
        #expect(satisfied.contains(key(item, slot: 8 * 60)))
        #expect(!satisfied.contains(key(item, slot: 13 * 60)))
    }
}
