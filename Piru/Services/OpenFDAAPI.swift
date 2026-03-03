import Foundation

/// OpenFDA API client — fetches prescription drug data
struct OpenFDAAPI {
    private static let baseURL = "https://api.fda.gov/drug/label.json"

    struct FDADrug: Decodable {
        let openfda: OpenFDA?
        let dosage_and_administration: [String]?
        let warnings: [String]?
        let drug_interactions: [String]?

        struct OpenFDA: Decodable {
            let brand_name: [String]?
            let generic_name: [String]?
            let route: [String]?
            let substance_name: [String]?
            let pharm_class_epc: [String]?
        }
    }

    /// Pharmacologic classes to fetch — covers major drug categories
    private static let pharmClasses: [String] = [
        // Psychiatric
        "Selective Serotonin Reuptake Inhibitor",
        "Serotonin and Norepinephrine Reuptake Inhibitor",
        "Tricyclic Antidepressant",
        "Monoamine Oxidase Inhibitor",
        "Atypical Antipsychotic",
        "Typical Antipsychotic",
        "Central Nervous System Stimulant",
        // Sedatives/Anxiolytics
        "Benzodiazepine",
        "Barbiturate",
        "Central Nervous System Depressant",
        // Pain
        "Opioid Agonist",
        "Opioid Antagonist",
        "Partial Opioid Agonist",
        "Nonsteroidal Anti-inflammatory Drug",
        "Local Anesthetic",
        // Cardiovascular
        "Beta-Adrenergic Blocker",
        "Alpha-1 Adrenergic Blocker",
        "Alpha-2 Adrenergic Agonist",
        "Calcium Channel Blocker",
        "Angiotensin Converting Enzyme Inhibitor",
        "Angiotensin 2 Receptor Blocker",
        "Thiazide Diuretic",
        "Loop Diuretic",
        "Potassium-sparing Diuretic",
        "HMG-CoA Reductase Inhibitor",
        "Anticoagulant",
        "Sodium Channel Blocker",
        "Potassium Channel Blocker",
        // GI
        "Proton Pump Inhibitor",
        "Histamine H2 Receptor Antagonist",
        // Allergy
        "Histamine H1 Receptor Antagonist",
        // Neuro
        "Anticonvulsant",
        "Dopamine Agonist",
        "Dopamine Antagonist",
        "Cholinesterase Inhibitor",
        "NMDA Receptor Antagonist",
        "Muscle Relaxant",
        "Anticholinergic",
        // Endocrine
        "Thyroid Hormone",
        "Estrogen",
        "Progestin",
        "Androgen",
        "Corticosteroid",
        "GLP-1 Receptor Agonist",
        "SGLT2 Inhibitor",
        "DPP-4 Inhibitor",
        "5-alpha Reductase Inhibitor",
        // Urological
        "Phosphodiesterase 5 Inhibitor",
        // Immune
        "Immunosuppressant",
        "Calcineurin Inhibitor",
        "Tumor Necrosis Factor Blocker",
        "Janus Kinase Inhibitor",
        // Antimicrobial
        "Fluoroquinolone Antimicrobial",
        "Penicillin-class Antimicrobial",
        "Cephalosporin Antimicrobial",
        "Macrolide Antimicrobial",
        "Tetracycline Antimicrobial",
        "Aminoglycoside Antimicrobial",
        "Antifungal",
        // Respiratory
        "Leukotriene Receptor Antagonist",
        "Beta2-Adrenergic Agonist",
        // Other
        "Retinoid",
        "Vitamin D Analog",
        "Xanthine Oxidase Inhibitor",
        "Uricosuric",
        "Nucleoside Reverse Transcriptase Inhibitor",
        "Protease Inhibitor",
    ]

    /// Fetch drugs from all pharmacologic classes
    static func fetchCommonDrugs() async throws -> [FDADrug] {
        var allDrugs: [FDADrug] = []
        var seenNames: Set<String> = []

        for cls in pharmClasses {
            guard let encoded = cls.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(baseURL)?search=openfda.pharm_class_epc:\"\(encoded)\"&limit=100") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let result = try JSONDecoder().decode(FDAResult.self, from: data)
                for drug in result.results ?? [] {
                    // Dedup by generic name
                    if let name = drug.openfda?.generic_name?.first?.uppercased(), !seenNames.contains(name) {
                        seenNames.insert(name)
                        allDrugs.append(drug)
                    }
                }
                // Rate limit
                try await Task.sleep(for: .milliseconds(260))
            } catch {
                continue
            }
        }

        print("[OpenFDAAPI] Fetched \(allDrugs.count) unique drugs from \(pharmClasses.count) classes")
        return allDrugs
    }

    /// Convert an FDA drug to our Substance model
    static func toSubstance(_ drug: FDADrug) -> Substance? {
        guard let genericName = drug.openfda?.generic_name?.first else { return nil }

        // Skip combo drugs and junk
        let name = genericName.capitalized
        if name.contains(",") || name.contains(" And ") { return nil }
        if name.count < 3 { return nil }

        var aliases: [String] = []
        if let brands = drug.openfda?.brand_name {
            // Only keep unique, clean brand names
            let seen = Set([name.uppercased()])
            for brand in brands {
                let clean = brand.capitalized
                if !seen.contains(clean.uppercased()) && !clean.contains(",") {
                    aliases.append(clean)
                }
            }
            // Limit to 5 aliases
            aliases = Array(aliases.prefix(5))
        }

        let category = mapCategory(drug.openfda?.pharm_class_epc)
        let routes: [SubstanceRoute] = (drug.openfda?.route ?? ["ORAL"]).prefix(3).map { routeStr in
            SubstanceRoute(
                route: RouteOfAdministration.from(string: routeStr),
                unit: "mg",
                doses: DoseRange()
            )
        }
        let defaultRoute = routes.first?.route ?? .oral

        return Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: defaultRoute,
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
        if joined.contains("barbiturate") { return .depressant }
        if joined.contains("stimulant") { return .stimulant }
        if joined.contains("serotonin reuptake") || joined.contains("antidepressant") || joined.contains("monoamine oxidase") { return .antidepressant }
        if joined.contains("antipsychotic") { return .antipsychotic }
        if joined.contains("antihistamine") || joined.contains("histamine") { return .antihistamine }
        if joined.contains("anti-inflammatory") || joined.contains("analgesic") { return .analgesic }
        if joined.contains("anticonvulsant") { return .gabapentinoid }
        if joined.contains("muscle relaxant") || joined.contains("depressant") { return .depressant }
        if joined.contains("corticosteroid") || joined.contains("vitamin") { return .supplement }
        if joined.contains("cholinesterase") || joined.contains("nmda") { return .nootropic }
        return .other
    }

    private struct FDAResult: Decodable {
        let results: [FDADrug]?
    }

    enum APIError: Error {
        case badURL
        case badResponse
    }
}
