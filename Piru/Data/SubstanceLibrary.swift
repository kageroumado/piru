import Foundation

@MainActor
enum SubstanceLibrary {
    // MARK: - Data

    /// All substances — starts with bundled, updated by API fetch
    private(set) static var all: [Substance] = bundledSubstances

    /// Bundled fallback data
    static let bundledSubstances: [Substance] = {
        guard let url = Bundle.main.url(forResource: "substances", withExtension: "json") else {
            fatalError("substances.json not found in app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Substance].self, from: data)
        } catch {
            fatalError("Failed to decode substances.json: \(error)")
        }
    }()

    // MARK: - Derived Data (rebuilt when `all` changes)

    private(set) static var byCategory: [SubstanceCategory: [Substance]] = {
        Dictionary(grouping: bundledSubstances, by: \.category)
    }()

    private(set) static var nonEmptyCategories: [SubstanceCategory] = {
        SubstanceCategory.allCases.filter { byCategory[$0] != nil }
    }()

    private static var nameLookup: [String: Substance] = {
        Dictionary(bundledSubstances.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    private static var fullLookup: [String: Substance] = {
        var map: [String: Substance] = [:]
        for substance in bundledSubstances {
            map[substance.name.lowercased()] = substance
            for alias in substance.aliases {
                if map[alias.lowercased()] == nil {
                    map[alias.lowercased()] = substance
                }
            }
        }
        return map
    }()

    private static var searchIndex: [(substance: Substance, nameLower: String, aliasesLower: [String])] = {
        bundledSubstances.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }
    }()

    // MARK: - Update from API

    /// Replace the substance list with API-fetched data and rebuild all indexes
    static func updateAll(_ substances: [Substance]) {
        all = substances
        rebuildIndexes()
    }

    /// Fetch from APIs and update. Call on app launch.
    static func fetchFromAPIs() {
        Task.detached {
            let substances = await SubstanceService.shared.loadAll()
            guard !substances.isEmpty else { return }
            await MainActor.run {
                updateAll(substances)
            }
        }
    }

    private static func rebuildIndexes() {
        byCategory = Dictionary(grouping: all, by: \.category)
        nonEmptyCategories = SubstanceCategory.allCases.filter { byCategory[$0] != nil }
        nameLookup = Dictionary(all.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var newFullLookup: [String: Substance] = [:]
        for substance in all {
            newFullLookup[substance.name.lowercased()] = substance
            for alias in substance.aliases {
                if newFullLookup[alias.lowercased()] == nil {
                    newFullLookup[alias.lowercased()] = substance
                }
            }
        }
        fullLookup = newFullLookup

        searchIndex = all.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }
    }

    // MARK: - Lookup

    static func substances(in category: SubstanceCategory) -> [Substance] {
        byCategory[category] ?? []
    }

    static func lookup(_ name: String) -> Substance? {
        nameLookup[name.lowercased()]
    }

    static func lookupByNameOrAlias(_ name: String) -> Substance? {
        fullLookup[name.lowercased()]
    }

    // MARK: - Search

    static func search(_ query: String, limit: Int = 50) -> [Substance] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()

        var exact: [Substance] = []
        var aliasExact: [Substance] = []
        var prefix: [Substance] = []
        var contains: [Substance] = []

        for item in searchIndex {
            if item.nameLower == q {
                exact.append(item.substance)
            } else if item.aliasesLower.contains(q) {
                aliasExact.append(item.substance)
            } else if item.nameLower.hasPrefix(q) || item.aliasesLower.contains(where: { $0.hasPrefix(q) }) {
                prefix.append(item.substance)
            } else if item.nameLower.contains(q) || item.aliasesLower.contains(where: { $0.contains(q) }) {
                contains.append(item.substance)
            }
        }

        let combined = exact + aliasExact + prefix + contains
        return Array(combined.prefix(limit))
    }

    /// Total substance count — useful for UI display
    static var count: Int { all.count }

    /// Source breakdown
    static var sourceBreakdown: [String: Int] {
        var counts: [String: Int] = [:]
        for s in all {
            let source = s.sources.first ?? "Bundled"
            counts[source, default: 0] += 1
        }
        return counts
    }
}
