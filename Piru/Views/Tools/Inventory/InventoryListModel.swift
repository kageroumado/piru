import SwiftData
import SwiftUI

// MARK: - Sort

/// How the inventory manager orders its rows.
///
/// The same key also orders *sections* when grouping is on: a section inherits
/// the rank of its best-ranked item, so switching grouping on and off never
/// changes what the chosen order is trying to say. (``name`` is the exception —
/// there the sections themselves sort alphabetically, which is what "by name"
/// means once the rows are already grouped.)
enum InventorySort: String, CaseIterable, Identifiable {
    /// Needs-attention first: out → low → healthy, then most recent activity.
    case status
    /// Alphabetical by display title.
    case name
    /// Emptiest first, as a fraction of baseline. Items without a baseline have
    /// no comparable level and sort last.
    case supply
    /// Most recently restocked or corrected first.
    case recent
    /// The user's dragged arrangement — the only mode where rows can be moved.
    case manual

    var id: String {
        rawValue
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .status: "Status"
        case .name: "Name"
        case .supply: "Supply Level"
        case .recent: "Recently Updated"
        case .manual: "Manual"
        }
    }

    var icon: String {
        switch self {
        case .status: "exclamationmark.triangle"
        case .name: "textformat"
        case .supply: "gauge.with.needle"
        case .recent: "clock"
        case .manual: "hand.draw"
        }
    }
}

// MARK: - Section

/// One rendered group of inventory rows. In flat mode the list is a single
/// section with no ``category``; grouped, there is one per substance class.
struct InventorySectionGroup: Identifiable {
    /// Stable across rebuilds so SwiftUI keeps section identity while filtering.
    let id: String
    /// `nil` in flat mode — the section then renders headerless.
    let category: SubstanceCategory?
    let items: [InventoryItem]
}

// MARK: - Model

/// Owns the inventory manager's view options — sort, grouping, search, and the
/// two filter facets — plus the filtering/grouping itself.
///
/// This is a model rather than a pile of `@State` for the usual reason: the
/// manager would otherwise re-evaluate its whole body (81 rows, each doing a
/// library lookup) on every keystroke of the search field. Keeping the options
/// here also makes the sectioning a plain, testable function of its inputs.
///
/// Sort and grouping persist across visits (they read as a *preference*);
/// search and filters deliberately reset, matching the Journal.
@Observable
@MainActor
final class InventoryListModel {
    /// Shared because two surfaces render the same ordering — the manager and the
    /// Tools summary card. A per-view instance would read the persisted options
    /// once at init and then miss every later change, so the card would keep
    /// showing the previous sort until the tab was rebuilt.
    static let shared = InventoryListModel()

    // MARK: Options

    var sort: InventorySort {
        didSet { defaults.set(sort.rawValue, forKey: Keys.sort) }
    }

    var isGrouped: Bool {
        didSet { defaults.set(isGrouped, forKey: Keys.grouped) }
    }

    var searchText: String = ""
    /// Empty means "every status" — the menu shows no checkmarks in that state.
    var filterStatuses: Set<StockStatus> = []
    /// Empty means "every class".
    var filterCategories: Set<SubstanceCategory> = []

    /// Classes the user has folded away. Persisted: collapsing a class you never
    /// think about should stay collapsed next visit.
    private(set) var collapsedCategories: Set<SubstanceCategory> {
        didSet { defaults.set(collapsedCategories.map(\.rawValue), forKey: Keys.collapsed) }
    }

    /// The user's manual arrangement of class sections. Empty means "derive it
    /// from the sort", which is the default.
    private(set) var categoryOrder: [SubstanceCategory] {
        didSet { defaults.set(categoryOrder.map(\.rawValue), forKey: Keys.categoryOrder) }
    }

    private enum Keys {
        static let sort = "inventory.sort"
        static let grouped = "inventory.grouped"
        static let collapsed = "inventory.collapsedCategories"
        static let categoryOrder = "inventory.categoryOrder"
    }

    /// Where `sort` and `isGrouped` persist. Injectable so tests get their own
    /// suite instead of writing the user's real preferences.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.sort)
        sort = raw.flatMap(InventorySort.init(rawValue:)) ?? .status
        // Grouped is the default for a fresh install; `object(forKey:)` (not
        // `bool(forKey:)`) distinguishes "never set" from an explicit `false`.
        isGrouped = defaults.object(forKey: Keys.grouped) as? Bool ?? true
        let collapsedRaw = defaults.stringArray(forKey: Keys.collapsed) ?? []
        collapsedCategories = Set(collapsedRaw.compactMap(SubstanceCategory.init(rawValue:)))
        let orderRaw = defaults.stringArray(forKey: Keys.categoryOrder) ?? []
        categoryOrder = orderRaw.compactMap(SubstanceCategory.init(rawValue:))
    }

    // MARK: Derived state

    var hasActiveFilters: Bool {
        !filterStatuses.isEmpty || !filterCategories.isEmpty
    }

    /// Reordering only makes sense when a manual order is what's on screen —
    /// any other sort would immediately overwrite the drag, and dragging across
    /// section boundaries has no meaning.
    var canReorder: Bool {
        sort == .manual && !isGrouped
    }

    func clearFilters() {
        filterStatuses = []
        filterCategories = []
    }

    // MARK: Collapsing

    /// Whether a class section shows its rows.
    ///
    /// A live search force-expands everything: a collapsed section would swallow
    /// its own matches, so the search would look like it found nothing.
    func isExpanded(_ category: SubstanceCategory) -> Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !collapsedCategories.contains(category)
    }

    func toggleCollapsed(_ category: SubstanceCategory) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }

    /// Fold/unfold everything at once — with ~20 classes, doing it one at a time
    /// to get an overview is a chore.
    func setAllCollapsed(_ collapsed: Bool, in categories: [SubstanceCategory]) {
        collapsedCategories = collapsed ? Set(categories) : []
    }

    // MARK: Class arrangement

    /// `true` once the user has dragged classes into their own order, which then
    /// wins over the sort-derived section order.
    var hasCustomCategoryOrder: Bool {
        !categoryOrder.isEmpty
    }

    func setCategoryOrder(_ order: [SubstanceCategory]) {
        categoryOrder = order
    }

    /// Hand section ordering back to the sort.
    func resetCategoryOrder() {
        categoryOrder = []
    }

    // MARK: Category resolution

    /// Memoized `substance → class` lookups, keyed by the lowercased canonical
    /// name. Resolving 81 items through ``SubstanceLibrary`` on every body pass
    /// is the one genuinely expensive part of grouping, and the answer only
    /// changes when the library does.
    private var categoryCache: [String: SubstanceCategory] = [:]

    func category(for item: InventoryItem) -> SubstanceCategory {
        let key = item.substance.lowercased()
        if let cached = categoryCache[key] { return cached }
        let resolved = SubstanceLibrary.lookup(item.substance)?.category ?? .other
        categoryCache[key] = resolved
        return resolved
    }

    /// Every class present in the *unfiltered* inventory, alphabetized — the
    /// filter menu offers only classes the user actually stocks.
    func availableCategories(in items: [InventoryItem]) -> [SubstanceCategory] {
        Set(items.map(category(for:)))
            .sorted { String(localized: $0.displayName) < String(localized: $1.displayName) }
    }

    // MARK: Sectioning

    /// The full pipeline: filter → sort → group. Pure with respect to the
    /// options, so the view just renders whatever comes back.
    func sections(for items: [InventoryItem]) -> [InventorySectionGroup] {
        arrange(filtered(items))
    }

    /// Every item in the manager's order, flattened — what the Tools summary card
    /// takes its top few from.
    ///
    /// Deliberately skips ``filtered``: sort and class arrangement are settings
    /// the user chose for how inventory *reads*, while search and the filter
    /// facets are a transient narrowing of one screen. A hub card that quietly
    /// hid most of the inventory because a filter was left on elsewhere would be
    /// a lie about what's in stock.
    func ordered(_ items: [InventoryItem]) -> [InventoryItem] {
        arrange(items).flatMap(\.items)
    }

    /// Sort, then group when grouping is on — the ordering half of the pipeline,
    /// shared so the card and the list can't drift apart.
    private func arrange(_ items: [InventoryItem]) -> [InventorySectionGroup] {
        let rows = sorted(items)
        guard isGrouped else {
            return rows.isEmpty ? [] : [InventorySectionGroup(id: "all", category: nil, items: rows)]
        }
        return grouped(rows)
    }

    /// Search + both facets. Search matches the display title, the stored
    /// canonical name (so "bromoketamine" finds the row shown as "2-Br-DCK"),
    /// the salt, and the class name.
    private func filtered(_ items: [InventoryItem]) -> [InventoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if !filterStatuses.isEmpty, !filterStatuses.contains(item.stockStatus) { return false }
            if !filterCategories.isEmpty, !filterCategories.contains(category(for: item)) { return false }
            guard !query.isEmpty else { return true }
            let haystack = [
                item.displayTitle,
                item.substance,
                item.saltForm ?? "",
                String(localized: category(for: item).displayName),
            ]
            return haystack.contains { $0.lowercased().contains(query) }
        }
    }

    private func sorted(_ items: [InventoryItem]) -> [InventoryItem] {
        switch sort {
        case .status:
            items.sorted {
                $0.sortPriority != $1.sortPriority
                    ? $0.sortPriority < $1.sortPriority
                    : $0.lastActivity > $1.lastActivity
            }
        case .name:
            items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .supply:
            // No baseline means no comparable level, so those rows collect at the
            // end rather than pretending to be full or empty.
            items.sorted {
                let left = $0.fillFraction ?? .infinity
                let right = $1.fillFraction ?? .infinity
                return left == right
                    ? $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                    : left < right
            }
        case .recent:
            items.sorted { $0.lastActivity > $1.lastActivity }
        case .manual:
            items.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    /// Bucket the already-sorted rows by class, preserving the row order inside
    /// each section.
    ///
    /// Section order follows the same key as the rows: first appearance in the
    /// sorted list, which means a section is ranked by its best item (the class
    /// holding the only Out item leads a status sort). Sorting *by name* is the
    /// exception — there the sections themselves go alphabetical.
    ///
    /// A user-dragged ``categoryOrder`` overrides all of that. Classes it doesn't
    /// mention (a newly tracked one, say) keep their derived position and settle
    /// after the arranged ones rather than jumping to the top.
    private func grouped(_ rows: [InventoryItem]) -> [InventorySectionGroup] {
        var buckets: [SubstanceCategory: [InventoryItem]] = [:]
        var order: [SubstanceCategory] = []
        for item in rows {
            let category = category(for: item)
            if buckets[category] == nil { order.append(category) }
            buckets[category, default: []].append(item)
        }
        if sort == .name {
            order.sort { String(localized: $0.displayName) < String(localized: $1.displayName) }
        }
        if hasCustomCategoryOrder {
            let derived = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
            let arranged = Dictionary(uniqueKeysWithValues: categoryOrder.enumerated().map { ($0.element, $0.offset) })
            order.sort {
                let left = (arranged[$0] ?? .max, derived[$0] ?? 0)
                let right = (arranged[$1] ?? .max, derived[$1] ?? 0)
                return left < right
            }
        }
        return order.map {
            InventorySectionGroup(id: $0.rawValue, category: $0, items: buckets[$0] ?? [])
        }
    }
}

// MARK: - Row ordering primitives

extension InventoryItem {
    /// Sort priority: out first, then low, then healthy.
    var sortPriority: Int {
        switch stockStatus {
        case .out: 0
        case .low: 1
        case .ok: 2
        }
    }

    /// Most recent manual activity, falling back to creation — used to order
    /// items of equal status by "recently used".
    var lastActivity: Date {
        manualEvents.map(\.date).max() ?? createdAt
    }
}
