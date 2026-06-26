import Foundation
import SwiftData
import Testing
@testable import Piru

@MainActor
@Suite("JournalModel grouping")
struct JournalModelTests {
    /// An in-memory store with the full current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A name guaranteed absent from the substance library: it resolves to a dose
    /// *marker* (not a curve), which is enough to make a card carry graph data
    /// without coupling the test to bundled substance values.
    private let substanceName = "ZZTestSubstanceNotInLibrary"

    /// Two doses ~10 min apart in one recent cluster → one session → one day card.
    private func makeEntries(_ context: ModelContext) throws -> [DoseEntry] {
        let base = Date.now.addingTimeInterval(-30 * 60)
        for offset in [0.0, 600.0] {
            context.insert(DoseEntry(
                substance: substanceName,
                amount: 100,
                timestamp: base.addingTimeInterval(offset),
            ))
        }
        try context.save()
        SessionService.assignUnassignedDoses(in: context)
        try context.save()
        // Newest-first, matching `EntryListView`'s `@Query` sort.
        return try context.fetch(
            FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]),
        )
    }

    private func regroup(_ model: JournalModel, _ entries: [DoseEntry], signature: Int) {
        model.rebuildGroups(
            entries: entries,
            grouping: .byDay,
            searchText: "",
            selectedTag: nil,
            filterCategories: [],
            stackRedoses: true,
            entriesSignature: signature,
        )
    }

    /// Regression: on a cold launch the search `.task` can fire its `regroup()`
    /// while the entries `.task` is still suspended at the batch-cache `await`, so
    /// the Day cards build from an empty `derived` and show no graph. When the
    /// derive then resolves and regroups with the *same* filter signature, the
    /// rebuild must still happen — otherwise the matching signature short-circuits
    /// it and every journal graph stays blank until an unrelated change (a scroll)
    /// forces a re-bucket. The derive-revision in the groups signature is what
    /// distinguishes "derived changed, rebuild" from "same filters, skip".
    @Test
    func `A regroup that ran before the derive resolved still gets graph data once it lands`() async throws {
        let context = try makeContext()
        let entries = try makeEntries(context)
        // Constant across the race: the filter inputs never change, only `derived`.
        let signature = 0xC0FFEE

        let model = JournalModel()
        model.refreshColorMap([])

        // The race: regroup before the derive has resolved anything.
        regroup(model, entries, signature: signature)
        let before = try #require(model.sessionDays.first?.sessions.first)
        #expect(before.states.isEmpty && before.markers.isEmpty)

        // The derive resolves and (via onPrefixReady) regroups with the same
        // filter signature, then the final regroup runs.
        await model.rebuildDerived(entries: entries, colors: []) {
            regroup(model, entries, signature: signature)
        }
        regroup(model, entries, signature: signature)

        let after = try #require(model.sessionDays.first?.sessions.first)
        #expect(
            !after.states.isEmpty || !after.markers.isEmpty,
            "cards must carry graph data once the derive resolves, even though the filter signature is unchanged",
        )
    }
}
