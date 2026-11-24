import Foundation
import SwiftData
import Testing
@testable import Piru

/// The strip resolves a long log in chunks with a yield between them. A
/// commit during a yield can delete the doses still to be read, and a
/// deleted dose's fields trap once the deletion is saved, so the resolver
/// asks whether to stop after every yield and skips doses whose context is
/// gone.
@MainActor
@Suite("Timeline strip resolve", .serialized)
struct TimelineStripResolveTests {
    private func makeContext() throws -> (ModelContext, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (ModelContext(container), container)
    }

    private func doses(_ count: Int, in context: ModelContext) throws -> [DoseEntry] {
        let start = DebugClock.now.addingTimeInterval(-Double(count) * 3_600)
        let entries = (0 ..< count).map { index in
            DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", timestamp: start.addingTimeInterval(Double(index) * 3_600))
        }
        for entry in entries {
            context.insert(entry)
        }
        try context.save()
        return entries
    }

    @Test
    func `A wipe during a yield stops the resolve before it reads another dose`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (context, container) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let entries = try doses(600, in: context)

        var checks = 0
        let resolved = await TimelineStripBuilder.resolve(
            entries, colors: [], colorMap: [:], sessions: [:],
            shouldStop: {
                checks += 1
                // What Delete Everything does between two chunks.
                for entry in entries {
                    context.delete(entry)
                }
                try? context.save()
                return true
            },
        )

        #expect(resolved == nil)
        #expect(checks == 1)
    }

    @Test
    func `Doses deleted and saved are skipped`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (context, container) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let entries = try doses(10, in: context)
        for entry in entries.prefix(4) {
            context.delete(entry)
        }
        try context.save()

        let resolved = try #require(await TimelineStripBuilder.resolve(
            entries, colors: [], colorMap: [:], sessions: [:], shouldStop: { false },
        ))

        #expect(resolved.items.count == 6)
    }

    @Test
    func `A resolve that is never stopped reads every chunk`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (context, container) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let entries = try doses(600, in: context)

        var checks = 0
        let resolved = try #require(await TimelineStripBuilder.resolve(
            entries, colors: [], colorMap: [:], sessions: [:],
            shouldStop: {
                checks += 1
                return false
            },
        ))

        #expect(resolved.items.count == 600)
        #expect(checks == 2)
    }
}
