import Foundation
import Observation
import os

nonisolated private let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceLibrary")

@Observable @MainActor
final class LibraryLoadingState {
    static let shared = LibraryLoadingState()
    var substanceCount = 0
    var isLoading = true
    var statusText: String = String(localized: "Starting...")
    private init() {}
}

/// The merged, cached, in-memory substance catalogue that powers search,
/// detail views, and interaction checking.
///
/// ## Load pipeline
///
/// Data is composed in stages so the UI can render TripSit-only results
/// immediately while richer sources stream in:
///
/// 1. **TripSit** — primary source. Each drug becomes a `Substance` via
///    `TripSitAPI.toSubstance`; the list is published and the UI unblocks.
/// 2. **DailyMed** — clinical drugs fetched by name and deduplicated into the
///    TripSit set via ``SubstanceDeduplicator``.
/// 3. **`HalfLifeDatabase`** — fills in `halfLifeMinutes` for every substance
///    missing it (by name or alias, then a duration heuristic as last resort).
/// 4. **`MechanismOfActionDatabase`** — fills in mechanism strings where
///    available.
/// 5. **PsychonautWiki** — runs *after* the cache is saved on a detached
///    background path. Adds per-route dose ranges, full duration profiles,
///    subjective effects, and tolerance info without blocking the UI.
///
/// ## Caching
///
/// The merged set is persisted to `substances_cache.json` in the documents
/// directory with a 7-day TTL (see ``cacheMaxAge``). On launch the cache is
/// rehydrated synchronously (so views have data on first frame) and only
/// re-fetched if stale or `forceRefresh: true`.
///
/// ## Concurrency
///
/// The entire library is `@MainActor`-isolated. Reads (`all`, ``lookup(_:)``,
/// ``lookupByNameOrAlias(_:)``, ``search(_:limit:)``) are safe from any
/// MainActor context. Writes happen only inside ``fetchFromAPIs(forceRefresh:)``
/// via the private ``updateAll(_:)`` choke point — this is the one-way
/// mutation invariant the rest of the app relies on.
enum SubstanceLibrary {
    // MARK: - Data

    @MainActor private(set) static var all: [Substance] = loadCache() ?? loadInitialBundledSubstances()

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
        logger.debug("Cache age: \(Int(age / 3600))h \(Int(age.truncatingRemainder(dividingBy: 3600) / 60))m")
        return age < cacheMaxAge
    }

    @MainActor static func fetchFromAPIs(forceRefresh: Bool = false) {
        logger.info("fetchFromAPIs called (force: \(forceRefresh)), starting Task...")
        Task {
            logger.debug("Task started")
            LibraryLoadingState.shared.substanceCount = all.count

            // Skip API fetch if cache is fresh and non-empty (unless forced)
            if !forceRefresh && !all.isEmpty && cacheIsFresh() {
                logger.info("Cache is fresh, skipping API fetch (\(all.count) substances)")
                isLoading = false
                InteractionChecker.rebuildCache()
                LibraryLoadingState.shared.isLoading = false
                LibraryLoadingState.shared.statusText = String(localized: "Done")
                return
            }

            if forceRefresh {
                clearCache()
                logger.info("Cache cleared for force refresh")
            }

            LibraryLoadingState.shared.isLoading = true
            LibraryLoadingState.shared.statusText = String(localized: "Fetching TripSit data...")

            let tripSitDrugs: [String: TripSitAPI.TripSitDrug]
            do {
                tripSitDrugs = try await TripSitAPI.fetchAll()
                logger.info("TripSit: \(tripSitDrugs.count) drugs fetched")
            } catch {
                logger.error("TripSit fetch failed: \(error.localizedDescription, privacy: .public)")
                tripSitDrugs = [:]
            }

            // Stage 1: Show TripSit data immediately
            let tripSitSubstances = tripSitDrugs.values.map { TripSitAPI.toSubstance($0) }
            if !tripSitSubstances.isEmpty {
                let sorted = tripSitSubstances.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                updateAll(sorted)
                logger.info("Stage 1: \(all.count) substances (TripSit)")
            }

            // Load TripSit combo data into the interaction checker
            if !tripSitDrugs.isEmpty {
                InteractionChecker.loadTripSitCombos(from: tripSitDrugs)
            }

            // Stage 1.5: Merge the bundled research-chemical dataset. Covers
            // NPS, PIHKAL/TIHKAL compounds, novel arylcyclohexylamines, AMPAkines,
            // afinils, dysdelics, and the long tail of obscure compounds that
            // TripSit/PW/DailyMed don't reach. Bundled fills gaps; TripSit wins
            // conflicts because it represents widely-used harm-reduction data.
            if let bundled = loadBundledSubstances(), !bundled.isEmpty {
                LibraryLoadingState.shared.statusText = String(localized: "Loading research-chemical dataset...")
                let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: bundled)
                updateAll(merged)
                logger.info("Stage 1.5: \(all.count) substances (TripSit + bundled)")
            }

            // Stage 1.6: Merge the bundled drug.community dataset (~420 records).
            // Adds DMXE, novel arylcyclohexylamines, fluorinated amphetamines,
            // and other long-tail RCs that drug.community curated. Shipped
            // offline so first-launch users get the data without network access.
            enrichFromDrugCommunity()

            // Stage 2: Fetch DailyMed clinical drugs by direct name lookup.
            LibraryLoadingState.shared.statusText = String(localized: "Fetching clinical drug data...")
            let clinicalDrugs = await DailyMedAPI.fetchClinicalDrugs()
            if !clinicalDrugs.isEmpty {
                let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: clinicalDrugs)
                updateAll(merged)
            }
            logger.info("Stage 2: \(all.count) substances (TripSit + DailyMed)")

            // Stage 3: Enrich half-life data from HalfLifeDatabase + duration heuristic
            LibraryLoadingState.shared.statusText = String(localized: "Enriching half-life data...")
            let enriched = enrichHalfLifeData(all)
            updateAll(enriched)
            let hlCount = enriched.filter { $0.halfLifeMinutes != nil }.count
            logger.info("Stage 3: \(hlCount)/\(enriched.count) substances have half-life data")

            // Stage 4: Enrich mechanism of action data from MechanismOfActionDatabase
            LibraryLoadingState.shared.statusText = String(localized: "Adding mechanism data...")
            let withMOA = enrichMechanismOfAction(enriched)
            updateAll(withMOA)
            let moaCount = withMOA.filter { $0.mechanismOfAction != nil }.count
            logger.info("Stage 4: \(moaCount)/\(withMOA.count) substances have mechanism of action data")

            saveCache(all)
            isLoading = false
            InteractionChecker.rebuildCache()
            LibraryLoadingState.shared.isLoading = false
            LibraryLoadingState.shared.statusText = "Done"
            logger.info("Done! \(all.count) total substances")

            // Background enrichment: PsychonautWiki fetches per-route dose ranges,
            // full duration profiles, subjective effects, and tolerance info.
            // Runs without blocking the UI — results merge in and re-save the cache.
            await enrichFromPsychonautWiki()
        }
    }

    // MARK: - drug.community Bundled Enrichment

    /// Load the full drug.community dataset from the bundled JSON snapshot
    /// and merge into the library. Replaces what used to be per-substance
    /// HTTP fetches against `drug.community/api/info` — the dataset is now
    /// shipped offline so first-launch users get the long tail without
    /// network access, and the API endpoint can come and go without
    /// affecting the app.
    @MainActor private static func enrichFromDrugCommunity() {
        let substances = DrugCommunityAPI.loadSubstancesFromBundle()
        guard !substances.isEmpty else {
            logger.warning("Bundled drug.community dataset is empty or missing")
            return
        }

        LibraryLoadingState.shared.statusText = String(localized: "Adding research chemicals...")
        let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: substances)
        updateAll(merged)
        logger.info("drug.community bundled merge: \(substances.count) records → \(all.count) total")
    }

    // MARK: - PsychonautWiki Background Enrichment

    /// Fetch PsychonautWiki data for psychoactive substances in the background.
    /// Merges results into the library and re-saves the cache without blocking the UI.
    @MainActor private static func enrichFromPsychonautWiki() async {
        let psychoactiveCategories: Set<SubstanceCategory> = [
            .psychedelic, .dissociative, .dysdelic, .empathogen, .cannabinoid,
            .stimulant, .eugeroic, .opioid, .benzodiazepine, .depressant,
            .gabapentinoid, .nootropic, .ampakine, .other,
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

        logger.info("Background PW enrichment: querying \(pwNames.count) substances...")
        let pwSubstances = await PsychonautWikiAPI.fetchSubstances(names: pwNames)
        guard !pwSubstances.isEmpty else {
            logger.warning("Background PW enrichment: no results")
            return
        }

        let merged = SubstanceDeduplicator.deduplicatedMerge(existing: all, incoming: pwSubstances)
        updateAll(merged)
        saveCache(all)
        logger.info("Background PW enrichment: merged \(pwSubstances.count) substances, \(all.count) total")
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
    ///
    /// These exist because some upstream sources ship dose data in units that
    /// are ambiguous, label-specific, or actively dangerous if displayed
    /// verbatim — e.g. TripSit's `units` field for alcohol (UK ~8 g vs US ~14 g
    /// ethanol per "unit"), or DailyMed DXM syrup labels where mass detection
    /// lands on "mL". Overrides are applied after every merge, including PW
    /// enrichment, so a more "complete" downstream source can't silently
    /// re-introduce the bad units. Duration data from upstream is preserved.
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
        // TripSit ships DXM doses in mg/kg for some sources, and DailyMed's
        // syrup labels make unit detection land on "mL" — both interpretations
        // are unsafe to surface as a harm-reduction reference. Pin to
        // PsychonautWiki's canonical oral DXM HBr mg reference instead.
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
        ],
        // TripSit reports alcohol in ambiguous "units" (1-6 units) — UK/US
        // standard-drink definitions vary (8 g vs 14 g of ethanol), which makes
        // the raw numbers dangerous as a harm-reduction reference. Pin to
        // PsychonautWiki's canonical oral ethanol values, denominated in grams:
        // Threshold 10 g (≈ one standard drink), Heavy 60 g+ (≈ 4-6 drinks).
        "alcohol": [
            DoseOverride(
                route: .oral,
                unit: "g",
                doses: DoseRange(
                    threshold: 10,
                    light: 10...20,
                    common: 20...40,
                    strong: 40...60,
                    heavy: 60
                )
            )
        ],

        // The remaining overrides come from the 2026-05-24 library audit
        // (`Specs/library-audit-2026-05-24.md`). Each value is sourced from
        // FDA prescribing labels, PsychonautWiki, or established clinical
        // references; the source is cited inline. Audit ran the SubstanceValidator
        // `audit` subcommand and the resulting ground-truth disagreements were
        // researched against authoritative documents.

        // FDA Wellbutrin XL labeling — max 450 mg/day across IR/SR/XR. The DailyMed
        // parser was pulling the IR starting dose (150 mg) as heavy.
        "bupropion": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 75,
                    light: 75...150,
                    common: 150...300,
                    strong: 300...450,
                    heavy: 450
                )
            )
        ],

        // FDA Adderall labeling — IR max 40 mg/day for ADHD, up to 60 mg/day
        // for narcolepsy. We use 60 as heavy so legitimate narcolepsy patients
        // aren't flagged. TripSit had heavy at 75 mg (recreational); FDA cap wins.
        "adderall": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 5,
                    light: 5...10,
                    common: 10...30,
                    strong: 30...40,
                    heavy: 60
                )
            )
        ],

        // PsychonautWiki deliriant scale — full delirium begins above ~500 mg
        // with cardiotoxicity and seizure risk; lethal overlap above ~1000 mg.
        // Library was 1050 mg from merged sources, which is in the lethal range.
        "diphenhydramine": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 12.5,
                    light: 25...100,
                    common: 100...300,
                    strong: 300...500,
                    heavy: 700
                )
            )
        ],

        // FDA Synthroid prescribing info — 1.6 µg/kg/day typical; >200 µg
        // rarely needed, >300 µg suggests malabsorption. Library had the
        // *starting* dose (25 µg) as heavy. Unit gotcha: dosed in µg, not mg.
        "levothyroxine": [
            DoseOverride(
                route: .oral,
                unit: "µg",
                doses: DoseRange(
                    threshold: 12.5,
                    light: 25...75,
                    common: 75...150,
                    strong: 150...200,
                    heavy: 300
                )
            )
        ],

        // PsychonautWiki nicotine — one 4 mg gum is "common-to-strong";
        // two pieces (~8 mg) is heavy. Library had heavy = 4 mg (one gum).
        "nicotine": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 0.2,
                    light: 1...3,
                    common: 3...5,
                    strong: 5...7,
                    heavy: 7
                )
            )
        ],

        // FDA Nuvigil labeling — max 250 mg/day; PsychonautWiki extends heavy
        // to 300 mg recreationally. 300 mg gives a small buffer above the FDA cap.
        "armodafinil": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 20,
                    light: 40...100,
                    common: 100...200,
                    strong: 200...300,
                    heavy: 300
                )
            )
        ],

        // FDA Provigil labeling — max 400 mg/day. Use the FDA ceiling so
        // legitimate narcolepsy patients aren't flagged.
        "modafinil": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 25,
                    light: 50...100,
                    common: 100...200,
                    strong: 200...400,
                    heavy: 400
                )
            )
        ],

        // Per-dose Rx single ceiling 800 mg (Mayo Clinic / Drugs.com); daily
        // Rx max 3200 mg, OTC max 1200 mg — tracked separately, not via heavy.
        "ibuprofen": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 100,
                    light: 200...400,
                    common: 400...600,
                    strong: 600...800,
                    heavy: 800
                )
            )
        ],

        // FDA acetaminophen guidance — per-dose extra-strength ceiling 1000 mg
        // (one extra-strength Tylenol); daily max 4000 mg with manufacturer-
        // recommended 3000 mg for chronic use. Hepatotoxicity onset ~7.5 g acute.
        "paracetamol": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 325,
                    light: 325...500,
                    common: 500...1000,
                    strong: 1000...1000,
                    heavy: 1000
                )
            )
        ],

        // PsychonautWiki ketamine — route-aware. Oral and insufflation differ
        // by ~3× because oral bioavailability is ~17% vs nasal ~45%. Confusing
        // 150 mg insufflated (heavy) with 150 mg oral (common) is dangerous.
        "ketamine": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 50,
                    light: 50...100,
                    common: 100...300,
                    strong: 300...450,
                    heavy: 450
                )
            ),
            DoseOverride(
                route: .insufflation,
                unit: "mg",
                doses: DoseRange(
                    threshold: 5,
                    light: 10...30,
                    common: 30...75,
                    strong: 75...150,
                    heavy: 150
                )
            ),
            DoseOverride(
                route: .intramuscular,
                unit: "mg",
                doses: DoseRange(
                    threshold: 5,
                    light: 15...30,
                    common: 30...75,
                    strong: 75...120,
                    heavy: 120
                )
            )
        ],

        // Sleep Foundation / Drugs.com — >5 mg no more effective; >10 mg
        // increases side effects without benefit. JAMA 2017 caveat: US OTC
        // labeling is notoriously inaccurate (actual content 17–478% of label).
        "melatonin": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 0.3,
                    light: 0.3...1,
                    common: 1...3,
                    strong: 3...5,
                    heavy: 10
                )
            )
        ],

        // TripSit shipped theophylline as µg — almost certainly a unit-parse
        // bug (clinical doses are 200–400 mg/day; serum therapeutic 10–20 µg/mL
        // gets misread as oral dose). Replace with the actual mg ranges from
        // FDA labeling for Theo-Dur etc. Heavy caps at 600 mg per-dose; daily
        // max 800-900 mg is split across doses, so per-event "heavy" is 600.
        "theophylline": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange(
                    threshold: 100,
                    light: 100...200,
                    common: 200...400,
                    strong: 400...500,
                    heavy: 600
                )
            )
        ],

        // MK-801 (dizocilpine) is a research-only NMDA antagonist. Human
        // recreational use is rare and the public-source dose data ("50–100 µg
        // oral") is implausible — animal studies use 0.1–0.3 mg/kg. Clear the
        // route entirely; better to surface no dose than a misleading one.
        "mk-801": [
            DoseOverride(
                route: .oral,
                unit: "mg",
                doses: DoseRange()
            )
        ]
    ]

    /// Drop dose-ladder rungs that violate `threshold ≤ light ≤ common ≤ strong ≤ heavy`.
    /// Mostly cleans up DailyMed-derived data where the parser misread pediatric
    /// or renal-adjustment numbers as adult heavy doses. Applied to every route
    /// on every library update so cached data is sanitised on load.
    static func enforceMonotonicity(_ substances: [Substance]) -> [Substance] {
        substances.map { s in
            let cleaned = s.routes.map { route in
                SubstanceRoute(
                    route: route.route,
                    unit: route.unit,
                    doses: DailyMedAPI.enforceMonotonicity(route.doses),
                    duration: route.duration
                )
            }
            return Substance(
                name: s.name,
                aliases: s.aliases,
                category: s.category,
                defaultRoute: s.defaultRoute,
                routes: cleaned,
                effects: s.effects,
                subjectiveEffects: s.subjectiveEffects,
                toleranceInfo: s.toleranceInfo,
                halfLifeMinutes: s.halfLifeMinutes,
                sources: s.sources,
                mechanismOfAction: s.mechanismOfAction
            )
        }
    }

    static func applyDoseOverrides(_ substances: [Substance]) -> [Substance] {
        substances.map { s in
            let candidates = [s.name.lowercased()] + s.aliases.map { $0.lowercased() }
            guard let overrides = candidates.lazy.compactMap({ doseOverrides[$0] }).first else { return s }

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
        all = applyDoseOverrides(enforceMonotonicity(substances))
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
            logger.error("Failed to encode cache")
            return
        }
        Task.detached(priority: .utility) {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("substances_cache.json")
            try? data.write(to: url)
            logger.debug("Cache saved (\(data.count) bytes)")
        }
    }

    private static func loadCache() -> [Substance]? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("substances_cache.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode([Substance].self, from: data) else { return nil }
        return applyDoseOverrides(decoded)
    }

    /// Initial population for ``all`` on first launch (no cache present).
    /// Merges every bundled dataset so the library is non-empty before any
    /// network call returns — users can search and log without waiting on
    /// TripSit/DailyMed. The same datasets are re-merged later inside
    /// ``fetchFromAPIs(forceRefresh:)`` to integrate live data on top.
    @MainActor private static func loadInitialBundledSubstances() -> [Substance] {
        var seed: [Substance] = loadBundledSubstances() ?? []
        let dc = DrugCommunityAPI.loadSubstancesFromBundle()
        if !dc.isEmpty {
            seed = SubstanceDeduplicator.deduplicatedMerge(existing: seed, incoming: dc)
        }
        return applyDoseOverrides(enforceMonotonicity(seed))
    }

    /// Load the comprehensive default dataset that ships in the app bundle.
    /// Covers research chemicals, NPS, nootropics, dissociative analogues,
    /// salvinorin derivatives, PIHKAL/TIHKAL compounds, and compounds whose
    /// only information is a reference link to literature. Returns nil when
    /// the resource is missing or unparseable so first-launch can fall back
    /// to an empty list until APIs respond.
    static func loadBundledSubstances() -> [Substance]? {
        guard let url = Bundle.main.url(forResource: "substances-bundled", withExtension: "json") else {
            logger.warning("Bundled substances resource not found")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("Failed to read bundled substances at \(url.path, privacy: .public)")
            return nil
        }
        do {
            let decoded = try JSONDecoder().decode([Substance].self, from: data)
            logger.info("Loaded \(decoded.count) bundled substances")
            return decoded
        } catch {
            logger.error("Failed to decode bundled substances: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
