import Foundation
import SwiftData
import Testing
@testable import Piru

/// `QuickLogManager.seedIfNeeded(history:context:)` populates the curated chips
/// once from the screen's recent-window history. These tests pin that one-time
/// seed: it ranks each (substance, route) group's measurements by frequency,
/// caps each group at `perGroupLimit`, and is idempotent.
///
/// `@MainActor` so the `ModelContainer` builds serialize with the app's other
/// container suites — see ``StoreRecoveryTests`` for why.
@Suite("QuickLogSeed")
@MainActor
struct QuickLogSeedTests {
    /// The seed flag is app-group `UserDefaults`, shared process-wide. Clear it
    /// so each test runs against a fresh "never seeded" state.
    private static let seededKey = "quickLogSeeded.v1"

    private func resetSeedFlag() {
        UserDefaults(suiteName: StoreRecovery.appGroupID)?.removeObject(forKey: Self.seededKey)
    }

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
        resetSeedFlag()
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
        resetSeedFlag()
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
    func `is idempotent — a second call adds nothing`() throws {
        resetSeedFlag()
        let ctx = try makeContext()
        ctx.insert(DoseEntry(substance: "Caffeine", amount: 100, route: .oral))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        let afterFirst = try ctx.fetchCount(FetchDescriptor<QuickLogDose>())
        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)
        let afterSecond = try ctx.fetchCount(FetchDescriptor<QuickLogDose>())

        #expect(afterFirst == 1)
        #expect(afterSecond == afterFirst) // flag guards the re-run
    }

    @Test
    func `splits the same substance across routes into distinct groups`() throws {
        resetSeedFlag()
        let ctx = try makeContext()
        ctx.insert(DoseEntry(substance: "Ketamine", amount: 50, route: .oral))
        ctx.insert(DoseEntry(substance: "Ketamine", amount: 50, route: .insufflation))
        try ctx.save()

        try QuickLogManager.seedIfNeeded(history: ctx.fetch(FetchDescriptor<DoseEntry>()), context: ctx)

        let seeded = try ctx.fetch(FetchDescriptor<QuickLogDose>())
        #expect(Set(seeded.map(\.route)) == [.oral, .insufflation])
    }
}
