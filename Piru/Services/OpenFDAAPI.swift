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

    /// Junk class keywords to skip
    private static let skipKeywords = [
        "Allergen", "Allergenic", "Antiseptic", "Non-Standardized", "Standardized",
        "Bismuth", "Vehicle", "Solvent", "Emollient", "Surfactant", "Preservative",
        "Intrauterine", "Sunscreen", "Keratolytic", "Laxative", "Antacid",
        "Astringent", "Counterirritant"
    ]

    /// Fetch all pharmacologic classes from FDA, then query each for drugs
    static func fetchCommonDrugs() async throws -> [FDADrug] {
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

        // Step 2: Query each class for drugs (batch of 100 per class)
        var allDrugs: [FDADrug] = []
        var seenNames: Set<String> = []

        for cls in allClasses {
            guard let encoded = cls.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(baseURL)?search=openfda.pharm_class_epc:\"\(encoded)\"&limit=100") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let result = try JSONDecoder().decode(FDAResult.self, from: data)
                for drug in result.results ?? [] {
                    if let name = drug.openfda?.generic_name?.first?.uppercased(), !seenNames.contains(name) {
                        seenNames.insert(name)
                        allDrugs.append(drug)
                    }
                }
                // Rate limit: 240 req/min without key = 250ms minimum
                try await Task.sleep(for: .milliseconds(260))
            } catch {
                continue
            }
        }

        print("[OpenFDAAPI] Fetched \(allDrugs.count) unique drugs from \(allClasses.count) classes")
        return allDrugs
    }

    /// Convert an FDA drug to our Substance model
    static func toSubstance(_ drug: FDADrug) -> Substance? {
        guard let genericName = drug.openfda?.generic_name?.first else { return nil }

        let name = genericName.capitalized
        // Skip combos, junk, too-short names
        if name.contains(",") || name.uppercased().contains(" AND ") { return nil }
        if name.count < 4 { return nil }
        // Skip obvious non-drugs
        let junk = ["Hand Sanitizer", "Sunscreen", "Toothpaste", "Deodorant",
                     "Shampoo", "Soap", "Lotion", "Oxygen", "Air ", "Water"]
        if junk.contains(where: { name.contains($0) }) { return nil }

        var aliases: [String] = []
        if let brands = drug.openfda?.brand_name {
            let seen = Set([name.uppercased()])
            for brand in brands.prefix(8) {
                let clean = brand.capitalized
                if !seen.contains(clean.uppercased()) && !clean.contains(",") && clean.count > 2 {
                    aliases.append(clean)
                }
            }
            aliases = Array(Set(aliases)).sorted().prefix(5).map { $0 }
        }

        let category = mapCategory(drug.openfda?.pharm_class_epc)
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

    private static func mapCategory(_ classes: [String]?) -> SubstanceCategory {
        guard let classes else { return .other }
        let joined = classes.joined(separator: " ").lowercased()

        if joined.contains("opioid") { return .opioid }
        if joined.contains("benzodiazepine") { return .benzodiazepine }
        if joined.contains("barbiturate") || joined.contains("depressant") || joined.contains("muscle relaxant") { return .depressant }
        if joined.contains("stimulant") { return .stimulant }
        if joined.contains("serotonin reuptake") || joined.contains("antidepressant") || joined.contains("monoamine oxidase") || joined.contains("mood stabilizer") { return .antidepressant }
        if joined.contains("antipsychotic") { return .antipsychotic }
        if joined.contains("antihistamine") || joined.contains("histamine") { return .antihistamine }
        if joined.contains("anti-inflammatory") || joined.contains("analgesic") { return .analgesic }
        if joined.contains("anti-epileptic") || joined.contains("anticonvulsant") { return .gabapentinoid }
        if joined.contains("cholinesterase") || joined.contains("nmda") || joined.contains("nootropic") { return .nootropic }
        if joined.contains("corticosteroid") || joined.contains("vitamin") { return .supplement }
        return .other
    }

    enum APIError: Error {
        case badURL
        case badResponse
    }
}
