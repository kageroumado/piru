import Foundation
import SwiftData
import Testing
@testable import Piru

/// `QuickLogManager.seedIfNeeded(history:context:)` populates the curated chips
/// from the screen's recent-window history. These tests pin its behaviour: it
/// ranks each (substance, route) group's measurements by frequency, caps each
/// group at `perGroupLimit`, is idempotent while the table is populated, and —
/// crucially — re-seeds when the table is empty so a store reset/restore brings
/// the chips back (the seed is keyed purely off the table's emptiness, with no
/// cross-store `UserDefaults` flag that could outlive the store and suppress it).
///
/// `@MainActor` so the `ModelContainer` builds serialize with the app's other
/// container suites — see ``StoreRecoveryTests`` for why.
@Suite("QuickLogSeed")
@MainActor
struct QuickLogSeedTests {
    /// A fresh in-memory container on the current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    @Test
    func `seeds curated chips from history, frequency-ranked`() throws {
        let ctx = try makeContext()

        // Caffeine 100 mg logged 3×, 50 mg once — both in one (oral) group.
        for _ in 0 ..< 3 {
            ctx.insert(DoseEntry(substance: "Caffeine", amount: 100, route: .oral))
        }
        ctx.insert(DoseEntry(substance: "Caffeine", amount: 50, route: .oral))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)

        let seeded = try ctx.fetch(FetchDescriptor<QuickLogDose>())
        #expect(seeded.count == 2) // two distinct measurements, one group
        let frequent = seeded.min { $0.sortOrder < $1.sortOrder } // rank 0
        #expect(frequent?.amount == 100) // the 3× measure ranks first
    }

    @Test
    func `caps each (substance, route) group at perGroupLimit`() throws {
        let ctx = try makeContext()

        // More distinct measurements than the cap, all in one group.
        for amount in stride(from: 10.0, through: 10.0 * Double(QuickLogDose.perGroupLimit + 4), by: 10) {
            ctx.insert(DoseEntry(substance: "Test", amount: amount, route: .oral))
        }
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)

        let seeded = try ctx.fetch(FetchDescriptor<QuickLogDose>())
        #expect(seeded.count == QuickLogDose.perGroupLimit)
    }

    @Test
    func `is idempotent while populated — a second call adds nothing`() throws {
        let ctx = try makeContext()
        ctx.insert(DoseEntry(substance: "Caffeine", amount: 100, route: .oral))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        let afterFirst = try ctx.fetchCount(FetchDescriptor<QuickLogDose>())
        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        let afterSecond = try ctx.fetchCount(FetchDescriptor<QuickLogDose>())

        #expect(afterFirst == 1)
        #expect(afterSecond == afterFirst) // a populated table is left untouched
    }

    @Test
    func `splits the same substance across routes into distinct groups`() throws {
        let ctx = try makeContext()
        ctx.insert(DoseEntry(substance: "Ketamine", amount: 50, route: .oral))
        ctx.insert(DoseEntry(substance: "Ketamine", amount: 50, route: .insufflation))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)

        let seeded = try ctx.fetch(FetchDescriptor<QuickLogDose>())
        #expect(Set(seeded.map(\.route)) == [.oral, .insufflation])
    }

    /// Regression: after a store reset/restore the curated table is empty while
    /// the dose history is intact. Seeding must run again rather than be blocked
    /// by a stale "already seeded" marker — the bug where the quick-log list came
    /// back empty after a delete-all → import (or a mid-cycle schema-change wipe).
    @Test
    func `re-seeds when the table is emptied but history remains`() throws {
        let ctx = try makeContext()
        ctx.insert(DoseEntry(substance: "Caffeine", amount: 100, route: .oral))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<QuickLogDose>()) == 1)

        // Simulate the store reset that wiped the curated rows but not the doses.
        try ctx.delete(model: QuickLogDose.self)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<QuickLogDose>()) == 0)

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<QuickLogDose>()) == 1) // healed
    }

    /// A brand-new user with no dose history has nothing to seed — the empty
    /// table must stay empty rather than the guard mis-firing.
    @Test
    func `does not seed when there is no history`() throws {
        let ctx = try makeContext()
        try QuickLogManager.seedIfNeeded(history: [], context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<QuickLogDose>()) == 0)
    }
}
