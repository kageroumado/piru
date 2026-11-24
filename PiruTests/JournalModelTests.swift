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
            for: Schema(PiruSchema.models),
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
            filterTags: [],
            filterCategories: [],
            filterRoutes: [],
            stackRedoses: true,
            revision: signature,
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

    /// The Grouped view's buckets outlive a commit by one debounced regroup.
    /// A row drawn in that window after a wipe (a restore that replaces the
    /// journal) read `entry.route` on a deleted dose and trapped; the buckets
    /// hold each row's own copy of what it prints.
    @Test
    func `Grouped rows still print once their doses are deleted`() async throws {
        let context = try makeContext()
        let entries = try makeEntries(context)
        let ids = entries.map(\.id)
        let timestamps = entries.map(\.timestamp)

        let model = JournalModel()
        model.refreshColorMap([])
        await model.rebuildDerived(entries: entries, colors: [])
        for key in [JournalGroupKey.substance, .category] {
            model.rebuildGroups(
                entries: entries, grouping: .grouped, groupKey: key, searchText: "",
                filterTags: [], filterCategories: [], filterRoutes: [],
                stackRedoses: true, revision: 0,
            )
        }
        #expect(model.substanceGroups.map(\.name) == [substanceName])
        #expect(model.categoryGroups.map(\.category) == [.other])

        // The wipe: every row deleted and saved, the buckets not yet rebuilt.
        try PiruSchema.deleteAll(in: context)

        for rows in [model.substanceGroups.first?.rows, model.categoryGroups.first?.rows] {
            let rows = try #require(rows)
            #expect(rows.map(\.id) == ids)
            #expect(rows.map(\.timestamp) == timestamps)
            #expect(rows.map(\.route) == [.oral, .oral])
            #expect(rows.map(\.amountDisplay) == ["100", "100"])
            #expect(rows.map(\.title) == [substanceName, substanceName])
        }
    }

    /// A dose the derive has not reached is bucketed from the live entry, and
    /// an edited dose's row follows the next derive.
    @Test
    func `Grouped rows follow an edit at the next derive`() async throws {
        let context = try makeContext()
        let entries = try makeEntries(context)
        let model = JournalModel()
        model.refreshColorMap([])
        let regroup = { (revision: Int) in
            model.rebuildGroups(
                entries: entries, grouping: .grouped, groupKey: .substance, searchText: "",
                filterTags: [], filterCategories: [], filterRoutes: [],
                stackRedoses: true, revision: revision,
            )
        }

        regroup(0)
        #expect(model.substanceGroups.first?.rows.map(\.amountDisplay) == ["100", "100"])

        await model.rebuildDerived(entries: entries, colors: [])
        entries[0].amount = 250
        entries[0].route = .insufflation
        await model.rebuildDerived(entries: entries, colors: [])
        regroup(1)
        let rows = try #require(model.substanceGroups.first?.rows)
        #expect(rows.map(\.amountDisplay) == ["250", "100"])
        #expect(rows.map(\.route) == [.insufflation, .oral])
    }

    /// Choosing a skin re-creates the app's root, and the Journal with it. The
    /// new Journal starts from what the last one resolved, and owes a derive
    /// only when the log or the colors moved since, or the store is another.
    @Test
    func `A new Journal takes over the last derive of its store while it is current`() async throws {
        let context = try makeContext()
        let entries = try makeEntries(context)
        let first = JournalModel()
        await first.rebuildDerived(entries: entries, colors: [])
        first.markDerived(logRevision: 7)
        first.handOver(in: context)

        let current = JournalModel()
        #expect(current.takeOver(in: context, revision: 7, colors: []))
        #expect(current.isDerived(atLogRevision: 7))
        regroup(current, entries, signature: 1)
        let card = try #require(current.sessionDays.first?.sessions.first)
        #expect(!card.states.isEmpty || !card.markers.isEmpty)

        // The log moved: what was resolved is the base of the derive still owed.
        let behind = JournalModel()
        #expect(!behind.takeOver(in: context, revision: 8, colors: []))
        #expect(!behind.isDerived(atLogRevision: 8))
        #expect(behind.derived.count == entries.count)

        // A color changed: the resolved tints are stale.
        let recolored = JournalModel()
        let color = SubstanceColor(substance: substanceName, tint: P3Color(red: 0.2, green: 0.4, blue: 0.6), usesDefault: false)
        #expect(!recolored.takeOver(in: context, revision: 7, colors: [color]))
        #expect(!recolored.isDerived(atLogRevision: 7))

        // Another store's Journal finds nothing.
        let other = try makeContext()
        let elsewhere = JournalModel()
        #expect(!elsewhere.takeOver(in: other, revision: 7, colors: []))
        #expect(elsewhere.derived.isEmpty)

        // The journal was deleted.
        JournalModel.dropHandover()
        let afterDeletion = JournalModel()
        #expect(!afterDeletion.takeOver(in: context, revision: 7, colors: []))
        #expect(afterDeletion.derived.isEmpty)
    }

    /// kageroumado/piru#23: with the day starting at 4 AM, a session begun at
    /// 02:30 goes under the evening before, and an hour of 0 keeps calendar days.
    @Test
    func `Day sections follow the Day Starts At hour`() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let evening = try #require(calendar.date(from: DateComponents(year: 2_026, month: 3, day: 10, hour: 22)))
        let small = try #require(calendar.date(from: DateComponents(year: 2_026, month: 3, day: 11, hour: 2, minute: 30)))
        // No session assignment: each dose is its own card, starting at its own time.
        for timestamp in [evening, small] {
            context.insert(DoseEntry(substance: substanceName, amount: 100, timestamp: timestamp))
        }
        try context.save()
        let entries = try context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))

        let model = JournalModel()
        model.refreshColorMap([])
        let regroup = { (hour: Int) in
            model.rebuildGroups(
                entries: entries, grouping: .byDay, searchText: "",
                filterTags: [], filterCategories: [], filterRoutes: [],
                stackRedoses: true, revision: 0, dayBoundaryHour: hour,
            )
        }

        regroup(4)
        #expect(model.sessionDays.map(\.date) == [calendar.startOfDay(for: evening)])
        #expect(model.sessionDays.first?.sessions.count == 2)

        regroup(0)
        #expect(model.sessionDays.map(\.date) == [calendar.startOfDay(for: small), calendar.startOfDay(for: evening)])
    }
}
