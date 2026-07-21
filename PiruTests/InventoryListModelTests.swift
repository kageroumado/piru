import Foundation
import SwiftData
import Testing
@testable import Piru

/// Covers the inventory manager's arranging layer: filtering, sorting, and
/// grouping. These are the parts that decide what the user actually sees in an
/// 80-item list, and they're pure functions of the model's options — so they're
/// worth pinning down without a view.
@MainActor
@Suite("Inventory list arranging")
struct InventoryListModelTests {
    // MARK: Fixtures

    /// An in-memory store with the full current schema. The container is held by
    /// the returned context, and the context is what callers keep alive.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A model backed by a throwaway defaults suite, so persisting `sort` /
    /// `isGrouped` never touches the real app preferences.
    private func makeModel() throws -> InventoryListModel {
        let suite = try #require(UserDefaults(suiteName: "InventoryListModelTests-\(UUID().uuidString)"))
        return InventoryListModel(defaults: suite)
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    private func makeItem(
        _ ctx: ModelContext,
        _ substance: String,
        quantity: Double,
        lowStockThreshold: Double? = nil,
        baseline: Double? = nil,
        sortOrder: Int = 0,
        restockedHoursAgo: Double? = nil,
    ) -> InventoryItem {
        let events: [ManualEvent] = restockedHoursAgo.map {
            [ManualEvent(kind: .restock, amount: quantity, date: now.addingTimeInterval(-$0 * 3_600))]
        } ?? []
        let item = InventoryItem(
            substance: substance,
            trackingStart: now,
            lowStockThreshold: lowStockThreshold,
            baselineQuantity: baseline,
            manualEvents: events,
            createdAt: now,
            sortOrder: sortOrder,
        )
        // `currentQuantity` is a cache of the dose replay; setting it directly is
        // exactly what `recompute` does, and keeps these tests about arranging
        // rather than about stock math (covered by the Inventory suite).
        item.currentQuantity = quantity
        ctx.insert(item)
        return item
    }

    // MARK: Sorting

    @Test
    func `Status sort puts out first, then low, then healthy`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 500)
        makeItem(ctx, "Bromazepam", quantity: 0)
        makeItem(ctx, "Melatonin", quantity: 5, lowStockThreshold: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .status
        model.isGrouped = false

        let rows = model.sections(for: items).first?.items ?? []
        #expect(rows.map(\.stockStatus) == [.out, .low, .ok])
    }

    @Test
    func `Name sort is alphabetical by display title`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Melatonin", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        makeItem(ctx, "Caffeine", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .name
        model.isGrouped = false

        let titles = (model.sections(for: items).first?.items ?? []).map(\.displayTitle)
        #expect(titles == titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test
    func `Supply sort ranks by fraction of baseline, with no-baseline items last`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 80, baseline: 100) // 0.8
        makeItem(ctx, "Melatonin", quantity: 10, baseline: 100) // 0.1
        makeItem(ctx, "Bromazepam", quantity: 50) // no baseline
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .supply
        model.isGrouped = false

        let rows = model.sections(for: items).first?.items ?? []
        #expect(rows.map(\.substance) == ["Melatonin", "Caffeine", "Bromazepam"])
        #expect(rows.last?.fillFraction == nil)
    }

    @Test
    func `Manual sort follows sortOrder`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10, sortOrder: 2)
        makeItem(ctx, "Melatonin", quantity: 10, sortOrder: 0)
        makeItem(ctx, "Bromazepam", quantity: 10, sortOrder: 1)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .manual
        model.isGrouped = false

        let rows = model.sections(for: items).first?.items ?? []
        #expect(rows.map(\.substance) == ["Melatonin", "Bromazepam", "Caffeine"])
    }

    // MARK: Reordering rule

    @Test
    func `Reordering is offered only in manual, ungrouped mode`() throws {
        let model = try makeModel()
        for sort in InventorySort.allCases {
            for grouped in [true, false] {
                model.sort = sort
                model.isGrouped = grouped
                #expect(model.canReorder == (sort == .manual && !grouped))
            }
        }
    }

    // MARK: Filtering

    @Test
    func `Status filter keeps only the selected statuses`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 500)
        makeItem(ctx, "Bromazepam", quantity: 0)
        makeItem(ctx, "Melatonin", quantity: 5, lowStockThreshold: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false
        model.filterStatuses = [.out, .low]

        let rows = model.sections(for: items).flatMap(\.items)
        #expect(rows.count == 2)
        #expect(!rows.contains { $0.stockStatus == .ok })
    }

    @Test
    func `An empty status filter means every status`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 500)
        makeItem(ctx, "Bromazepam", quantity: 0)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false
        #expect(!model.hasActiveFilters)
        #expect(model.sections(for: items).flatMap(\.items).count == 2)
    }

    @Test
    func `Search matches the substance name`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false
        model.searchText = "caff"

        let rows = model.sections(for: items).flatMap(\.items)
        #expect(rows.map(\.substance) == ["Caffeine"])
    }

    @Test
    func `Search matches the substance class, not just the name`() throws {
        let ctx = try makeContext()
        let caffeine = makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false
        // Query by the *class* name — no item's own name contains it, so a hit
        // proves the class is part of the haystack.
        let className = String(localized: model.category(for: caffeine).displayName)
        model.searchText = className

        let rows = model.sections(for: items).flatMap(\.items)
        #expect(rows.contains { $0.substance == "Caffeine" })
        #expect(rows.allSatisfy { model.category(for: $0) == model.category(for: caffeine) })
    }

    @Test
    func `Filtering everything away yields no sections, not an empty one`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.searchText = "nothing-matches-this"
        #expect(model.sections(for: items).isEmpty)
    }

    // MARK: Grouping

    @Test
    func `Flat mode returns exactly one headerless section`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false

        let sections = model.sections(for: items)
        #expect(sections.count == 1)
        #expect(sections[0].category == nil)
        #expect(sections[0].items.count == 2)
    }

    @Test
    func `Grouped mode makes one section per class, and every row belongs to its section`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        makeItem(ctx, "Melatonin", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = true

        let sections = model.sections(for: items)
        let distinctClasses = Set(items.map(model.category(for:)))
        #expect(sections.count == distinctClasses.count)
        for section in sections {
            #expect(section.items.allSatisfy { model.category(for: $0) == section.category })
        }
        #expect(sections.flatMap(\.items).count == items.count)
    }

    @Test
    func `Status sort floats the class holding an Out item to the top section`() throws {
        let ctx = try makeContext()
        let healthy = makeItem(ctx, "Caffeine", quantity: 500)
        let empty = makeItem(ctx, "Bromazepam", quantity: 0)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .status
        model.isGrouped = true

        // Only meaningful when the two land in different classes; if the bundled
        // data ever merges them the grouping assertion above still covers us.
        try #require(model.category(for: healthy) != model.category(for: empty))
        #expect(model.sections(for: items).first?.category == model.category(for: empty))
    }

    @Test
    func `Name sort orders the sections alphabetically by class`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        makeItem(ctx, "Melatonin", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .name
        model.isGrouped = true

        let names = model.sections(for: items).compactMap(\.category).map { String(localized: $0.displayName) }
        #expect(names == names.sorted())
    }

    // MARK: Summary-card ordering

    @Test
    func `The card's order follows the manager's sort`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Melatonin", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 0)
        makeItem(ctx, "Caffeine", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = false

        model.sort = .status
        #expect(model.ordered(items).first?.stockStatus == .out)

        model.sort = .name
        let titles = model.ordered(items).map(\.displayTitle)
        #expect(titles == titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test
    func `The card ignores search and filters, which are one screen's narrowing`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 500)
        makeItem(ctx, "Bromazepam", quantity: 0)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.filterStatuses = [.out]
        model.searchText = "caff"

        // The list narrows to one row...
        #expect(model.sections(for: items).flatMap(\.items).isEmpty)
        // ...while the card still speaks for the whole inventory.
        #expect(model.ordered(items).count == 2)
    }

    @Test
    func `The card honors a custom class arrangement`() throws {
        let ctx = try makeContext()
        let healthy = makeItem(ctx, "Caffeine", quantity: 500)
        let empty = makeItem(ctx, "Bromazepam", quantity: 0)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .status
        model.isGrouped = true
        let healthyClass = model.category(for: healthy)
        try #require(healthyClass != model.category(for: empty))

        // Status alone would lead with the Out item; the arrangement outranks it.
        #expect(model.ordered(items).first?.substance == "Bromazepam")
        model.setCategoryOrder([healthyClass])
        #expect(model.ordered(items).first?.substance == "Caffeine")
    }

    // MARK: Collapsing

    @Test
    func `Collapsing a class hides its rows but keeps the section`() throws {
        let ctx = try makeContext()
        let caffeine = makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = true
        let stimulants = model.category(for: caffeine)
        model.toggleCollapsed(stimulants)

        #expect(!model.isExpanded(stimulants))
        // The section itself survives — the header is the only way back.
        let sections = model.sections(for: items)
        #expect(sections.contains { $0.category == stimulants })
        // Sectioning still reports the full membership; only the view hides rows.
        #expect(sections.first { $0.category == stimulants }?.items.count == 1)
    }

    @Test
    func `A live search force-expands collapsed classes so matches stay visible`() throws {
        let ctx = try makeContext()
        let caffeine = makeItem(ctx, "Caffeine", quantity: 10)
        _ = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        let category = model.category(for: caffeine)
        model.toggleCollapsed(category)
        #expect(!model.isExpanded(category))

        model.searchText = "caff"
        #expect(model.isExpanded(category))

        // Whitespace alone isn't a search, so it must not force anything open.
        model.searchText = "   "
        #expect(!model.isExpanded(category))
    }

    @Test
    func `Collapse-all and expand-all cover every present class`() throws {
        let ctx = try makeContext()
        makeItem(ctx, "Caffeine", quantity: 10)
        makeItem(ctx, "Bromazepam", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        let categories = model.availableCategories(in: items)

        model.setAllCollapsed(true, in: categories)
        #expect(categories.allSatisfy { !model.isExpanded($0) })

        model.setAllCollapsed(false, in: categories)
        #expect(categories.allSatisfy(model.isExpanded))
    }

    // MARK: Class arrangement

    @Test
    func `A dragged class order overrides the sort-derived section order`() throws {
        let ctx = try makeContext()
        let healthy = makeItem(ctx, "Caffeine", quantity: 500)
        let empty = makeItem(ctx, "Bromazepam", quantity: 0)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.sort = .status
        model.isGrouped = true

        let healthyClass = model.category(for: healthy)
        let emptyClass = model.category(for: empty)
        try #require(healthyClass != emptyClass)

        // Status sort would put the Out item's class first; arranging flips it.
        #expect(model.sections(for: items).first?.category == emptyClass)
        model.setCategoryOrder([healthyClass, emptyClass])
        #expect(model.hasCustomCategoryOrder)
        #expect(model.sections(for: items).first?.category == healthyClass)

        model.resetCategoryOrder()
        #expect(!model.hasCustomCategoryOrder)
        #expect(model.sections(for: items).first?.category == emptyClass)
    }

    @Test
    func `A class missing from the arrangement settles after the arranged ones`() throws {
        let ctx = try makeContext()
        let caffeine = makeItem(ctx, "Caffeine", quantity: 10)
        let bromazepam = makeItem(ctx, "Bromazepam", quantity: 10)
        let melatonin = makeItem(ctx, "Melatonin", quantity: 10)
        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())

        let model = try makeModel()
        model.isGrouped = true
        let arranged = [model.category(for: bromazepam), model.category(for: caffeine)]
        let unarranged = model.category(for: melatonin)
        try #require(!arranged.contains(unarranged))

        model.setCategoryOrder(arranged)
        let order = model.sections(for: items).compactMap(\.category)
        #expect(Array(order.prefix(2)) == arranged)
        #expect(order.last == unarranged)
    }

    // MARK: Persistence

    @Test
    func `Collapsed classes and the class arrangement survive a new model`() throws {
        let suite = try #require(UserDefaults(suiteName: "InventoryListModelTests-fold-\(UUID().uuidString)"))

        let first = InventoryListModel(defaults: suite)
        #expect(first.collapsedCategories.isEmpty)
        #expect(!first.hasCustomCategoryOrder)
        first.toggleCollapsed(.benzodiazepine)
        first.setCategoryOrder([.opioid, .stimulant])

        let second = InventoryListModel(defaults: suite)
        #expect(second.collapsedCategories == [.benzodiazepine])
        #expect(second.categoryOrder == [.opioid, .stimulant])
    }

    @Test
    func `Sort and grouping survive a new model on the same defaults`() throws {
        let suite = try #require(UserDefaults(suiteName: "InventoryListModelTests-persist-\(UUID().uuidString)"))

        let first = InventoryListModel(defaults: suite)
        #expect(first.sort == .status)
        #expect(first.isGrouped) // grouped is the fresh-install default
        first.sort = .supply
        first.isGrouped = false

        let second = InventoryListModel(defaults: suite)
        #expect(second.sort == .supply)
        #expect(!second.isGrouped)
    }
}
