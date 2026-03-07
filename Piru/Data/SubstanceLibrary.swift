import Foundation
import Observation

@Observable @MainActor
final class LibraryLoadingState {
    static let shared = LibraryLoadingState()
    var substanceCount = 0
    var isLoading = true
    var statusText = "Starting..."
    private init() {}
}

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

    @MainActor private(set) static var isLoading = true

    // MARK: - API Fetch

    /// Maximum age for the substance cache before re-fetching (7 days)
    private static let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60

    private static func cacheIsFresh() -> Bool {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("substances_cache.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false
        }
        let age = Date().timeIntervalSince(modDate)
        print("[SubstanceLibrary] Cache age: \(Int(age / 3600))h \(Int(age.truncatingRemainder(dividingBy: 3600) / 60))m")
        return age < cacheMaxAge
    }

    @MainActor static func fetchFromAPIs(forceRefresh: Bool = false) {
        print("[SubstanceLibrary] fetchFromAPIs called (force: \(forceRefresh)), starting Task...")
        Task {
            print("[SubstanceLibrary] Task started")
            LibraryLoadingState.shared.substanceCount = all.count

            // Skip API fetch if cache is fresh and non-empty (unless forced)
            if !forceRefresh && !all.isEmpty && cacheIsFresh() {
                print("[SubstanceLibrary] Cache is fresh, skipping API fetch (\(all.count) substances)")
                isLoading = false
                InteractionChecker.rebuildCache()
                LibraryLoadingState.shared.isLoading = false
                LibraryLoadingState.shared.statusText = "Done"
                return
            }

            if forceRefresh {
                clearCache()
                print("[SubstanceLibrary] Cache cleared for force refresh")
            }

            LibraryLoadingState.shared.isLoading = true
            LibraryLoadingState.shared.statusText = "Fetching TripSit data..."

            let tripSitDrugs: [String: TripSitAPI.TripSitDrug]
            do {
                tripSitDrugs = try await TripSitAPI.fetchAll()
                print("[SubstanceLibrary] TripSit: \(tripSitDrugs.count) drugs fetched")
            } catch {
                print("[SubstanceLibrary] TripSit fetch failed: \(error)")
                tripSitDrugs = [:]
            }

            // Stage 1: Show TripSit data immediately
            let tripSitSubstances = tripSitDrugs.values.map { TripSitAPI.toSubstance($0) }
            if !tripSitSubstances.isEmpty {
                let sorted = tripSitSubstances.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                updateAll(sorted)
                print("[SubstanceLibrary] Stage 1: \(all.count) substances (TripSit)")
            }

            // Stage 2: Fetch DailyMed clinical drugs by direct name lookup.
            LibraryLoadingState.shared.statusText = "Fetching clinical drug data..."
            let clinicalDrugs = await DailyMedAPI.fetchClinicalDrugs()
            if !clinicalDrugs.isEmpty {
                let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: clinicalDrugs)
                updateAll(merged)
            }
            print("[SubstanceLibrary] Stage 2: \(all.count) substances (TripSit + DailyMed)")

            // Stage 3: Enrich half-life data from HalfLifeDatabase + duration heuristic
            LibraryLoadingState.shared.statusText = "Enriching half-life data..."
            let enriched = enrichHalfLifeData(all)
            updateAll(enriched)
            let hlCount = enriched.filter { $0.halfLifeMinutes != nil }.count
            print("[SubstanceLibrary] Stage 3: \(hlCount)/\(enriched.count) substances have half-life data")



            saveCache(all)
            isLoading = false
            InteractionChecker.rebuildCache()
            LibraryLoadingState.shared.isLoading = false
            LibraryLoadingState.shared.statusText = "Done"
            print("[SubstanceLibrary] Done! \(all.count) total substances")

            // Background enrichment: PsychonautWiki fetches per-route dose ranges,
            // full duration profiles, subjective effects, and tolerance info.
            // Runs without blocking the UI — results merge in and re-save the cache.
            await enrichFromPsychonautWiki()
        }
    }

    // MARK: - PsychonautWiki Background Enrichment

    /// Fetch PsychonautWiki data for psychoactive substances in the background.
    /// Merges results into the library and re-saves the cache without blocking the UI.
    @MainActor private static func enrichFromPsychonautWiki() async {
        let psychoactiveCategories: Set<SubstanceCategory> = [
            .psychedelic, .dissociative, .empathogen, .cannabinoid,
            .stimulant, .opioid, .benzodiazepine, .depressant,
            .gabapentinoid, .nootropic, .other,
        ]
        var pwNames = all
            .filter { psychoactiveCategories.contains($0.category) }
            .map(\.name)

        // Extra nootropics/research chems not in TripSit or DailyMed
        let extraNames = [
            // Racetams
            "IDRA-21", "Sunifiram", "Unifiram", "Oxiracetam", "Nebracetam",
            "Phenylpiracetam hydrazide",
            // Peptides
            "NSI-189", "Dihexa", "Semax", "Selank", "Cerebrolysin", "P21", "BPC-157",
            // Cholinergics & precursors
            "Alpha-GPC", "CDP-Choline", "Uridine", "Phosphatidylserine",
            // Herbals & naturals
            "Lion\'s Mane", "Bacopa monnieri", "Ginkgo biloba", "Rhodiola rosea",
            "Polygala tenuifolia", "Magnolia bark", "Sabroxy",
            // Stimulant-adjacent
            "Sulbutiamine", "Vinpocetine", "Centrophenoxine", "Emoxypine", "Cortexin",
            "RGPU-95", "Dynamine", "Methylliberine",
            // Afinils
            "Adrafinil", "Flmodafinil", "Hydrafinil",
            // Others
            "SAM-e", "Agmatine", "NALT", "Tyrosine", "DMAE",
            "9-Me-BC", "Tianeptine", "Memantine", "Tasimelteon",
        ]
        let existingLower = Set(pwNames.map { $0.lowercased() })
        for name in extraNames where !existingLower.contains(name.lowercased()) {
            pwNames.append(name)
        }

        guard !pwNames.isEmpty else { return }

        print("[SubstanceLibrary] Background PW enrichment: querying \(pwNames.count) substances...")
        let pwSubstances = await PsychonautWikiAPI.fetchSubstances(names: pwNames)
        guard !pwSubstances.isEmpty else {
            print("[SubstanceLibrary] Background PW enrichment: no results")
            return
        }

        let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: pwSubstances)
        updateAll(merged)
        saveCache(all)
        print("[SubstanceLibrary] Background PW enrichment: merged \(pwSubstances.count) substances, \(all.count) total")
    }

    // MARK: - Half-Life Enrichment

    /// Fill in missing halfLifeMinutes from HalfLifeDatabase, then fall back to duration heuristic.
    private static func enrichHalfLifeData(_ substances: [Substance]) -> [Substance] {
        substances.map { s in
            guard s.halfLifeMinutes == nil else { return s }

            // Try HalfLifeDatabase by name, then aliases
            var hl = HalfLifeDatabase.halfLife(for: s.name)
            if hl == nil {
                for alias in s.aliases {
                    if let found = HalfLifeDatabase.halfLife(for: alias) {
                        hl = found
                        break
                    }
                }
            }

            // Fall back: estimate from total duration (totalDuration / 4)
            if hl == nil {
                let totalMid = s.routes.lazy.compactMap { $0.duration?.total?.midpoint }.first
                if let total = totalMid, total > 0 {
                    hl = total / 4
                }
            }

            guard let halfLife = hl else { return s }

            return Substance(
                name: s.name,
                aliases: s.aliases,
                category: s.category,
                defaultRoute: s.defaultRoute,
                routes: s.routes,
                effects: s.effects,
                subjectiveEffects: s.subjectiveEffects,
                toleranceInfo: s.toleranceInfo,
                halfLifeMinutes: halfLife,
                sources: s.sources
            )
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
        LibraryLoadingState.shared.substanceCount = all.count
    }

    // MARK: - Cache

    @MainActor private static func saveCache(_ substances: [Substance]) {
        guard let data = try? JSONEncoder().encode(substances) else {
            print("[SubstanceLibrary] Failed to encode cache")
            return
        }
        Task.detached(priority: .utility) {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("substances_cache.json")
            try? data.write(to: url)
            print("[SubstanceLibrary] Cache saved (\(data.count) bytes)")
        }
    }

    private static func loadCache() -> [Substance]? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("substances_cache.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Substance].self, from: data)
    }

    private static func clearCache() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("substances_cache.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("interactions_cache.json"))
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
