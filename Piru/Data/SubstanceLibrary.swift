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

    // MARK: - Name Normalization (for dedup)

    /// Normalize a substance name for deduplication comparison
    private static func normalizeName(_ name: String) -> String {
        var n = name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "α", with: "alpha")
            .replacingOccurrences(of: "β", with: "beta")
            .replacingOccurrences(of: "γ", with: "gamma")
            .replacingOccurrences(of: "δ", with: "delta")
        return n
    }

    /// Pharmaceutical salt/form suffixes that don't change the active molecule
    private static let saltSuffixes: [String] = [
        "hydrochloride", "hcl", "sodium", "potassium", "calcium", "magnesium",
        "sulfate", "sulphate", "maleate", "tartrate", "fumarate", "hemifumarate",
        "mesylate", "besylate", "tosylate", "bromide", "chloride", "iodide",
        "acetate", "phosphate", "citrate", "succinate", "oxalate", "gluconate",
        "pamoate", "embonate", "valerate", "decanoate", "enanthate", "propionate",
        "monohydrate", "dihydrate", "trihydrate", "anhydrous",
    ]

    /// Strip trailing pharmaceutical salt suffixes from an already-normalized name.
    /// Used only for dedup key generation — the stored name is unchanged.
    private static func saltStripped(_ normalized: String) -> String {
        var result = normalized
        var changed = true
        while changed {
            changed = false
            for suffix in saltSuffixes where result.hasSuffix(suffix) && result.count > suffix.count {
                result = String(result.dropLast(suffix.count))
                changed = true
                break
            }
        }
        return result
    }

    /// Well-known name mappings for cross-source dedup
    private static let knownAliases: [String: String] = [
        "mdma": "34methylenedioxymethamphetamine",
        "34methylenedioxymethamphetamine": "mdma",
        "lsd": "lysergicaciddiethylamide",
        "lysergicaciddiethylamide": "lsd",
        "thc": "delta9tetrahydrocannabinol",
        "delta9tetrahydrocannabinol": "thc",
        "ghb": "gammahydroxybutyricacid",
        "gammahydroxybutyricacid": "ghb",
        "gbl": "gammabutyrolactone",
        "gammabutyrolactone": "gbl",
        "pcp": "phencyclidine",
        "phencyclidine": "pcp",
        "dmt": "nn dimethyltryptamine",
        "dxm": "dextromethorphan",
        "dextromethorphan": "dxm",
        "mda": "34methylenedioxyamphetamine",
        "34methylenedioxyamphetamine": "mda",
        "2cb": "4bromo25dimethoxyphenethylamine",
        "nac": "nacetylcysteine",
        "nacetylcysteine": "nac",
        // UK name (TripSit) ↔ US FDA name (OpenFDA) cross-source pairs
        "paracetamol": "acetaminophen",
        "acetaminophen": "paracetamol",
        "adrenaline": "epinephrine",
        "epinephrine": "adrenaline",
        "noradrenaline": "norepinephrine",
        "norepinephrine": "noradrenaline",
    ]

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
                let merged = deduplicatedMerge(existing: all, incoming: clinicalDrugs)
                updateAll(merged)
            }
            print("[SubstanceLibrary] Stage 2: \(all.count) substances (TripSit + DailyMed)")

            // Stage 3: Enrich half-life data from HalfLifeDatabase + duration heuristic
            LibraryLoadingState.shared.statusText = "Enriching half-life data..."
            let enriched = enrichHalfLifeData(all)
            updateAll(enriched)
            let hlCount = enriched.filter { $0.halfLifeMinutes != nil }.count
            print("[SubstanceLibrary] Stage 3: \(hlCount)/\(enriched.count) substances have half-life data")

            // Stage 4: Fetch drug interaction data from FDA label drug_interactions sections
            LibraryLoadingState.shared.statusText = "Fetching interaction data..."
            let fdaInteractionData = await DailyMedAPI.fetchInteractions(for: all)
            if !fdaInteractionData.isEmpty {
                InteractionChecker.setFDAInteractions(fdaInteractionData)
                print("[SubstanceLibrary] Stage 4: \(fdaInteractionData.count) FDA-sourced interactions loaded")
            }

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
        let pwNames = all
            .filter { psychoactiveCategories.contains($0.category) }
            .map(\.name)
        guard !pwNames.isEmpty else { return }

        print("[SubstanceLibrary] Background PW enrichment: querying \(pwNames.count) substances...")
        let pwSubstances = await PsychonautWikiAPI.fetchSubstances(names: pwNames)
        guard !pwSubstances.isEmpty else {
            print("[SubstanceLibrary] Background PW enrichment: no results")
            return
        }

        let merged = deduplicatedMerge(existing: all, incoming: pwSubstances)
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

    // MARK: - Deduplication

    /// Build a set of all normalized names + aliases for an array of substances
    private static func buildNameIndex(_ substances: [Substance]) -> Set<String> {
        var index: Set<String> = []
        for s in substances {
            index.insert(s.name.lowercased())
            index.insert(normalizeName(s.name))
            for a in s.aliases {
                index.insert(a.lowercased())
                index.insert(normalizeName(a))
            }
            // Add known alias mappings
            let norm = normalizeName(s.name)
            if let mapped = knownAliases[norm] {
                index.insert(mapped)
            }
        }
        return index
    }

    /// Merge incoming substances into existing, deduplicating by normalized name + aliases
    private static func deduplicatedMerge(existing: [Substance], incoming: [Substance]) -> [Substance] {
        var byNormalized: [String: Int] = [:] // normalized name -> index in result
        var result = existing
        var dupeCount = 0
        var newCount = 0

        // Index existing
        for (i, s) in result.enumerated() {
            byNormalized[s.name.lowercased()] = i
            let norm = normalizeName(s.name)
            byNormalized[norm] = i
            byNormalized[saltStripped(norm)] = i
            for a in s.aliases {
                let aNorm = normalizeName(a)
                byNormalized[a.lowercased()] = i
                byNormalized[aNorm] = i
                byNormalized[saltStripped(aNorm)] = i
            }
            if let mapped = knownAliases[norm] { byNormalized[mapped] = i }
        }

        for s in incoming {
            let nameNorm = normalizeName(s.name)
            let nameLower = s.name.lowercased()

            // Check if any name/alias matches existing (including salt-stripped forms)
            var matchIdx: Int? = byNormalized[nameLower]
                ?? byNormalized[nameNorm]
                ?? byNormalized[saltStripped(nameNorm)]

            if matchIdx == nil {
                if let mapped = knownAliases[nameNorm] { matchIdx = byNormalized[mapped] }
            }

            if matchIdx == nil {
                for a in s.aliases {
                    let aNorm = normalizeName(a)
                    if let idx = byNormalized[a.lowercased()] ?? byNormalized[aNorm] ?? byNormalized[saltStripped(aNorm)] {
                        matchIdx = idx
                        break
                    }
                }
            }

            if let idx = matchIdx {
                // Merge: prefer the one with more data, combine sources
                dupeCount += 1
                let existing = result[idx]
                let merged = mergeSubstances(existing, s)
                result[idx] = merged

                // Update index for new aliases
                for a in merged.aliases {
                    byNormalized[a.lowercased()] = idx
                    byNormalized[normalizeName(a)] = idx
                }
            } else {
                // New substance
                newCount += 1
                let newIdx = result.count
                result.append(s)
                byNormalized[nameLower] = newIdx
                byNormalized[nameNorm] = newIdx
                byNormalized[saltStripped(nameNorm)] = newIdx
                for a in s.aliases {
                    let aNorm = normalizeName(a)
                    byNormalized[a.lowercased()] = newIdx
                    byNormalized[aNorm] = newIdx
                    byNormalized[saltStripped(aNorm)] = newIdx
                }
            }
        }

        print("[SubstanceLibrary] Dedup: \(incoming.count) incoming → \(dupeCount) matched existing, \(newCount) added as new")
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Merge two substances: prefer the one with more complete data, combine sources + aliases
    private static func mergeSubstances(_ a: Substance, _ b: Substance) -> Substance {
        // Determine which has better data
        let aScore = dataScore(a)
        let bScore = dataScore(b)
        let primary = aScore >= bScore ? a : b
        let secondary = aScore >= bScore ? b : a

        // Prefer the shorter, non-salt name when both normalize to the same base
        let finalName: String
        if primary.name.count > secondary.name.count,
           saltStripped(normalizeName(primary.name)) == saltStripped(normalizeName(secondary.name)) {
            finalName = secondary.name
        } else {
            finalName = primary.name
        }

        // Merge aliases (unique)
        let allAliases = Set(primary.aliases + secondary.aliases + [secondary.name, primary.name])
            .filter { $0.lowercased() != finalName.lowercased() }
        let mergedAliases = Array(allAliases).sorted()

        // Merge sources
        let mergedSources = Array(Set(primary.sources + secondary.sources)).sorted()

        // Use primary's routes but add any missing routes from secondary
        var routes = primary.routes
        let primaryRoutes = Set(primary.routes.map { $0.route })
        for r in secondary.routes where !primaryRoutes.contains(r.route) {
            routes.append(r)
        }

        // Merge effects
        let primaryEffects = Set(primary.effects.map { $0.lowercased() })
        let newEffects = secondary.effects.filter { !primaryEffects.contains($0.lowercased()) }

        return Substance(
            name: finalName,
            aliases: mergedAliases,
            category: primary.category,
            defaultRoute: primary.defaultRoute,
            routes: routes,
            effects: primary.effects + newEffects,
            subjectiveEffects: primary.subjectiveEffects.isEmpty ? secondary.subjectiveEffects : primary.subjectiveEffects,
            toleranceInfo: primary.toleranceInfo ?? secondary.toleranceInfo,
            halfLifeMinutes: primary.halfLifeMinutes ?? secondary.halfLifeMinutes,
            sources: mergedSources
        )
    }

    /// Score how complete a substance's data is (higher = more data)
    private static func dataScore(_ s: Substance) -> Int {
        var score = 0
        if s.halfLifeMinutes != nil { score += 3 }
        if s.toleranceInfo != nil { score += 2 }
        for r in s.routes {
            if r.doses.threshold != nil || r.doses.light != nil || r.doses.common != nil { score += 3 }
            if r.duration != nil { score += 2 }
        }
        score += s.effects.count > 0 ? 2 : 0
        if !s.subjectiveEffects.isEmpty { score += 2 }
        score += s.aliases.count
        return score
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
