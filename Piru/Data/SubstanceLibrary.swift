import Foundation

enum SubstanceLibrary {
    // MARK: - Data

    @MainActor private(set) static var all: [Substance] = loadCache() ?? []

    @MainActor private(set) static var byCategory: [SubstanceCategory: [Substance]] = Dictionary(grouping: all, by: \.category)

    @MainActor private(set) static var nonEmptyCategories: [SubstanceCategory] = SubstanceCategory.allCases.filter { byCategory[$0] != nil }

    @MainActor private static var nameLookup: [String: Substance] = Dictionary(all.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

    @MainActor private static var fullLookup: [String: Substance] = {
        var map: [String: Substance] = [:]
        for s in all {
            map[s.name.lowercased()] = s
            for a in s.aliases { if map[a.lowercased()] == nil { map[a.lowercased()] = s } }
        }
        return map
    }()

    @MainActor private static var searchIndex: [(substance: Substance, nameLower: String, aliasesLower: [String])] = all.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }

    // MARK: - API Fetch

    @MainActor static func fetchFromAPIs() {
        Task {
            let tripSitDrugs = (try? await TripSitAPI.fetchAll()) ?? [:]
            let fdaDrugs = (try? await OpenFDAAPI.fetchCommonDrugs()) ?? []

            let tripSitSubstances = tripSitDrugs.values.map { TripSitAPI.toSubstance($0) }
            let fdaSubstances = fdaDrugs.compactMap { OpenFDAAPI.toSubstance($0) }

            // Merge: TripSit primary, FDA fills gaps
            var byName: [String: Substance] = [:]
            var allNames: Set<String> = []

            for s in tripSitSubstances {
                let key = s.name.lowercased()
                byName[key] = s
                allNames.insert(key)
                for a in s.aliases { allNames.insert(a.lowercased()) }
            }

            for s in fdaSubstances {
                let key = s.name.lowercased()
                if !allNames.contains(key) && !s.aliases.contains(where: { allNames.contains($0.lowercased()) }) {
                    byName[key] = s
                    allNames.insert(key)
                }
            }

            let merged = Array(byName.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            guard !merged.isEmpty else { return }

            // Save cache in background
            if let data = try? JSONEncoder().encode(merged) {
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = dir.appendingPathComponent("substances_cache.json")
                try? data.write(to: url)
            }

            await MainActor.run {
                updateAll(merged)
            }
        }
    }

    @MainActor private static func updateAll(_ substances: [Substance]) {
        all = substances
        byCategory = Dictionary(grouping: all, by: \.category)
        nonEmptyCategories = SubstanceCategory.allCases.filter { byCategory[$0] != nil }
        nameLookup = Dictionary(all.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var newFull: [String: Substance] = [:]
        for s in all {
            newFull[s.name.lowercased()] = s
            for a in s.aliases { if newFull[a.lowercased()] == nil { newFull[a.lowercased()] = s } }
        }
        fullLookup = newFull
        searchIndex = all.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }
    }

    // MARK: - Cache

    private static func loadCache() -> [Substance]? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("substances_cache.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Substance].self, from: data)
    }

    // MARK: - Lookup

    @MainActor static func substances(in category: SubstanceCategory) -> [Substance] {
        byCategory[category] ?? []
    }

    @MainActor static func lookup(_ name: String) -> Substance? {
        nameLookup[name.lowercased()]
    }

    @MainActor static func lookupByNameOrAlias(_ name: String) -> Substance? {
        fullLookup[name.lowercased()]
    }

    @MainActor static var count: Int { all.count }

    // MARK: - Search

    @MainActor static func search(_ query: String, limit: Int = 50) -> [Substance] {
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

        return Array((exact + aliasExact + prefix + contains).prefix(limit))
    }
}
