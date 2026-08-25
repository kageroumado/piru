import Foundation
import SwiftData
import Testing
@testable import Piru

/// The composed batch pipeline behind every multi-dose logging surface
/// (quick-log tray, both daily-med sites): insert → session assignment →
/// first-time color → one commit → change signal. The stages have their own
/// suites (SessionServiceTests, the QuickLog suites); this one pins the
/// composition.
@MainActor
@Suite("DoseLogBatch")
struct DoseLogBatchTests {
    /// An in-memory store with the full current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// Absent from the substance library, so the tests are independent of
    /// bundled data.
    private let unknown = "ZZBatchTestSubstance"

    private func entry(_ substance: String, hoursFromNow: Double = 0) -> DoseEntry {
        DoseEntry(
            substance: substance,
            amount: 100,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(hoursFromNow * 3_600),
        )
    }

    @Test
    func `Batch inserts every dose with a session assigned, in one commit`() throws {
        let context = try makeContext()
        let doses: [(entry: DoseEntry, substance: Substance?)] = [
            (entry(unknown), nil),
            (entry(unknown, hoursFromNow: 1), nil),
        ]

        DoseLogService.shared.logBatch(doses, colors: [], in: context)

        let saved = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(saved.count == 2)
        for dose in saved {
            #expect(dose.session != nil)
        }
        // Close doses share one session; the single commit left nothing pending.
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
        #expect(!context.hasChanges)
    }

    @Test
    func `First-time substance gets exactly one deterministic color`() throws {
        let context = try makeContext()
        let doses: [(entry: DoseEntry, substance: Substance?)] = [
            (entry(unknown), nil),
            (entry(unknown, hoursFromNow: 0.5), nil),
        ]

        DoseLogService.shared.logBatch(doses, colors: [], in: context)

        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        #expect(colors.count == 1)
        #expect(colors.first?.substance == unknown)
        #expect(colors.first?.hexColor == PresetColor.deterministic(for: unknown).hex)
    }

    @Test
    func `An already-colored substance mints no duplicate`() throws {
        let context = try makeContext()
        let existing = SubstanceColor(substance: unknown, hexColor: PresetColor.all[0].hex)
        context.insert(existing)
        try context.save()

        DoseLogService.shared.logBatch([(entry(unknown), nil)], colors: [existing], in: context)

        #expect(try context.fetch(FetchDescriptor<SubstanceColor>()).count == 1)
    }

    @Test
    func `Revision bumps exactly once per batch`() throws {
        let context = try makeContext()
        let before = DoseLogService.shared.revision

        DoseLogService.shared.logBatch(
            [(entry(unknown), nil), (entry(unknown, hoursFromNow: 1), nil)],
            colors: [],
            in: context,
        )

        #expect(DoseLogService.shared.revision == before + 1)
    }

    @Test
    func `beforeSave mutations ride the same commit`() throws {
        let context = try makeContext()

        DoseLogService.shared.logBatch(
            [(entry(unknown), nil)],
            colors: [],
            in: context,
            beforeSave: {
                context.insert(DailyDoseItem(substance: unknown, amount: 10))
            },
        )

        #expect(try context.fetch(FetchDescriptor<DailyDoseItem>()).count == 1)
        #expect(!context.hasChanges)
    }

    @Test
    func `Empty batch is a complete no-op`() throws {
        let context = try makeContext()
        let before = DoseLogService.shared.revision

        DoseLogService.shared.logBatch([], colors: [], in: context)

        #expect(DoseLogService.shared.revision == before)
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).isEmpty)
        #expect(!context.hasChanges)
    }
}
