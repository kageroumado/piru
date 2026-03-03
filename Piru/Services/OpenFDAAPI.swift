import Foundation

/// OpenFDA API client — fetches prescription drug data
struct OpenFDAAPI {
    private static let baseURL = "https://api.fda.gov/drug/label.json"

    struct FDAResult: Decodable {
        let meta: Meta?
        let results: [FDADrug]?

        struct Meta: Decodable {
            let results: ResultsMeta?
            struct ResultsMeta: Decodable {
                let total: Int?
            }
        }
    }

    struct FDADrug: Decodable {
        let openfda: OpenFDA?
        let dosage_and_administration: [String]?
        let warnings: [String]?
        let drug_interactions: [String]?
        let indications_and_usage: [String]?

        struct OpenFDA: Decodable {
            let brand_name: [String]?
            let generic_name: [String]?
            let route: [String]?
            let substance_name: [String]?
            let pharm_class_epc: [String]?  // Established Pharmacologic Class
        }
    }

    /// Fetch drugs by pharmacologic class to get meaningful categories
    static func fetchByClass(_ pharmClass: String, limit: Int = 100) async throws -> [FDADrug] {
        let query = pharmClass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pharmClass
        let urlStr = "\(baseURL)?search=openfda.pharm_class_epc:\"\(query)\"&limit=\(limit)"
        guard let url = URL(string: urlStr) else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse
        }

        let result = try JSONDecoder().decode(FDAResult.self, from: data)
        return result.results ?? []
    }

    /// Fetch a single drug by name
    static func fetchDrug(_ name: String) async throws -> FDADrug? {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlStr = "\(baseURL)?search=openfda.generic_name:\"\(query)\"&limit=1"
        guard let url = URL(string: urlStr) else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let result = try JSONDecoder().decode(FDAResult.self, from: data)
        return result.results?.first
    }

    /// Fetch common drug classes and return all unique drugs
    static func fetchCommonDrugs() async throws -> [FDADrug] {
        let classes = [
            "Opioid Agonist", "Benzodiazepine", "Selective Serotonin Reuptake Inhibitor",
            "Serotonin and Norepinephrine Reuptake Inhibitor",
            "Atypical Antipsychotic", "Typical Antipsychotic",
            "Central Nervous System Stimulant", "Barbiturate",
            "Nonsteroidal Anti-inflammatory Drug",
            "Histamine H1 Receptor Antagonist", "Beta-Adrenergic Blocker",
            "Proton Pump Inhibitor", "HMG-CoA Reductase Inhibitor",
            "Angiotensin Converting Enzyme Inhibitor",
            "Calcium Channel Blocker", "Thiazide Diuretic",
            "Anticonvulsant", "Tricyclic Antidepressant",
            "Dopamine Agonist", "Muscle Relaxant",
            "Corticosteroid", "Anticoagulant"
        ]

        var allDrugs: [FDADrug] = []
        for cls in classes {
            do {
                let drugs = try await fetchByClass(cls, limit: 50)
                allDrugs.append(contentsOf: drugs)
                // Rate limit: OpenFDA allows 240 requests/minute without key
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                continue // Skip failed classes
            }
        }
        return allDrugs
    }

    /// Convert an FDA drug to our Substance model
    static func toSubstance(_ drug: FDADrug) -> Substance? {
        guard let genericName = drug.openfda?.generic_name?.first else { return nil }

        let name = genericName.capitalized
        var aliases: [String] = []
        if let brands = drug.openfda?.brand_name {
            aliases = brands.map { $0.capitalized }
        }

        // Map pharma class to our category
        let category = mapCategory(drug.openfda?.pharm_class_epc)

        // Map routes
        let routes: [SubstanceRoute] = (drug.openfda?.route ?? ["ORAL"]).map { routeStr in
            SubstanceRoute(
                route: RouteOfAdministration.from(string: routeStr),
                unit: "mg",
                doses: DoseRange()
            )
        }

        let defaultRoute = routes.first?.route ?? .oral

        // Extract effects from indications
        let effects: [String] = []

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
            routes: routes,
            effects: effects,
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
        if joined.contains("stimulant") { return .stimulant }
        if joined.contains("antidepressant") || joined.contains("serotonin reuptake") { return .antidepressant }
        if joined.contains("antipsychotic") { return .antipsychotic }
        if joined.contains("antihistamine") || joined.contains("histamine") { return .antihistamine }
        if joined.contains("anti-inflammatory") || joined.contains("analgesic") { return .analgesic }
        if joined.contains("anticonvulsant") { return .gabapentinoid }
        if joined.contains("barbiturate") { return .depressant }
        if joined.contains("corticosteroid") { return .supplement }
        return .other
    }

    enum APIError: Error {
        case badURL
        case badResponse
    }
}
