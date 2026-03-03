import Foundation
import Observation

@MainActor
@Observable
final class SubstanceLibrary {
    static let shared = SubstanceLibrary()

    private(set) var all: [Substance] = []
    private(set) var isLoading = true
    private(set) var error: String?

    // MARK: - Derived Data

    private(set) var byCategory: [SubstanceCategory: [Substance]] = [:]
    private(set) var nonEmptyCategories: [SubstanceCategory] = []
    private var nameLookup: [String: Substance] = [:]
    private var fullLookup: [String: Substance] = [:]
    private var searchIndex: [(substance: Substance, nameLower: String, aliasesLower: [String])] = []

    // MARK: - Cache

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("substances_cache.json")
    }()
    private let cacheMaxAge: TimeInterval = 7 * 24 * 3600 // 1 week

    private init() {}

    // MARK: - Loading

    /// Call on app launch. Loads from cache immediately, then refreshes from APIs.
    func load() async {
        isLoading = true
        error = nil

        // 1. Try cache first for instant display
        if let cached = loadCache(), !cached.isEmpty {
            updateAll(cached)
            isLoading = false

            // Refresh in background if cache is stale
            if !isCacheFresh() {
                Task { await refreshFromAPIs() }
            }
            return
        }

        // 2. No cache — fetch from APIs
        await refreshFromAPIs()
    }

    /// Force refresh from APIs
    func refreshFromAPIs() async {
        if all.isEmpty { isLoading = true }

        async let tripSitTask = fetchTripSit()
        async let fdaTask = fetchFDA()

        let tripSit = await tripSitTask
        let fda = await fdaTask

        let merged = mergeSubstances(tripSit: tripSit, fda: fda)

        if merged.isEmpty {
            error = "Could not load substances. Check your internet connection."
            isLoading = false
            return
        }

        updateAll(merged)
        saveCache(merged)
        isLoading = false
        error = nil
    }

    // MARK: - API Fetching

    private func fetchTripSit() async -> [Substance] {
        do {
            let drugs = try await TripSitAPI.fetchAll()
            return drugs.values.map { TripSitAPI.toSubstance($0) }
        } catch {
            return []
        }
    }

    private func fetchFDA() async -> [Substance] {
        do {
            let drugs = try await OpenFDAAPI.fetchCommonDrugs()
            return drugs.compactMap { OpenFDAAPI.toSubstance($0) }
        } catch {
            return []
        }
    }

    // MARK: - Merging

    private func mergeSubstances(tripSit: [Substance], fda: [Substance]) -> [Substance] {
        var byName: [String: Substance] = [:]
        var allNames: Set<String> = []

        // TripSit is primary for recreational substances
        for s in tripSit {
            let key = s.name.lowercased()
            byName[key] = s
            allNames.insert(key)
            for alias in s.aliases {
                allNames.insert(alias.lowercased())
            }
        }

        // FDA fills in prescription meds
        for s in fda {
            let key = s.name.lowercased()
            if byName[key] == nil {
                let aliasMatch = s.aliases.contains { allNames.contains($0.lowercased()) }
                if !aliasMatch {
                    byName[key] = s
                    allNames.insert(key)
                    for alias in s.aliases {
                        allNames.insert(alias.lowercased())
                    }
                }
            }
        }

        return Array(byName.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Update & Index

    private func updateAll(_ substances: [Substance]) {
        all = substances
        byCategory = Dictionary(grouping: substances, by: \.category)
        nonEmptyCategories = SubstanceCategory.allCases.filter { byCategory[$0] != nil }

        nameLookup = Dictionary(substances.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var newFull: [String: Substance] = [:]
        for s in substances {
            newFull[s.name.lowercased()] = s
            for alias in s.aliases {
                if newFull[alias.lowercased()] == nil {
                    newFull[alias.lowercased()] = s
                }
            }
        }
        fullLookup = newFull

        searchIndex = substances.map { ($0, $0.name.lowercased(), $0.aliases.map { $0.lowercased() }) }

        
    }

    // MARK: - Cache

    private func saveCache(_ substances: [Substance]) {
        do {
            let data = try JSONEncoder().encode(substances)
            try data.write(to: cacheURL)
        } catch {
            print("SubstanceLibrary: cache write failed: \(error)")
        }
    }

    private func loadCache() -> [Substance]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([Substance].self, from: data)
    }

    private func isCacheFresh() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < cacheMaxAge
    }

    // MARK: - Lookup

    func substances(in category: SubstanceCategory) -> [Substance] {
        byCategory[category] ?? []
    }

    func lookup(_ name: String) -> Substance? {
        nameLookup[name.lowercased()]
    }

    func lookupByNameOrAlias(_ name: String) -> Substance? {
        fullLookup[name.lowercased()]
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 50) -> [Substance] {
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

    var count: Int { all.count }
}
