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

            // Load TripSit combo data into the interaction checker
            if !tripSitDrugs.isEmpty {
                InteractionChecker.loadTripSitCombos(from: tripSitDrugs)
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

            // Stage 4: Enrich mechanism of action data from MechanismOfActionDatabase
            LibraryLoadingState.shared.statusText = "Adding mechanism data..."
            let withMOA = enrichMechanismOfAction(enriched)
            updateAll(withMOA)
            let moaCount = withMOA.filter { $0.mechanismOfAction != nil }.count
            print("[SubstanceLibrary] Stage 4: \(moaCount)/\(withMOA.count) substances have mechanism of action data")

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
                sources: s.sources,
                mechanismOfAction: s.mechanismOfAction
            )
        }
    }

    // MARK: - Mechanism of Action Enrichment

    /// Fill in missing mechanismOfAction from MechanismOfActionDatabase (specific matches only).
    /// Category-level fallbacks are resolved at display time in SubstanceDetailView.
    private static func enrichMechanismOfAction(_ substances: [Substance]) -> [Substance] {
        substances.map { s in
            guard s.mechanismOfAction == nil else { return s }

            // Try specific substance lookup by name, then aliases
            var moa = MechanismOfActionDatabase.mechanism(for: s.name)
            if moa == nil {
                for alias in s.aliases {
                    if let found = MechanismOfActionDatabase.mechanism(for: alias) {
                        moa = found
                        break
                    }
                }
            }

            guard let mechanism = moa else { return s }

            return Substance(
                name: s.name,
                aliases: s.aliases,
                category: s.category,
                defaultRoute: s.defaultRoute,
                routes: s.routes,
                effects: s.effects,
                subjectiveEffects: s.subjectiveEffects,
                toleranceInfo: s.toleranceInfo,
                halfLifeMinutes: s.halfLifeMinutes,
                sources: s.sources,
                mechanismOfAction: mechanism
            )
        }
    }

    // MARK: - Dose Overrides

    /// A substance-specific replacement for a single route's dose data. Applied
    /// after every merge to ensure source fixes can't be clobbered by later
    /// enrichment (e.g. PsychonautWiki) that would otherwise win on data completeness.
    private struct DoseOverride {
        let route: RouteOfAdministration
        let unit: String
        let doses: DoseRange
    }

    /// Per-substance dose overrides keyed by lowercased name. Each route listed
    /// here is replaced wholesale; any duration data TripSit/PW provided for the
    /// same route is preserved.
    private static let doseOverrides: [String: [DoseOverride]] = [
        // TripSit's smoked cannabis doses (Light 10-20mg, Common 20-60mg,
        // Strong 60-100mg+) don't match either mg-of-THC or a plausible
        // flower-weight interpretation. Replace with PsychonautWiki's
        // canonical inhaled THC reference.
        "cannabis": [
            DoseOverride(
                route: .inhalation,
                unit: "mg",
                doses: DoseRange(
                    threshold: 0.4,
                    light: 0.4...2,
                    common: 2...4,
                    strong: 4...10,
                    heavy: 10
                )
            ),
            // Oral (edibles) — TripSit provides oral duration but no oral doses.
            // Numbers align with PsychonautWiki's oral THC reference and
            // standard dispensary single-serving sizing (≈10 mg = one edible).
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 2.5,
                    light: 2.5...5,
                    common: 5...15,
                    strong: 15...30,
                    heavy: 30
                )
            ),
            // Sublingual (tinctures/oromucosal sprays) — faster onset and
            // partial first-pass bypass put potencies between inhaled and oral.
            DoseOverride(
                route: .sublingual,
                unit: "mg",
                doses: DoseRange(
                    threshold: 1,
                    light: 1...2.5,
                    common: 2.5...10,
                    strong: 10...20,
                    heavy: 20
                )
            )
        ],
        // TripSit serves DXM in mg/kg (now filtered upstream); DailyMed's syrup
        // labels make unit detection land on "mL". Pin to PsychonautWiki's
        // canonical oral DXM HBr reference so the display is always mg.
        "dextromethorphan": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 75,
                    light: 100...200,
                    common: 200...400,
                    strong: 400...700,
                    heavy: 700
                )
            )
        ]
    ]

    private static func applyDoseOverrides(_ substances: [Substance]) -> [Substance] {
        substances.map { s in
            guard let overrides = doseOverrides[s.name.lowercased()] else { return s }

            var routes = s.routes
            for override in overrides {
                let replacement = SubstanceRoute(
                    route: override.route,
                    unit: override.unit,
                    doses: override.doses,
                    duration: routes.first { $0.route == override.route }?.duration
                )
                if let idx = routes.firstIndex(where: { $0.route == override.route }) {
                    routes[idx] = replacement
                } else {
                    routes.append(replacement)
                }
            }

            return Substance(
                name: s.name,
                aliases: s.aliases,
                category: s.category,
                defaultRoute: s.defaultRoute,
                routes: routes,
                effects: s.effects,
                subjectiveEffects: s.subjectiveEffects,
                toleranceInfo: s.toleranceInfo,
                halfLifeMinutes: s.halfLifeMinutes,
                sources: s.sources,
                mechanismOfAction: s.mechanismOfAction
            )
        }
    }

    @MainActor private static func updateAll(_ substances: [Substance]) {
        all = applyDoseOverrides(substances)
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
        guard let decoded = try? JSONDecoder().decode([Substance].self, from: data) else { return nil }
        return applyDoseOverrides(decoded)
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
        var seen = Set<UUID>()

        for item in searchIndex {
            if item.nameLower == q {
                exact.append(item.substance)
                seen.insert(item.substance.id)
            } else if item.aliasesLower.contains(q) {
                aliasExact.append(item.substance)
                seen.insert(item.substance.id)
            } else if item.nameLower.hasPrefix(q) || item.aliasesLower.contains(where: { $0.hasPrefix(q) }) {
                prefix.append(item.substance)
                seen.insert(item.substance.id)
            } else if item.nameLower.contains(q) || item.aliasesLower.contains(where: { $0.contains(q) }) {
                contains.append(item.substance)
                seen.insert(item.substance.id)
            }
        }

        var results = exact + aliasExact + prefix + contains
        if results.count < limit && q.count >= 4 {
            results += fuzzyMatch(q, excluding: seen, limit: limit - results.count)
        }
        return Array(results.prefix(limit))
    }

    // MARK: - Fuzzy Search

    @MainActor private static func fuzzyMatch(_ query: String, excluding seen: Set<UUID>, limit: Int) -> [Substance] {
        let maxDistance = max(1, Int(Double(query.count) * 0.3))
        var matches: [(substance: Substance, distance: Int)] = []

        for item in searchIndex {
            guard !seen.contains(item.substance.id) else { continue }
            var bestDist = Int.max
            bestDist = min(bestDist, levenshtein(query, item.nameLower))
            if bestDist > maxDistance {
                for alias in item.aliasesLower {
                    bestDist = min(bestDist, levenshtein(query, alias))
                    if bestDist <= maxDistance { break }
                }
            }
            if bestDist <= maxDistance {
                matches.append((item.substance, bestDist))
            }
        }

        return matches.sorted { $0.distance < $1.distance }.prefix(limit).map(\.substance)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

}
