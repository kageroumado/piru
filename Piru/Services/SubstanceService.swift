import Foundation

/// Manages substance data from multiple API sources with local caching
actor SubstanceService {
    static let shared = SubstanceService()

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubstanceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let tripSitCacheFile = "tripsit_substances.json"
    private let fdaCacheFile = "fda_substances.json"
    private let mergedCacheFile = "all_substances.json"
    private let cacheMaxAge: TimeInterval = 7 * 24 * 3600 // 1 week

    /// Load all substances — from cache if fresh, otherwise from APIs with bundled fallback
    func loadAll() async -> [Substance] {
        // Try merged cache first
        if let cached = loadFromCache(mergedCacheFile), isCacheFresh(mergedCacheFile) {
            return cached
        }

        // Try fetching from APIs
        async let tripSitTask = fetchTripSit()
        async let fdaTask = fetchFDA()

        let tripSitSubstances = await tripSitTask
        let fdaSubstances = await fdaTask

        // Merge API results with bundled data
        let bundled = await MainActor.run { SubstanceLibrary.all }
        let merged = mergeSubstances(bundled: bundled, tripSit: tripSitSubstances, fda: fdaSubstances)

        // Cache the merged result
        saveToCache(merged, filename: mergedCacheFile)

        return merged
    }

    /// Force refresh from APIs
    func refresh() async -> [Substance] {
        clearCache(mergedCacheFile)
        return await loadAll()
    }

    // MARK: - API Fetching

    private func fetchTripSit() async -> [Substance] {
        do {
            let drugs = try await TripSitAPI.fetchAll()
            let substances = await MainActor.run { drugs.values.map { TripSitAPI.toSubstance($0) } }
            saveToCache(substances, filename: tripSitCacheFile)
            return substances
        } catch {
            // Fall back to cache
            return loadFromCache(tripSitCacheFile) ?? []
        }
    }

    private func fetchFDA() async -> [Substance] {
        do {
            let drugs = try await OpenFDAAPI.fetchCommonDrugs()
            let substances = await MainActor.run { drugs.compactMap { OpenFDAAPI.toSubstance($0) } }
            saveToCache(substances, filename: fdaCacheFile)
            return substances
        } catch {
            return loadFromCache(fdaCacheFile) ?? []
        }
    }

    // MARK: - Merging

    /// Merge substances from all sources, deduplicating by name
    private func mergeSubstances(bundled: [Substance], tripSit: [Substance], fda: [Substance]) -> [Substance] {
        var byName: [String: Substance] = [:]

        // Bundled data has highest priority (our curated data)
        for s in bundled {
            byName[s.name.lowercased()] = s
        }

        // TripSit fills in gaps
        for s in tripSit {
            let key = s.name.lowercased()
            if byName[key] == nil {
                // Check aliases too
                let existingNames = Set(byName.keys)
                let aliasMatch = s.aliases.contains { existingNames.contains($0.lowercased()) }
                if !aliasMatch {
                    byName[key] = s
                }
            }
        }

        // FDA fills in prescription meds we don't have
        for s in fda {
            let key = s.name.lowercased()
            if byName[key] == nil {
                let existingNames = Set(byName.keys)
                let aliasMatch = s.aliases.contains { existingNames.contains($0.lowercased()) }
                if !aliasMatch {
                    byName[key] = s
                }
            }
        }

        return Array(byName.values).sorted { $0.name < $1.name }
    }

    // MARK: - Caching

    private func saveToCache(_ substances: [Substance], filename: String) {
        let url = cacheURL.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(substances)
            try data.write(to: url)
        } catch {
            print("SubstanceService: Failed to cache \(filename): \(error)")
        }
    }

    private func loadFromCache(_ filename: String) -> [Substance]? {
        let url = cacheURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Substance].self, from: data)
    }

    private func isCacheFresh(_ filename: String) -> Bool {
        let url = cacheURL.appendingPathComponent(filename)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < cacheMaxAge
    }

    private func clearCache(_ filename: String) {
        let url = cacheURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
