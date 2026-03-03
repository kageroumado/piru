import Foundation

enum SubstanceLibrary {
    // MARK: - Data Loading

    static let all: [Substance] = {
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

    static let byCategory: [SubstanceCategory: [Substance]] = {
        Dictionary(grouping: all, by: \.category)
    }()

    static func substances(in category: SubstanceCategory) -> [Substance] {
        byCategory[category] ?? []
    }

    /// Non-empty categories, precomputed once (substance data is static).
    static let nonEmptyCategories: [SubstanceCategory] = {
        SubstanceCategory.allCases.filter { byCategory[$0] != nil }
    }()

    private static let nameLookup: [String: Substance] = {
        Dictionary(all.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Includes aliases for O(1) lookup by name or alias
    private static let fullLookup: [String: Substance] = {
        var map: [String: Substance] = [:]
        for substance in all {
            map[substance.name.lowercased()] = substance
            for alias in substance.aliases {
                // Don't overwrite if already mapped (name takes priority)
                if map[alias.lowercased()] == nil {
                    map[alias.lowercased()] = substance
                }
            }
        }
        return map
    }()

    /// O(1) exact-name lookup, used by QuickLogView grouping.
    static func lookup(_ name: String) -> Substance? {
        nameLookup[name.lowercased()]
    }

    /// O(1) lookup by name or alias
    static func lookupByNameOrAlias(_ name: String) -> Substance? {
        fullLookup[name.lowercased()]
    }

    /// Precomputed lowercased names/aliases so `search()` never calls `.lowercased()` per item.
    private static let searchIndex: [(substance: Substance, nameLower: String, aliasesLower: [String])] = {
        all.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }
    }()

    static func search(_ query: String, limit: Int = 50) -> [Substance] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()

        // Exact name match first, then alias match, then prefix, then contains
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
}
