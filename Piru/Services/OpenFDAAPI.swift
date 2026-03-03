import Foundation

/// OpenFDA API client — fetches prescription drug data from all pharmacologic classes
struct OpenFDAAPI {
    private static let baseURL = "https://api.fda.gov/drug/label.json"

    struct FDADrug: Decodable {
        let openfda: OpenFDA?

        struct OpenFDA: Decodable {
            let brand_name: [String]?
            let generic_name: [String]?
            let route: [String]?
            let pharm_class_epc: [String]?
        }
    }

    private struct FDAResult: Decodable {
        let results: [FDADrug]?
    }

    private struct CountResult: Decodable {
        let results: [CountTerm]?
        struct CountTerm: Decodable {
            let term: String
            let count: Int
        }
    }

    /// Skip only truly irrelevant topical/cosmetic classes
    private static let skipKeywords = [
        "Allergen", "Allergenic", "Non-Standardized", "Standardized",
        "Vehicle", "Solvent", "Surfactant", "Preservative",
        "Sunscreen", "Keratolytic"
    ]

    /// Common medications that should NEVER be filtered out
    private static let whitelistedNames: Set<String> = [
        // Cardiovascular
        "LISINOPRIL", "LOSARTAN", "AMLODIPINE", "METOPROLOL", "ATENOLOL",
        "PROPRANOLOL", "CARVEDILOL", "DILTIAZEM", "VERAPAMIL", "NIFEDIPINE",
        "HYDROCHLOROTHIAZIDE", "FUROSEMIDE", "SPIRONOLACTONE", "CLOPIDOGREL",
        "WARFARIN", "APIXABAN", "RIVAROXABAN", "DIGOXIN", "HYDRALAZINE",
        "CLONIDINE", "DOXAZOSIN", "PRAZOSIN", "OLMESARTAN", "VALSARTAN",
        "IRBESARTAN", "TELMISARTAN", "ENALAPRIL", "RAMIPRIL", "BENAZEPRIL",
        // Statins / Lipids
        "ATORVASTATIN", "ROSUVASTATIN", "SIMVASTATIN", "PRAVASTATIN",
        "LOVASTATIN", "EZETIMIBE", "FENOFIBRATE", "GEMFIBROZIL",
        // Diabetes
        "METFORMIN", "INSULIN", "GLIPIZIDE", "GLYBURIDE", "GLIMEPIRIDE",
        "PIOGLITAZONE", "SITAGLIPTIN", "EMPAGLIFLOZIN", "DAPAGLIFLOZIN",
        "LIRAGLUTIDE", "SEMAGLUTIDE", "DULAGLUTIDE",
        // Thyroid
        "LEVOTHYROXINE", "METHIMAZOLE", "PROPYLTHIOURACIL",
        // GI
        "OMEPRAZOLE", "PANTOPRAZOLE", "ESOMEPRAZOLE", "LANSOPRAZOLE",
        "RANITIDINE", "FAMOTIDINE", "METOCLOPRAMIDE", "ONDANSETRON",
        "LOPERAMIDE", "SUCRALFATE", "MISOPROSTOL", "LACTULOSE",
        // Antidepressants / Mood
        "SERTRALINE", "FLUOXETINE", "PAROXETINE", "CITALOPRAM", "ESCITALOPRAM",
        "VENLAFAXINE", "DULOXETINE", "DESVENLAFAXINE", "BUPROPION",
        "MIRTAZAPINE", "TRAZODONE", "NORTRIPTYLINE", "AMITRIPTYLINE",
        "DOXEPIN", "IMIPRAMINE", "CLOMIPRAMINE", "VILAZODONE", "VORTIOXETINE",
        "LITHIUM",
        // Antipsychotics
        "QUETIAPINE", "OLANZAPINE", "RISPERIDONE", "ARIPIPRAZOLE",
        "HALOPERIDOL", "CHLORPROMAZINE", "ZIPRASIDONE", "LURASIDONE",
        "CLOZAPINE", "PALIPERIDONE", "CARIPRAZINE", "BREXPIPRAZOLE",
        // Anxiolytics / Sedatives
        "HYDROXYZINE", "BUSPIRONE", "PROMETHAZINE", "DIPHENHYDRAMINE",
        // Stimulants / ADHD
        "AMPHETAMINE", "METHYLPHENIDATE", "LISDEXAMFETAMINE", "ATOMOXETINE",
        "MODAFINIL", "ARMODAFINIL", "GUANFACINE",
        // Anticonvulsants
        "GABAPENTIN", "PREGABALIN", "TOPIRAMATE", "LAMOTRIGINE", "LEVETIRACETAM",
        "PHENYTOIN", "CARBAMAZEPINE", "OXCARBAZEPINE", "VALPROIC ACID",
        "ZONISAMIDE", "LACOSAMIDE", "ETHOSUXIMIDE",
        // Analgesics / NSAIDs
        "IBUPROFEN", "ACETAMINOPHEN", "ASPIRIN", "NAPROXEN", "MELOXICAM",
        "CELECOXIB", "DICLOFENAC", "INDOMETHACIN", "KETOROLAC",
        // Muscle relaxants
        "CYCLOBENZAPRINE", "TIZANIDINE", "BACLOFEN", "CARISOPRODOL",
        "METHOCARBAMOL", "DANTROLENE",
        // Opioids
        "TRAMADOL", "CODEINE", "MORPHINE", "OXYCODONE", "HYDROCODONE",
        "FENTANYL", "METHADONE", "BUPRENORPHINE", "NALOXONE", "NALTREXONE",
        "TAPENTADOL", "HYDROMORPHONE", "OXYMORPHONE",
        // Corticosteroids
        "PREDNISONE", "PREDNISOLONE", "DEXAMETHASONE", "METHYLPREDNISOLONE",
        "HYDROCORTISONE", "BUDESONIDE", "FLUTICASONE", "TRIAMCINOLONE",
        "BETAMETHASONE", "FLUDROCORTISONE",
        // Respiratory
        "ALBUTEROL", "MONTELUKAST", "THEOPHYLLINE", "TIOTROPIUM",
        "IPRATROPIUM", "FLUTICASONE", "CETIRIZINE", "LORATADINE",
        "FEXOFENADINE", "DESLORATADINE", "LEVOCETIRIZINE",
        // Antibiotics
        "AMOXICILLIN", "AZITHROMYCIN", "DOXYCYCLINE", "CIPROFLOXACIN",
        "LEVOFLOXACIN", "TRIMETHOPRIM", "NITROFURANTOIN", "METRONIDAZOLE",
        "CLINDAMYCIN", "CEPHALEXIN", "AMOXICILLIN", "CEFTRIAXONE",
        "SULFAMETHOXAZOLE", "PENICILLIN", "ERYTHROMYCIN", "CLARITHROMYCIN",
        "MOXIFLOXACIN", "VANCOMYCIN", "LINEZOLID", "DAPTOMYCIN",
        // Antifungals
        "FLUCONAZOLE", "ITRACONAZOLE", "TERBINAFINE", "NYSTATIN",
        "KETOCONAZOLE", "VORICONAZOLE", "POSACONAZOLE",
        // Antivirals
        "VALACYCLOVIR", "ACYCLOVIR", "OSELTAMIVIR",
        // Migraine
        "SUMATRIPTAN", "RIZATRIPTAN", "ZOLMITRIPTAN", "ELETRIPTAN",
        // Urology
        "SILDENAFIL", "TADALAFIL", "FINASTERIDE", "DUTASTERIDE",
        "TAMSULOSIN", "ALFUZOSIN", "OXYBUTYNIN", "TOLTERODINE",
        // Dermatology
        "MINOXIDIL", "ISOTRETINOIN",
        // Dementia
        "DONEPEZIL", "MEMANTINE", "RIVASTIGMINE", "GALANTAMINE",
        // Gout
        "COLCHICINE", "ALLOPURINOL", "FEBUXOSTAT",
        // Immunosuppressants
        "METHOTREXATE", "AZATHIOPRINE", "MYCOPHENOLATE", "TACROLIMUS",
        "CYCLOSPORINE", "HYDROXYCHLOROQUINE", "SULFASALAZINE",
        // Misc
        "WARFARIN", "HEPARIN", "ENOXAPARIN",
    ]

    /// Junk product names to skip (topical/cosmetic only)
    private static let junkProducts: Set<String> = [
        "HAND SANITIZER", "SUNSCREEN", "TOOTHPASTE", "DEODORANT",
        "SHAMPOO", "SOAP", "LOTION", "BODY WASH", "HAND WASH",
        "FACE WASH", "MOUTHWASH", "LIP BALM"
    ]

    /// Fetch all pharmacologic classes from FDA, then query each for drugs.
    /// Calls `onProgress` periodically with newly found drugs so the UI can update incrementally.
    static func fetchCommonDrugs(
        onProgress: ((_ newDrugs: [FDADrug], _ classesProcessed: Int, _ totalClasses: Int) async -> Void)? = nil
    ) async throws -> [FDADrug] {
        // Step 1: Get all pharmacologic classes
        guard let classURL = URL(string: "\(baseURL)?count=openfda.pharm_class_epc.exact&limit=500") else {
            throw APIError.badURL
        }
        let (classData, classResp) = try await URLSession.shared.data(from: classURL)
        guard let http = classResp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse
        }
        let classResult = try JSONDecoder().decode(CountResult.self, from: classData)
        let allClasses = (classResult.results ?? [])
            .filter { term in !skipKeywords.contains(where: { term.term.contains($0) }) }
            .map { $0.term.replacingOccurrences(of: " [EPC]", with: "") }

        print("[OpenFDAAPI] Found \(allClasses.count) pharmacologic classes to query")

        // Step 2: Query classes concurrently in batches of 5
        var allDrugs: [FDADrug] = []
        var seenNames: Set<String> = []
        var lastReportedCount = 0
        let concurrency = 5

        for batchStart in stride(from: 0, to: allClasses.count, by: concurrency) {
            let batchEnd = min(batchStart + concurrency, allClasses.count)
            let classBatch = Array(allClasses[batchStart..<batchEnd])

            await withTaskGroup(of: [FDADrug].self) { group in
                for cls in classBatch {
                    group.addTask {
                        await Self.fetchClass(cls)
                    }
                }
                for await drugs in group {
                    for drug in drugs {
                        if let name = drug.openfda?.generic_name?.first?.uppercased(), !seenNames.contains(name) {
                            seenNames.insert(name)
                            allDrugs.append(drug)
                        }
                    }
                }
            }

            // Report progress every ~25 classes or when done
            let classesProcessed = batchEnd
            let shouldReport = classesProcessed % 25 < concurrency || classesProcessed >= allClasses.count
            if allDrugs.count > lastReportedCount && shouldReport {
                let newDrugs = Array(allDrugs[lastReportedCount...])
                lastReportedCount = allDrugs.count
                await onProgress?(newDrugs, classesProcessed, allClasses.count)
                print("[OpenFDAAPI] Progress: \(classesProcessed)/\(allClasses.count) classes, \(allDrugs.count) drugs so far")
            }
        }

        print("[OpenFDAAPI] Fetched \(allDrugs.count) unique drugs from \(allClasses.count) classes")
        return allDrugs
    }

    /// Fetch whitelisted drugs that are missing from the class-based results (many common drugs have no pharm_class_epc)
    static func fetchMissingWhitelisted(alreadyFound: Set<String>) async -> [FDADrug] {
        let missing = whitelistedNames.filter { !alreadyFound.contains($0) }
        guard !missing.isEmpty else { return [] }

        print("[OpenFDAAPI] Fetching \(missing.count) whitelisted drugs missing from class-based results")
        var results: [FDADrug] = []
        let concurrency = 5

        let missingArray = Array(missing)
        for batchStart in stride(from: 0, to: missingArray.count, by: concurrency) {
            let batchEnd = min(batchStart + concurrency, missingArray.count)
            let batch = Array(missingArray[batchStart..<batchEnd])

            await withTaskGroup(of: FDADrug?.self) { group in
                for name in batch {
                    group.addTask {
                        await Self.fetchByGenericName(name)
                    }
                }
                for await drug in group {
                    if let drug { results.append(drug) }
                }
            }
        }

        print("[OpenFDAAPI] Found \(results.count)/\(missing.count) missing whitelisted drugs")
        return results
    }

    /// Fetch a single drug by generic name
    private static func fetchByGenericName(_ name: String, retryOnRateLimit: Bool = true) async -> FDADrug? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search", value: "openfda.generic_name:\"\(name)\""),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 429 && retryOnRateLimit {
                try? await Task.sleep(for: .seconds(3))
                return await fetchByGenericName(name, retryOnRateLimit: false)
            }

            guard http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(FDAResult.self, from: data)
            return result.results?.first
        } catch {
            return nil
        }
    }

    /// Fetch drugs for a single pharmacologic class with timeout and retry on rate limit
    private static func fetchClass(_ cls: String, retryOnRateLimit: Bool = true) async -> [FDADrug] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search", value: "openfda.pharm_class_epc:\"\(cls)\""),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }

            if http.statusCode == 429 && retryOnRateLimit {
                try? await Task.sleep(for: .seconds(3))
                return await fetchClass(cls, retryOnRateLimit: false)
            }

            guard http.statusCode == 200 else { return [] }
            let result = try JSONDecoder().decode(FDAResult.self, from: data)
            return result.results ?? []
        } catch {
            return []
        }
    }

    /// Formulation descriptors that appear after commas in FDA names (not ingredient separators)
    private static let formulationKeywords: [String] = [
        "EXTENDED-RELEASE", "DELAYED-RELEASE", "SUSTAINED-RELEASE",
        "MODIFIED-RELEASE", "CONTROLLED-RELEASE", "IMMEDIATE-RELEASE",
        "LONG-ACTING", "SHORT-ACTING", "ENTERIC-COATED",
        "ORAL", "TABLET", "CAPSULE", "INJECTION", "SOLUTION", "SUSPENSION",
        "TOPICAL", "OPHTHALMIC", "RECTAL", "NASAL", "INHALATION",
        "USP", "HCL", "ER", "DR", "SR", "XR", "XL", "CR", "LA",
    ]

    /// Returns true if the name looks like a multi-ingredient combination drug
    private static func isComboDrug(_ nameUpper: String) -> Bool {
        // Explicit multi-ingredient separators
        if nameUpper.contains(" AND ") { return true }
        if nameUpper.contains(" / ") { return true }
        if nameUpper.contains("; ") { return true }
        if nameUpper.contains(" WITH ") { return true }
        if nameUpper.contains(" - ") { return true }
        // Commas: check if parts after commas are formulation descriptors or actual ingredients
        if nameUpper.contains(",") {
            let parts = nameUpper.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts.dropFirst() {
                let isFormulation = formulationKeywords.contains(where: { part.hasPrefix($0) || part == $0 })
                if !isFormulation {
                    // This part after the comma looks like another ingredient
                    return true
                }
            }
        }
        return false
    }

    /// Counts approximate number of active ingredients in an FDA name
    private static func ingredientCount(_ nameUpper: String) -> Int {
        let separators = [" AND ", " / ", " - "]
        var maxCount = separators.map { nameUpper.components(separatedBy: $0).count }.max() ?? 1
        // Count comma-separated ingredients (excluding formulation suffixes)
        if nameUpper.contains(",") {
            let parts = nameUpper.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let ingredientParts = parts.filter { part in
                // First part is always an ingredient; check if subsequent parts are formulations
                part == parts.first || !formulationKeywords.contains(where: { part.hasPrefix($0) || part == $0 })
            }
            maxCount = max(maxCount, ingredientParts.count)
        }
        return maxCount
    }

    /// Common pharmaceutical salt suffixes (not separate ingredients)
    private static let saltSuffixes: Set<String> = [
        "HYDROCHLORIDE", "HCL", "SODIUM", "POTASSIUM", "CALCIUM", "MAGNESIUM",
        "SULFATE", "PHOSPHATE", "CITRATE", "TARTRATE", "MALEATE", "SUCCINATE",
        "FUMARATE", "MESYLATE", "BESYLATE", "ACETATE", "BROMIDE", "CHLORIDE",
        "NITRATE", "OXIDE", "CARBONATE", "GLUCONATE", "LACTATE", "BITARTRATE",
        "MONOHYDRATE", "DIHYDRATE", "TRIHYDRATE", "ANHYDROUS",
        "DISODIUM", "DIPOTASSIUM", "DIHYDROCHLORIDE", "HEMISULFATE",
    ]

    /// Check if a name is just a whitelisted drug + salt form (e.g. "VENLAFAXINE HYDROCHLORIDE")
    private static func isWhitelistedWithSalt(_ nameUpper: String) -> Bool {
        for drug in whitelistedNames {
            guard nameUpper.hasPrefix(drug), nameUpper.count > drug.count else { continue }
            let remainder = nameUpper.dropFirst(drug.count).trimmingCharacters(in: .whitespaces)
            let remainderWords = remainder.components(separatedBy: .whitespaces)
            if remainderWords.allSatisfy({ saltSuffixes.contains($0) }) {
                return true
            }
        }
        return false
    }

    /// Convert an FDA drug to our Substance model
    static func toSubstance(_ drug: FDADrug) -> Substance? {
        guard let genericName = drug.openfda?.generic_name?.first else { return nil }

        let name = genericName.capitalized
        let nameUpper = genericName.uppercased()

        // Exact whitelist match (e.g. "ASPIRIN") — always keep
        let isExactWhitelisted = whitelistedNames.contains(nameUpper)
        // Whitelisted drug + salt form (e.g. "VENLAFAXINE HYDROCHLORIDE") — always keep
        let isSaltForm = !isExactWhitelisted && isWhitelistedWithSalt(nameUpper)
        let isProtected = isExactWhitelisted || isSaltForm

        // Reject ALL combinations unless it's an exact match or simple salt form
        if !isProtected {
            if ingredientCount(nameUpper) >= 3 { return nil }
            if isComboDrug(nameUpper) { return nil }
        }

        // For non-protected drugs, apply quality filters
        let isWhitelisted = isProtected ||
            whitelistedNames.contains(where: { nameUpper.contains($0) })

        if !isWhitelisted {
            // Reject overly long names (verbose chemical nomenclature)
            if nameUpper.count > 60 { return nil }

            // Skip names shorter than 2 chars
            if name.count < 2 { return nil }

            // Skip obvious non-drug products
            if junkProducts.contains(where: { nameUpper.contains($0) }) { return nil }

            // Skip if route is ONLY topical/ophthalmic/otic with no oral route
            if let routes = drug.openfda?.route {
                let routeSet = Set(routes.map { $0.uppercased() })
                let topicalOnly = Set(["TOPICAL", "OPHTHALMIC", "OTIC", "DENTAL", "NASAL SPRAY"])
                if routeSet.isSubset(of: topicalOnly) && !routeSet.isEmpty { return nil }
            }
        }

        var aliases: [String] = []
        if let brands = drug.openfda?.brand_name {
            let seen = Set([nameUpper])
            for brand in brands.prefix(8) {
                let clean = brand.capitalized
                if !seen.contains(clean.uppercased()) && clean.count > 2 {
                    aliases.append(clean)
                }
            }
            aliases = Array(Set(aliases)).sorted().prefix(5).map { $0 }
        }

        let category = nameOverrides[nameUpper] ?? mapCategory(drug.openfda?.pharm_class_epc)
        let routes: [SubstanceRoute] = (drug.openfda?.route ?? ["ORAL"]).prefix(3).map { routeStr in
            SubstanceRoute(
                route: RouteOfAdministration.from(string: routeStr),
                unit: "mg",
                doses: DoseRange()
            )
        }

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: routes.first?.route ?? .oral,
            routes: routes,
            effects: [],
            subjectiveEffects: [],
            toleranceInfo: nil,
            halfLifeMinutes: nil,
            sources: ["OpenFDA"]
        )
    }

    /// Convert a batch of FDA drugs with rejection stats logging
    static func convertAllWithStats(_ drugs: [FDADrug]) -> [Substance] {
        var noGenericName = 0
        var tooShort = 0
        var junkProduct = 0
        var topicalOnly = 0
        var comboDrug = 0
        var tooLong = 0
        var noRouteKept = 0

        var results: [Substance] = []
        for drug in drugs {
            if let substance = toSubstance(drug) {
                if drug.openfda?.route == nil { noRouteKept += 1 }
                results.append(substance)
            } else {
                // Determine rejection reason for logging
                guard let gn = drug.openfda?.generic_name?.first else {
                    noGenericName += 1
                    continue
                }
                let nameUpper = gn.uppercased()
                let isProtected = whitelistedNames.contains(nameUpper) || isWhitelistedWithSalt(nameUpper)

                if !isProtected && (ingredientCount(nameUpper) >= 3 || isComboDrug(nameUpper)) {
                    comboDrug += 1
                    continue
                }

                let isWhitelisted = isProtected ||
                    whitelistedNames.contains(where: { nameUpper.contains($0) })

                if !isWhitelisted {
                    if nameUpper.count > 60 {
                        tooLong += 1
                    } else if gn.capitalized.count < 2 {
                        tooShort += 1
                    } else if junkProducts.contains(where: { nameUpper.contains($0) }) {
                        junkProduct += 1
                    } else if let routes = drug.openfda?.route {
                        let routeSet = Set(routes.map { $0.uppercased() })
                        let topicalOnlySet: Set<String> = ["TOPICAL", "OPHTHALMIC", "OTIC", "DENTAL", "NASAL SPRAY"]
                        if routeSet.isSubset(of: topicalOnlySet) && !routeSet.isEmpty {
                            topicalOnly += 1
                        }
                    }
                }
            }
        }

        let rejected = drugs.count - results.count
        print("[OpenFDAAPI] Conversion: \(results.count) converted, \(rejected) rejected (\(noGenericName) no generic name, \(comboDrug) combo drug, \(tooLong) too long, \(tooShort) name too short, \(junkProduct) junk product, \(topicalOnly) topical-only)")
        if noRouteKept > 0 {
            print("[OpenFDAAPI] \(noRouteKept) drugs had no route data → defaulted to oral")
        }
        return results
    }

    /// Name-based overrides for whitelisted drugs that may lack pharm_class_epc
    private static let nameOverrides: [String: SubstanceCategory] = [
        // Cardiovascular
        "LISINOPRIL": .cardiovascular, "LOSARTAN": .cardiovascular, "AMLODIPINE": .cardiovascular,
        "METOPROLOL": .cardiovascular, "ATENOLOL": .cardiovascular, "PROPRANOLOL": .cardiovascular,
        "CARVEDILOL": .cardiovascular, "DILTIAZEM": .cardiovascular, "VERAPAMIL": .cardiovascular,
        "NIFEDIPINE": .cardiovascular, "HYDROCHLOROTHIAZIDE": .cardiovascular, "FUROSEMIDE": .cardiovascular,
        "SPIRONOLACTONE": .cardiovascular, "CLOPIDOGREL": .cardiovascular, "WARFARIN": .cardiovascular,
        "APIXABAN": .cardiovascular, "RIVAROXABAN": .cardiovascular, "DIGOXIN": .cardiovascular,
        "HYDRALAZINE": .cardiovascular, "CLONIDINE": .cardiovascular, "DOXAZOSIN": .cardiovascular,
        "PRAZOSIN": .cardiovascular, "OLMESARTAN": .cardiovascular, "VALSARTAN": .cardiovascular,
        "IRBESARTAN": .cardiovascular, "TELMISARTAN": .cardiovascular, "ENALAPRIL": .cardiovascular,
        "RAMIPRIL": .cardiovascular, "BENAZEPRIL": .cardiovascular, "HEPARIN": .cardiovascular,
        "ENOXAPARIN": .cardiovascular,
        // Statins / Lipids
        "ATORVASTATIN": .cardiovascular, "ROSUVASTATIN": .cardiovascular, "SIMVASTATIN": .cardiovascular,
        "PRAVASTATIN": .cardiovascular, "LOVASTATIN": .cardiovascular, "EZETIMIBE": .cardiovascular,
        "FENOFIBRATE": .cardiovascular, "GEMFIBROZIL": .cardiovascular,
        // Diabetes / Endocrine
        "METFORMIN": .endocrine, "INSULIN": .endocrine, "GLIPIZIDE": .endocrine,
        "GLYBURIDE": .endocrine, "GLIMEPIRIDE": .endocrine, "PIOGLITAZONE": .endocrine,
        "SITAGLIPTIN": .endocrine, "EMPAGLIFLOZIN": .endocrine, "DAPAGLIFLOZIN": .endocrine,
        "LIRAGLUTIDE": .endocrine, "SEMAGLUTIDE": .endocrine, "DULAGLUTIDE": .endocrine,
        "LEVOTHYROXINE": .endocrine, "METHIMAZOLE": .endocrine, "PROPYLTHIOURACIL": .endocrine,
        // GI
        "OMEPRAZOLE": .gastrointestinal, "PANTOPRAZOLE": .gastrointestinal,
        "ESOMEPRAZOLE": .gastrointestinal, "LANSOPRAZOLE": .gastrointestinal,
        "RANITIDINE": .gastrointestinal, "FAMOTIDINE": .gastrointestinal,
        "METOCLOPRAMIDE": .gastrointestinal, "ONDANSETRON": .gastrointestinal,
        "LOPERAMIDE": .gastrointestinal, "SUCRALFATE": .gastrointestinal,
        "MISOPROSTOL": .gastrointestinal, "LACTULOSE": .gastrointestinal,
        // Respiratory
        "ALBUTEROL": .respiratory, "MONTELUKAST": .respiratory, "THEOPHYLLINE": .respiratory,
        "TIOTROPIUM": .respiratory, "IPRATROPIUM": .respiratory, "FLUTICASONE": .respiratory,
        // Antihistamines
        "CETIRIZINE": .antihistamine, "LORATADINE": .antihistamine, "FEXOFENADINE": .antihistamine,
        "DESLORATADINE": .antihistamine, "LEVOCETIRIZINE": .antihistamine,
        // Immunological
        "METHOTREXATE": .immunological, "AZATHIOPRINE": .immunological,
        "MYCOPHENOLATE": .immunological, "TACROLIMUS": .immunological,
        "CYCLOSPORINE": .immunological, "HYDROXYCHLOROQUINE": .immunological,
        "SULFASALAZINE": .immunological,
        // Urology
        "SILDENAFIL": .cardiovascular, "TADALAFIL": .cardiovascular,
        "FINASTERIDE": .endocrine, "DUTASTERIDE": .endocrine,
        "TAMSULOSIN": .cardiovascular, "ALFUZOSIN": .cardiovascular,
        "OXYBUTYNIN": .gastrointestinal, "TOLTERODINE": .gastrointestinal,
        // Gout
        "COLCHICINE": .analgesic, "ALLOPURINOL": .analgesic, "FEBUXOSTAT": .analgesic,
    ]

    private static func mapCategory(_ classes: [String]?) -> SubstanceCategory {
        guard let classes else { return .other }
        let joined = classes.joined(separator: " ").lowercased()

        // Opioids
        if joined.contains("opioid") { return .opioid }
        // Benzodiazepines
        if joined.contains("benzodiazepine") { return .benzodiazepine }
        // Depressants (barbiturates, muscle relaxants, GABAergics, sedatives)
        if joined.contains("barbiturate") || joined.contains("muscle relaxant") { return .depressant }
        if joined.contains("gamma-aminobutyric") || joined.contains("gaba") { return .depressant }
        if joined.contains("sedative") || joined.contains("hypnotic") || joined.contains("anesthetic") || joined.contains("anxiolytic") { return .depressant }
        if joined.contains("melatonin receptor") || joined.contains("orexin receptor") { return .depressant }
        if joined.contains("neuromuscular blocker") || joined.contains("anticholinergic") { return .depressant }
        if joined.contains("phenothiazine") { return .depressant }
        if joined.contains("depressant") { return .depressant }
        // Stimulants
        if joined.contains("stimulant") || joined.contains("amphetamine") { return .stimulant }
        if joined.contains("nicotinic agonist") || joined.contains("nicotine") { return .stimulant }
        if joined.contains("methylxanthine") { return .stimulant }
        if joined.contains("catecholamine") || joined.contains("sympathomimetic") { return .stimulant }
        // Antidepressants
        if joined.contains("serotonin reuptake") || joined.contains("antidepressant") || joined.contains("monoamine oxidase") || joined.contains("mood stabilizer") { return .antidepressant }
        if joined.contains("norepinephrine reuptake") || joined.contains("dopamine and norepinephrine") { return .antidepressant }
        // Antipsychotics
        if joined.contains("antipsychotic") { return .antipsychotic }
        // Cannabinoids
        if joined.contains("cannabinoid") { return .cannabinoid }
        // Antihistamines
        if joined.contains("antihistamine") || joined.contains("histamine") { return .antihistamine }
        if joined.contains("leukotriene") { return .antihistamine }
        // Analgesics (NSAIDs, triptans, migraine)
        if joined.contains("anti-inflammatory") || joined.contains("analgesic") { return .analgesic }
        if joined.contains("serotonin-1") || joined.contains("triptan") { return .analgesic }
        if joined.contains("calcitonin gene-related") || joined.contains("ergot") { return .analgesic }
        if joined.contains("cyclooxygenase") { return .analgesic }
        // Anticonvulsants / GABAergic
        if joined.contains("anti-epileptic") || joined.contains("anticonvulsant") || joined.contains("gabapentin") { return .gabapentinoid }
        // Nootropics
        if joined.contains("cholinesterase") || joined.contains("nmda") || joined.contains("nootropic") { return .nootropic }
        // Cardiovascular (antiarrhythmics, antihypertensives, diuretics, statins, anticoagulants)
        if joined.contains("arrhythmic") || joined.contains("platelet") { return .cardiovascular }
        if joined.contains("diuretic") || joined.contains("vasodilator") { return .cardiovascular }
        if joined.contains("angiotensin") || joined.contains("adrenergic blocker") { return .cardiovascular }
        if joined.contains("calcium channel") || joined.contains("cardiac") { return .cardiovascular }
        if joined.contains("coagul") || joined.contains("thrombin") || joined.contains("factor xa") { return .cardiovascular }
        if joined.contains("hmg-coa") || joined.contains("statin") { return .cardiovascular }
        if joined.contains("nitrate vasodilator") || joined.contains("anti-anginal") { return .cardiovascular }
        if joined.contains("aldosterone") || joined.contains("endothelin") { return .cardiovascular }
        if joined.contains("warfarin") { return .cardiovascular }
        // Antimicrobials (antibiotics, antifungals, antivirals, antiparasitics)
        if joined.contains("antibacterial") || joined.contains("antifungal") || joined.contains("antiviral") { return .antimicrobial }
        if joined.contains("antimicrobial") || joined.contains("antimycobacterial") { return .antimicrobial }
        if joined.contains("antiparasitic") || joined.contains("anthelmintic") || joined.contains("antimalarial") { return .antimicrobial }
        if joined.contains("antiprotozoal") || joined.contains("pediculicide") || joined.contains("antiseptic") { return .antimicrobial }
        if joined.contains("penicillin") || joined.contains("cephalosporin") || joined.contains("fluoroquinolone") { return .antimicrobial }
        if joined.contains("quinolone") || joined.contains("aminoglycoside") || joined.contains("macrolide") { return .antimicrobial }
        if joined.contains("tetracycline") || joined.contains("sulfonamide") || joined.contains("polymyxin") { return .antimicrobial }
        if joined.contains("rifamycin") || joined.contains("lincosamide") || joined.contains("glycopeptide") { return .antimicrobial }
        if joined.contains("nucleoside analog") { return .antimicrobial }
        // Gastrointestinal
        if joined.contains("proton pump") || joined.contains("laxative") { return .gastrointestinal }
        if joined.contains("antidiarrheal") || joined.contains("bile acid") || joined.contains("bismuth") { return .gastrointestinal }
        if joined.contains("gastrointestinal") || joined.contains("guanylate cyclase-c") { return .gastrointestinal }
        if joined.contains("chloride channel activator") || joined.contains("intestinal lipase") { return .gastrointestinal }
        if joined.contains("serotonin-3 receptor antagonist") || joined.contains("serotonin-4 receptor agonist") { return .gastrointestinal }
        if joined.contains("neurokinin-1 receptor antagonist") || joined.contains("nitrogen binding") { return .gastrointestinal }
        if joined.contains("calculi dissolution") { return .gastrointestinal }
        // Respiratory
        if joined.contains("expectorant") || joined.contains("antitussive") || joined.contains("mucolytic") { return .respiratory }
        if joined.contains("phosphodiesterase 4 inhibitor") { return .respiratory }
        if joined.contains("beta2-adrenergic") { return .respiratory }
        // Endocrine (hormones, diabetes, thyroid)
        if joined.contains("estrogen") || joined.contains("progestin") || joined.contains("progesterone") { return .endocrine }
        if joined.contains("androgen") || joined.contains("testosterone") { return .endocrine }
        if joined.contains("insulin") || joined.contains("sulfonylurea") || joined.contains("glp-1") { return .endocrine }
        if joined.contains("glinide") || joined.contains("glucosidase inhibitor") || joined.contains("thiazolidinedione") { return .endocrine }
        if joined.contains("sglt") || joined.contains("dipeptidyl peptidase") { return .endocrine }
        if joined.contains("thyro") || joined.contains("l-thyroxine") || joined.contains("l-triiodothyronine") { return .endocrine }
        if joined.contains("gonadotropin") || joined.contains("growth hormone") || joined.contains("somatostatin") { return .endocrine }
        if joined.contains("parathyroid") || joined.contains("adrenocorticotropic") || joined.contains("oxytocic") { return .endocrine }
        if joined.contains("melanocortin") || joined.contains("leptin") { return .endocrine }
        if joined.contains("peroxisome proliferator") || joined.contains("mineralocorticoid") { return .endocrine }
        if joined.contains("cortisol synthesis") || joined.contains("aryl hydrocarbon") { return .endocrine }
        // Immunological (immunosuppressants, cancer drugs, biologics)
        if joined.contains("kinase inhibitor") || joined.contains("alkylating") || joined.contains("antimetabolite") { return .immunological }
        if joined.contains("immunosuppressant") || joined.contains("tumor necrosis") { return .immunological }
        if joined.contains("interleukin") || joined.contains("interferon") { return .immunological }
        if joined.contains("proteasome inhibitor") || joined.contains("immunoglobulin") { return .immunological }
        if joined.contains("monoclonal antibody") || joined.contains("chimeric antigen") { return .immunological }
        if joined.contains("cytolytic") || joined.contains("immunoconjugate") || joined.contains("immunotherapy") { return .immunological }
        if joined.contains("programmed death") || joined.contains("ctla-4") { return .immunological }
        if joined.contains("aromatase inhibitor") || joined.contains("thalidomide") { return .immunological }
        if joined.contains("histone deacetylase") || joined.contains("poly(adp") || joined.contains("hedgehog") { return .immunological }
        if joined.contains("topoisomerase") || joined.contains("microtubule") { return .immunological }
        if joined.contains("antirheumatic") || joined.contains("janus kinase") { return .immunological }
        if joined.contains("sphingosine") || joined.contains("complement inhibitor") { return .immunological }
        if joined.contains("t cell") || joined.contains("b lymphocyte") { return .immunological }
        // Supplements
        if joined.contains("corticosteroid") || joined.contains("vitamin") { return .supplement }
        if joined.contains("amino acid") || joined.contains("omega-3") || joined.contains("nicotinic acid") { return .supplement }
        if joined.contains("folate") || joined.contains("carnitine") { return .supplement }
        // Adrenergic agonists (after cardiovascular blocker check)
        if joined.contains("adrenergic agonist") { return .stimulant }
        return .other
    }

    enum APIError: Error {
        case badURL
        case badResponse
    }
}
